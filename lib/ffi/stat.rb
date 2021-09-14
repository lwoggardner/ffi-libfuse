# frozen_string_literal: true

require_relative 'struct_wrapper'
require_relative 'stat/native'
require_relative 'stat/constants'

module FFI
  # Ruby representation of stat.h struct
  class Stat
    class << self
      # @return [Stat] Newly allocated stat representing a regular file - see {Stat#file}
      def file(**fields)
        new.file(**fields)
      end

      # @return [Stat] Newly allocated stat representing a directory - see {Stat#dir}
      def dir(**fields)
        new.dir(**fields)
      end
      alias directory dir
    end

    # We need to be a StructWrapper because of clash with #size
    include StructWrapper

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

    time_members = Native
                   .members
                   .select { |m| m.to_s.start_with?('st_') && m.to_s.end_with?('timespec') }
                   .map { |m| m[3..-5].to_sym }

    ffi_attr_reader(*time_members, format: 'st_%sspec', &:time)

    ffi_attr_writer(*time_members, format: 'st_%sspec', simple: false) do |sec, nsec = 0|
      t = self[__method__[0..-2].to_sym]
      t.set_time(sec, nsec)
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
    def dir(mode:, nlink: 1, uid: Process.uid, gid: Process.gid, **args)
      mode = ((S_IFDIR & S_IFMT) | (mode & 0o777))
      fill(mode: mode, uid: uid, gid: gid, nlink: nlink, **args)
    end
    alias directory dir
  end
end
