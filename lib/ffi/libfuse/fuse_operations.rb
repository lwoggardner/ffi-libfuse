# frozen_string_literal: true

require_relative 'fuse_version'
require_relative '../ruby_object'
require_relative 'fuse_conn_info'
require_relative 'fuse_buffer'
require_relative 'fuse_context'
require_relative 'fuse_file_info'
require_relative 'fuse_poll_handle'
require_relative '../stat_vfs'
require_relative '../flock'
require_relative 'thread_pool'
require_relative '../stat'
require_relative '../struct_array'
require_relative '../encoding'
require_relative 'fuse_callbacks'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    # All paths are encoded in ruby's view of the filesystem encoding
    typedef Encoding.for('filesystem'), :fs_string

    # typedef int (*fuse_fill_dir_t) (void *buf, const char *name, const struct stat *stbuf, off_t off);
    fill_dir_t_args = [:pointer, :fs_string, Stat.by_ref, :off_t]
    if FUSE_MAJOR_VERSION > 2
      enum :fuse_readdir_flags, [:fuse_readdir_plus, (1 << 0)]
      enum :fuse_fill_dir_flags, [:fuse_fill_dir_plus, (1 << 1)]
      fill_dir_t_args << :fuse_fill_dir_flags
    end

    bitmask :fuse_ioctl_flags, %i[compat unrestricted retry dir]
    bitmask :lock_op, [:lock_sh, 0, :lock_ex, 2, :lock_nb, 4, :lock_un, 8]
    bitmask :falloc_mode, %i[keep_size punch_hole no_hide_stale collapse_range zero_range insert_range unshare_range]
    bitmask :flags_mask, %i[nullpath_ok nopath utime_omit_ok] if FUSE_MAJOR_VERSION < 3

    # @!visibility private
    XAttr = enum :xattr, [:xattr_create, 1, :xattr_replace]

    callback :fill_dir_t, fill_dir_t_args, :int

    # The file system operations as specified in libfuse.
    #
    # All Callback methods are optional, but some are essential for a useful filesystem
    # e.g. {getattr},{readdir}
    #
    # Almost all callback operations take a path which can be of any length and will return 0 for success, or raise a
    # {::SystemCallError} on failure
    #
    class FuseOperations < FFI::Struct
      include FuseCallbacks

      # Callbacks that are expected to return meaningful positive integers
      MEANINGFUL_RETURN = %i[read write write_buf lseek copy_file_range getxattr listxattr].freeze

      # @return [Boolean] true if fuse_callback expects a meaningful integer return
      def self.meaningful_return?(fuse_callback)
        MEANINGFUL_RETURN.include?(fuse_callback)
      end

      # Container to dynamically build up the operations layout which is dependent on the loaded libfuse version
      op = {}

      # @!group FUSE Callbacks

      # @!method getattr(path,stat,fuse_file_info = nil)
      #   @abstract
      #   Get file attributes.
      #
      #   Similar to stat().  The 'st_dev' and 'st_blksize' fields are ignored. The 'st_ino' field is ignored
      #   except if the 'use_ino' mount option is given.
      #
      #   @param [String] path
      #   @param [Stat] stat to be filled with result information
      #   @param [FuseFileInfo] fuse_file_info
      #     will always be nil if the file is not currently open, but may also be nil if the file is open.
      #   @return [Integer] 0 for success or -ve Errno value

      #   int (*getattr) (const char *, struct stat *);
      op[:getattr] = [Stat.by_ref]
      op[:getattr] << FuseFileInfo.by_ref if FUSE_MAJOR_VERSION >= 3

      # @!method readlink(path, target_buffer, buffer_size)
      #   @abstract
      #   Resolve the target of a symbolic link
      #
      #   @param [String] path
      #   @param [FFI::Pointer] target_buffer
      #
      #     The buffer should be filled with a null terminated string.  The buffer size argument includes the space for
      #     the terminating null character.	If the linkname is too long to fit in the buffer, it should be truncated.
      #
      #   @param [Integer] buffer_size
      #
      #   @return [Integer] 0 for success.

      # int (*readlink) (const char *, char *, size_t);
      op[:readlink] = %i[pointer size_t]

      # @!method getdir
      # @deprecated use {readdir} instead

      # int (*getdir) (const char *, fuse_dirh_t, fuse_dirfil_t);
      op[:getdir] = %i[pointer pointer] if FUSE_MAJOR_VERSION < 3

      # @!method mknod(path,mode,dev)
      #  Create a file node
      #
      #  @param [String] path
      #  @param [Integer] mode
      #  @param [Integer] dev
      #  This is called for creation of all non-directory, non-symlink nodes.  If the filesystem defines a create()
      #  method, then for regular files that will be called instead.
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*mknod) (const char *, mode_t, dev_t);
      op[:mknod] = %i[mode_t dev_t]

      # @!method mkdir(path,mode)
      #  @abstract
      #  Create a directory
      #
      #  @param [String] path
      #  @param [Integer] mode
      #  Note that the mode argument may not have the type specification bits set, i.e. S_ISDIR(mode) can be false.  To
      #  obtain the correct directory type bits use mode | {FFI::Stat::S_IFDIR}
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*mkdir) (const char *, mode_t);
      op[:mkdir] = [:mode_t]

      # @!method unlink(path)
      #  @abstract
      #  Remove a file
      #  @param [String] path
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*unlink) (const char *);
      op[:unlink] = []

      # @!method rmdir(path)
      #  @abstract
      #  Remove a directory
      #  @param [String] path
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*rmdir) (const char *);
      op[:rmdir] = []

      # @!method symlink(path,target)
      #  @abstract
      #  Create a symbolic link
      #  @param [String] path
      #  @param [String] target the link target
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*symlink) (const char *, const char *);
      op[:symlink] = [:fs_string]

      # @!method rename(from_path,to_path)
      #  @abstract
      #  Rename a file
      #  @param [String] from_path
      #  @param [String] to_path
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*rename) (const char *, const char *);
      op[:rename] = [:fs_string]

      # @!method link(path,target)
      #  @abstract
      #  Create a hard link to a file
      #  @param [String] path
      #  @param [String] target
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*link) (const char *, const char *);
      op[:link] = [:fs_string]

      # @!method chmod(path,mode,fuse_file_info=nil)
      #  @abstract
      #  Change the permission bits of a file
      #  @param [String] path
      #  @param [Integer] mode
      #  @param [FuseFileInfo] fuse_file_info (Fuse3 only)
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*chmod) (const char *, mode_t);
      op[:chmod] = [:mode_t]
      op[:chmod] << FuseFileInfo.by_ref if FUSE_MAJOR_VERSION >= 3

      # @!method chown(path,uid,gid,fuse_file_info=nil)
      #  @abstract
      #  Change the owner and group of a file
      #  @param [String] path
      #  @param [Integer] uid
      #  @param [Integer] gid
      #  @param [FuseFileInfo] fuse_file_info (Fuse3 only)
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*chown) (const char *, uid_t, gid_t);
      op[:chown] = %i[uid_t gid_t]
      op[:chown] << FuseFileInfo.by_ref if FUSE_MAJOR_VERSION >= 3

      # @!method truncate(path,offset,fuse_file_info=nil)
      #  @abstract
      #  Change the size of a file
      #  @param [String] path
      #  @param [Integer] offset
      #  @param [FuseFileInfo] fuse_file_info (Fuse3 only)
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*truncate) (const char *, off_t);
      op[:truncate] = [:off_t]
      op[:truncate] << FuseFileInfo.by_ref if FUSE_MAJOR_VERSION >= 3

      # Not directly implemented see utimens
      # int (*utime) (const char *, struct utimbuf *);
      op[:utime] = [:pointer] if FUSE_MAJOR_VERSION < 3

      # @!method open(path,fuse_file_info)
      #  @abstract
      #  File open operation
      #
      #  No creation (O_CREAT, O_EXCL) and by default also no truncation (O_TRUNC) flags will be passed to open(). If an
      #  application specifies O_TRUNC, fuse first calls truncate() and then open(). Only if 'atomic_o_trunc' has been
      #  specified and kernel version is 2.6.24 or later, O_TRUNC is passed on to open.
      #
      #  Unless the 'default_permissions' mount option is given, open should check if the operation is permitted for the
      #  given flags.
      #
      #  Optionally open may also return an arbitrary filehandle in the fuse_file_info structure, which
      #  will be passed to all file operations.
      #
      #  @param [String] path
      #  @param [FuseFileInfo] fuse_file_info
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*open) (const char *, struct fuse_file_info *);
      op[:open] = [FuseFileInfo.by_ref]

      # @!method read(path,buf,size,offset,fuse_file_info)
      #  @abstract
      #  Read data from an open file
      #  @param [String] path
      #  @param [FFI::Pointer] buf
      #  @param [Integer] size
      #  @param [Integer] offset
      #  @param [FuseFileInfo] fuse_file_info
      #
      #  @return [Integer]
      #    Read should return exactly the number of bytes requested except on EOF or error, otherwise the rest of the
      #    data will be substituted with zeroes.	 An exception to this is when the 'direct_io' mount option is
      #    specified, in which case the return value of the read system call will reflect the return value of this
      #    operation.

      # int (*read) (const char *, char *, size_t, off_t, struct fuse_file_info *);
      op[:read] = [:pointer, :size_t, :off_t, FuseFileInfo.by_ref]

      # @!method write(path, data, size,offset,fuse_file_info)
      #  @abstract
      #  Write data to an open file
      #
      #  @param [String] path
      #  @param [FFI::Pointer] data
      #  @param [Integer] size
      #  @param [Integer] offset
      #  @param [FuseFileInfo] fuse_file_info
      #
      #  @return [Integer]
      #    Write should return exactly the number of bytes requested except on error.	 An exception to this is when the
      #     'direct_io' mount option is specified (see read operation).

      # int (*write) (const char *, const char *, size_t, off_t, struct fuse_file_info *);
      op[:write] = [:pointer, :size_t, :off_t, FuseFileInfo.by_ref]

      # @!method statfs(path,statvfs)
      #  @abstract
      #  Get file system statistics
      #
      #  @param [String] path
      #  @param [StatVfs] statvfs result struct
      #    Note 'frsize', 'favail', 'fsid' and 'flag' fields are ignored
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*statfs) (const char *, struct statvfs *);
      op[:statfs] = [StatVfs.by_ref]

      # @!method flush(path,fuse_file_info)
      #  Possibly flush cached data
      #
      #  BIG NOTE: This is not equivalent to fsync().  It's not a request to sync dirty data.
      #
      #  Flush is called on each close() of a file descriptor.  So if a filesystem wants to return write errors in
      #  close() and the file has cached dirty data, this is a good place to write back data and return any errors.
      #  Since many applications ignore close() errors this is not always useful.
      #
      #  NOTE: The flush() method may be called more than once for each open().	This happens if more than one file
      #  descriptor refers to an opened file due to dup(), dup2() or fork() calls.	It is not possible to determine if a
      #  flush is final, so each flush should be treated equally.  Multiple write-flush sequences are relatively rare,
      #  so this shouldn't be a problem.
      #
      #  Filesystems shouldn't assume that flush will always be called after some writes, or that if will be called at
      #  all.
      #
      #  @param [String] path
      #  @param [FuseFileInfo] fuse_file_info
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*flush) (const char *, struct fuse_file_info *);
      op[:flush] = [FuseFileInfo.by_ref]

      # @!method release(path,fuse_file_info)
      #  Release an open file
      #
      #  Release is called when there are no more references to an open file: all file descriptors are closed and all
      #  memory mappings are unmapped.
      #
      #  For every open() call there will be exactly one release() call with the same flags and file descriptor.	 It is
      #  possible to have a file opened more than once, in which case only the last release will mean, that no more
      #  reads \/ writes will happen on the file.
      #
      #  @param [String] path
      #  @param [FuseFileInfo] fuse_file_info
      #
      #  @return [Integer] The return value of release is ignored.

      # int (*release) (const char *, struct fuse_file_info *);
      op[:release] = [FuseFileInfo.by_ref]

      # @!method fsync(path,datasync,fuse_file_info)
      #  Synchronize file contents
      #
      #  @param [String] path
      #  @param [Integer] datasync If non-zero, then only the user data should be flushed, not the meta data.
      #  @param [FuseFileInfo] fuse_file_info
      #
      #  @return [Integer] 0 for success or -ve errno

      # int (*fsync) (const char *, int, struct fuse_file_info *);
      op[:fsync] = [:int, FuseFileInfo.by_ref]

      # @!method setxattr(path,name,data,size,flags)
      #  @abstract
      #  Set extended attributes
      #  @param [String] path
      #  @param [String] name
      #  @param [String] data
      #  @param [Integer] size
      #  @param [Symbol|Integer] flags (:xattr_create or :xattr_replace)
      #  @return [Integer] 0 for success or -ve errno
      #  @see setxattr(2)

      # int (*setxattr) (const char *, const char *, const char *, size_t, int);
      op[:setxattr] = %i[string string size_t xattr]

      # @!method getxattr(path,name,buf,size)
      #  @abstract
      #  Get extended attributes
      #  @param [String] path
      #  @param [String] name
      #  @param [FFI::Pointer] buf
      #  @param [Integer] size
      #  @return [Integer]
      #  @see getxattr(2)

      # int (*getxattr) (const char *, const char *, char *, size_t);
      op[:getxattr] = %i[string pointer size_t]

      # @!method listxattr(path,buf,size)
      #  @abstract
      #  List extended attributes
      #  @param [String] path
      #  @param [FFI::Pointer] buf
      #  @param [Integer] size
      #  @return [Integer]
      #  @see listxattr(2)

      # int (*listxattr) (const char *, char *, size_t);
      op[:listxattr] = %i[pointer size_t]

      # @!method removexattr(path,name)
      #  @abstract
      #  Remove extended attributes
      #  @param [String] path
      #  @param [String] name
      #  @return [Integer] 0 on success or -ve errno
      #  @see removexattr(2)

      # int (*removexattr) (const char *, const char *);
      op[:removexattr] = [:string]

      if FUSE_VERSION >= 23

        # @!method opendir(path,fuse_file_info)
        #  @abstract
        #  Open directory
        #
        #  Unless the 'default_permissions' mount option is given, this method should check if opendir is permitted for
        #  this directory. Optionally opendir may also return an arbitrary filehandle in the fuse_file_info structure,
        #  which will be passed to readdir, releasedir and fsyncdir.
        #
        # @param [String] path
        # @param [FuseFileInfo] fuse_file_info
        # @return [Integer] 0 for success or -ve errno

        # int (*opendir) (const char *, struct fuse_file_info *);
        op[:opendir] = [FuseFileInfo.by_ref]

        # @!method readdir(path,buffer,filler,offset,fuse_file_info, fuse_readdir_flag = 0)
        #  @abstract
        #  Read directory
        #
        #  The filesystem may choose between two modes of operation:
        #
        #  1) The readdir implementation ignores the offset parameter, and passes zero to the filler function's offset.
        #  The filler function will not return '1' (unless an error happens), so the whole directory is read in a single
        #  readdir operation.
        #
        #  2) The readdir implementation keeps track of the offsets of the directory entries.  It uses the offset
        #  parameter and always passes non-zero offset to the filler function.  When the buffer is full (or an error
        #  happens) the filler function will return '1'.
        #
        #  @param [String] path
        #  @param [FFI::Pointer] buffer
        #  @param [Proc<FFI::Pointer,String,Stat,Integer,Integer=0>] filler the filler function to be called
        #   for each directory entry, ie filler.call(buffer,next_name,next_stat,next_offset, fuse_fill_dir_flag)
        #
        #  @param [Integer] offset the starting offset
        #  @param [FuseFileInfo] fuse_file_info
        #  @param [Symbol] fuse_readdir_flag (Fuse3 only)
        #
        #  @return [Integer] 0 on success or -ve errno
        #

        # int (*readdir) (const char *, void *buf, fuse_fill_dir_t, off_t, struct fuse_file_info *);
        op[:readdir] = [:pointer, :fill_dir_t, :off_t, FuseFileInfo.by_ref]
        op[:readdir] << :fuse_readdir_flags if FUSE_MAJOR_VERSION > 2

        # @!method releasedir(path,fuse_file_info)
        #  Release directory
        #  @param [String] path
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [Integer] 0 for success or -ve errno

        # int (*releasedir) (const char *, struct fuse_file_info *);
        op[:releasedir] = [FuseFileInfo.by_ref]

        # @!method fsyncdir(path,datasync,fuse_file_info)
        #  Synchronize directory contents
        #
        #  @param [String] path
        #  @param [Integer] datasync If non-zero, then only the user data should be flushed, not the meta data
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [Integer] 0 for success or -ve errno

        # int (*fsyncdir) (const char *, int, struct fuse_file_info *);
        op[:fsyncdir] = [:int, FuseFileInfo.by_ref]

        # @!method init(fuse_conn_info,fuse_config=nil)
        #  @abstract
        #  Initialize filesystem
        #
        #  @param [FuseConnInfo] fuse_conn_info
        #  @param [FuseConfig|nil] fuse_config only provided for fuse3 and later
        #
        #  @return [Object]
        #    The return value will passed in the private_data field of fuse_context to all file operations and as a
        #    parameter to the destroy() method.
        #

        # fuse2: void *(*init) (struct fuse_conn_info *conn);
        # fuse3: void *(*init) (struct fuse_conn_info *conn, struct fuse_config *cfg);
        op[:init] =
          if FUSE_MAJOR_VERSION >= 3
            require_relative 'fuse_config'
            callback([FuseConnInfo.by_ref, FuseConfig.by_ref], RubyObject)
          else
            callback([FuseConnInfo.by_ref], RubyObject)
          end

        # @!method destroy(obj)
        #  @abstract
        #  @param [Object] obj - the object passed from {init}.
        #  Clean up filesystem. Called on filesystem exit.

        # void (*destroy) (void *);
        op[:destroy] = callback([RubyObject], :void)
      end

      if FUSE_VERSION >= 25

        # @!method access(path,mode)
        #  @abstract
        #  Check file access permissions
        #
        #  This will be called for the access() system call.  If the 'default_permissions' mount option is given, this
        #  method is not called.
        #
        #  This method is not called under Linux kernel versions 2.4.x
        #
        #  @param [String] path
        #  @param [Integer] mode
        #  @return [Integer] 0 for success or -ve errno
        #  @see access(2)

        # int (*access) (const char *, int);
        op[:access] = [:int]

        # @!method create(path,mode,fuse_file_info)
        #  @abstract
        #  Create and open a file
        #
        #  If the file does not exist, first create it with the specified mode, and then open it.
        #
        #  If this method is not implemented or under Linux kernel versions earlier than 2.6.15, the mknod() and open()
        #  methods will be called instead.
        #
        #  @param [String] path
        #  @param [Integer] mode
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [Integer] 0 for success or -ve errno

        # int (*create) (const char *, mode_t, struct fuse_file_info *);
        op[:create] = [:mode_t, FuseFileInfo.by_ref]

        # @!method ftruncate(path,offset,fuse_file_info)
        #  @deprecated in Fuse3 implement {truncate} instead
        #  @abstract
        #  Change the size of an open file
        #
        #  This method is called instead of the truncate() method if the truncation was invoked from an ftruncate()
        #  system call.
        #
        #  If this method is not implemented or under Linux kernel versions earlier than 2.6.15, the truncate() method
        #  will be called instead.
        #
        #  @param [String] path
        #  @param [Integer] offset
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [Integer] 0 for success or -ve errno

        # int (*ftruncate) (const char *, off_t, struct fuse_file_info *);
        op[:ftruncate] = [:off_t, FuseFileInfo.by_ref] if FUSE_MAJOR_VERSION < 3

        # @!method fgetattr(path,stat,fuse_file_info)
        #  @deprecated in Fuse3 implement {getattr} instead
        #  Get attributes from an open file
        #
        #  This method is called instead of the getattr() method if the file information is available.
        #
        #  Currently this is only called after the create() method if that is implemented (see above).  Later it may be
        #  called for invocations of fstat() too.
        #  @param [String] path
        #  @param [Stat] stat
        #  @param [FuseFileInfo] fuse_file_info
        #  @return [Integer] 0 for success or -ve errno

        # int (*fgetattr) (const char *, struct stat *, struct fuse_file_info *);
        op[:fgetattr] = [Stat, FuseFileInfo.by_ref] if FUSE_MAJOR_VERSION < 3
      end
      if FUSE_VERSION >= 26
        # @!method lock(path,fuse_file_info,cmd,flock)
        #  @abstract
        #
        #  Perform POSIX file locking operation
        #  @param [String] path
        #  @param [FuseFileInfo] fuse_file_info
        #    For checking lock ownership, the 'fuse_file_info->owner' argument must be used.
        #  @param [Symbol] cmd either :getlck, :setlck or :setlkw.
        #  @param [Flock] flock
        #    For the meaning of fields in 'struct flock' see the man page for fcntl(2).  The whence field will always
        #    be set to :seek_set.
        #
        #  @return [Integer] 0 for success or -ve errno
        #
        #  For :f_getlk operation, the library will first check currently held locks, and if a conflicting lock is found
        #  it will return information without calling this method.	 This ensures, that for local locks the pid field
        #  is correctly filled in.	The results may not be accurate in case of race conditions and in the presence of
        #  hard links, but its unlikely that an application would rely on accurate GETLK results in these cases.  If a
        #  conflicting lock is not found, this method will be called, and the filesystem may fill out l_pid by a
        #  meaningful value, or it may leave this field zero.
        #
        #  For :f_setlk and :f_setlkw the pid field will be set to the pid of the process performing the locking
        #  operation.
        #
        #  @note if this method is not implemented, the kernel will still allow file locking to work locally.  Hence it
        #  is only interesting for network filesystem and similar.

        # int (*lock) (const char *, struct fuse_file_info *, int cmd, struct flock *);
        op[:lock] = [FuseFileInfo.by_ref, Flock::Enums::LockCmd, Flock.by_ref]

        # @!method utimens(path,time_specs,fuse_file_info=nil)
        #  @abstract
        #  Change the access and modification times of a file with nanosecond resolution
        #
        #  This supersedes the old utime() interface.  New applications should use this.
        #
        #  @param [String] path
        #  @param [Array<Stat::TimeSpec>] time_specs atime,mtime
        #  @param [FuseFileInfo] fuse_file_info (only since Fuse3)
        #  @return [Integer] 0 for success or -ve errno
        #
        #  @see utimensat(2)
        #

        # int (*utimens) (const char *, const struct timespec tv[2]);
        op[:utimens] = [FFI::Stat::TimeSpec.array(2)]
        op[:utimens] << FuseFileInfo.by_ref if FUSE_MAJOR_VERSION >= 3

        # @!method bmap(path,blocksize,index)
        #  @abstract
        #  Map block index within file to block index within device
        #
        #  @param [String] path
        #  @param [Integer] blocksize
        #  @param [FFI::Pointer] index pointer to index result
        #  @return [Integer] 0 success or -ve errno
        #  @note This makes sense only for block device backed filesystem mounted with the 'blkdev' option

        # int (*bmap) (const char *, size_t blocksize, uint64_t *idx);
        op[:bmap] = %i[size_t pointer]

      end

      # @!method fuse_flags
      #   @abstract
      #   Configuration method to set fuse flags
      #
      #   - :nullpath_ok
      #
      #     Flag indicating that the filesystem can accept a NULL path as the first argument for the following
      #     operations: read, write, flush, release, fsync, readdir, releasedir, fsyncdir, ftruncate, fgetattr, lock,
      #     ioctl and poll
      #
      #     If this flag is set these operations continue to work on unlinked files even if "-ohard_remove" option was
      #     specified.
      #
      #   - :nopath
      #
      #     Flag indicating that the path need not be calculated for the following operations: read, write, flush,
      #     release, fsync, readdir, releasedir, fsyncdir, ftruncate, fgetattr, lock, ioctl and poll
      #
      #     Closely related to flag_nullpath_ok, but if this flag is set then the path will not be calculaged even if
      #     the file wasnt unlinked.  However the path can still be non-NULL if it needs to be calculated for some other
      #     reason.
      #
      #   - :utime_omit_ok
      #
      #     Flag indicating that the filesystem accepts special UTIME_NOW and UTIME_OMIT values in its utimens
      #     operation.
      #
      #   @return [Array[]Symbol>] a list of flags to set capabilities
      #   @note Not available in Fuse3
      #   @deprecated in Fuse3 use fuse_config object in {init}
      op[:flags] = :flags_mask if FUSE_MAJOR_VERSION < 3

      if FUSE_VERSION >= 28

        # @!method ioctl(path,cmd,arg,fuse_file_info, flags,data)
        #  @abstract
        #  Ioctl
        #  @param [String] path
        #  @param [Integer] cmd
        #  @param [FFI::Pointer] arg
        #  @param [FuseFileInfo] fuse_file_info
        #  @param [Array<Symbol>] flags
        #
        #    - :compat       32bit compat ioctl on 64bit machine
        #    - :unrestricted not restricted to well-formed ioctls, retry allowed (lowlevel fuse)
        #    - :retry        retry with new iovecs (lowlevel fuse)
        #    - :dir          is a directory file handle
        #
        #  @param [FFI::Pointer] data
        #
        #  The size and direction of data is determined by _IOC_*() decoding of cmd.  For _IOC_NONE, data will be NULL,
        #  for _IOC_WRITE data is out area, for _IOC_READ in area and if both are set in/out area.  In all non-NULL
        #  cases, the area is of _IOC_SIZE(cmd) bytes.

        # int (*ioctl) (const char *, int cmd, void *arg, struct fuse_file_info *, unsigned int flags, void *data);
        op[:ioctl] = [:int, :pointer, FuseFileInfo.by_ref, :fuse_ioctl_flags, :pointer]

        # @!method poll(path,fuse_file_info,ph,reventsp)
        #  @abstract
        #  Poll for IO readiness events
        #
        #  @param [String] path
        #  @param [FuseFileInfo] fuse_file_info
        #  @param [FusePollHandle|nil] ph
        #    If ph is set, the client should notify when IO readiness events occur by calling
        #    {FusePollHandle#notify_poll} (possibly asynchronously)
        #
        #    Regardless of the number of times poll is received, single notification is enough to clear
        #     all.  Notifying more times incurs overhead but doesnt harm correctness.
        #
        #  @param [FFI::Pointer] reventsp  return events
        #  @return [Integer] 0 for success, -ve for error
        #  @see poll(2)

        # int (*poll) (const char *, struct fuse_file_info *, struct fuse_pollhandle *ph, unsigned *reventsp);
        op[:poll] = [FuseFileInfo.by_ref, FusePollHandle, :pointer]

        # @!method write_buf(path,buf,offset,fuse_file_info)
        #  @abstract
        #  Write contents of buffer to an open file
        #
        #  Similar to the write() method, but data is supplied in a generic buffer.
        #  Use {FuseBufVec#copy_to_fd} to copy data to an open file descriptor, or {FuseBufVec#copy_to_str} to extract
        #  string data from the buffer
        #
        #  @param [String] path
        #  @param [FuseBufVec] buf
        #  @param [Integer] offset
        #  @param [FuseFileInfo] fuse_file_info
        #
        #  @return [Integer] the number of bytes written or -ve errno

        # int (*write_buf) (const char *, struct fuse_bufvec *buf, off_t off, struct fuse_file_info *);
        op[:write_buf] = [FuseBufVec.by_ref, :off_t, FuseFileInfo.by_ref]

        # @!method read_buf(path,bufp,size,offset,fuse_file_info)
        #  @abstract
        #
        #  Similar to the read() method, but data is stored and returned in a generic buffer.
        #
        #  No actual copying of data has to take place, the source file descriptor may simply be stored in the buffer
        #  for later data transfer.
        #
        #  @param [String] path
        #  @param [FFI::Pointer<FuseBufVec>] bufp
        #   The buffer must be allocated dynamically and stored at the location pointed to by bufp.  If the buffer
        #   contains memory regions, they too must be allocated using malloc().  The allocated memory will be freed by
        #   the caller.
        #  @param [Integer] size
        #  @param [Integer] offset
        #  @param [FuseFileInfo] fuse_file_info
        #  @return 0 success or -ve errno

        # int (*read_buf) (const char *, struct fuse_bufvec **bufp, size_t size, off_t off, struct fuse_file_info *);
        op[:read_buf] = [:pointer, :size_t, :off_t, FuseFileInfo.by_ref]

        # @!method flock(path,fuse_file_info,op)
        #  @abstract
        #  Perform BSD file locking operation
        #
        #  @param [String] path
        #  @param [FuseFileInfo] fuse_file_info
        #   Additionally fi->owner will be set to a value unique to this open file. This same value will be supplied
        #   to {release} when the file is released.
        #  @param [Array<Symbol>] op the lock operation
        #   The op argument will contain one of :lock_sh, :lock_ex, or :lock_un
        #   Nonblocking requests also include :lock_nb
        #  @return 0 or -ve errno
        #  @see flock(2)
        #
        #  @note: if this method is not implemented, the kernel will still allow file locking to work locally.  Hence it
        #  is only interesting for network filesystem and similar.

        # int (*flock) (const char *, struct fuse_file_info *, int op);
        op[:flock] = [FuseFileInfo.by_ref, :lock_op]

        # @!method fallocate(path,mode,offset,len,fuse_file_info)
        #  @abstract
        #  Allocates space for an open file
        #
        #  This function ensures that required space is allocated for specified file.  If this function returns success
        #  then any subsequent write request to specified range is guaranteed not to fail because of lack of space on
        #  the file system media.
        #
        #  @param [String] path
        #  @param [Array<Symbol>] mode allocation mode flags
        #    :keep_size :punch_hole :no_hide_stale :collapse_range :zero_range :insert_range :unshare_range
        #    see linux/falloc.h
        #  @param [Integer] offset
        #  @param [Integer] len
        #  @return 0 or -ve errno
        #
        # @see fallocate(2)

        # Introduced in version 2.9.1  - fuse_version does not contain patch level.
        #    this will generate a warning on 2.9.0 that the struct is bigger than expected
        #    and thus some operations (ie falllocate) may be unsupported.
        #
        # int (*fallocate) (const char *, int, off_t, off_t, struct fuse_file_info *);
        op[:fallocate] = [:falloc_mode, :off_t, :off_t, FuseFileInfo.by_ref]

        if FUSE_MAJOR_VERSION >= 3

          # @!method copy_file_range(path_in,fi_in, offset_in, path_out, fi_out, offset_out, size, flags)
          #  @abstract
          #  Copy a range of data from one file to another
          #
          #  Performs an optimized copy between two file descriptors without the additional cost of transferring data
          #  through the FUSE kernel module to user space (glibc) and then back into the FUSE filesystem again.
          #
          #  In case this method is not implemented, glibc falls back to reading data from the source and writing to the
          #  destination. Effectively doing an inefficient copy of the data.
          #
          #  @param [String] path_in
          #  @param [FuseFileInfo] fi_in
          #  @param [Integer] offset_in
          #  @param [String] path_out
          #  @param [FuseFileInfo] fi_out
          #  @param [Integer] offset_out
          #  @param [Integer] size
          #  @param [Array<Symbol>] flags (unused)
          #  @return [Integer] copied size or -ve errno

          # ssize_t (*copy_file_range) (
          #    const char *path_in, struct fuse_file_info *fi_in, off_t offset_in, const char *path_out,
          #    struct fuse_file_info *fi_out, off_t offset_out, size_t size, int flags
          # );
          op[:copy_file_range] =
            callback [
              :fs_string, FuseFileInfo.by_ref, :off_t,
              :fs_string, FuseFileInfo.by_ref, :off_t,
              :size_t, :int
            ], :ssize_t

          # @!method lseek(path,offset,whence,fuse_file_info)
          #  @abstract
          #  Find next data or hole after the specified offset
          #  @param [String] path
          #  @param [Integer] offset
          #  @param [Symbol] whence
          #    either :seek_set ,:seek_cur, :seek_end, :seek_data, :seek_hole
          #  @return [Integer] the found offset in bytes from the beginning of the file or -ve errno
          #  @see lseek(2)

          # off_t (*lseek) (const char *, off_t off, int whence, struct fuse_file_info *);
          op[:lseek] = callback [:fs_string, :off_t, Flock::Enums::SeekWhence, FuseFileInfo.by_ref], :off_t
        end
      end

      # @!endgroup

      layout_data = op.transform_values do |v|
        if v.is_a?(Array) && !v.last.is_a?(Integer)
          # A typical fuse callback
          callback([:fs_string] + v, :int)
        else
          v
        end
      end

      layout layout_data

      # @overload initialize(fuse_wrappers: [], fuse_flags: [], delegate: self)
      #  Build a FuseOperations struct and register callback methods
      #
      #  The methods to register are identified by delegate.{fuse_respond_to?} if available
      #  otherwise delegate.{::respond_to?} is used.
      #
      #  @param [Object] delegate
      #   delegate object that quacks like our abstract methods (after any wrappers)
      #
      #   if not provided defaults to self, ie a subclass of FuseOperations that implements the otherwise abstract
      #   callback and configuration methods, or a naked FuseOperations that must be externally configured.
      #
      #  @param [Array] fuse_wrappers
      #   A list of fuse_wrappers (see {register}). Passed into delegate.{fuse_wrappers} if available
      #
      #  @param [Array<Symbol>] fuse_flags list of configuration flags (Not used in Fuse3)
      #   concatenated #fuse_flags if available
      def initialize(*args, fuse_wrappers: [], fuse_flags: [], delegate: self)
        super(*args) # FFI::Struct constructor
        return if args.any? # only configure if this is a new allocation

        initialize_callbacks(wrappers: fuse_wrappers, delegate: delegate)

        return unless FUSE_MAJOR_VERSION < 3

        fuse_flags.concat(delegate.fuse_flags) if delegate.respond_to?(:fuse_flags)
        send(:[]=, :flags, fuse_flags.uniq)
      end

      # @!visibility private
      def fuse_callbacks
        self.class.fuse_callbacks
      end

      # @return [Set<Symbol>] list of callback methods
      def self.fuse_callbacks
        @fuse_callbacks ||= Set.new(members - [:flags])
      end

      # @return [Set<Symbol>] list of path callback methods
      def self.path_callbacks
        @path_callbacks ||= fuse_callbacks - %i[init destroy]
      end
    end
  end
end
