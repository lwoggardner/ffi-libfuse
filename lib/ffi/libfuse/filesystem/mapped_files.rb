# frozen_string_literal: true

require_relative '../adapter'
require_relative 'accounting'

module FFI
  module Libfuse
    module Filesystem
      # An abstract filesystem mapping paths to either real files or an alternate filesystem based on outcome of
      # {#map_path} as implemented by including class
      #
      # Real files permissions are made read-only by default. Including classes can override {#stat_mask} to
      # change this behaviour
      #
      # Implements callbacks satisfying {Adapter::Ruby} which is automatically included.
      module MappedFiles
        # Do we have ffi-xattr to handle extended attributes in real files
        HAS_XATTR =
          begin
            require 'ffi-xattr'
            true
          rescue LoadError
            false
          end

        # @return [Accounting|nil]
        #   if set the accounting object will be used to provide {#statfs} for the root path
        # @note the real LIBC statvfs is always used for non-root paths
        attr_accessor :accounting

        # @!method map_path(path)
        #  @abstract
        #  @param [String] path the path in the fuse filesystem
        #  @return [String] mapped_path in an underlying filesystem
        #
        #    Fuse callbacks are fulfilled using Ruby's native File methods called on this path
        #  @return [String, Adapter::Ruby::Prepend] mapped_path, filesystem
        #
        #    If an optional filesystem value is returned fuse callbacks will be passed on to this filesystem with the
        #    mapped_path and other callback args unchanged
        #  @return [nil]
        #
        #    eg on create to indicate the path does not exist

        # Manipulate file attributes
        #
        # Default implementation forces read-only permissions
        # @overload stat_mask(path,stat)
        #   @param [String] path the path received by {#getattr}
        #   @param [FFI::Stat] stat loaded from the mapped file, can be filled, mapped as necessary
        #   @return [FFI::Stat] stat
        def stat_mask(_path, stat)
          stat.mask(0o0222)
        end

        # @!group FUSE Callbacks

        # Pass to real stat and then {#stat_mask}
        def getattr(path, stat, ffi = nil)
          if (fd = ffi&.fh&.fileno)
            stat.fstat(fd)
          else
            path_method(__method__, path, stat, ffi) { |rp| stat.stat(rp) }
          end

          stat_mask(path, stat)
        end

        # Create real file - assuming the path can be mapped before it exists
        def create(path, perms, ffi)
          path_method(__method__, path, perms, ffi, error: Errno::EROFS) do |rp|
            File.open(rp, ffi.flags, perms)
          end
        end

        # @return [File] the newly opened file at {#map_path}(path)
        def open(path, ffi)
          path_method(__method__, path, ffi) { |rp| File.open(rp, ffi.flags) }
        end

        # Truncates the file handle (or the real file)
        def truncate(path, size, ffi = nil)
          return ffi.fh.truncate(size) if ffi&.fh

          path_method(__method__, path, size, ffi) { |rp| File.truncate(rp, size) }
        end

        # Delete the real file
        def unlink(path)
          path_method(__method__, path) { |rp| File.unlink(rp) }
        end

        # Calls File.utime on an Integer file handle or the real file
        def utimens(_path, atime, mtime, ffi = nil)
          return File.utime(atime, mtime, ffi.fh) if ffi&.fh.is_a?(Integer)

          path_method(__method__, atime, mtime, ffi) { |rp| File.utime(atime, mtime, rp) }
        end

        # @return [String] the value of the extended attribute name from the real file
        def getxattr(path, name)
          return nil unless HAS_XATTR

          path_method(__method__, path, name) { |rp| Xattr.new(rp)[name] }
        end

        # @return [Array<String>] the list of extended attributes from the real file
        def listxattr(path)
          return [] unless HAS_XATTR

          path_method(__method__, path) { |rp| Xattr.new(rp).list }
        end

        # TODO: Set xattr
        # TODO: chmod, change the stat[:mode]
        # TODO: chown, change the stat[:uid,:gid]

        def statfs(path, statvfs)
          return accounting&.to_statvfs(statvfs) if root?(path)

          path_method(__method__, path, statvfs) { |rp| statvfs.from(rp) }
        end
        # @!endgroup

        # @!visibility private
        def self.included(mod)
          mod.prepend(Adapter::Ruby::Prepend)
        end

        private

        def path_method(callback, path, *args, error: Errno::ENOENT, block: nil)
          rp, fs = map_path(path)
          raise error if error && !rp

          fs ? fs.send(callback, rp, *args, &block) : yield(rp)
        end
      end
    end
  end
end
