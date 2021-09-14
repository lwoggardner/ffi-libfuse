# frozen_string_literal: true

require_relative 'safe'
require_relative 'debug'

module FFI
  module Libfuse
    module Adapter
      # Wrapper module to give more natural ruby signatures to the fuse callbacks, in particular to avoid dealing with
      # FFI Pointers
      #
      # @note includes {Debug} and {Safe}
      module Ruby
        # adapter module prepended to the including module
        # @!visibility private
        # rubocop:disable Metrics/ModuleLength
        module Shim
          include Adapter

          # Fuse3 support outer module can override this
          def fuse3_compat?
            FUSE_MAJOR_VERSION >= 3
          end

          def write(*args)
            *pre, path, buf, size, offset, info = args
            super(*pre, path, buf.read_bytes(size), offset, info)
            size
          end

          def read(*args)
            *pre, path, buf, size, offset, info = args
            res = super(*pre, path, size, offset, info)

            return -Errno::ERANGE::Errno unless res.size <= size

            buf.write_bytes(res)
            res.size
          end

          def readlink(*args)
            *pre, path, buf, size = args
            link = super(*pre, path)
            buf.write_bytes(link, [0..size])
            0
          end

          # rubocop:disable Metrics/AbcSize

          # changes args (removes buf and filler), processes return, changes block
          # *pre, path, buf, filler, offset, fuse_file_info, flag = nil
          def readdir(*args)
            flag_arg = args.pop if fuse3_compat?
            *pre, buf, filler, offset, fuse_file_info = args
            args = pre + [offset, fuse_file_info]
            args << flag_arg if fuse3_compat?
            buffer_available = true
            super(*args) do |name, stat, buffered = false, flag = 0|
              raise StopIteration unless buffer_available

              offset = buffered if buffered.is_a?(Integer)
              offset += 1 if buffered && !buffered.is_a?(Integer) # auto-track offsets
              stat = Stat.new.fill(stat) if stat && !stat.is_a?(Stat)
              filler_args = [buf, name, stat, offset]
              filler_args << flag if fuse3_compat?
              buffer_available = filler.call(*filler_args).zero?
            end
          end
          # rubocop:enable Metrics/AbcSize

          def setxattr(*args)
            # fuse converts the void* data buffer to a const char* null terminated string
            # which libfuse reads directly, so size is irrelevant
            *pre, path, name, data, _size, flags = args
            super(*pre, path, name, data, flags)
          end

          def getxattr(*args)
            *pre, path, name, buf, size = args
            res = super(*pre, path, name)

            return -Errno::ENODATA::Errno unless res

            res = res.to_s

            return res.size if size.zero?
            return -Errno::ERANGE::Errno if res.size > size

            buf.write_bytes(res)
            res.size
          end

          def listxattr(*args)
            *pre, path, buf, size = args
            res = super(*pre, path)
            res.reduce(0) do |offset, name|
              name = name.to_s
              unless size.zero?
                return -Errno::ERANGE::Errno if offset + name.size >= size

                buf.put_string(offset, name) # put string includes the NUL terminator
              end
              offset + name.size + 1
            end
          end

          def read_buf(*args)
            *pre, path, bufp, size, offset, fuse_file_info = args
            buf = FuseBufVec.new
            super(*pre, path, buf, size, offset, fuse_file_info)
            bufp.put_pointer(0, buf)
            0
          end

          # extract atime, mtime from times array, convert from FFI::Stat::TimeSpec to ruby Time
          def utimens(*args)
            ffi = args.pop if fuse3_compat?
            *pre, path, times = args

            # Empty times means set both to current time
            times = [Stat::TimeSpec.now, Stat::TimeSpec.now] unless times&.size == 2

            # If both times are set to UTIME_NOW, make sure they get the same value!
            now = times.any?(&:now?) && Time.now
            atime, mtime = times.map { |t| t.time(now) }

            args = pre + [path, atime, mtime]
            args << ffi if fuse3_compat?
            super(*args)
            0
          end

          # accept a filehandle object as result of these methods
          # keep a reference to the filehandle until corresponding release
          %i[create open opendir].each do |fuse_method|
            define_method(fuse_method) do |*args|
              fh = super(*args)
              store_filehandle(args.last, fh)
              0
            end
          end

          %i[release release_dir].each do |fuse_method|
            define_method(fuse_method) do |*args|
              super(*args)
            ensure
              release_filehandle(args.last)
            end
          end

          private

          def store_filehandle(ffi, filehandle)
            return unless filehandle

            @filehandles ||= {}
            @filehandles[ffi]
            ffi.fh = filehandle
          end

          def release_filehandle(ffi)
            return unless ffi.fh

            @filehandles.delete(ffi.fh.object_id)
          end
        end
        # rubocop:enable Metrics/ModuleLength

        # @!group FUSE Callbacks

        # @!method open(path,fuse_file_info)
        #  File open
        #  @abstract
        #  @param [String] path
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [Object] file handle (available to future operations in fuse_file_info.fh)
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
        #  Write file data
        #  @abstract
        #  @param [String] path
        #  @param [String] data
        #  @param [Integer] offset
        #  @param [FuseFileInfo] info
        #  @return [void]
        #  @see FuseOperations#write

        # @!method read(path,size,offset,info)
        #  @abstract
        #  Read file data
        #
        #  @param [String] path
        #  @param [Integer] size
        #  @param [Integer] offset
        #  @param [FuseFileInfo] info
        #
        #  @return [String] the data, expected to be exactly size bytes, except if EOF
        #  @see FuseOperations#read

        # @!method readlink(path)
        #  @abstract
        #  Resolve target of a symbolic link
        #  @param [String] path
        #  @return [String] the link target
        #  @see FuseOperations#readlink

        # @!method readdir(path,offset,fuse_file_info,&filler)
        #  @abstract
        #  List directory entries
        #
        #  The filesystem may choose between two modes of operation:
        #
        #  1) The readdir implementation ignores the offset parameter yielding only name, stat pairs for each entry.
        #  The yield will always return true so the whole directory is read in a single readdir operation.
        #
        #  2) The readdir implementation keeps track of the offsets of the directory entries.  It uses the offset
        #  parameter and always yields buffered=true to the filler function. When the buffer is full, or an error
        #  occurs, yielding to the filler function will return false. Subsequent yields will raise StopIteration
        #
        #  @param [String] path
        #  @param [Integer] offset the starting offset (inclusive!)
        #
        #   this is either 0 for a new operation, or the last value previously yielded to the filler function
        #   (when it returned false to indicate the buffer was full). Type 2 implementations should therefore include
        #
        #  @param [FuseFileInfo] fuse_file_info
        #
        #  @raise [SystemCallError] an appropriate Errno value
        #  @return [void]
        #
        #  @yieldparam [String] name the name of a directory entry
        #  @yieldparam [Stat|nil] stat the directory entry stat
        #
        #    Note sending nil values will cause Fuse to issue #getattr operations for each entry
        #
        #  @yieldparam [Integer|Boolean] offset (optional - default false)
        #
        #   integer value will be used as offset.  The last value yielded (with false return) will be used
        #   for the next readdir call
        #
        #   otherwise truthy to indicate support for restart from monotonically increasing offset
        #
        #   false to indicate type 1 operation - full listing
        #
        #  @yieldreturn [Boolean]
        #
        #   * true if buffer accepted the directory entry
        #   * false on first time buffer is full.  StopIteration will be raised on subsequent yields
        #
        #  @see FuseOperations#readdir

        # @!method getxattr(path,name)
        #  @abstract
        #  Get extended attribute
        #  @param [String] path
        #  @param [String] name the attribute name
        #  @return [nil|String] the attribute value or nil if it does not exist
        #  @see FuseOperations#getxattr

        # @!method listxattr(path,name)
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

        # @!method read_buf(path,buffers,size,offset,fuse_file_info)
        #  @abstract
        #  Read through fuse data buffers
        #  @param [String] path
        #  @param [FuseBufVec] buffers
        #  @param [Integer] size
        #  @param [Integer] offset
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [void]
        #  @see FuseOperations#read_buf

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

        # @!endgroup

        # @!visibility private
        def self.included(mod)
          mod.prepend(Shim)
          mod.include(Safe)
          mod.include(Debug)
        end
      end
    end
  end
end
