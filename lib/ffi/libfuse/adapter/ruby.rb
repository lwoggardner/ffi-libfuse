# frozen_string_literal: true

require_relative 'safe'
require_relative 'debug'
require 'set'

module FFI
  module Libfuse
    module Adapter
      # This module assists with converting native C libfuse into idiomatic Ruby
      #
      # Class Method helpers
      # ===
      # These functions deal with the native fuse FFI::Pointers, Buffers etc
      #
      # The class {ReaddirFiller} assists with the complexity of the readdir callback
      #
      # FUSE Callbacks
      # ===
      #
      # Including this module in a Filesystem module changes the method signatures for callbacks to be more idiomatic
      #  ruby (via prepending {Prepend}). It also includes the type 1 adapters {Context}, {Debug} and {Safe}
      #
      # Filesystems that return {::IO} like objects from #{open} need not implement other file io operations
      # Similarly Filesystems that return {::Dir} like objects from #{opendir} need not implement #{readdir}
      #
      module Ruby
        # Helper class for {FuseOperations#readdir}
        # @example
        #   def readdir(path, buf, filler, _offset, _ffi, *flags)
        #     rdf = FFI::Adapter::Ruby::ReaddirFiller.new(buf, filler)
        #     %w[. ..].each { |dot_entry| rdf.fill(dot_entry) }
        #     entries.each { |entry| rdf.fill(entry) }
        #   end
        # @example
        #   # short version
        #   def readdir(path, buf, filler, _offset, _ffi, *flags)
        #     %w[. ..].concat(entries).each(&FFI::Adapter::Ruby::ReaddirFiller.new(buf,filler))
        #   end
        class ReaddirFiller
          # @param [FFI::Pointer] buf from #{FuseOperations#readdir}
          # @param [FFI::Function] filler from #{FuseOperations#readdir}
          # @param [Boolean] fuse3 does the filler function expect fuse 3 compatibility
          def initialize(buf, filler, fuse3: FUSE_MAJOR_VERSION >= 3)
            @buf = buf
            @filler = filler
            @stat_buf = nil
            @fuse3 = fuse3
          end

          # Fill readdir from a directory handle
          # @param [#seek, #read, #tell] dir_handle
          # @param [Integer] offset
          # @raise [Errno::ENOTSUP] unless dir_handle quacks like ::Dir
          def readdir_fh(dir_handle, offset = 0)
            raise Errno::ENOTSUP unless %i[seek read tell].all? { |m| dir_handle.respond_to?(m) }

            dir_handle.seek(offset)
            loop while (name = dir_handle.read) && fill(name, offset: dir_handle.tell)
          end

          # @param [String] name a directory entry
          # @param [FFI::Stat|Hash<Symbol,Integer>|nil] stat or stat fields to fill a {::FFI::Stat}
          #
          #    Note sending nil values will cause Fuse to issue #getattr operations for each entry
          #
          #    It is safe to reuse the same {FFI::Stat} object between calls
          # @param [Integer] offset
          # @param [Boolean] fill_dir_plus true if stat has full attributes for inode caching
          # @return [Boolean] true if the buffer accepted the entry
          # @raise [StopIteration] if called after a previous call returned false
          def fill(name, stat: nil, offset: 0, fill_dir_plus: false)
            raise StopIteration unless @buf

            fill_flags = fill_flags(fill_dir_plus: fill_dir_plus)
            fill_stat = fill_stat(stat)
            return true if @filler.call(@buf, name, fill_stat, offset, *fill_flags).zero?

            @buf = nil
          end

          # @return [Proc] a proc to pass to something that yields like #{fill}
          def to_proc
            proc do |name, stat: nil, offset: 0, fill_dir_plus: false|
              fill(name, stat: stat, offset: offset, fill_dir_plus: fill_dir_plus)
            end
          end

          private

          def fill_flags(fill_dir_plus:)
            return [] unless @fuse3

            [fill_dir_plus ? :fuse_fill_dir_plus : 0]
          end

          def fill_stat(from)
            return from if !from || from.is_a?(::FFI::Stat)

            (@stat_buf ||= ::FFI::Stat.new).fill(from)
          end
        end

        # rubocop:disable Metrics/ModuleLength

        # Can be prepended to concrete filesystem implementations to skip duplicate handling of {Debug}, {Safe}
        #
        # @note callbacks still expect to be ultimately handled by {Safe}, ie they raise SystemCallError and can
        #   return non Integer results
        module Prepend
          include Adapter

          # Returns true if our we can support fuse_method callback
          #
          # ie. when
          #
          #   * fuse_method is implemented directly by our superclass
          #   * the adapter can handle the callback via
          #       * file or directory handle returned from {#open} or {#opendir}
          #       * fallback to an alternate implementation (eg {#read_buf} -> {#read}, {#write_buf} -> {#write})
          def fuse_respond_to?(fuse_method)
            fuse_methods =
              case fuse_method
              when :read, :write, :flush, :release
                %i[open]
              when :read_buf
                %i[open read]
              when :write_buf
                %i[open write]
              when :readdir, :releasedir
                %i[opendir]
              else
                []
              end
            fuse_methods << fuse_method

            fuse_methods.any? { |m| defined?(super) ? super(m) : fuse_super_respond_to?(m) }
          end

          # Helper to test if path is root
          def root?(path)
            path.respond_to?(:root?) ? path.root? : path.to_s == '/'
          end

          # @!visibility private
          # Fuse 3 compatibility
          # @return [Boolean] true if this filesystem is receiving Fuse3 compatible arguments
          # @see Fuse3Support
          def fuse3_compat?
            FUSE_MAJOR_VERSION >= 3
          end

          # @!group FUSE Callbacks

          # Writes data to path via
          #
          #   * super as per {Ruby#write} if defined
          #   * {Ruby.write_fh} on ffi.fh
          def write(path, buf, size = buf.size, offset = 0, ffi = nil)
            return Ruby.write_fh(buf, size, offset, ffi&.fh) unless defined?(super)

            Ruby.write_data(buf, size) { |data| super(path, data, offset, ffi) }
          end

          # Writes data to path with {FuseBuf}s via
          #
          #   * super directly if defined
          #   * {FuseBufVec#copy_to_fd} if ffi.fh has non-nil :fileno
          #   * {FuseBufVec#copy_to_str} with the result of {Ruby#write}
          def write_buf(path, bufv, offset, ffi)
            return super if defined?(super)

            fd = ffi&.fh&.fileno
            return bufv.copy_to_fd(fd, offset) if fd

            data = bufv.copy_to_str
            write(path, data, data.size, offset, ffi)
          end

          # Flush data to path via
          #
          #   * super if defined
          #   * :flush on ffi.fh if defined
          def flush(path, ffi)
            return super if defined?(super)

            fh = ffi&.fh
            fh.flush if fh.respond_to?(:flush)
          end

          # Sync data to path via
          #
          #   * super as per {Ruby#fsync} if defined
          #   * :datasync on ffi.fh if defined and datasync is non-zero
          #   * :fysnc on ffi.fh if defined
          def fsync(path, datasync, ffi)
            return super(path, datasync != 0, ffi) if defined?(super)

            fh = ffi&.fh
            return fh.datasync if datasync && fh.respond_to?(:datasync)

            fh.fsync if fh.respond_to?(:fsync)
          end

          # Read data from path via
          #
          #  * super as per {Ruby#read} if defined
          #  * ffi.fh as per {Ruby.read}
          def read(path, buf, size, offset, ffi)
            Ruby.read(buf, size, offset) do
              defined?(super) ? super(path, size, offset, ffi) : ffi&.fh
            end
          end

          # Read data with {FuseBuf}s via
          #
          #  * super if defined
          #  * ffi.fh.fileno if defined and not nil
          #  * result of {#read}
          def read_buf(path, bufp, size, offset, ffi)
            return super if defined?(super)

            Ruby.read_buf(bufp, size, offset) do
              fh = ffi&.fh
              fd = fh.fileno if fh.respond_to?(:fileno)
              next fd if fd

              read(path, nil, size, offset, ffi)
            end
          end

          # Read link name from path via super as per {Ruby#readlink}
          def readlink(path, buf, size)
            raise Errno::ENOTSUP unless defined?(super)

            Ruby.readlink(buf, size) { super(path, size) }
          end

          # Read directory entries via
          #
          #  * super as per {Ruby#readdir} if defined
          #  * ffi.fh using {ReaddirFiller#readdir_fh}
          def readdir(path, buf, filler, offset, ffi, flag_arg = nil)
            rd_filler = ReaddirFiller.new(buf, filler, fuse3: fuse3_compat?)

            flag_args = {}
            flag_args[:readdir_plus] = (flag_arg == :fuse_readdir_plus) if fuse3_compat?
            return super(path, offset, ffi, **flag_args, &rd_filler) if defined?(super)

            rd_filler.readdir_fh(ffi.fh, offset)
          rescue StopIteration
            # do nothing
          end

          # Set extended attributes via super as per {Ruby#setxattr}
          def setxattr(path, name, data, _size, flags)
            raise Errno::ENOTSUP unless defined?(super)

            # fuse converts the void* data buffer to a const char* null terminated string
            # which libfuse reads directly, so size is irrelevant
            super(path, name, data, flags)
          end

          # Get extended attributes via super as per {Ruby#getxattr}
          def getxattr(path, name, buf, size)
            raise Errno::ENOTSUP unless defined?(super)

            Ruby.getxattr(buf, size) { super(path, name) }
          end

          # List extended attributes via super as per {Ruby#listxattr}
          def listxattr(*args)
            raise Errno::ENOTSUP unless defined?(super)

            path, buf, size = args
            Ruby.listxattr(buf, size) { super(path) }
          end

          # Set file atime, mtime via super as per {Ruby#utimens}
          def utimens(path, times, *fuse3_args)
            raise Errno::ENOTSUP unless defined?(super)

            atime, mtime = Stat::TimeSpec.fill_times(times[0, 2], 2).map(&:time)
            super(path, atime, mtime, *fuse3_args)
            0
          end

          # @!method create(path, mode, ffi)
          #   Calls super if defined as per {Ruby#create} storing result in ffi.fh and protecting it from GC
          #   until {#release}

          # @!method open(path, ffi)
          #   Calls super if defined as per {Ruby#open} storing result in ffi.fh and protecting it from GC
          #   until {#release}

          # @!method opendir(path, ffi)
          #   Calls super if defined as per {Ruby#opendir} storing result in ffi.fh and protecting it from GC
          #   until {#releasedir}

          %i[create open opendir].each do |fuse_method|
            define_method(fuse_method) do |*args|
              fh = super(*args) if fuse_super_respond_to?(fuse_method)
              store_handle(args.last, fh)
              0
            end
          end

          # @!method release(path, ffi)
          #   Calls super if defined and allows ffi.fh to be GC'd

          # @!method releasedir(path, ffi)
          #   Calls super if defined and allows ffi.fh to be GC'd

          %i[release releasedir].each do |fuse_method|
            define_method(fuse_method) do |*args|
              super(*args) if fuse_super_respond_to?(fuse_method)
            ensure
              release_handle(args.last)
            end
          end

          # Calls super if defined and storing result to protect from GC until {#destroy}
          def init(*args)
            o = super(*args) if fuse_super_respond_to?(:init)
            handles << o if o
          end

          # Calls super if defined and allows init_obj to be GC'd
          def destroy(init_obj)
            super if fuse_super_respond_to?(:destroy)
            handles.delete(init_obj) if init_obj
          end

          # @!endgroup
          private

          def handles
            @handles ||= Set.new.compare_by_identity
          end

          def store_handle(ffi, file_handle)
            return unless file_handle

            handles << file_handle
            ffi.fh = file_handle
          end

          def release_handle(ffi)
            return unless ffi.fh

            handles.delete(ffi.fh)
          end
        end
        # rubocop:enable Metrics/ModuleLength

        # @!group FUSE Callbacks

        # @!method create(path, mode, fuse_file_info)
        #  Create file
        #  @abstract
        #  @param [String] path
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [Object] file handle available to future operations in fuse_file_info.fh

        # @!method open(path,fuse_file_info)
        #  File open
        #  @abstract
        #  @param [String] path
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [Object] file handle available to future operations in fuse_file_info.fh
        #
        #    File handles are kept from being GC'd until {FuseOperations#release}
        #
        #    If the file handle quacks like {::IO} then the file io operations
        #    :read, :write, :flush, :fsync, :release will be invoked on the file handle if not implemented
        #    by the filesystem
        #
        #  @see FuseOperations#open

        # @!method create(path,mode,fuse_file_info)
        #  File creation
        #  @abstract
        #  @param [String] path
        #  @param [Integer] mode
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [Object] file handle (available to future operations in fuse_file_info.fh)
        #  @see FuseOperations#create

        # @!method opendir(path,fuse_file_info)
        #  Directory open
        #  @abstract
        #  @param [String] path
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [Object] directory handle (available to future operations in fuse_file_info.fh)
        #  @see FuseOperations#opendir

        # @!method write(path,data,offset,info)
        #  @abstract
        #  Write file data. If not implemented will attempt to use info.fh as an IO via :pwrite, or :seek + :write
        #  @param [String] path
        #  @param [String] data
        #  @param [Integer] offset
        #  @param [FuseFileInfo] info
        #  @return [void]
        #  @raise [Errno::ENOTSUP] if not implemented and info.fh does not quack like IO
        #  @see FuseOperations#write

        # @!method write_buf(path,buffers,offset,info)
        #  @abstract
        #  Write file data from buffers
        #  If not implemented, will try to use info.fh,fileno to perform libfuse' file descriptor io, otherwise
        #  the string data is extracted from buffers and passed to #{write}

        # @!method read(path,size,offset,info)
        #  @abstract
        #  Read file data. If not implemented will attempt to use info.fh to perform the read.
        #  @param [String] path
        #  @param [Integer] size
        #  @param [Integer] offset
        #  @param [FuseFileInfo] info
        #  @return [String] the data, expected to be exactly size bytes, except if EOF
        #  @return [#pread, #read] something that supports :pread, or :seek and :read
        #  @raise [Errno::ENOTSUP] if not implemented, and info.fh does not quack like IO
        #  @see FuseOperations#read
        #  @see FuseOperations#read_buf

        # @!method read_buf(path,buffers,size,offset,info)
        #  @abstract
        #  If not implemented and info.fh has :fileno then libfuse' file descriptor io will be used,
        #  otherwise will use {read} to populate buffers

        # @!method readlink(path, size)
        #  @abstract
        #  Resolve target of a symbolic link
        #  @param [String] path
        #  @param [Integer] size
        #  @return [String] the link target, truncated to size if necessary
        #  @see FuseOperations#readlink

        # @!method readdir(path,offset,fuse_file_info, readdir_plus:, &filler)
        #  @abstract
        #  List directory entries
        #
        #  The filesystem may choose between three modes of operation:
        #
        #  1) The readdir implementation ignores the offset parameter yielding only name, and optional stat
        #  The yield will always return true so the whole directory is read in a single readdir operation.
        #
        #  2) The readdir implementation keeps track of the offsets of the directory entries.  It uses the offset
        #  parameter to restart the iteration and yields non-zero offsets for each entry. When the buffer is full, or
        #  an error occurs, yielding to the filler function will return false. Subsequent yields will raise
        #  StopIteration
        #
        #  3) Return a Dir like object from {opendir} and do not implement this method.  The directory
        #    will be enumerated from offset via calling :seek, :read and :tell on fuse_file_info.fh
        #
        #  @param [String] path
        #  @param [Integer] offset the starting offset (inclusive!)
        #
        #   this is either 0 for a new operation, or the last value previously yielded to the filler function
        #   (when it returned false to indicate the buffer was full).
        #
        #  @param [FuseFileInfo] fuse_file_info
        #  @param [Boolean] readdir_plus true if extended readdir is supported (Fuse3 only)
        #  @raise [SystemCallError] an appropriate Errno value
        #  @return [void]
        #  @yield [name,stat:,offset:,fill_dir_plus:]
        #    See {ReaddirFiller#fill}
        #  @see FuseOperations#readdir
        #  @see ReaddirFiller#fill

        # @!method getxattr(path,name)
        #  @abstract
        #  Get extended attribute
        #  @param [String] path
        #  @param [String] name the attribute name
        #  @return [nil|String] the attribute value or nil if it does not exist
        #  @see FuseOperations#getxattr

        # @!method listxattr(path)
        #  @abstract
        #  List extended attributes
        #  @param [String] path
        #  @return [Array<String>] list of xattribute names
        #  @see FuseOperations#listxattr

        # @!method setxattr(path, name, data, flags)
        #  @abstract
        #  Set extended attribute
        #  @param [String] path
        #  @param [String] name
        #  @param [String] data
        #  @param [Symbol|Integer] flags 0, :xattr_create, :xattr_replace
        #  @return [void]
        #  @raise [Errno::EEXIST] for :xattr_create and name already exists
        #  @raise [Errno::ENODATA] for :xattr_replace and name does not already exist
        #  @see FuseOperations#setxattr

        # @!method utimens(path,atime,mtime,fuse_file_info=nil)
        #  @abstract
        #  Change the access and/or modification times of a file with nanosecond resolution
        #
        #  @param [String] path
        #  @param [Time|nil] atime if set the file's new access time (in UTC)
        #  @param [Time|nil] mtime if set the file's new modification time (in UTC)
        #  @param [FuseFileInfo] fuse_file_info (since Fuse3)
        #  @return [void]
        #  @see FuseOperations#utimens
        #
        #  @note
        #   Either atime or mtime can be nil corresponding to utimensat(2) receiving UTIME_OMIT.
        #   The special value UTIME_NOW passed from Fuse is automatically set to the current time

        # @!method fsync(path, datasync, fuse_file_info)
        #  @abstract
        #  @param [String] path
        #  @param [Boolean] datasync if true only the user data should be flushed, not the meta data.
        #  @param [FuseFileInfo] fuse_file_info

        # @!endgroup

        # @!visibility private
        def self.included(mod)
          mod.prepend(Prepend)
          mod.include(Context)
          mod.include(Debug)
          mod.include(Safe)
        end

        class << self
          # Helper for implementing {FuseOperations#readlink}
          # @param [FFI::Pointer] buf
          # @param [Integer] size
          # @yield []
          # @yieldreturn [String] the link name
          # @raise [Errno::ENOTSUP] if no data is returned
          # @raise [Errno::ENAMETOOLONG] if data returned is larger than size
          # @return [void]
          def readlink(buf, size)
            link = yield
            raise Errno::ENOTSUP unless link
            raise Errno::ENAMETOOLONG unless link.size < size # includes terminating NUL

            buf.put_string(link)
            0
          end

          # Helper for implementing {FuseOperations#read}
          # @param [FFI::Pointer] buf
          # @param [Integer] size
          # @param [Integer] offset
          # @return [Integer] size of data read
          # @yield []
          # @yieldreturn [String, #pread, #pwrite] the resulting data or IO like object
          # @raise [Errno::ENOTSUP] if no data is returned
          # @raise [Errno::ERANGE] if data return is larger than size
          # @see data_to_str
          def read(buf, size, offset = 0)
            data = yield
            raise Errno::ENOTSUP unless data

            return data unless buf # called from read_buf

            data = data_to_str(data, size, offset)
            raise Errno::ERANGE unless data.size <= size

            buf.write_bytes(data)
            data.size
          end

          # Helper for implementing {FuseOperations#read_buf}
          # @param [FFI::Pointer] bufp
          # @param [Integer] size
          # @param [Integer] offset
          # @yield []
          # @yieldreturn [Integer|:fileno|String,:pread,:pwrite] a file descriptor, String or io like object
          # @see data_to_bufvec
          def read_buf(bufp, size, offset)
            data = yield
            raise Errno::ENOTSUP unless data

            bufp.write_pointer(data_to_bufvec(data, size, offset).to_ptr)
            0
          end

          # Helper to convert input data to a string for use with {FuseOperations#read}
          # @param [String|:pread|:read] io input data that is a String or quacks like {::IO}
          # @param [Integer] size
          # @param [Integer] offset
          # @return [String] extracted data
          def data_to_str(io, size, offset)
            return io if io.is_a?(String)
            return io.pread(size, offset) if io.respond_to?(:pread)
            return io.read(size) if io.respond_to?(:read)

            io.to_s
          end

          # Helper to convert string or IO to {FuseBufVec} for {FuseOperations#read_buf}
          # @param [Integer|:fileno|String|:pread|:read] data the io like input data or an integer file descriptor
          # @param [Integer] size
          # @param [Integer] offset
          # @return [FuseBufVec]
          def data_to_bufvec(data, size, offset)
            data = data.fileno if data.respond_to?(:fileno)
            return FuseBufVec.init(autorelease: false, size: size, fd: data, pos: offset) if data.is_a?(Integer)

            str = data_to_str(data, size, offset)
            FuseBufVec.init(autorelease: false, size: str.size, mem: FFI::MemoryPointer.from_string(str))
          end

          # Helper to implement #{FuseOperations#write}
          # @param [FFI::Pointer|:to_s] buf
          # @param [Integer] size
          # @return [Integer] size
          # @yield [data]
          # @yieldparam [String] data extracted from buf
          # @yieldreturn [void]
          def write_data(buf, size)
            data = buf.read_bytes(size) if buf.respond_to?(:read_bytes)
            data ||= buf.to_s
            data = data[0..size] if data.size > size
            yield data
            size
          end

          # Helper to write a data buffer to an open file
          # @param [FFI::Pointer] buf
          # @param [Integer] size
          # @param [Integer] offset
          # @param [:pwrite,:seek,:write] handle an IO like file handle
          # @return [Integer] size
          # @raise [Errno::ENOTSUP] if handle is does not quack like an open file
          def write_fh(buf, size, offset, handle)
            write_data(buf, size) do |data|
              if handle.respond_to?(:pwrite)
                handle.pwrite(data, offset)
              elsif handle.respond_to?(:write)
                handle.seek(offset) if handle.respond_to?(:seek)
                handle.write(data)
              else
                raise Errno::ENOTSUP
              end
            end
          end

          # Helper for implementing {FuseOperations#getxattr}
          #
          # @param [FFI::Pointer] buf
          # @param [Integer] size
          # @yieldreturn [String] the xattr name
          def getxattr(buf, size)
            res = yield
            raise Errno::ENODATA unless res

            res = res.to_s

            return res.size if size.zero?
            raise Errno::ERANGE if res.size > size

            buf.write_bytes(res)
            res.size
          end

          # Helper for implementing {FuseOperations#listxattr}
          # @param [FFI::Pointer] buf
          # @param [Integer] size
          # @yieldreturn [Array<String>] a list of extended attribute names
          def listxattr(buf, size)
            res = yield
            res.reduce(0) do |offset, name|
              name = name.to_s
              unless size.zero?
                raise Errno::ERANGE if offset + name.size >= size

                buf.put_string(offset, name) # put string includes the NUL terminator
              end
              offset + name.size + 1
            end
          end
        end
      end
    end
  end
end
