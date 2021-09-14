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

      ffi_attr_reader(:uid, :gid, :pid, :mode, :private_data)

      ffi_attr_reader(:umask) if FUSE_VERSION >= 28

      # @!attribute [r] uid
      #   @return [Integer] user id of the calling process

      # @!attribute [r] gid
      #  @return [Integer] group id of the calling process

      # @!attribute [r] pid
      #  @return [Integer] process id of the calling thread

      # @!attribute [r] private_data
      #  @return [Object] private filesystem data
      #  @see FuseOperations#init

      # @!attribute [r] umask
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

      class << self
        # @return [FuseContext] the context for the current filesystem operation
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
