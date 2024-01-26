# frozen_string_literal: true

require_relative 'fuse_version'
require_relative '../accessors'
require_relative '../boolean_int'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    capabilities =
      if FUSE_MAJOR_VERSION >= 3
        %i[
          async_read
          posix_locks
          atomic_o_trunc
          export_support
          dont_mask
          splice_write
          splice_move
          splice_read
          flock_locks
          ioctl_dir
          auto_inval_data
          readdirplus
          readdirplus_auto
          async_dio
          writeback_cache
          no_open_support
          parallel_dirops
          posix_acl
          handle_killpriv
          cache_symlinks
          no_opendir_support
          explicit_inval_data
        ]
      else
        %i[
          async_readcap
          posix_locks
          atomic_o_trunc
          export_support
          big_writes
          dont_mask
          splice_write
          splice_move
          splice_read
          flock_locks
          ioctl_dir
        ]
      end

    bitmask :fuse_cap, capabilities

    #
    # Connection information
    #
    # Some of the elements are read-write, these can be changed to indicate the value requested by the filesystem.  The
    # requested value must usually be smaller than the indicated value.
    #
    # @see FuseOperations#init
    class FuseConnInfo < FFI::Struct
      fuse_layout =
        if FUSE_MAJOR_VERSION >= 3
          {
            proto_major: :uint,
            proto_minor: :uint,
            max_write: :uint,
            max_read: :uint,
            max_readahead: :uint,
            capable: :fuse_cap,
            want: :fuse_cap,
            max_background: :uint,
            congestion_threshold: :uint,
            time_gran: :uint,
            reserved: [:uint, 22] # for future use
          }
        else
          {
            proto_major: :uint,
            proto_minor: :uint,
            async_read: :bool_int, # long deprecated
            max_write: :uint,
            max_readahead: :uint,
            capable: :fuse_cap,
            want: :fuse_cap,
            max_background: :uint,
            congestion_threshold: :uint,
            reserved: [:uint, 23]
          }
        end.freeze

      include(FFI::Accessors)

      layout fuse_layout

      # @!attribute [r] proto_major
      # @return [Integer] Major version of the protocol (read-only)

      # @!attribute [r] proto_minor
      # @return [Integer] Minor version of the protocol (read-only)

      ffi_attr_reader :proto_major, :proto_minor

      # @!attribute [rw] max_read
      # @return [Integer] Maximum size of read requests.
      #
      # A value of zero indicates no limit. However, even if the filesystem does not specify a limit, the maximum size
      # of read requests will still be limited by the kernel.
      #
      # @note For the time being, the maximum size of read requests must be set both here *and* passed to
      # using the ``-o max_read=<n>`` mount option. At some point in the future, specifying the mount
      # option will no longer be necessary.
      # @since Fuse3
      ffi_attr_accessor :max_read if FUSE_MAJOR_VERSION >= 3

      # @!attribute [rw] max_write
      #   @return [Integer] Maximum size of the write buffer

      # @!attribute [rw] max_readahead
      #   @return [Integer] Maximum size of the readahead buffer

      ffi_attr_accessor :max_write, :max_readahead

      # @!attribute [r] capable
      # Capability flags supported by kernel fuse module
      #
      #  * `:async_read` Indicates that the filesystem supports asynchronous read requests.
      #
      #  If this capability is not requested/available, the kernel will ensure that there is at most one pending read
      #  request per file-handle at any time, and will attempt to order read requests by increasing offset.
      #
      #  This feature is enabled by default when supported by the kernel.
      #
      #  * `:posix_locks`  Indicates that the filesystem supports "remote" locking.
      #
      #  This feature is enabled by default when supported by the kernel,
      #  and if getlk() and setlk() handlers are implemented.
      #
      #  * `:atomic_o_trunc` Indicates that the filesystem supports the O_TRUNC open flag.
      #
      #  If disabled, and an application specifies O_TRUNC, fuse first calls truncate() and then open() with O_TRUNC
      #  filtered out.
      #
      #  This feature is enabled by default when supported by the kernel.
      #
      #  * `:export_support` Indicates that the filesystem supports lookups of "." and "..".
      #
      #  This feature is disabled by default.
      #
      #  * `:big_writes` Indicates the filesystem can handle write size larger than 4kB.
      #
      #   Removed in Fuse3 where is now always active. Filesystems that want to limit the size of write requests should
      #   use the {#max_write} option instead.
      #
      #  * `:dont_mask` Indicates that the kernel should not apply the umask to the file mode on create operations.
      #
      #  This feature is disabled by default.
      #
      #  * `:splice_write` Indicates that libfuse should try to use splice() when writing to the fuse device.
      #
      #  This may improve performance. This feature is disabled by default.
      #
      #  * `:splice_move` Indicates that libfuse should try to move pages instead of copying when writing to / reading
      #    from the fuse device.
      #
      #  This may improve performance. This feature is disabled by default.
      #
      #  * `:splice_read` Indicates that libfuse should try to use splice() when reading from the fuse device.
      #
      #  This may improve performance. This feature is enabled by default when supported by the kernel and
      #  if the filesystem implements a write_buf() handler.
      #
      #  * `:flock_locks` If set, the calls to flock(2) will be emulated using POSIX locks and must then be handled by
      #  the filesystem's :flock handler.
      #
      #  If not set, flock(2) calls will be handled by the FUSE kernel module internally (so any access that does not go
      #  through the kernel cannot be taken into account).
      #
      #  This feature is enabled by default when supported by the kernel and if the filesystem implements a flock()
      #  handler.
      #
      #  * `:ioctl_dir` Indicates that the filesystem supports ioctl's on directories.
      #
      #  This feature is enabled by default when supported by the kernel.
      #
      # * :`auto_inval_data`
      #
      #  Traditionally, while a file is open the FUSE kernel module only asks the filesystem for an update of the file's
      #  attributes when a client attempts to read beyond EOF. This is unsuitable for e.g. network filesystems, where
      #  the file contents may change without the kernel knowing about it.
      #
      #  If this flag is set, FUSE will check the validity of the attributes on every read. If the attributes are no
      #  longer valid (i.e., if the *attr_timeout* passed to fuse_reply_attr() or set in `struct fuse_entry_param` has
      #  passed), it will first issue a `getattr` request. If the new mtime differs from the previous value, any cached
      #  file *contents* will be invalidated as well.
      #
      #  This flag should always be set when available. If all file changes go through the kernel, *attr_timeout* should
      #  be set to a very large number to avoid unnecessary getattr() calls.
      #
      #  This feature is enabled by default when supported by the kernel.
      #
      #  * `:readdirplus` Indicates that the filesystem supports readdirplus.
      #
      #  This feature is enabled by default when supported by the kernel and if the filesystem implements the
      #  readdirplus() handler
      #
      #  * `:readdirplus_auto` Indicates that the filesystem supports adaptive readdirplus.
      #
      #  If :readdirplus is not set, this flag has no effect.
      #
      #  If :readdirplus is set and this flag is not set, the kernel will always issue readdirplus() requests to
      #  retrieve directory contents.
      #
      #  If :readdirplus is set and this flag is set, the kernel will issue both readdir() and readdirplus() requests,
      #  depending on how much information is expected to be required.
      #
      #  As of Linux 4.20, the algorithm is as follows: when userspace starts to read directory entries, issue a
      #  :reaadirplus request to the filesystem. If any entry attributes have been looked up by the time userspace
      #  requests the next batch of entries continue with :reaadirplus, otherwise switch to plain :readdir.  This will
      #  result in eg plain "ls" triggering :reaadirplus first then :readdir after that because it doesn't do lookups.
      #  "ls -l" should result in all :reaadirplus, except if dentries are already cached.
      #
      #  This feature is enabled by default when supported by the kernel and if the filesystem implements both a
      #  readdirplus() and a readdir() handler.
      #
      #  **Note** The high-level operations mix :readdir and :readdirplus into one operation
      #  with flags to indicate behaviour. As such for the purposes of above :readdirplus is always implemented!
      #
      #  * `:async_dio` Indicates that the filesystem supports asynchronous direct I/O submission.
      #
      #   If this capability is not requested/available, the kernel will ensure that there is at most one pending read
      #   and one pending write request per direct I/O file-handle at any time.
      #
      #   This feature is enabled by default when supported by the kernel.
      #
      #  * `:writeback_cache` Indicates that writeback caching should be enabled.
      #
      #   This means that individual write request may be buffered and merged in the kernel before they are send to the
      #   filesystem.
      #
      #   This feature is disabled by default.
      #
      #  * `:no_open_support` Indicates support for zero-message opens.
      #
      #   If this flag is set in the `capable` field of the `fuse_conn_info` structure, then the filesystem may return
      #  `ENOSYS` from the open() handler to indicate success. Further attempts to open files will be handled in the
      #   kernel. (If this flag is not set, returning ENOSYS will be treated as an error and signaled to the caller).
      #
      #   Setting (or unsetting) this flag in the `want` field has *no effect*.
      #
      #  * `:parallel_dirops` Indicates support for parallel directory operations.
      #
      #  If this flag is unset, the FUSE kernel module will ensure that lookup() and readdir() requests are never issued
      #  concurrently for the same directory.
      #
      #  This feature is enabled by default when supported by the kernel.
      #
      #  * `:posix_acl` Indicates support for POSIX ACLs.
      #
      #  If this feature is enabled, the kernel will cache and have responsibility for enforcing ACLs. ACL will be
      #  stored as xattrs and passed to userspace, which is responsible for updating the ACLs in the filesystem, keeping
      #  the file mode in sync with the ACL, and ensuring inheritance of default ACLs when new filesystem nodes are
      #  created. Note that this requires that the file system is able to parse and interpret the xattr representation
      #  of ACLs.
      #
      #  Enabling this feature implicitly turns on the ``default_permissions`` mount option (even if it was not passed
      #  to mount(2)).
      #
      #  This feature is disabled by default.
      #
      #  * `:handle_killpriv` Indicates that the filesystem is responsible for unsetting setuid and setgid bits when a
      #  file is written, truncated, or its owner is changed.
      #
      #  This feature is enabled by default when supported by the kernel.
      #
      #  * `:cache_symlinks` Indicates that the kernel supports caching symlinks in its page cache.
      #
      #  When this feature is enabled, symlink targets are saved in the page cache. You can invalidate a cached link by
      #  calling: `fuse_lowlevel_notify_inval_inode(se, ino, 0, 0);`
      #
      #  This feature is disabled by default.
      #
      #  * `:no_opendir_support` Indicates support for zero-message opendirs.
      #
      #  If this flag is set then the filesystem may return `ENOSYS` from the opendir() handler to indicate success.
      #  Further opendir and releasedir messages will be handled in the kernel. (If this flag is not set, returning
      #  ENOSYS will be treated as an error and signalled to the caller.)
      #
      #  Setting (or unsetting) this flag in the `want` field has *no effect*.
      #
      #  * `:explicit_inval_data` Indicates support for invalidating cached pages only on explicit request.
      #
      #  If this flag is set in the `capable` field of the `fuse_conn_info` structure, then the FUSE kernel module
      #  supports invalidating cached pages only on explicit request by the filesystem through
      #  fuse_lowlevel_notify_inval_inode() or fuse_invalidate_path().
      #
      #  By setting this flag in the `want` field of the `fuse_conn_info` structure, the filesystem is responsible for
      #  invalidating cached pages through explicit requests to the kernel.
      #
      #  Note that setting this flag does not prevent the cached pages from being flushed by OS itself and/or through
      #  user actions.
      #
      #  Note that if both :explicit_inval_data and :auto_inval_data are set then :auto_inval_data takes precedence.
      #
      #  This feature is disabled by default.
      # @return [Array<Symbol>]
      ffi_attr_reader :capable

      # @param [Array<Symbol>] capabilities
      # @return [Boolean] true if {#capable} of all capabilities
      def capable?(*capabilities)
        capabilities.all? { |c| self[:capable].include?(c) }
      end

      # @attribute [rw] want
      # @overload want()
      #  Capability flags that the filesystem wants to enable.
      #
      #  libfuse attempts to initialize this field with reasonable default values before calling the :init handler.
      #
      # @overload want(*capabiities)
      #  Add to the capabilities wanted by the filesystem
      #  @param [Array<Symbol>] capabilities list to add
      # @overload want(**capabilities)
      #  @param [Hash<Symbol,Boolean>] capabilities map of capability names to whether they are explicitly wanted
      #   or unwanted
      # @return [Array<Symbol>]
      # @see capable
      ffi_attr_reader_method(:want) do |*caps, **h|
        next self[:want] if caps.empty? && h.empty?

        h.merge!(caps.pop) if caps.last.is_a?(Hash)
        add, del = h.keys.partition { |c| h[c] }
        self[:want] = (self[:want] - del + add + caps)
      end

      # @param [Array<Symbol>] capabilities
      # @return [Boolean] true if all capabilities are wanted
      def wanted?(*capabilities)
        capabilities.all? { |c| self[:want].include?(c) }
      end

      # @!attribute [rw] max_background
      # @return [Integer] Maximum number of pending "background" requests.
      #
      # A background request is any type of request for which the total number is not limited by other means. As of
      # kernel 4.8, only two types of requests fall into this category:
      #
      #   1. Read-ahead requests
      #   2. Asynchronous direct I/O requests
      #
      # Read-ahead requests are generated (if max_readahead is non-zero) by the kernel to preemptively fill its
      # caches when it anticipates that userspace will soon read more data.
      #
      # Asynchronous direct I/O requests are generated if :async_dio is enabled and userspace submits a large
      # direct I/O request. In this case the kernel will internally split it up into multiple smaller requests and
      # submit them to the filesystem concurrently.
      #
      # Note that the following requests are *not* background requests: writeback requests (limited by the kernel's
      # flusher algorithm), regular (i.e., synchronous and buffered) userspace read/write requests (limited to one per
      # thread), asynchronous read requests (Linux's io_submit(2) call actually blocks, so these are also limited to one
      # per thread).
      ffi_attr_accessor :max_background

      # @!attribute [rw] congestion_threshold
      # @return [Integer] Kernel congestion threshold parameter
      #
      # f the number of pending background requests exceeds this number, the FUSE kernel module will mark the filesystem
      # as "congested". This instructs the kernel to expect that queued requests will take some time to complete, and to
      # adjust its algorithms accordingly (e.g. by putting a waiting thread to sleep instead of using a busy-loop).
      ffi_attr_accessor :congestion_threshold

      # @!attribute [rw] time_gran
      # @return [Integer] timestamp granularity supported by the file-system
      #
      # When :writeback_cache is enabled, the kernel is responsible for updating mtime and ctime when write requests are
      # received. The updated values are passed to the filesystem with setattr() requests. However, if the filesystem
      # does not support the full resolution of the kernel timestamps (nanoseconds), the mtime and ctime values used by
      # kernel and filesystem will differ (and result in an apparent change of times after a cache flush).
      #
      # To prevent this problem, this variable can be used to inform the kernel about the timestamp granularity
      # supported by the file-system. The value should be power of 10.  The default is 1, i.e. full nano-second
      # resolution. Filesystems supporting only second resolution should set this to 1000000000.
      ffi_attr_accessor :time_gran if FUSE_MAJOR_VERSION >= 3
    end
  end
end
