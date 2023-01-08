# frozen_string_literal: true

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    # @!visibility private
    class GemHelper
      SEMVER_TAG_REGEX = /^v\d+\.\d+\.\d+/.freeze

      # branches the format is refs/heads/<branch_name>,
      # tags it is refs/tags/<tag_name>.
      # for pull requests it is refs/pull/<pr_number>/merge,
      GIT_REF_TYPES = { 'heads' => :branch, 'tags' => :tag, 'pull' => :pull }.freeze

      class << self
        # set when install'd.
        attr_accessor :instance

        def install_tasks(main_branch:, version:)
          require 'bundler/gem_tasks'
          include Rake::DSL if defined? Rake::DSL
          new(main_branch: main_branch, version: version).install
        end

        def git_ref(env: ENV)
          ref = env.fetch('GIT_REF') do
            # get branch ref, or detached head ref to tag
            `git symbolic-ref HEAD 2>/dev/null || git name-rev HEAD | awk '{ gsub(/[\\^~@].*$/,"",$2); printf("refs/%s\\n",$2)}'`.strip # rubocop:disable Layout/LineLength
          rescue StandardError
            nil
          end

          return [ref, nil] unless ref&.start_with?('refs/')

          _refs, ref_type, ref_name = ref.split('/', 3)
          [ref_name, GIT_REF_TYPES[ref_type]]
        end

        def gem_version(main_branch:, version:, env: ENV)
          ref_name, ref_type = git_ref(env: env)

          version =
            case ref_type
            when :branch
              ref_name == main_branch ? [version] : [version, ref_name]
            when :tag
              SEMVER_TAG_REGEX.match?(ref_name) ? [ref_name[1..]] : [version, ref_name]
            when :pull
              pr_number, merge, _rest = ref_name.split('/')
              # GITHUB_BASE_REF	The name of the base ref or target branch of the pull request in a workflow run
              base_ref = env.fetch('GIT_BASE_REF', 'undefined')
              [version, base_ref, "#{merge}#{pr_number}"]
            else
              [version, 'pre', ref_name]
            end.select { |p| p && !p.empty? }.join('.').tr('//_-', '')

          [version, ref_name, ref_type]
        end
      end

      attr_reader :version, :main_branch, :git_ref_name, :git_ref_type, :gem_version, :gem_version_tag

      def initialize(version:, main_branch:)
        @version = version
        @main_branch = main_branch
        @gem_version, @git_ref_name, @git_ref_type =
          self.class.gem_version(main_branch: main_branch, version: version)
        @gem_version_tag = "v#{@gem_version}"
      end

      def install
        task 'release:guard_clean' => %i[release_guard_tag]

        desc 'Version info'
        task :version do
          v, gv = [version, gem_version].map { |ver| Gem::Version.new(ver) }
          msg = "VERSION='#{v}' GEM_VERSION='#{gv}'"
          raise "Mismatched versions - #{msg}" unless gv.release == v

          puts msg
        end

        task release_guard_tag: [:version] do
          # If we're on a tag then tag must be tag for this version
          if git_ref_type == :tag && git_ref_name != gem_version_tag
            raise "Checkout is tag '#{git_ref_name}' but does not match the gem version '#{gem_version}'"
          end

          # BASH expression - test tag does not exist OR exists and points at HEAD
          cmd = '[ -z "$(git tag -l ${V_TAG})" ] || git tag --points-at HEAD | grep "^${V_TAG}$" > /dev/null'
          unless system({ 'V_TAG' => gem_version_tag }, cmd)
            raise "Tag #{gem_version_tag} exists but does not point at HEAD"
          end
        end
      end
    end
  end
end
