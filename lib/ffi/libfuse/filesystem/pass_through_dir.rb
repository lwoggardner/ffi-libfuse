# frozen_string_literal: true

require_relative 'mapped_files'

module FFI
  module Libfuse
    module Filesystem
      # A Filesystem that maps paths to an underlying directory
      class PassThroughDir
        include MappedFiles
        include Adapter::Debug
        include Adapter::Safe
        include Utils

        # @return [String] The base directory
        attr_accessor :base_dir

        # @!group FUSE Callbacks

        # @return [Dir] the directory at {#map_path}(path)
        def opendir(path, _ffi)
          Dir.new(map_path(path))
        end

        # Removes the directory at {#map_path}(path)
        def rmdir(path)
          return Dir.rmdir(map_path(path)) unless root?(path)

          accounting&.adjust(0, -1) if root?(path)
          self
        end

        # Creates the directory at {#map_path}(path)
        def mkdir(path, mode)
          return Dir.mkdir(map_path(path), mode) unless root?(path)

          accounting&.adjust(0, +1)
          self
        end

        # Creates the File at {#map_path}(path)
        def create(path, perms = 0o644, ffi = nil)
          File.open(map_path(path), ffi&.flags, perms)
        end

        # @!endgroup

        # @return [String] {#base_dir} + path
        def map_path(path)
          root?(path) ? @base_dir : "#{@base_dir}#{path}"
        end
      end
    end
  end
end
