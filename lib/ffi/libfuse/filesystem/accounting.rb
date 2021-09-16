# frozen_string_literal: true

require_relative '../../stat_vfs'

module FFI
  module Libfuse
    module Filesystem
      # Helper for filesystem accounting
      class Accounting
        OPTIONS = { 'max_space=' => :max_space, 'max_nodes=' => :max_nodes }.freeze

        HELP =
          <<~END_HELP
            #{name} options:
                -o max_space=<int>     maximum space consumed by files, --ve will always show free space
                -o max_nodes=<int>     maximum number of files and directories, -ve will always show free nodes

          END_HELP

        def fuse_opt_proc(key:, value:, **)
          return :keep unless OPTIONS.values.include?(key)

          public_send("#{key}=", value.to_i)
          :handled
        end

        # @return [Integer] maximum allowed space in bytes
        #
        #   Positive values will limit values in {adjust} to stay below this value
        #
        #   Negative or zero will simply report this amount of space as 'free' in  {to_statvfs}
        attr_accessor :max_space

        # @return [Integer] maximum number of (virtual) inodes
        #
        #   Positive values will limit {adjust} to stay below this value
        #
        #   Negative or zero will simply report this number of inodes as 'free' in {to_statvfs}
        attr_accessor :max_nodes

        # @return [Integer] accumulated space in bytes
        attr_reader :space

        # @return [Integer] accumulated inodes (typically count of files and directories)
        attr_reader :nodes

        # @return [Integer] block size for statvfs
        attr_accessor :block_size

        def initialize(max_space: 0, max_nodes: 0)
          @nodes = 0
          @space = 0
          @max_space = max_space
          @max_nodes = max_nodes
        end

        # Adjust accumlated statistics
        # @param [Integer] delta_space change in {#space} usage
        # @param [Integer] delta_nodes change in {#nodes} usage
        # @return [self]
        # @raise [Errno::ENOSPC] if adjustment {#space}/{#nodes} would exceed {#max_space} or {#max_nodes}
        def adjust(delta_space, delta_nodes = 0, strict: true)
          strict_space = strict && delta_space.positive? && max_space.positive?
          raise Errno::ENOSPC if strict_space && space + delta_space > max_space

          strict_nodes = strict && delta_nodes.positive? && max_nodes.positive?
          raise Errno::ENOSPC if strict_nodes && nodes + delta_nodes > max_nodes

          @nodes += delta_nodes
          @space += delta_space
          self
        end

        # Adjust for incremental write
        # @param [Integer] current_size
        # @param [Integer] data_size size of new data
        # @param [Integer] offset offset of new data
        # @return [self]
        def write(current_size, data_size, offset, strict: true)
          adjust(offset + data_size - current_size, strict: strict) if current_size < offset + data_size
          self
        end

        # Adjust for truncate
        # @param [Integer] current_size
        # @param [Integer] new_size the size being truncated to
        # @return [self]
        def truncate(current_size, new_size)
          adjust(new_size - current_size, strict: false) if new_size < current_size
          self
        end

        # rubocop:disable Metrics/AbcSize

        # @param [FFI::StatVfs] statvfs an existing statvfs buffer to fill
        # @param [Integer] block_size
        # @return [FFI::StatVfs] the filesystem statistics
        def to_statvfs(statvfs = FFI::StatVfs.new, block_size: self.block_size || 1024)
          used_blocks, max_blocks = [space, max_space].map { |s| s / block_size }
          max_blocks = used_blocks - max_blocks unless max_blocks.positive?
          max_files = max_nodes.positive? ? max_nodes : nodes - max_nodes
          statvfs.bsize    = block_size # block size (in Kb)
          statvfs.frsize   = block_size # fragment size pretty much always bsize
          statvfs.blocks   = max_blocks
          statvfs.bfree    = max_blocks - used_blocks
          statvfs.bavail   = max_blocks - used_blocks
          statvfs.files    = max_files
          statvfs.ffree    = max_files - nodes
          statvfs
        end
        # rubocop:enable Metrics/AbcSize
      end
    end
  end
end
