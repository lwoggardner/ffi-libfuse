# frozen_string_literal: true

require_relative 'struct_wrapper'
require_relative 'stat/constants'

module FFI
  # Ruby representation of stat.h struct
  class Stat
    # Use a StructWrapper because of clash with #size and the ability to attach functions
    include StructWrapper

    extend FFI::Library
    ffi_lib FFI::Library::LIBC

    # stat/native will attach functions to Stat
    require_relative 'stat/native'
    native_struct(Native)

    # @!attribute [rw] mode
    #  @return [Integer] file mode (type | perms)

    # @!attribute [rw] size
    #  @return [Integer] size of file in bytes

    # @!attribute [rw] nlink
    #  @return [Integer] number of links

    # @!attribute [rw] uid
    #  @return [Integer] owner user id

    # @!attribute [rw] gid
    #  @return [Integer] owner group id

    int_members = Native
                  .members
                  .select { |m| m.to_s.start_with?('st_') && !m.to_s.end_with?('timespec') }
                  .to_h { |m| [:"#{m[3..]}", m] }

    ffi_attr_accessor(**int_members)

    # @!attribute [rw] atime
    #   @return [Time] time of last access

    # @!attribute [rw] mtime
    #   @return [Time] time of last modification

    # @!attribute [rw] ctime
    #   @return [Time] time of last status change

    time_members = Native.members.select { |m| m.to_s =~ /^st_.*timespec$/ }.to_h { |m| [:"#{m[3..-5]}", m] }

    ffi_attr_reader(**time_members, &:time)

    ffi_attr_writer_method(**time_members) do |sec, nsec = 0|
      _attr, member = ffi_attr_writer_member(__method__)
      self[member].set_time(sec, nsec)
    end

    # Fill content for a regular file
    # @param [Integer] mode
    # @param [Integer] size
    # @param [Integer] uid
    # @param [Integer] gid
    # @param [Hash] args additional system specific stat fields
    # @return [self]
    def file(mode:, size:, nlink: 1, uid: Process.uid, gid: Process.gid, **args)
      mode = ((S_IFREG & S_IFMT) | (mode & 0o777))
      fill(mode: mode, size: size, nlink: nlink, uid: uid, gid: gid, **args)
    end

    # Fill content for a directory
    # @param [Integer] mode
    # @param [Integer] nlink
    # @param [Integer] uid
    # @param [Integer] gid
    # @param [Hash] args additional system specific stat fields
    # @return [self]
    def dir(mode:, nlink: 3, uid: Process.uid, gid: Process.gid, **args)
      mode = ((S_IFDIR & S_IFMT) | (mode & 0o777))
      fill(mode: mode, uid: uid, gid: gid, nlink: nlink, **args)
    end
    alias directory dir

    # Fill content for a symbolic link
    # @param [Integer] size length of the target name (including null terminator)
    # @param [Integer] mode
    # @param [Integer] uid
    # @param [Integer] gid
    # @param [Hash] args additional system specific stat fields
    # @return [self]
    def symlink(size:, mode: 0o777, nlink: 1, uid: Process.uid, gid: Process.gid, **args)
      mode = ((S_IFLNK & S_IFMT) | (mode & 0o777))
      fill(mode: mode, nlink: nlink, size: size, uid: uid, gid: gid, **args)
    end

    # Fill attributes from file (using native LIBC calls)
    # @param [Integer|:to_s] file descriptor or a file path
    # @param [Boolean] follow links
    # @return [self]
    def from(file, follow: true)
      return fstat(file) if file.is_a?(Integer)

      return stat(file.to_s) if follow

      lstat(file.to_s)
    end

    # @!method stat(path)
    # Fill attributes from file, following links
    # @param [:to_s] path a file path
    # @raise [SystemCallError] on error
    # @return [self]

    # @!method lstat(path)
    # Fill attributes from file path, without following links
    # @param [:to_s] path
    # @raise [SystemCallError] on error
    # @return [self]

    # @!method fstat(fileno)
    # Fill attributes from file descriptor
    # @param [:to_i] fileno file descriptor
    # @raise [SystemCallError] on error
    # @return [self]

    %i[stat lstat fstat].each do |m|
      define_method(m) do |file|
        res = self.class.send("native_#{m}", (m == :fstat ? file.to_i : file.to_s), native)
        raise SystemCallError.new('', FFI::LastError.error) unless res.zero?

        self
      end
    end

    # Apply permissions mask to mode
    # @param [Integer] mask (see umask)
    # @param [Hash] overrides see {fill}
    # @return self
    def mask(mask = S_ISUID, **overrides)
      fill(mode: mode & (~mask), **overrides)
    end

    def file?
      mode & S_IFREG != 0
    end

    def directory?
      mode & S_IFDIR != 0
    end

    def setuid?
      mode & S_ISUID != 0
    end

    def setgid?
      mode & S_ISGID != 0
    end

    def sticky?
      mode & S_ISVTX != 0
    end

    def symlink?
      mode & S_IFLNK != 0
    end

    class << self
      # @!method file(**fields)
      # @return [Stat]
      # @raise [SystemCallError]
      # @see Stat#file

      # @!method dir(**fields)
      # @return [Stat]
      # @raise [SystemCallError]
      # @see Stat#dir

      # @!method symlink(**fields)
      # @return [Stat]
      # @raise [SystemCallError]
      # @see Stat#symlink

      %i[file dir symlink].each { |m| define_method(m) { |stat = new, **args| stat.send(m, **args) } }
      alias directory dir

      # @!method from(file, stat = new(), follow: false)
      # @return [Stat]
      # @raise [SystemCallError]
      # @see Stat#from

      # @!method stat(file, stat = new())
      # @return [Stat]
      # @raise [SystemCallError]
      # @see Stat#stat

      # @!method lstat(file, stat = new())
      # @return [Stat]
      # @raise [SystemCallError]
      # @see Stat#lstat

      # @!method fstat(file, stat = new())
      # @return [Stat]
      # @raise [SystemCallError]
      # @see Stat#fstat
      %i[from stat lstat fstat].each { |m| define_method(m) { |file, stat = new, **args| stat.send(m, file, **args) } }
    end
  end
end
