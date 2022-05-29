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
                  .map { |m| m[3..].to_sym }

    ffi_attr_accessor(*int_members, format: 'st_%s')

    # @!attribute [rw] atime
    #   @return [Time] time of last access

    # @!attribute [rw] mtime
    #   @return [Time] time of last modification

    # @!attribute [rw] ctime
    #   @return [Time] time of last status change

    time_members = Native.members.select { |m| m.to_s =~ /^st_.*timespec$/ }.map { |m| m[3..-5].to_sym }

    ffi_attr_reader(*time_members, format: 'st_%sspec', &:time)

    ffi_attr_writer(*time_members, format: 'st_%sspec', simple: false) do |sec, nsec = 0|
      self[__method__[0..-2].to_sym].set_time(sec, nsec)
    end

    # Fill content for a regular file
    # @param [Integer] mode
    # @param [Integer] size
    # @param [Integer] uid
    # @param [Integer] gid
    # @param [Hash] args additional system specific stat fields
    # @return [self]
    def file(mode:, size:, uid: Process.uid, gid: Process.gid, **args)
      mode = ((S_IFREG & S_IFMT) | (mode & 0o777))
      fill(mode: mode, size: size, uid: uid, gid: gid, **args)
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
    def mask(mask = 0o4000, **overrides)
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

    class << self
      # @!method file(stat,**fields)
      # @return [Stat]
      # @raise [SystemCallError]
      # @see Stat#file

      # @!method dir(stat,**fields)
      # @return [Stat]
      # @raise [SystemCallError]
      # @see Stat#dir
      %i[file dir].each { |m| define_method(m) { |stat = new, **args| stat.send(m, **args) } }
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
