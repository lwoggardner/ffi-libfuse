# frozen_string_literal: true

require_relative 'fuse_version'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    bitmask :fuse_buf_flags, [:is_fd, 1, :fd_seek, :fd_retry]
    bitmask :fuse_buf_copy_flags, [:no_splice, 1, :force_splice, 2, :splice_move, 4, :splice_nonblock, 8]

    #
    # Single data buffer
    #
    # Generic data buffer for I/O, extended attributes, etc...Data may be supplied as a memory pointer or as a file
    #  descriptor
    #
    # @todo define helper methods to create buffers pointing to file_descriptors or allocated memory
    class FuseBuf < FFI::Struct
      layout(
        size: :size_t, #  Size of data in bytes
        flags: :fuse_buf_flags, # Buffer flags
        mem: :pointer, # Memory pointer - used if :is_fd flag is not set
        fd: :int, # File descriptor - used if :is_fd is set
        pos: :off_t # File position - used if :fd_seek flag is set.
      )

      # rubocop:disable  Naming/MethodParameterName

      # @param [Integer] size Size of data in bytes
      # @param [Integer] fd File descriptor
      # @param [FFI::Pointer] mem Memory pointer
      # @param [Boolean] fd_retry
      #  Retry operation on file descriptor
      #
      #  If this flag is set then retry operation on file descriptor until .size bytes have been copied or an error or
      #  EOF is detected.
      #
      # @param [Integer] pos
      #  If > 0 then used to seek to the given offset before performing operation on file descriptor.
      # @return [self]
      def fill(size:, mem: FFI::Pointer::NULL, fd: -1, fd_retry: false, pos: 0)
        self[:size] = size
        self[:mem] = mem
        self[:fd] = fd
        flags = []
        flags << :is_fd if fd != -1
        flags << :fd_seek if pos.positive?
        flags << :fd_retry if fd_retry
        self[:flags] = flags
        self[:pos] = pos
        self
      end
    end
    # rubocop:enable Naming/MethodParameterName

    #
    # Data buffer vector
    #
    # An array of data buffers, each containing a memory pointer or a file descriptor.
    #
    # Allocate dynamically to add more than one buffer.
    #
    # @todo find a use for {FuseOperations#read_buf} and implement necessary helpers
    class FuseBufVec < FFI::Struct
      layout(
        count: :size_t,
        idx: :size_t,
        off: :size_t,
        buf: :pointer
      )
      # @!attribute [r] count
      #   @todo implement
      #   @return [Integer] the number of buffers in the array

      # @!attribute [r] index
      #   @todo implement
      #   @return [Integer] index of current buffer within the array

      # @!attribute [r] offset
      #   @todo implement
      #   @return [Integer] current offset within the current buffer

      # @!attribute [r] buffers
      #   @todo implement
      #   @return [Array<FuseBuf>] array of buffers

      # @see #init
      def self.init(**buf_options)
        new.init(**buf_options)
      end

      # Allocate a vector containing a single buffer
      #
      # See fuse_common.h FUSE_BUFVEC_INIT macro
      # @param [Hash<Symbol,Object>] buf_options see {FuseBuf.fill}
      def init(**buf_options)
        self[:count] = 1
        self[:idx] = 0
        self[:off] = 0
        self[:buf] = FuseBuf.new.fill(**buf_options), to_ptr
        self
      end

      # @return [Integer] total size of data in a fuse buffer vector
      def buf_size
        Libfuse.fuse_buf_size(self)
      end

      # Copy data from one buffer vector to another
      # @param [FuseBufVec] dst Destination buffer vector
      # @param [Array<Symbol>] flags Buffer copy flags
      #  - :no_splice
      #    Don't use splice(2)
      #
      #    Always fall back to using read and write instead of splice(2) to copy data from one file descriptor to
      #    another.
      #
      #    If this flag is not set, then only fall back if splice is unavailable.
      #
      #  - :force_splice
      #
      #    Always use splice(2) to copy data from one file descriptor to another.  If splice is not available, return
      #    -EINVAL.
      #
      #  - :splice_move
      #
      #    Try to move data with splice.
      #
      #    If splice is used, try to move pages from the source to the destination instead of copying. See
      #    documentation of SPLICE_F_MOVE in splice(2) man page.
      #
      #  - :splice_nonblock
      #
      #    Don't block on the pipe when copying data with splice
      #
      #    Makes the operations on the pipe non-blocking (if the pipe is full or empty).  See SPLICE_F_NONBLOCK in
      #    the splice(2) man page.
      #
      # @return [Integer] actual number of bytes copied or -errno on error
      #
      def copy_to(dst, *flags)
        Libfuse.fuse_buf_copy(dst, self, flags)
      end
    end

    attach_function :fuse_buf_size, [FuseBufVec.by_ref], :size_t
    attach_function :fuse_buf_copy, [FuseBufVec.by_ref, FuseBufVec.by_ref, :fuse_buf_copy_flags], :ssize_t

    class << self
      # @!visibility private
      # @!method fuse_buf_size
      # @!method fuse_buf_copy
    end
  end
end
