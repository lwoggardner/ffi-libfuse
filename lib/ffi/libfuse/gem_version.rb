# frozen_string_literal: true

require_relative 'version'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    # @!visibility private

    def self.gem_version(main_branch: 'main', version: VERSION, env: ENV)
      ref_name = env.fetch('GITHUB_REF_NAME') do
        `git name-rev HEAD | awk '{print $2'}`.strip
      rescue StandardError
        'undefined'
      end

      ref_type = env.fetch('GITHUB_REF_TYPE') do
        match = %r{^tags/([^^]*)}.match(ref_name)
        ref_name = match[1] if match
        match ? 'tag' : 'branch'
      end

      ref_name = ref_name.tr('//_-', '')

      case ref_type
      when 'tag'
        ref_name =~ /^v\d+\.\d+\.\d+/ ? [ref_name[1..]] : [version, ref_name]
      when 'branch'
        ref_name == main_branch ? [version] : [version, ref_name]
      else
        [version, ref_name]
      end.compact.join('.')
    end

    GEM_VERSION = gem_version
  end
end
