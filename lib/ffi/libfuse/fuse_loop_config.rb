# frozen_string_literal: true

require_relative '../accessors'
require_relative '../boolean_int'

module FFI
  module Libfuse
    # For native fuse_loop_mt only
    class FuseLoopConfig < FFI::Struct
      include(FFI::Accessors)

      # @!attribute [w] clone_fd?
      #   whether to use separate device fds for each thread (may increase performance)
      #   Unused by ffi-libfuse as we do not call fuse_loop_mt
      #   @return [Boolean]

      # @!attribute [w] max_idle_threads
      #   The maximum number of available worker threads before they start to get deleted when they become idle. If not
      #    specified, the default is 10.
      #
      #   Adjusting this has performance implications; a very small number of threads in the pool will cause a lot of
      #    thread creation and deletion overhead and performance may suffer. When set to 0, a new thread will be created
      #    to service every operation.
      #   @deprecated at Fuse 3.12. Use max_threads instead
      #   @return [Integer] the maximum number of threads to leave idle

      # @!attribute [w] max_threads
      #   @return [Integer]
      #   @since Fuse 3.12

      if FUSE_VERSION >= 312
        layout(
          version_id: :int,
          clone_fd: :bool_int,
          max_idle_threads: :uint,
          max_threads: :uint
        )

        Libfuse.attach_function :fuse_loop_cfg_create, [], by_ref
        Libfuse.attach_function :fuse_loop_cfg_destroy, [:pointer], :void

        ffi_attr_reader(:clone_fd?)
        Libfuse.attach_function :fuse_loop_cfg_set_clone_fd, %i[pointer uint], :void
        def clone_fd=(bool_val)
          Libfuse.fuse_loop_cfg_set_clone_fd(to_ptr, bool_val ? 1 : 0)
        end

        ffi_attr_reader(:max_idle_threads)
        Libfuse.attach_function :fuse_loop_cfg_set_idle_threads, %i[pointer uint], :uint
        def max_idle_threads=(val)
          Libfuse.fuse_loop_cfg_set_idle_threads(to_ptr, val) if val
        end

        Libfuse.attach_function :fuse_loop_cfg_set_max_threads, %i[pointer uint], :uint
        ffi_attr_reader(:max_threads)
        def max_threads=(val)
          Libfuse.fuse_loop_cfg_set_max_threads(to_ptr, val) if val
        end

        class << self
          def create(max_idle_threads: nil, max_threads: 10, clone_fd: false, **_)
            cfg = Libfuse.fuse_loop_cfg_create
            ObjectSpace.define_finalizer(cfg, finalizer(cfg.to_ptr))
            cfg.clone_fd = clone_fd
            cfg.max_idle_threads = max_idle_threads if max_idle_threads
            cfg.max_threads = max_threads if max_threads
            cfg
          end

          def finalizer(ptr)
            proc { |_| Libfuse.fuse_loop_cfg_destroy(ptr) }
          end
        end
      else
        layout(
          clone_fd: :bool_int,
          max_idle_threads: :uint
        )

        ffi_attr_accessor(:clone_fd?)
        ffi_attr_accessor(:max_idle_threads)

        class << self
          def create(clone_fd: false, max_idle_threads: 10, **_)
            new.fill(max_idle_threads: max_idle_threads, clone_fd: clone_fd)
          end
        end
      end
    end
  end
end
