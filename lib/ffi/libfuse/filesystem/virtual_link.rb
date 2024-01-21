# frozen_string_literal: true

module FFI
  module Libfuse
    module Filesystem
      module Ruby
        # Filesystem methods representing a symbolic link
        # Satisfies the contract of {Adapter::Ruby}
        module VirtualLink
          attr_accessor :target

          include VirtualNode
          def initialize(accounting: nil)
            @target = target
            super(accounting: accounting)
          end

          def readlink(_path, size)
            @target[0, size - 1] # buffer size needs null terminator
          end

          def symlink(from_path, path)
            raise Errno::ENOENT unless root?(path)

            @target = from_path
            init_node(0o777)
          end

          def link(_from_path, path)
            raise Errno::ENOENT unless root?(path)

            # Cannot hard link a symbolic link
            raise Errno::EPERM
          end

          def unlink(path)
            raise Errno::ENOENT unless root?(path)

            accounting&.adjust(0, -1)
          end

          def getattr(path, stat = nil, _ffi = nil)
            # We don't exist until create or otherwise or virtual stat exists
            raise Errno::ENOENT unless root?(path) && virtual_stat

            stat&.symlink(size: @target.length + 1, **virtual_stat)
            self
          end
        end
      end

      # A Filesystem that represents a single symbolic link at the root
      class VirtualLink
        prepend Adapter::Ruby::Prepend
        include Fuse2Compat
        include Ruby::VirtualLink
      end
    end
  end
end
