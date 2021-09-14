# frozen_string_literal: true

require_relative 'fuse_version'
require_relative '../accessors'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    # These are constants in fuse_common.h but defined like bitmask
    #
    #  FUSE_CAP_ASYNC_READ: filesystem supports asynchronous read requests
    #  FUSE_CAP_POSIX_LOCKS: filesystem supports "remote" locking
    #  FUSE_CAP_ATOMIC_O_TRUNC: filesystem handles the O_TRUNC open flag
    #  FUSE_CAP_EXPORT_SUPPORT: filesystem handles lookups of "." and ".."
    #  FUSE_CAP_BIG_WRITES: filesystem can handle write size larger than 4kB
    #  FUSE_CAP_DONT_MASK: don't apply umask to file mode on create operations
    #  FUSE_CAP_SPLICE_WRITE: ability to use splice() to write to the fuse device
    #  FUSE_CAP_SPLICE_MOVE: ability to move data to the fuse device with splice()
    #  FUSE_CAP_SPLICE_READ: ability to use splice() to read from the fuse device
    #  FUSE_CAP_FLOCK_LOCKS: ?
    #  FUSE_CAP_IOCTL_DIR: ioctl support on directories

    #  FUSE_IOCTL_COMPAT: 32bit compat ioctl on 64bit machine
    #  FUSE_IOCTL_UNRESTRICTED: not restricted to well-formed ioctls, retry allowed
    #  FUSE_IOCTL_RETRY: retry with new iovecs
    #  FUSE_IOCTL_DIR: is a directory
    bitmask :fuse_ioctl, %i[compat unrestricted retry dir]

    # #define FUSE_CAP_ASYNC_READ	(1 << 0)
    # #define FUSE_CAP_POSIX_LOCKS	(1 << 1)
    # #define FUSE_CAP_ATOMIC_O_TRUNC	(1 << 3)
    # #define FUSE_CAP_EXPORT_SUPPORT	(1 << 4)
    # #define FUSE_CAP_BIG_WRITES	(1 << 5)
    # #define FUSE_CAP_DONT_MASK	(1 << 6)
    # #define FUSE_CAP_SPLICE_WRITE	(1 << 7)
    # #define FUSE_CAP_SPLICE_MOVE	(1 << 8)
    # #define FUSE_CAP_SPLICE_READ	(1 << 9)
    # #define FUSE_CAP_FLOCK_LOCKS	(1 << 10)
    # #define FUSE_CAP_IOCTL_DIR	(1 << 11)

    if FUSE_MAJOR_VERSION >= 3
      bitmask :fuse_cap, %i[
        async_read posix_locks atomic_o_trunc export_support
        big_writes dont_mask splice_write splice_move splice_read
        flock_locks ioctl_dir
      ]
    else
      bitmask :fuse_cap, %i[
        async_read posix_locks atomic_o_trunc export_support
        dont_mask splice_write splice_move splice_read flock_locks ioctl_dir
        auto_inval_data readdirplus readdirplus_auto async_dio writeback_cache no_open_support
        parallel_dirops posix_acl handle_killpriv explicit_inval_data
      ]
    end
    #
    # Connection information
    #
    # Some of the elements are read-write, these can be changed to
    # indicate the value requested by the filesystem.  The requested
    # value must usually be smaller than the indicated value.
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
            #
            # Capability flags that the kernel supports (read-only)
            #
            capable: :fuse_cap,
            #
            # Capability flags that the filesystem wants to enable.
            #
            # libfuse attempts to initialize this field with
            # reasonable default values before calling the init() handler.
            #
            want: :fuse_cap,
            #
            # Maximum number of pending "background" requests. A
            # background request is any type of request for which the
            # total number is not limited by other means. As of kernel
            # 4.8, only two types of requests fall into this category:
            #
            #   1. Read-ahead requests
            #   2. Asynchronous direct I/O requests
            #
            # Read-ahead requests are generated (if max_readahead is
            # non-zero) by the kernel to preemptively fill its caches
            # when it anticipates that userspace will soon read more
            # data.
            #
            # Asynchronous direct I/O requests are generated if
            # FUSE_CAP_ASYNC_DIO is enabled and userspace submits a large
            # direct I/O request. In this case the kernel will internally
            # split it up into multiple smaller requests and submit them
            # to the filesystem concurrently.
            #
            # Note that the following requests are *not* background
            # requests: writeback requests (limited by the kernel's
            # flusher algorithm), regular (i.e., synchronous and
            # buffered) userspace read/write requests (limited to one per
            # thread), asynchronous read requests (Linux's io_submit(2)
            # call actually blocks, so these are also limited to one per
            # thread).
            #
            max_background: :uint,
            #
            # Kernel congestion threshold parameter. If the number of pending
            # background requests exceeds this number, the FUSE kernel module will
            # mark the filesystem as "congested". This instructs the kernel to
            # expect that queued requests will take some time to complete, and to
            # adjust its algorithms accordingly (e.g. by putting a waiting thread
            # to sleep instead of using a busy-loop).
            #
            congestion_threshold: :uint,
            #
            # When FUSE_CAP_WRITEBACK_CACHE is enabled, the kernel is responsible
            # for updating mtime and ctime when write requests are received. The
            # updated values are passed to the filesystem with setattr() requests.
            # However, if the filesystem does not support the full resolution of
            # the kernel timestamps (nanoseconds), the mtime and ctime values used
            # by kernel and filesystem will differ (and result in an apparent
            # change of times after a cache flush).
            #
            # To prevent this problem, this variable can be used to inform the
            # kernel about the timestamp granularity supported by the file-system.
            # The value should be power of 10.  The default is 1, i.e. full
            # nano-second resolution. Filesystems supporting only second resolution
            # should set this to 1000000000.
            #
            time_gran: :uint,
            #
            # For future use.
            #
            reserved: [:uint, 22]
          }
        else
          {
            proto_major: :uint,
            proto_minor: :uint,
            async_read: :uint, # This slot is max_read in Fuse 3
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
      #  @return [Integer] Major version of the protocol (read-only)

      # @!attribute [r] proto_minor
      #  @return [Integer] Minor version of the protocol (read-only)

      ffi_attr_reader :proto_major, :proto_minor

      #  Is asynchronous read supported (read-write)
      ffi_attr_accessor :async_read if FUSE_MAJOR_VERSION < 3

      # @!attribute [rw] max_read
      #  @return [Integer] Maximum size of read requests.
      #
      #   A value of zero indicates no limit. However, even if the filesystem does not specify a limit, the maximum size
      #   of read requests will still be limited by the kernel.
      #
      #  @note For the time being, the maximum size of read requests must be set both here *and* passed to
      #  using the ``-o max_read=<n>`` mount option. At some point in the future, specifying the mount
      #  option will no longer be necessary.
      ffi_attr_accessor :max_read if FUSE_MAJOR_VERSION >= 3

      # @!attribute [rw] max_write
      #   @return [Integer] Maximum size of the write buffer

      # @!attribute [rw] max_readahead
      #   @return [Integer] Maximum size of the readahead buffer

      ffi_attr_accessor :max_write, :max_readahead

      # Capability flags that kernel supports
      ffi_attr_reader :capable

      # Is capable of all of these FUSE_CAPs
      def capable?(*of)
        of.all? { |c| self[:capable].include?(c) }
      end

      # Capability flags that the filesystem wants
      ffi_attr_accessor :want

      # Maximum number of backgrounded requests
      ffi_attr_accessor :max_background

      # Kernel congestion threshold parameter
      ffi_attr_reader :congestion_threshold

      ffi_attr_accessor :time_gran if FUSE_MAJOR_VERSION >= 3
    end
  end
end
