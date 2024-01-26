# frozen_string_literal: true

require_relative '../accessors'
require_relative '../boolean_int'
module FFI
  module Libfuse
    #
    # Configuration of the high-level API
    #
    # This structure is initialized from the arguments passed to fuse_new(), and then passed to the file system's init()
    # handler which should ensure that the configuration is compatible with the file system implementation.
    #
    # Some options can only be set via the filesystem init method (:use_ino etc..) because the filesystem either
    # supports them or it doesn't.
    class FuseConfig < FFI::Struct
      include FFI::Accessors

      spec =
        {
          # @!attribute [r] gid
          # @return [Integer|nil] if set, this value will be used for the :gid attribute of each file
          set_gid: :bool_int,
          gid: :uint,

          # @!attribute [r] uid
          # @return [Integer|nil] if set, this value will be used for the :uid attribute of each file
          set_uid: :bool_int,
          uid: :uint,

          # @!attribute [r] umask
          # @return [Integer|nil] if set, this mask will be applied to the mode attribute of each file
          set_mode: :bool_int,
          umask: :uint,

          # @!attribute [rw] entry_timeout
          # The timeout in seconds for which name lookups will be cached.
          # @return [Float]
          entry_timeout: :double,

          # @!attribute [rw] negative_timeout
          # The timeout in seconds for which a negative lookup will be cached.
          #
          # This means, that if file did not exist (lookup returned ENOENT), the lookup will only be redone after the
          # timeout, and the file/directory will be assumed to not exist until then. A value of zero means that
          # negative lookups are not cached.
          #
          # @return [Float]
          negative_timeout: :double,

          # @!attribute [rw] attr_timeout
          # The timeout in seconds for which file/directory attributes
          #
          #  (as returned by e.g. the `getattr` handler) are cached.
          #
          # @return [Float]
          attr_timeout: :double,

          # @!attribute [rw] intr?
          # Allow requests to be interrupted
          # @return [Boolean]
          intr: :bool_int,

          # @!attribute [rw] intr_signal
          # Which signal number to send to the filesystem when a request is interrupted.
          #
          # The default is hardcoded to USR1.
          #
          # @return [Integer]
          intr_signal: :int,

          # @!attribute [rw] remember
          # the number of seconds inodes are remembered
          #
          # Normally, FUSE assigns inodes to paths only for as long as the kernel is aware of them. With this option
          # inodes are instead remembered for at least this many seconds.  This will require more memory, but may be
          # necessary when using applications that make use of inode numbers.
          #
          # A number of -1 means that inodes will be remembered for the entire life-time of the file-system process.
          #
          # @return [Integer]
          remember: :int,

          # @!attribute [rw] hard_remove?
          # should open files be removed immediately
          #
          # The default behavior is that if an open file is deleted, the file is renamed to a hidden file
          # (.fuse_hiddenXXX), and only removed when the file is finally released.  This relieves the filesystem
          # implementation of having to deal with this problem. This option disables the hiding behavior, and files are
          # removed immediately in an unlink operation (or in a rename operation which overwrites an existing file).
          #
          # It is recommended that you not use the hard_remove option. When hard_remove is set, the following libc
          # functions fail on unlinked files (returning errno of ENOENT): read(2), write(2), fsync(2), close(2),
          # f*xattr(2), ftruncate(2), fstat(2), fchmod(2), fchown(2)
          #
          # @return [Boolean]
          hard_remove: :bool_int,

          # @!attribute [rw] use_ino?
          # use filesystem provided inode values
          #
          # Honor the st_ino field in the functions getattr() and fill_dir(). This value is used to fill in the st_ino
          # field in the stat(2), lstat(2), fstat(2) functions and the d_ino field in the readdir(2) function. The
          # filesystem does not have to guarantee uniqueness, however some applications rely on this value being unique
          # for the whole filesystem.
          #
          # Note that this does *not* affect the inode that libfuse and the kernel use internally (also called the
          # "nodeid").
          #
          # @return [Boolean]
          use_ino: :bool_int,

          # @!attribute [rw] readdir_ino?
          # generate inodes for readdir even if {#use_ino?} is set
          #
          # If use_ino option is not given, still try to fill in the d_ino field in readdir(2). If the name was
          # previously looked up, and is still in the cache, the inode number found there will be used.  Otherwise it
          # will be set to -1. If use_ino option is given, this option is ignored.
          # @return [Boolean]
          readdir_ino: :bool_int,

          # @!attribute [rw] direct_io?
          # disables the use of kernel page cache (file content cache) in the kernel for this filesystem.
          #
          # This has several affects:
          #
          # 1. Each read(2) or write(2) system call will initiate one or more read or write operations, data will not be
          #    cached in the kernel.
          #
          # 2. The return value of the read() and write() system calls will correspond to the return values of the read
          #    and write operations. This is useful for example if the file size is not known in advance (before reading
          #    it).
          #
          # Internally, enabling this option causes fuse to set {FuseFileInfo#direct_io} overwriting any value that was
          # put there by the file system during :open
          # @return [Boolean]
          direct_io: :bool_int,

          # @!attribute [rw] kernel_cache?
          # disables flushing the cache of the file contents on every open(2).
          #
          # This should only be enabled on filesystem where the file data is never changed externally (not through the
          # mounted FUSE filesystem).  Thus it is not suitable for network filesystem and other intermediate filesystem.
          #
          # **Note**:  if neither this option or {#direct_io?} is specified data is still cached after the open(2),
          # so a read(2) system call will not always initiate a read operation.
          #
          # Internally, enabling this option causes fuse to set {FuseFileInfo#keep_cache} overwriting any value that was
          # put there by the file system.
          # @return [Boolean]
          kernel_cache: :bool_int,

          # @!attribute [rw] auto_cache?
          # invalidate cached data on open based on changes in file attributes
          #
          # This option is an alternative to `kernel_cache`. Instead of unconditionally keeping cached data, the cached
          # data is invalidated on open(2) if if the modification time or the size of the file has changed since it was
          # last opened.
          # @return [Boolean]
          auto_cache: :bool_int,

          # @!attribute [rw] ac_attr_timeout
          #  if set the timeout in seconds for which file attributes are cached for the purpose of checking if
          #  auto_cache should flush the file data on open.
          # @return [Float|nil]
          ac_attr_timeout_set: :bool_int,
          ac_attr_timeout: :double,

          # @!attribute [rw] nullpath_ok?
          # operations on open files and directories are ok to receive nil paths
          #
          # If this option is given the file-system handlers for the following operations will not receive path
          # information: read, write, flush, release, fsync, readdir, releasedir, fsyncdir, lock, ioctl and poll.
          #
          # For the truncate, getattr, chmod, chown and utimens operations the path will be provided only if the
          # {FuseFileInfo} argument is nil.
          # @return [Boolean]
          nullpath_ok: :bool_int,

          # The remaining options are used by libfuse internally and should not be touched.
          show_help: :bool_int,
          modules: :pointer,
          debug: :bool_int
        }

      layout(spec)

      # Find the attrs that have a corresponding setter (prefix set_ or suffix _set
      # map attr => setter
      setters = spec.keys
                    .map { |k| [k.to_s.sub(/^set_/, '').sub(/_set$/, '').to_sym, k] }
                    .reject { |(s, a)| s == a }
                    .to_h

      ffi_attr_reader_method(*setters.keys) do
        self[setters[__method__]] ? self[__method__] : nil
      end

      ffi_attr_writer_method(*setters.keys) do |val|
        self[setters[__method__]] = !val.nil?
        self[__method__] = val || 0
      end

      ffi_attr_reader(:show_help?, :debug?)
      remaining = (spec.keys - setters.keys - setters.values - %i[show_help modules debug])
      ffi_attr_accessor(*remaining.map { |a| spec[a] == :bool_int ? "#{a}?" : a })
    end
  end
end
