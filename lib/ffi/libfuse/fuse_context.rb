# frozen_string_literal: true

require_relative 'fuse_common'
require_relative '../ruby_object'
require_relative '../accessors'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    # Context for each callback operation
    # @see get
    class FuseContext < FFI::Struct
      include FFI::Accessors
      base = { fuse: :fuse, uid: :uid_t, gid: :gid_t, pid: :pid_t, private_data: RubyObject }
      base[:umask] = :mode_t if FUSE_VERSION >= 28
      layout base

      ffi_attr_reader(*members, simple: false) do
        m = __method__

        # Use overrides if they are available, or the default context if the underlying memory is invalid
        FuseContext.overrides[m] || (null? ? DEFAULT_CONTEXT[m] : self[m])
      end

      if FUSE_VERSION < 28
        attr_writer :umask

        def umask
          @umask ||= File.umask
        end
      end

      # @!attribute [r] uid
      #   @return [Integer] user id of the calling process

      # @!attribute [r] gid
      #  @return [Integer] group id of the calling process

      # @!attribute [r] pid
      #  @return [Integer] process id of the calling thread

      # @!attribute [r] private_data
      #  @return [Object] private filesystem data
      #  @see FuseOperations#init

      # @!attribute [rw] umask
      #
      #  Writable only for Fuse version < 28
      #  @return [Integer] umask of the calling process

      # @return [Boolean]
      # @see Libfuse.fuse_interrupted?
      def interrupted?
        Libfuse.fuse_interrupted?
      end

      # @return [void]
      # @raise [Errno::EINTR]
      # @see Libfuse.raise_interrupt
      def raise_interrupt
        Libfuse.raise_interrupt
      end

      # @param [Integer] perms
      # @return perms adjusted by {#umask}
      def mask(perms)
        perms & ~umask
      end

      DEFAULT_CONTEXT = { uid: Process.uid, gid: Process.gid, umask: File.umask }.freeze

      class << self
        # @overload overrides(hash)
        #  @param[Hash<Symbol,Object|nil] hash a list of override values that will apply to this context
        #
        #    If not set uid, gid, umask will be overridden from the current process, which is useful if
        #    {FuseContext} is referenced from outside of a fuse callback
        #  @yield [] executes block with the given hash overriding FuseContext values
        #  @return [Object] the result of the block
        # @overload overrides()
        #   @return [Hash] current thread local overrides for FuseContext
        def overrides(hash = nil)
          return Thread.current[:fuse_context_overrides] ||= {} unless block_given?

          begin
            Thread.current[:fuse_context_overrides] = hash || DEFAULT_CONTEXT
            yield
          ensure
            Thread.current[:fuse_context_overrides] = nil
          end
        end

        # @return [FuseContext] the context for the current filesystem operation
        # @note if called outside a fuse callback the native {FuseContext} will have invalid values. See {overrides}
        def fuse_get_context
          Libfuse.fuse_get_context
        end
        alias get fuse_get_context
      end
    end

    attach_function :fuse_get_context, [], FuseContext.by_ref
    attach_function :fuse_interrupted, [], :int
    class << self
      # @return [Boolean] if the fuse request is marked as interrupted
      def fuse_interrupted?
        fuse_interrupted != 0
      end

      # @return [void]
      # @raise [Errno::EINTR] if fuse request is marked as interrupted
      def raise_interrupt
        raise Errno::EINTR if fuse_interrupted?
      end

      # @!visibility private
      # @!method fuse_get_context
      # @!method fuse_interrupted
    end
  end
end
