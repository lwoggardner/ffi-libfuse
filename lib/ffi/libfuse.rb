# frozen_string_literal: true

require_relative 'libfuse/fuse_version'
require_relative 'libfuse/fuse2' if FFI::Libfuse::FUSE_MAJOR_VERSION == 2
require_relative 'libfuse/fuse3' if FFI::Libfuse::FUSE_MAJOR_VERSION == 3
require_relative 'libfuse/main'
require_relative 'libfuse/adapter'
require_relative 'devt'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    class << self
      # Filesystem entry point
      # @note This main function defaults to single-threaded operation by injecting the '-s' option. Pass `$0,*ARGV`
      #   if your filesystem can usefully support multi-threaded operation.
      #
      # @see Main.fuse_main
      def fuse_main(*argv, operations:, args: argv.any? ? argv : [$0, '-s', *ARGV], private_data: nil)
        Main.fuse_main(args: args, operations: operations, private_data: private_data) || -1
      end
    end
  end
end
