# frozen_string_literal: true

require_relative 'libfuse/fuse_version'
require_relative 'libfuse/fuse2' if FFI::Libfuse::FUSE_MAJOR_VERSION == 2
require_relative 'libfuse/fuse3' if FFI::Libfuse::FUSE_MAJOR_VERSION == 3
require_relative 'libfuse/main'
require_relative 'libfuse/adapter'
require_relative 'libfuse/filesystem'
require_relative 'devt'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    # Filesystems can raise this error to indicate errors from filesystem users
    class Error < StandardError; end

    # Opinionated default args for {.main}.
    #
    # Filesystems that want full control (eg to take advantage of multi-threaded operations) should call
    #  {Main.fuse_main} instead
    # @note These may change between major versions
    DEFAULT_ARGS = %w[-s -odefault_permissions].freeze

    class << self
      # Filesystem entry point
      # @see Main.fuse_main
      def fuse_main(*argv, operations:, args: argv.any? ? argv : Main.default_args(*DEFAULT_ARGS), private_data: nil)
        Main.fuse_main(args: args, operations: operations, private_data: private_data) || -1
      end
      alias main fuse_main
    end
  end
end
