# frozen_string_literal: true

require_relative '../accessors'
require_relative '../boolean_int'

module FFI
  module Libfuse
    # struct fuse_loop_config {
    #   int clone_fd;
    #   unsigned int max_idle_threads;
    # };

    # For native fuse_loop_mt only
    # @!visibility private
    class FuseLoopConfig < FFI::Struct
      include(FFI::Accessors)

      layout(
        clone_fd: :bool_int,
        max_idle_threads: :int
      )

      # @!attribute [rw] clone_fd?
      #   whether to use separate device fds for each thread (may increase performance)
      #   Unused by ffi-libfuse as we do not call fuse_loop_mt
      #   @return [Boolean]
      ffi_attr_accessor(:clone_fd?)

      # @!attribute [rw] max_idle_threads
      #   The maximum number of available worker threads before they start to get deleted when they become idle. If not
      #    specified, the default is 10.
      #
      #   Adjusting this has performance implications; a very small number of threads in the pool will cause a lot of
      #    thread creation and deletion overhead and performance may suffer. When set to 0, a new thread will be created
      #    to service every operation.
      #
      #   @return [Integer] the maximum number of threads to leave idle
      ffi_attr_accessor(:max_idle_threads)
    end
  end
end
