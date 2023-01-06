# frozen_string_literal: true

require_relative 'accounting'
require_relative 'mapped_files'

module FFI
  module Libfuse
    module Filesystem
      # Represents a single regular file at a given underlying path
      class PassThroughFile
        include MappedFiles

        # @param [String] real_path
        def initialize(real_path)
          @real_path = real_path
        end

        # @!visibility private
        def map_path(path)
          raise Errno::ENOENT unless root?(path)

          @real_path
        end

        # @!group FUSE Callbacks

        # Adjust accounting to add a node
        def create(path, perms, ffi)
          raise Errno::ENOENT unless root?(path)

          accounting&.adjust(0, +1)
          super
        end

        # Adjust accounting to remove a node
        def unlink(path)
          raise Errno::ENOENT unless root?(path)

          accounting&.adjust(0, -1)
          super
        end
      end
    end
  end
end
