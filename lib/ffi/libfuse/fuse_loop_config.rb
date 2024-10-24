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

      STRUCT_VERSION = (FUSE_MAJOR_VERSION > 3 || (FUSE_MAJOR_VERSION == 3 && FUSE_MINOR_VERSION >= 12) ? 2 : 1)
      if STRUCT_VERSION > 1
        layout(
          version_id: :int,
          clone_fd: :bool_int,
          max_idle_threads: :int,
          max_threads: :uint
        )
      else
        layout(
          clone_fd: :bool_int,
          max_idle_threads: :int
        )
      end

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
      #   @deprecated at Fuse 3.12. Use max_threads instead
      #   @return [Integer] the maximum number of threads to leave idle
      ffi_attr_accessor(:max_idle_threads)

      # @!attribute [rw] max_threads
      #   @return [Integer]
      #   @since Fuse 3.12
      ffi_attr_accessor(:max_threads) if STRUCT_VERSION > 1

      class << self
        def create(**opts)
          cfg =
            if STRUCT_VERSION >= 2
              cfg = Libfuse.fuse_loop_cfg_create
              ObjectSpace.define_finalizer(cfg, finalizer(cfg.to_ptr))
              cfg
            else
              FuseLoopConfig.new
            end

          cfg.fill(**opts.select { |k, _| ffi_public_attr_writers.include?(k) })
        end

        def finalizer(ptr)
          proc { |_| Libfuse.fuse_loop_cfg_destroy(ptr) }
        end

        if FuseLoopConfig::STRUCT_VERSION >= 2
          Libfuse.attach_function :fuse_loop_cfg_create, [], FuseLoopConfig.by_ref
          Libfuse.attach_function :fuse_loop_cfg_destroy, [:pointer], :void
        end
      end
    end
  end
end
