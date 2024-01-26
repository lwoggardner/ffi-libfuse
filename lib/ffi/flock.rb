# frozen_string_literal: true

require_relative 'accessors'

module FFI
  # Flocking operation
  class Flock < Struct
    # Enum definitions associated with Flock
    module Enums
      extend FFI::Library
      seek_whence = %i[seek_set seek_cur seek_end seek_data seek_hole]
      SeekWhenceShort = enum :short, seek_whence
      SeekWhence = enum :int, seek_whence

      LockType = enum :short, %i[rdlck wrlck unlck]
      LockCmd = enum :int, [:getlk, 5, :setlk, 6, :setlkw, 7]
    end

    include(Accessors)

    layout(
      # @!attribute [r] type
      #   @return [Symbol] lock type, :rdlck, :wrlck, :unlck
      l_type: Enums::LockType,

      # @!attribute [r] whence
      #   @return [Symbol] specifies what the offset is relative to, one of :seek_set, :seek_cur or :seek_end
      #    corresponding to the whence argument to fseek(2) or lseek(2),
      l_whence: Enums::SeekWhenceShort,

      # @!attribute [r] start
      #  @return [Integer] the offset of the start of the region to which the lock applies, and is given in bytes
      #   relative to the point specified by #{whence} member.
      l_start: :off_t,

      # @!attribute [r] len
      #  @return [Integer] the length of the region to be locked.
      #
      #    A value of 0 means the region extends to the end of the file.
      l_len: :off_t,

      # @!attribute [r] pid
      #  @return [Integer] the process ID (see Process Creation Concepts) of the process holding the lock.
      #   It is filled in by calling fcntl with the F_GETLK command, but is ignored when making a lock. If the
      #   conflicting lock is an open file description lock (see Open File Description Locks), then this field will be
      #   set to -1.
      l_pid: :pid_t
    )

    # Strip leading 'l_' to make attribute names
    ffi_attr_reader(**members.to_h { |m| [m[2..].to_sym, m] })
  end
end
