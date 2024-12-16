# frozen_string_literal: true

require_relative 'fuse_version'
require_relative '../struct_wrapper'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    bitmask :fuse_buf_flags, [:is_fd, 1, :fd_seek, :fd_retry]

    #
    # Single io buffer
    #
    # Generic io buffer for I/O, extended attributes, etc...Data may be supplied as a memory pointer or as a file
    #  descriptor
    #
    class FuseBuf
      # @!visibility private
      # Native FuseBuf layout
      class Native < FFI::Struct
        layout(
          size: :size_t, #  Size of io in bytes
          flags: FFI::Libfuse.find_type(:fuse_buf_flags), # Buffer flags
          mem: :pointer, # Memory pointer - used if :is_fd flag is not set
          fd: :int, # File descriptor - used if :is_fd is set
          pos: :off_t # File position - used if :fd_seek flag is set.
        )
      end

      include StructWrapper
      native_struct(Native)

      ffi_attr_reader(:mem, :fd, :pos)
      ffi_attr_accessor(:size)

      # @!attribute [r] mem
      #   @return [FFI::Pointer] the memory in the buffer

      alias memory mem

      # @!attribute [r] fd
      #   @return [Integer] the file descriptor number

      alias file_descriptor fd

      # @attribute [rw] size
      #   @return [Integer] the size of the buffer

      # @return [Boolean] true if this a memory buffer
      def mem?
        !fd?
      end

      # @return [Boolean] true if this is a file descriptor buffer
      def fd?
        self[:flags].include?(:is_fd)
      end
      alias file_descriptor? fd?

      # @overload fill(str:)
      #   Create a memory buffer from str
      #   @param [String,#to_s] str
      #
      # @overload fill(size:)
      #   Allocate an empty memory buffer of size bytes
      #   @param [Integer] size
      #
      # @overload fill(mem:, size: mem.size)
      #   Set the buffer to contain the previously allocated memory
      #   @param [FFI::Pointer] mem
      #   @param [Integer] size <= mem.size
      #
      # @overload fill(fd:, fd_retry: false, size:, pos: 0)
      #   Fill as a FileDescriptor buffer
      #   @param [Integer] fd File descriptor
      #   @param [Boolean] fd_retry
      #     Retry operations on file descriptor
      #
      #     If this flag is set then retry operation on file descriptor until size bytes have been copied or an error
      #     or EOF is detected.
      #
      #   @param [Integer] size
      #     number of bytes to read from fd
      #   @param [nil, Integer] pos
      #      If set then used to seek to the given offset before performing operation on file descriptor.
      # @return [self]
      def fill(
        str: nil,
        mem: str ? FFI::MemoryPointer.from_string(str.to_s) : FFI::Pointer::NULL, size: mem.null? ? 0 : mem.size,
        fd: -1, fd_retry: false, pos: nil # rubocop:disable Naming/MethodParameterName

      )
        # Allocate size bytes if we've been given a null pointer
        mem = FFI::MemoryPointer.new(:char, size, true) if fd == -1 && mem.null? && size.positive?

        mem.autorelease = to_ptr.autorelease? unless mem.null?

        self[:size] = size
        self[:mem] = mem
        self[:fd] = fd
        flags = []
        flags << :is_fd if fd != -1
        flags << :fd_seek if pos
        flags << :fd_retry if fd_retry
        self[:flags] = flags
        self[:pos] = pos || 0
        self
      end
    end
  end
end
