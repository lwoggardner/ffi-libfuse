# frozen_string_literal: true

require_relative 'version'
require_relative 'gem_helper'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    # @visibility private
    MAIN_BRANCH = 'main'
    # @!visibility private
    GEM_VERSION, = GemHelper.gem_version(main_branch: MAIN_BRANCH, version: VERSION)
  end
end
