# frozen_string_literal: true

require 'ffi'
require_relative 'time_spec'

module FFI
  class Stat
    # Native (and naked) stat from stat.h
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

      when 'x65_64-darwin'
        layout :st_dev,       :dev_t,
               :st_ino,       :uint32,
               :st_mode,      :mode_t,
               :st_nlink,     :nlink_t,
               :st_uid,       :uid_t,
               :st_gid,       :gid_t,
               :st_rdev,      :dev_t,
               :st_atimespec, TimeSpec,
               :st_mtimespec, TimeSpec,
               :st_ctimespec, TimeSpec,
               :st_size,      :off_t,
               :st_blocks,    :blkcnt_t,
               :st_blksize,   :blksize_t,
               :st_flags,     :uint32,
               :st_gen,       :uint32
      else
        raise NotImplementedError, "FFI::Stat not implemented for FFI::Platform #{Platform::NAME}"
      end
    end
  end
end
