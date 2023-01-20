# frozen_string_literal: true

require_relative 'accounting'
require 'stringio'

module FFI
  module Libfuse
    module Filesystem
      module Ruby
        # Filesystem methods representing a single synthetic file at the root and satisfying
        # Satisfies the contract of {Adapter::Ruby}
        module VirtualFile
          include VirtualNode

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

          def getattr(path, stat, ffi = nil)
            # We don't exist until create or otherwise or virtual stat exists
            raise Errno::ENOENT unless root?(path) && virtual_stat

            stat.file(size: (ffi&.fh || content).size, **virtual_stat)
            self
          end

          # @param [String] _path ignored, expected to be '/'
          # @param [Integer] mode
          # @param [FuseFileInfo] ffi
          # @return [Object] a file handled (captured by {Adapter::Ruby::Prepend})
          def create(_path, mode, ffi = nil)
            init_node(mode)
            @content = String.new(encoding: 'binary')
            sio(ffi) if ffi
          end

          def open(_path, ffi)
            virtual_stat[:atime] = Time.now.utc
            sio(ffi)
          end

          # write(const char* path, char *buf, size_t size, off_t offset, struct fuse_file_info* fi)
          def write(path, data, offset = 0, _ffi = nil)
            raise Errno::ENOENT unless root?(path)

            accounting&.write(content.size, data.size, offset)
            virtual_stat[:mtime] = Time.now.utc
            nil # just let the sio in ffi handle it
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
            io = ffi&.fh
            io || StringIO.new(content, ffi&.flags)
          end
        end
      end

      # A Filesystem representing a single synthetic file at the root
      class VirtualFile
        prepend Adapter::Ruby::Prepend
        include Fuse2Compat
        include Ruby::VirtualFile
      end
    end
  end
end
