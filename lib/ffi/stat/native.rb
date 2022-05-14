# frozen_string_literal: true

require 'ffi'
require_relative 'time_spec'

module FFI
  class Stat
    # @!visibility private
    class Native < Struct
      case Platform::NAME

      when 'x86_64-linux'
        layout :st_dev,     :dev_t,
               :st_ino,     :ino_t,
               :st_nlink,   :nlink_t,
               :st_mode,    :mode_t,
               :st_uid,     :uid_t,
               :st_gid,     :gid_t,
               :__pad0,     :int,
               :st_rdev,    :dev_t,
               :st_size,    :off_t,
               :st_blksize, :blksize_t,
               :st_blocks,  :blkcnt_t,
               :st_atimespec, TimeSpec,
               :st_mtimespec, TimeSpec,
               :st_ctimespec, TimeSpec

        Stat.attach_function :native_fstat, :stat, [:string, by_ref], :int
        Stat.attach_function :native_lstat, :lstat, [:string, by_ref], :int
        Stat.attach_function :native_fstat, :fstat, [:int, by_ref], :int

      when 'x86_64-darwin', 'aarch64-darwin'
        #  man stat - this is stat with 64 bit inodes.
        layout :st_dev,       :dev_t,
               :st_mode,      :mode_t,
               :st_nlink,     :nlink_t,
               :st_ino,       :ino_t,
               :st_uid,       :uid_t,
               :st_gid,       :gid_t,
               :st_rdev,      :dev_t,
               :st_atimespec, TimeSpec,
               :st_mtimespec, TimeSpec,
               :st_ctimespec, TimeSpec,
               :st_birthtimespec, TimeSpec,
               :st_size,      :off_t,
               :st_blocks,    :blkcnt_t,
               :st_blksize,   :blksize_t,
               :st_flags,     :uint32,
               :st_gen,       :uint32,
               :st_lspare,     :int32,
               :st_gspare,     :int64

        # TODO: these functions are deprecated, but at least on Catalina the old stat functions
        #       use the stat struct *without* 64 bit inodes
        Stat.attach_function :native_stat, :stat64, [:string, by_ref], :int
        Stat.attach_function :native_lstat, :lstat64, [:string, by_ref], :int
        Stat.attach_function :native_fstat, :fstat64, [:int, by_ref], :int

      else
        raise NotImplementedError, "FFI::Stat not implemented for FFI::Platform #{Platform::NAME}"
      end
    end
  end
end
