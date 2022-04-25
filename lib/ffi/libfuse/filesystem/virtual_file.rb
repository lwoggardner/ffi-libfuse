# frozen_string_literal: true

require_relative 'accounting'
require 'stringio'

module FFI
  module Libfuse
    module Filesystem
      # A Filesystem representing a single synthetic file at the root
      class VirtualFile < VirtualNode
        prepend Adapter::Ruby::Prepend

        # @return [String] the (binary) content of the synthetic file
        attr_reader :content

        # Create an empty synthetic file
        def initialize(accounting: nil)
          super(accounting: accounting)
        end

        # @!visibility private
        def path_method(_method, *_args)
          raise Errno::ENOENT
        end

        # @!group FUSE Callbacks

        def getattr(path, stat)
          # We don't exist until create or otherwise or virtual stat exists
          raise Errno::ENOENT unless root?(path) && virtual_stat

          stat.file(size: content.size, **virtual_stat)
          self
        end

        # @param [String] _path ignored, expected to be '/'
        # @param [Integer] mode
        # @param [FuseFileInfo] ffi
        # @return [Object] a file handled (captured by {Adapter::Ruby::Prepend})
        def create(_path, mode, ffi)
          init_node(mode)
          @content = String.new(encoding: 'binary')
          sio(ffi)
        end

        def open(_path, ffi)
          virtual_stat[:atime] = Time.now.utc
          sio(ffi)
        end

        # op[:read] = [:pointer, :size_t, :off_t, FuseFileInfo.by_ref]
        def read(path, size, off, ffi)
          raise Errno::ENOENT unless root?(path)

          io = sio(ffi)
          io.seek(off)
          io.read(size)
        end

        # write(const char* path, char *buf, size_t size, off_t offset, struct fuse_file_info* fi)
        def write(path, data, offset = 0, ffi = nil)
          raise Errno::ENOENT unless root?(path)

          accounting&.write(content.size, data.size, offset)
          io = sio(ffi)
          io.seek(offset)
          io.write(data)
          virtual_stat[:mtime] = Time.now.utc
        end

        def truncate(path, size, ffi = nil)
          raise Errno::ENOENT unless root?(path)

          accounting&.truncate(content.size, size)
          sio(ffi).truncate(size)
          virtual_stat[:mtime] = Time.now.utc
        end

        def unlink(path)
          raise Errno::ENOENT unless root?(path)

          accounting&.adjust(-content.size, -1)
        end

        private

        def sio(ffi)
          ffi&.fh || StringIO.new(content, ffi.flags)
        end
      end
    end
  end
end
