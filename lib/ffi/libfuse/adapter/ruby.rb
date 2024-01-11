# frozen_string_literal: true

require_relative 'safe'
require_relative 'debug'
require 'set'

module FFI
  module Libfuse
    module Adapter
      # This module assists with converting native C libfuse into idiomatic and duck-typed Ruby behaviour
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
            false
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

            fuse_methods.any? { |m| super(m) }
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

          # Read data from path via
          #
          #  * super as per {Ruby#read} if defined (or returns nil|false)
          #  * ffi.fh as per {Ruby.read}
          def read(path, buf, size, offset, ffi)
            io, super_offset = defined?(super) && Ruby.rescue_not_implemented { super(path, size, offset, ffi) }
            offset = super_offset if io
            io ||= ffi.fh

            return [io, offset] unless buf # nil buf as called from read_buf, just wants the io/data back

            Ruby.read(buf, size, offset) { io }
          end

          # Read data with {FuseBuf}s via
          #
          #  * super if defined
          #  * ffi.fh.fileno if defined and not nil
          #  * result of {#read}
          def read_buf(path, bufp, size, offset, ffi)
            io, super_offset = defined?(super) && Ruby.rescue_not_implemented { super(path, size, offset, ffi) }
            offset = super_offset if io

            io ||= ffi.fh if ffi.fh.is_a?(Integer) || ffi.fh.respond_to?(:fileno)

            io, offset = read(path, nil, size, offset, ffi) unless io

            Ruby.read_buf(bufp, size, offset) { io }
          end

          # Read link name from path via super as per {Ruby#readlink}
          def readlink(path, buf, size)
            raise Errno::ENOTSUP unless defined?(super)

            Ruby.readlink(buf, size) { super(path, size) }
          end

          # Writes data to path via
          #
          #   * super if defined
          #   * ffi.fh if not null and quacks like IO (see {IO.write})
          #
          def write(path, buf, size = buf.size, offset = 0, ffi = nil)
            Ruby.write(buf, size) do |data|
              (defined?(super) && Ruby.rescue_not_implemented { super(path, data, offset, ffi) }) || [ffi&.fh, offset]
            end
          end

          # Writes data to path with {FuseBufVec} via
          #
          #   * super directly if defined and returns truthy
          #   * ffi.fh if it represents a file descriptor
          #   * {#write}
          #
          def write_buf(path, bufv, offset, ffi)
            super_result =
              if defined?(super)
                Ruby.rescue_not_implemented do
                  super(path, offset, ffi) do |fh = nil, *flags|
                    Ruby.write_buf(bufv) { |data| data || [fh, *flags] }
                  end
                end
              end

            return super_result if super_result

            Ruby.write_buf(bufv) do |data|
              # only handle fileno,  otherwise fall back to write (which will try other kinds of IO)
              if data
                # fallback to #write
                write(path, data, data.size, offset, ffi)
              else
                [ffi&.fh.respond_to?(:fileno) && ffi.fh.fileno, offset]
              end
            end
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
            define_method(fuse_method) do |path, ffi|
              super(path, ffi) if fuse_super_respond_to?(fuse_method)
            ensure
              release_handle(ffi)
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

        # @!method write(path,data,offset,ffi)
        #  @abstract
        #  Write file data. If not implemented will pass ffi.fh (from {open}) to {IO.write}
        #  @param [String] path
        #  @param [String] data
        #  @param [Integer] offset
        #  @param [FuseFileInfo] ffi
        #  @return [Integer] number of bytes written (<= data.size)
        #  @return [IO] an IO object (data will be sent to {IO.write})
        #  @return [nil|false] treat as not implemented
        #  @raise [NotImplementedError, Errno::ENOTSUP] treat as not implemented
        #  @see FuseOperations#write

        # @!method write_buf(path,offset,ffi,&buffer)
        #  @abstract
        #  Write buffered data to a file via one of the following techniques
        #
        #  1. Yield object and flags to &buffer to write data directly to a {FuseBufVec}, File or IO
        #     and return the yield result (number of bytes written)
        #
        #  2. Yield with no params (or explicitly nil and flags) to retrieve String data (via {FuseBufVec#copy_to_str})
        #     to write to path@offset, returning the number of bytes written (eg data.size)
        #
        #  3. Return nil, false or do not implement to
        #      * try ffi.fh.fileno (from {#open}) as a file descriptor
        #      * or otherwise fallback to {#write}
        #
        #  @param [String] path
        #  @param [Integer] offset
        #  @param [FuseFileInfo] ffi
        #  @param [Proc] buffer
        #  @yield [io = nil, *flags] Send data to io, or if not set, receive data as a string
        #  @yieldparam [FuseBufVec] io write directly into these buffers via {FuseBufVec.copy_to}
        #  @yieldparam [Integer|:fileno] io write to an open file descriptor via {FuseBufVec.copy_to_fd}
        #  @yieldparam [IO] io quacks like IO passed to {IO.write} to receive data
        #  @yieldparam [nil|false] io pull data from buffers into a String
        #  @yieldparam [Array<Symbol>] flags see {FuseBufVec}
        #  @yieldreturn [String] if io not supplied, the chunk of data to write is returned
        #  @yieldreturn [Integer] the number of bytes written to io
        #  @return [Integer] number of bytes written (<= data.size)
        #  @return [nil|false] treat as not implemented (do not yield AND return nil/false)
        #  @raise [NotImplementedError, Errno::ENOTSUP] treat as not implemented
        #  @see FuseOperations#write_buf

        # @!method read(path,size,offset,ffi)
        #  @abstract
        #  Read file data.
        #
        #  If not implemented will send ffi.fh (from {open}) to {IO.read}
        #  @param [String] path
        #  @param [Integer] size
        #  @param [Integer] offset
        #  @param [FuseFileInfo] ffi
        #  @return [Array<Object,Integer>] io, offset will be passed to {IO.read}(io, size, offset)
        #  @return [nil|false] treat as not implemented
        #  @raise [NotImplementedError, Errno::ENOTSUP] treat as not implemented
        #  @see FuseOperations#read

        # @!method read_buf(path,size,offset,info)
        #  @abstract
        #  Read file data directly from a buffer
        #
        #  If not implemented first tries ffi.fh.fileno (from {#open}) as a file descriptor before
        #  falling back to {#read}
        #  @param [String] path
        #  @param [Integer] size
        #  @param [Integer] offset
        #  @param [FuseFileInfo] info
        #  @return [Array<Object,Integer>] io, offset passed to {FuseBufVec#copy_to_io}(io, offset)
        #  @return [nil|false] treat as not implemented
        #  @raise [NotImplementedError, Errno::ENOTSUP] treat as not implemented
        #  @see FuseOperations#read_buf

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
          # Helper to rescue not implemented or not supported errors from sub-filesystems
          # @return[Object] result of block
          # @return[nil] if block raises NotImplementedError or Errno::ENOTSUP
          def rescue_not_implemented
            yield
          rescue NotImplementedError, Errno::ENOTSUP
            nil
          end

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

            buf.put_string(0, link) # with NULL terminator.
            0
          end

          # Helper for implementing {FuseOperations#read}
          # @param [FFI::Pointer] buf
          # @param [Integer] size
          # @param [Integer, nil] offset
          # @return [Integer] returns the size of data read into buf
          # @yield []
          # @yieldreturn [String, IO] the resulting data or IO like object
          # @raise [Errno::ENOTSUP] if no data is returned
          # @raise [Errno::ERANGE] if data return is larger than size
          # @see Libfuse::IO.read
          def read(buf, size, offset = nil)
            io = yield
            raise Errno::ENOTSUP unless io

            data = Libfuse::IO.read(io, size, offset)
            raise Errno::ERANGE unless data.size <= size

            buf.write_bytes(data)
            data.size
          end

          # Helper for implementing {FuseOperations#read_buf}
          # @param [FFI::Pointer] bufp
          # @param [Integer] size
          # @param [Integer] offset
          # @return [Integer] 0 for success
          # @raise [Errno:ENOTSUP] if no data or io is returned
          # @yield []
          # @yieldreturn [FuseBufVec] list of buffers to read from
          # @yieldreturn [String, IO, Integer, :fileno] String, IO or file_descriptor to read from
          #   (see {FuseBufVec.create})
          def read_buf(bufp, size, offset = nil)
            io = yield
            raise Errno::ENOTSUP unless io

            fbv = io.is_a?(FuseBufVec) ? io : FuseBufVec.create(io, size, offset)
            fbv.store_to(bufp)

            0
          end

          # Helper to implement #{FuseOperations#write}
          # yields the data and receives expects IO to write the data to
          # @param [FFI::Pointer] buf
          # @param [Integer] size
          # @yield(data)
          # @yieldparam [String] data data to write
          # @yieldreturn [nil|false] data has not been handled (raises Errno::ENOTSUP)
          # @yieldreturn [Integer] number of bytes written (will not send to {IO.write})
          # @yieldreturn [IO] to use with {IO.write}
          # @return [Integer] number of bytes written
          # @raise [Errno::ENOTSUP] if nothing is returned from yield
          def write(buf, size)
            data = buf.read_bytes(size) if buf.respond_to?(:read_bytes)
            data ||= buf.to_s

            io, offset = yield data

            raise Errno::ENOSUP unless io
            return io if io.is_a?(Integer)

            Libfuse::IO.write(io, data, offset)
          end

          # Helper to implement #{FuseOperations#write_buf}
          #
          # Yields firstly with data = nil
          # A returned truthy object is sent to buvf.copy_to_io
          # Otherwise yields again with string data from bufv.copy_to_str expecting the caller to write the data
          # and return the number of bytes written
          #
          # @param [FuseBufVec] bufv
          # @yield [data]
          # @yieldparam [nil] data first yield is nil
          # @yieldparam [String] data second yield is the data
          # @yieldreturn [nil, Array<IO,Integer,Symbol...>] io, [offset,] *flags
          #   for first yield can return nil to indicate it wants the data as a string (via second yield)
          #   alternative an object to receive the data via {FuseBufVec#copy_to_io}(io, offset = nil, *flags)
          # @yieldreturn [Integer] second yield must return number of bytes written
          # @return [Integer] number of bytes written
          # @raise [Errno::ENOTSUP] if nothing is returned from either yield
          def write_buf(bufv)
            fh, *flags = yield nil # what kind of result do we want
            return bufv.copy_to_io(fh, offset, *flags) if fh

            data = bufv.copy_to_str(*flags)
            yield data || (raise Errno::ENOTSUP)
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
