# frozen_string_literal: true

require_relative '../accessors'
module FFI
  module Libfuse
    #
    # Configuration of the high-level API
    #
    # This structure is initialized from the arguments passed to fuse_new(), and then passed to the file system's init()
    # handler which should ensure that the configuration is compatible with the file system implementation.
    #
    class FuseConfig < FFI::Struct
      include FFI::Accessors
      layout(
        {
          # @!method set_gid?
          #   @return [Boolean]
          # @!attribute [r] gid
          #   @return [Integer]
          # If `set_gid?` is true the st_gid attribute of each file is overwritten with the value of `gid`.
          #
          set_gid: :int,
          gid: :uint,

          # @!method set_uid?
          #   @return [Boolean]
          # @!attribute [r] uid
          #   @return [Integer]
          # If `set_uid?' is true the st_uid attribute of each file is overwritten with the value of `uid`.
          #
          set_uid: :int,
          uid: :uint,

          # @!method set_mode?
          #   @return [Boolean]
          # @!attribute [r] mode
          #   @return [Integer]
          # If `set_mode?` is true, the any permissions bits set in `umask` are unset in the st_mode attribute of each
          # file.
          #
          set_mode: :int,
          umask: :uint,
          #
          # The timeout in seconds for which name lookups will be
          # cached.
          #
          entry_timeout: :double,
          #
          # The timeout in seconds for which a negative lookup will be
          # cached. This means, that if file did not exist (lookup
          # retuned ENOENT), the lookup will only be redone after the
          # timeout, and the file/directory will be assumed to not
          # exist until then. A value of zero means that negative
          # lookups are not cached.
          #
          negative_timeout: :double,
          #
          # The timeout in seconds for which file/directory attributes
          # (as returned by e.g. the `getattr` handler) are cached.
          #
          attr_timeout: :double,
          #
          # Allow requests to be interrupted
          #
          intr: :int,
          #
          # Specify which signal number to send to the filesystem when
          # a request is interrupted.  The default is hardcoded to
          # USR1.
          #
          intr_signal: :int,
          #
          # Normally, FUSE assigns inodes to paths only for as long as
          # the kernel is aware of them. With this option inodes are
          # instead remembered for at least this many seconds.  This
          # will require more memory, but may be necessary when using
          # applications that make use of inode numbers.
          #
          # A number of -1 means that inodes will be remembered for the
          # entire life-time of the file-system process.
          #
          remember: :int,
          #
          # The default behavior is that if an open file is deleted,
          # the file is renamed to a hidden file (.fuse_hiddenXXX), and
          # only removed when the file is finally released.  This
          # relieves the filesystem implementation of having to deal
          # with this problem. This option disables the hiding
          # behavior, and files are removed immediately in an unlink
          # operation (or in a rename operation which overwrites an
          # existing file).
          #
          # It is recommended that you not use the hard_remove
          # option. When hard_remove is set, the following libc
          # functions fail on unlinked files (returning errno of
          # ENOENT): read(2), write(2), fsync(2), close(2), f*xattr(2),
          # ftruncate(2), fstat(2), fchmod(2), fchown(2)
          #
          hard_remove: :int,
          #
          # Honor the st_ino field in the functions getattr() and
          # fill_dir(). This value is used to fill in the st_ino field
          # in the stat(2), lstat(2), fstat(2) functions and the d_ino
          # field in the readdir(2) function. The filesystem does not
          # have to guarantee uniqueness, however some applications
          # rely on this value being unique for the whole filesystem.
          #
          # Note that this does *not* affect the inode that libfuse
          # and the kernel use internally (also called the "nodeid").
          #
          use_ino: :int,
          #
          # If use_ino option is not given, still try to fill in the
          # d_ino field in readdir(2). If the name was previously
          # looked up, and is still in the cache, the inode number
          # found there will be used.  Otherwise it will be set to -1.
          # If use_ino option is given, this option is ignored.
          #
          readdir_ino: :int,
          #
          # This option disables the use of page cache (file content cache)
          # in the kernel for this filesystem. This has several affects:
          #
          # 1. Each read(2) or write(2) system call will initiate one
          #    or more read or write operations, data will not be
          #    cached in the kernel.
          #
          # 2. The return value of the read() and write() system calls
          #    will correspond to the return values of the read and
          #    write operations. This is useful for example if the
          #    file size is not known in advance (before reading it).
          #
          # Internally, enabling this option causes fuse to set the
          # `direct_io` field of `struct fuse_file_info` - overwriting
          # any value that was put there by the file system.
          #
          direct_io: :int,
          #
          # This option disables flushing the cache of the file
          # contents on every open(2).  This should only be enabled on
          # filesystem where the file data is never changed
          # externally (not through the mounted FUSE filesystem).  Thus
          # it is not suitable for network filesystem and other
          # intermediate filesystem.
          #
          # NOTE: if this option is not specified (and neither
          # direct_io) data is still cached after the open(2), so a
          # read(2) system call will not always initiate a read
          # operation.
          #
          # Internally, enabling this option causes fuse to set the
          # `keep_cache` field of `struct fuse_file_info` - overwriting
          # any value that was put there by the file system.
          #
          kernel_cache: :int,
          #
          # This option is an alternative to `kernel_cache`. Instead of
          # unconditionally keeping cached data, the cached data is
          # invalidated on open(2) if if the modification time or the
          # size of the file has changed since it was last opened.
          #
          auto_cache: :int,
          #
          # The timeout in seconds for which file attributes are cached
          # for the purpose of checking if auto_cache should flush the
          # file data on open.
          #
          ac_attr_timeout_set: :int,
          ac_attr_timeout: :double,
          #
          # If this option is given the file-system handlers for the
          # following operations will not receive path information:
          # read, write, flush, release, fsync, readdir, releasedir,
          # fsyncdir, lock, ioctl and poll.
          #
          # For the truncate, getattr, chmod, chown and utimens
          # operations the path will be provided only if the struct
          # fuse_file_info argument is NULL.
          #
          nullpath_ok: :int,
          #
          # The remaining options are used by libfuse internally and
          # should not be touched.
          #
          show_help: :int,
          modules: :pointer,
          debug: :int
        }
      )

      BOOL_ATTRS = %i[
        nullpath_ok ac_attr_timeout_set auto_cache kernel_cache direct_io
        readdir_ino use_ino hard_remove intr set_mode set_uid set_gid
      ].freeze

      ffi_attr_reader(*BOOL_ATTRS)
      ffi_attr_writer(*BOOL_ATTRS) { |v| v && v != 0 ? 1 : 0 }
      BOOL_ATTRS.each { |a| define_method("#{a}?") { send(a) != 0 } }

      OTHER_ATTRS = %i[ac_attr_timeout remember intr_signal attr_timeout negative_timeout entry_timeout umask uid
                       gid].freeze
      ffi_attr_accessor(*OTHER_ATTRS)
    end
  end
end
