# frozen_string_literal: true

require_relative 'version'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    # @!visibility private

    def self.gem_version(main_branch: 'main', version: VERSION, env: ENV)
      # GITHUB_REF
      # The ref given is fully-formed, meaning that for
      ref = env.fetch('GITHUB_REF') do
        # get branch ref, or detached head ref
        `git symbolic-ref HEAD 2>/dev/null || git name-rev HEAD | awk '{ gsub(/[\\^~@].*$/,"",$2); printf("refs/%s\\n",$2)}'`.strip # rubocop:disable Layout/LineLength
      rescue StandardError
        'pre'
      end

      case ref
      when %r{^refs/heads/.+}
        # branches the format is refs/heads/<branch_name>,
        ref_name = ref.split('/', 3).last
        ref_name == main_branch ? [version] : [version, ref_name]
      when %r{^refs/tags/.+}
        # and for tags it is refs/tags/<tag_name>.
        ref_name = ref.split('/', 3).last
        ref_name =~ /^v\d+\.\d+\.\d+/ ? [ref_name[1..]] : [version, ref_name]
      when %r{^refs/pull/.+}
        # for pull requests it is refs/pull/<pr_number>/merge,
        _, _, pr_number, merge, _rest = ref.split('/')
        # GITHUB_BASE_REF	The name of the base ref or target branch of the pull request in a workflow run
        base_ref = env.fetch('GITHUB_BASE_REF', 'undefined')
        [version, base_ref, "#{merge}#{pr_number}"]
      else
        [version, 'pre', ref]
      end.select { |p| p && !p.empty? }.join('.').tr('//_-', '')
    end

    GEM_VERSION = gem_version
  end
end
