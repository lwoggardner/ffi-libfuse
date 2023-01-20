# frozen_string_literal: true

require_relative 'fuse_version'
require_relative 'io'
require_relative 'fuse_buf'
require_relative '../accessors'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    #
    # Data buffer vector
    #
    # An list of io buffers, each containing a memory pointer or a file descriptor.
    #
    class FuseBufVec < FFI::Struct
      include Accessors

      layout(
        count: :size_t,
        idx: :size_t,
        off: :size_t,
        # buf is treated as a variable length array of FuseBuf at size +1 following the struct.
        buf: [FuseBuf::Native, 1] # struct fuse_buf[1]
      )

      ffi_attr_reader(:count, :idx, :off)

      # @!attribute [r] count
      #   @return [Integer] the number of buffers in the array

      # @!attribute [r] idx
      #   @return [Integer] index of current buffer within the array

      alias index idx

      # @!attribute [r] off
      #   @return [Integer] current offset within the current buffer

      alias offset off

      # Create and initialise from a ruby object that quacks like {::File}, {::IO}, or {::String}
      #
      # @param [Object] io
      #
      #   * Integer file descriptor or File like object that returns one via :fileno
      #   * Otherwise something to pass to {IO.read}(io, size, offset) to create a memory based buffer
      #
      # @param [Integer] size
      # @param [Integer] offset
      # @return [FuseBufVec]
      #
      # @note The returned object's memory is not auto-released, and thus suitable for use with
      #   {FuseOperations#read_buf} where the buffers are cleared by libfuse library..
      def self.create(io, size, offset = nil)
        fd = io.respond_to?(:fileno) ? io.fileno : io
        return init(autorelease: false, size: size, fd: fd, pos: offset || 0) if fd.is_a?(Integer)

        init(autorelease: false, str: Libfuse::IO.read(io, size, offset))
      end

      # Create and initialise a new FuseBufVec
      #
      # @param [Boolean] autorelease should the struct be freed on GC
      #
      #   Use false only if this object is going to be passed to the C library side. eg. {FuseOperations#read_buf}
      # @param [Hash<Symbol>] buf_options options for configuring the initial buffer (see {FuseBuf#fill})
      # @return [FuseBufVec]
      def self.init(autorelease: true, count: 1, **buf_options)
        bufvec_ptr = FFI::MemoryPointer.new(:uchar, FuseBufVec.size + (FuseBuf::Native.size * (count - 1)), true)
        bufvec_ptr.autorelease = autorelease
        bufvec = new(bufvec_ptr)
        bufvec[:count] = count
        bufvec[:idx] = 0
        bufvec[:off] = 0
        bufvec.buffers[0].fill(**buf_options) unless buf_options.empty?
        bufvec
      end

      # @return [Integer] total size of io in a fuse buffer vector (ie the size of all the fuse buffers)
      def buf_size
        Libfuse.fuse_buf_size(self)
      end

      # Set {index}/{offset} for reading/writing from pos
      # @param [Integer] pos
      # @return [self]
      # @raise [Errno::ERANGE] if seek past end of file
      def seek(pos)
        buffers.each_with_index do |b, i|
          if pos < b.size
            self[:idx] = i
            self[:off] = pos
            return self
          else
            pos -= b.size
          end
        end
        raise Errno::ERANGE
      end

      # Copy data from this set of buffers to another set
      #
      # @param [FuseBufVec] dst destination buffers
      # @param [Array<Symbol>] flags Buffer copy flags
      #
      #  - :no_splice
      #    Don't use splice(2)
      #
      #    Always fall back to using read and write instead of splice(2) to copy io from one file descriptor to
      #    another.
      #
      #    If this flag is not set, then only fall back if splice is unavailable.
      #
      #  - :force_splice
      #
      #    Always use splice(2) to copy io from one file descriptor to another.  If splice is not available, return
      #    -EINVAL.
      #
      #  - :splice_move
      #
      #    Try to move io with splice.
      #
      #    If splice is used, try to move pages from the source to the destination instead of copying. See
      #    documentation of SPLICE_F_MOVE in splice(2) man page.
      #
      #  - :splice_nonblock
      #
      #    Don't block on the pipe when copying io with splice
      #
      #    Makes the operations on the pipe non-blocking (if the pipe is full or empty).  See SPLICE_F_NONBLOCK in
      #    the splice(2) man page.
      #
      # @return [Integer] actual number of bytes copied or -errno on error
      #
      def copy_to(dst, *flags)
        Libfuse.fuse_buf_copy(dst, self, flags)
      end

      # Copy direct to file descriptor
      # @param [Integer] fileno a file descriptor
      # @param [nil, Integer] offset if non nil will first seek to offset
      # @param [Array<Symbol>] flags see {copy_to}
      # @return [Integer] number of bytes copied
      def copy_to_fd(fileno, offset = nil, *flags)
        dst = self.class.init(size: buf_size, fd: fileno, pos: offset)
        copy_to(dst, *flags)
      end

      # Copy to string via a temporary buffer
      # @param [Array<Symbol>] flags see {copy_to}
      # @return [String] the extracted data
      def copy_to_str(*flags)
        dst = self.class.init(size: buf_size)
        copied = copy_to(dst, *flags)
        dst.buffers.first.memory.read_string(copied)
      end

      # Copy from another set of buffers to this one
      # @param [FuseBufVec] src source buffers
      # @param [Array<Symbol>] flags
      # @return [Integer] number of bytes written
      # @see copy_to
      def copy_from(src, *flags)
        Libfuse.fuse_buf_copy(self, src, flags)
      end

      # Store ourself into a pointer location as received by {FuseOperations#read_buf}
      # @param [FFI::Pointer<FuseBufVec>] bufp
      # @return [void]
      def store_to(bufp)
        bufp.write_pointer(to_ptr)
      end

      # Write data from these buffers to another object
      #
      # @overload copy_to_io(io, *flags)
      # @overload copy_to_io(io, offset = nil, *flags)
      # @param [Object] io one of
      #
      #   * another {FuseBufVec} via io.{seek}(offset) and {copy_to}(io, *flags)
      #   * an {::Integer} file descriptor to write via {copy_to_fd}(io, offset, *flags)
      #   * a {::File} like object that returns a file descriptor via :fileno used as above
      #   * an {::IO} like object that accepts a string data as {IO.write}(io, {copy_to_str}(*flags), offset)
      #
      # @param [nil, Integer] offset position in io to begin writing at, or nil if io is already positioned
      # @param [Array<Symbol>] flags see {copy_to}
      #
      # @return [Integer] number of bytes written
      # @raise [Errno::EBADF] if io is not a valid target
      def copy_to_io(io, offset = nil, *flags)
        if offset.is_a?(Symbol)
          flags.unshift(offset)
          offset = nil
        end

        if io.is_a?(FuseBufVec)
          io.seek(offset) if offset
          return copy_to(io, *flags)
        end

        fd = (io.respond_to?(:fileno) ? io.fileno : io)
        return copy_to_fd(fd, offset || 0, *flags) if fd.is_a?(Integer)

        Libfuse::IO.write(io, copy_to_str(*flags), offset)
      end

      # @return [Array<FuseBuf>] list of buffers
      def buffers
        @buffers ||= Array.new(count) do |i|
          native = i.zero? ? self[:buf].first : FuseBuf::Native.new(self[:buf].to_ptr + (i * FuseBuf::Native.size))
          FuseBuf.new(native)
        end.freeze
      end
    end

    bitmask :fuse_buf_copy_flags, [:no_splice, 1, :force_splice, 2, :splice_move, 4, :splice_nonblock, 8]
    attach_function :fuse_buf_copy, [FuseBufVec.by_ref, FuseBufVec.by_ref, :fuse_buf_copy_flags], :ssize_t
    attach_function :fuse_buf_size, [FuseBufVec.by_ref], :size_t

    class << self
      # @!visibility private
      # @!method fuse_buf_size
      # @!method fuse_buf_copy
      # @!method fuse_buf_size
    end
  end
end
