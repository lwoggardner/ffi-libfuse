# frozen_string_literal: true

require 'ffi'
require_relative('accessors')

module FFI
  # Represents Statvfs for use with {Libfuse::FuseOperations#statfs} callback
  class StatVfs < Struct
    include Accessors

    case Platform::NAME
    when /darwin/
      layout(
        f_bsize: :ulong,
        f_frsize: :ulong,
        f_blocks: :uint,
        f_bfree: :uint,
        f_bavail: :uint,
        f_files: :uint,
        f_ffree: :uint,
        f_favail: :uint,
        f_fsid: :ulong,
        f_flag: :ulong,
        f_namemax: :ulong
      )
    when /linux/
      layout(
        :f_bsize, :ulong,
        :f_frsize, :ulong,
        :f_blocks, :uint64,
        :f_bfree, :uint64,
        :f_bavail, :uint64,
        :f_files, :uint64,
        :f_ffree, :uint64,
        :f_favail, :uint64,
        :f_fsid, :ulong,
        :f_flag, :ulong,
        :f_namemax, :ulong,
        :f_spare, [:int, 6]
      )
    else
      raise NotImplementedError, "FFI::StatVfs not implemented for FFI::Platform #{Platform::NAME}"
    end

    # @!attribute [rw] bsize
    #  @return [Integer] Filesystem block size

    # @!attribute [rw] frsize
    #  @return [Integer] Fragment size

    # @!attribute [rw] blocks
    #  @return [Integer] Size of fs in frsize units

    # @!attribute [rw] bfree
    #  @return [Integer] Number of free blocks

    # @!attribute [rw] bavail
    #  @return [Integer] Number of free blocks for unprivileged users

    # @!attribute [rw] files
    #  @return [Integer] Number of inodes

    # @!attribute [rw] ffree
    #  @return [Integer] Number of free inodes

    # @!attribute [rw] favail
    #  @return [Integer] Number of free inodes for unprivileged users

    # @!attribute [rw] fsid
    #  @return [Integer] Filesystem ID

    # @!attribute [rw] flag
    #  @return [Integer] Mount flags

    # @!attribute [rw] namemax
    #  @return [Integer] Maximum filename length

    int_members = members.grep(/^f_/).map { |m| m[2..].to_sym }
    ffi_attr_accessor(*int_members, format: 'f_%s')

    extend FFI::Library
    ffi_lib FFI::Library::LIBC

    attach_function :native_statvfs, :stat, [:string, by_ref], :int
    attach_function :native_fstatvfs, :fstat, [:int, by_ref], :int

    # Fill from native statvfs for path
    # @param [:to_s] path
    # @return [self]
    def statvfs(path)
      res = self.class.native_statvfs(path.to_s, self)
      raise SystemCallError.new('', FFI::LastError.errno) unless res.zero?

      self
    end

    # Fill from native fstatvfs for fileno
    # @param [Integer] fileno
    # @return [self]
    def fstatvfs(fileno)
      res = self.class.native_fstatvfs(fileno, self)
      raise SystemCallError.new('', FFI::LastError.errno) unless res.zero?

      self
    end

    # File from native LIBC calls for file
    # @param [Integer|:to_s] file a file descriptor or a file path
    # @return [self]
    def from(file)
      return fstatvfs(file) if file.is_a?(Integer)

      statvfs(file)
    end

    class << self
      # @!method from(file)
      # @return [StatVfs]
      # @raise [SystemCallError]
      # @see StatVfs#from

      # @!method statvfs(file)
      # @return [StatVfs]
      # @raise [SystemCallError]
      # @see StatVfs#statvfs

      # @!method fstatvfs(file)
      # @return [StatVfs]
      # @raise [SystemCallError]
      # @see StatVfs#fstatvfs
      %i[from statvfs fstatvfs].each { |m| define_method(m) { |file, stat = new, **args| stat.send(m, file, **args) } }

      # @!visibility private

      # @!method native_statvfs(path, statvfs_buf)
      # @!method native_fstatvfs(fd, statvfs_buf)
    end
  end
end
