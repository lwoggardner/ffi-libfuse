# frozen_string_literal: true

require_relative 'version'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    # @!visibility private

    SEMVER_TAG_REGEX = /^v\d+\.\d+\.\d+/.freeze

    # branches the format is refs/heads/<branch_name>,
    # tags it is refs/tags/<tag_name>.
    # for pull requests it is refs/pull/<pr_number>/merge,
    GIT_REF_TYPES = { 'heads' => :branch, 'tags' => :tag, 'pull' => :pull }.freeze

    def self.git_ref(env: ENV)
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

    def self.gem_version(main_branch: 'main', version: VERSION, env: ENV)
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

    GEM_VERSION, GIT_REF_NAME, GIT_REF_TYPE = gem_version
  end
end
