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
    class FuseBuf < FFI::Struct
      layout(
        size: :size_t, #  Size of data in bytes
        flags: :fuse_buf_flags, # Buffer flags
        mem: :pointer, # Memory pointer - used if :is_fd flag is not set
        fd: :int, # File descriptor - used if :is_fd is set
        pos: :off_t # File position - used if :fd_seek flag is set.
      )

      # rubocop:disable  Naming/MethodParameterName

      # @!attribute [r] mem
      #   @return [FFI::Pointer] the memory in the buffer
      def mem
        self[:mem]
      end
      alias memory mem

      # @!attribute [r] fd
      #   @return [Integer] the file descriptor number
      def fd
        self[:fd]
      end
      alias file_descriptor fd

      #  @return [Boolean] true if this a memory buffer
      def mem?
        !fd?
      end

      # @return [Boolean] true if this is a file descriptor buffer
      def fd?
        self[:flags].include?(:is_fd)
      end
      alias file_descriptor? fd?

      # Resize mem to smaller than initially allocated
      # @param [Integer] new_size
      # @return [void]
      def resize(new_size)
        self[:size] = new_size
      end

      # @overload fill(size:, mem:, auto_release)
      #   Fill as a Memory buffer
      #   @param [Integer] size Size of data in bytes
      #   @param [FFI::Pointer] mem Memory pointer allocated to size if required
      #   @param [Boolean] autorelease
      #
      # @overload fill(fd:, fd_retry:, pos:)
      #   Fill as a FileDescriptor buffer
      #   @param [Integer] fd File descriptor
      #   @param [Boolean] fd_retry
      #     Retry operations on file descriptor
      #
      #     If this flag is set then retry operation on file descriptor until .size bytes have been copied or an error
      #     or EOF is detected.
      #
      #   @param [Integer] pos
      #      If > 0 then used to seek to the given offset before performing operation on file descriptor.
      # @return [self]
      def fill(mem: FFI::Pointer::NULL, size: mem.null? ? 0 : mem.size, fd: -1, fd_retry: false, pos: 0)
        mem = FFI::MemoryPointer.new(:char, size, true) if fd == -1 && mem.null? && size.positive?
        mem.autorelease = to_ptr.autorelease? unless mem.null?

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
    class FuseBufVec < FFI::Struct
      layout(
        count: :size_t,
        idx: :size_t,
        off: :size_t,
        # but is treated as a variable length array of FuseBuf at size +1 following the struct.
        buf: [FuseBuf, 1] # struct fuse_buf[1]
      )

      # @!attribute [r] count
      #   @return [Integer] the number of buffers in the array
      def count
        self[:count]
      end

      # @!attribute [r] index
      #   @return [Integer] index of current buffer within the array
      def index
        self[:idx]
      end
      alias idx index

      # @!attribute [r] offset
      #   @return [Integer] current offset within the current buffer
      def offset
        self[:off]
      end
      alias off offset

      # @!attribute [r] buffers
      #   @return [Array<FuseBuf>] array of buffers
      def buffers
        @buffers ||= Array.new(count) do |i|
          next self[:buf].first if i.zero?

          FuseBuf.new(self[:buf].to_ptr + (i * FuseBuf.size))
        end
      end

      # @!attribute [r] current
      #  @return [FuseBuf] the current buffer
      def current
        return self[:buf].first if index.zero?

        FuseBuf.new(self[:buf].to_ptr + (index * FuseBuf.size))
      end

      # Create and initialise a new FuseBufVec
      # @param [Boolean] autorelease should the struct be freed on GC (default NO!!!)
      # @param [Hash] buf_options options for configuring the initial buffer. See {#init}
      # @yield(buf,index)
      # @yieldparam [FuseBuf] buf
      # @yieldparam [Integer] index
      # @yieldreturn [void]
      # @return [FuseBufVec]
      def self.init(autorelease: true, count: 1, **buf_options)
        bufvec_ptr = FFI::MemoryPointer.new(:uchar, FuseBufVec.size + (FuseBuf.size * (count - 1)), true)
        bufvec_ptr.autorelease = autorelease
        bufvec = new(bufvec_ptr)
        bufvec[:count] = count
        bufvec.init(**buf_options)

        buffers.each_with_index { |b, i| yield i, b } if block_given?
        bufvec
      end

      # Set and initialise a specific buffer
      #
      # See fuse_common.h FUSE_BUFVEC_INIT macro
      # @param [Integer] index the index of the buffer
      #   @param [Hash<Symbol,Object>] buf_options see {FuseBuf#fill}
      #   @return [FuseBuf] the initial buffer
      def init(index: 0, **buf_options)
        self[:idx] = index
        self[:off] = 0
        current.fill(**buf_options) unless buf_options.empty?
        self
      end

      # Would pref this to be called #size but clashes with FFI::Struct, might need StructWrapper
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

      # Copy our data direct to file descriptor
      # @param [Integer] fileno a file descriptor
      # @param [Integer] offset
      # @param [Array<Symbol>] flags - see {copy_to}
      # @return [Integer] number of bytes copied
      def copy_to_fd(fileno, offset = 0, *flags)
        dst = self.class.init(size: buf_size, fd: fileno, pos: offset)
        copy_to(dst, *flags)
      end

      # Copy to string via a temporary buffer
      # @param [Array<Symbol>] flags - see {copy_to}
      # @return [String] the extracted data
      def copy_to_str(*flags)
        dst = FuseBufVec.init(size: buf_size)
        copied = copy_to(dst, *flags)
        dst.current.memory.read_string(copied)
      end

      def copy_from(src, *flags)
        Libfuse.fuse_buf_copy(self, src, flags)
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
