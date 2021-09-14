# frozen_string_literal: true

require_relative 'fuse_version'
require_relative '../struct_wrapper'
require_relative '../ruby_object'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    bit_flags = %i[direct_io keep_cache flush nonseekable flock_release cache_readdir]
    bit_flags.unshift(:writepage) if FUSE_MAJOR_VERSION >= 3
    bitmask :file_info_flags, bit_flags

    # Native struct layout
    # @!visibility private
    class NativeFuseFileInfo < FFI::Struct
      # NOTE: cache_readdir added in Fuse3, but always available for compatibility
      if FUSE_MAJOR_VERSION == 2
        layout(
          flags: :int,
          fh_old: :ulong, # deprecated
          writepage: :int,
          bit_flags: :file_info_flags,
          fh: RubyObject.by_object_id(:uint64_t),
          lock_owner: :uint64_t
        )
      else
        layout(
          flags: :int,
          bit_flags: :file_info_flags,
          padding: :uint,
          fh: RubyObject.by_object_id(:uint64_t),
          lock_owner: :uint64_t,
          poll_events: :uint32_t
        )
      end
    end

    # FuseFileInfo
    class FuseFileInfo
      # This uses a struct wrapper as references can be null
      include(StructWrapper)
      native_struct(NativeFuseFileInfo)

      if FUSE_MAJOR_VERSION == 2
        ffi_attr_reader(:writepage) { |v| v != 0 }
      else
        ffi_bitflag_reader(:bit_flags, :writepage)
      end

      # @!attribute [r] flags
      #   @return [Integer] Open flags.  Available in open() and release()
      #   @see Fcntl
      ffi_attr_reader :flags

      # @!attribute [r] lock_owner
      #  @return [Integer] Lock owner id.  Available in locking operations and flush
      ffi_attr_reader :lock_owner

      # @!attribute [rw] fh
      #  Note this fh is weakly referenced by kernel fuse, make sure a reference is kept to prevent it from being
      #  garbage collected until release()
      #  @return [Object] File handle.  May be filled in by filesystem in open()
      ffi_attr_accessor(:fh)

      # @!attribute [r] writepage
      #  In case of a write operation indicates if this was caused by a delayed write from the page cache. If so, then
      #  the context's pid, uid, and gid fields will not be valid, and the *fh* value may not match the *fh* value that
      #  would have been sent with the corresponding individual write requests if write caching had been disabled.
      #  @return [Boolean] indicates if this was caused by a writepage

      # @!attribute [r] flush
      #  Set in flush operation, also maybe set in highlevel lock operation and lowlevel release operation.
      #  @return [Boolean] Indicates a flush operation.
      ffi_bitflag_reader(:bit_flags, :flush)

      # @!attribute [rw] direct_io
      #  @return [Boolean] Can be filled in by open, to use direct I/O on this file.

      # @!attribute [rw] keep_cache
      #   @return [Boolean]  Can be filled in by open, to indicate, that cached file data need not be invalidated.

      # @!attribute [rw] nonseekable
      #  @return [Boolean] Can be filled in by open, to indicate that the file is not seekable
      # @since Fuse2.8

      # @!attribute [rw] flock_release
      #  If set, lock_owner shall contain a valid value.
      #  May only be set in ->release().  Introduced in version 2.9
      #  @return [Boolean] Indicates that flock locks for this file should be released.

      # @!attribute [rw] cache_readdir
      #  Can be filled in by opendir.
      #  @return [Boolean] signals the kernel to enable caching of entries returned by readdir()
      #  @since Fuse3

      ffi_bitflag_accessor(:bit_flags, :direct_io, :keep_cache, :nonseekable, :flock_release, :cache_readdir)
    end
  end
end
