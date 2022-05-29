# frozen_string_literal: true

require_relative 'mapped_files'

module FFI
  module Libfuse
    module Filesystem
      # A read-only directory of {MappedFiles}
      #
      # Subclasses must implement {#entries} and {#map_path}
      class MappedDir
        include MappedFiles
        include Utils
        attr_accessor :stat

        # @!method entries
        #  @abstract
        #  @return [Enumerable] set of entries in this directory (excluding '.' and '..')

        def initialize(accounting: nil)
          @accounting = accounting
          @root = VirtualNode.new(accounting: accounting)
        end

        # @!group Fuse Callbacks

        # For the root path provides this directory's stat information, otherwise passes on to the next filesystem
        def getattr(path, stat = nil, _ffi = nil)
          return super unless root?(path)

          stat&.directory(@root.virtual_stat.merge({ nlink: entries.size + 2 }))

          self
        end

        # For root path enumerates {#entries}
        # @raise [Errno::ENOTDIR] unless root path
        def readdir(path, *_args, &block)
          raise Errno::ENOTDIR unless root?(path)

          %w[. ..].concat(entries).each(&block)
        end

        def mkdir(path, mode, *_args)
          raise Errno::EROFS unless root?(path)

          @root.init_node(mode)
        end

        # @!endgroup

        # Passes FUSE Callbacks on to the {#root} filesystem
        def method_missing(method, path = nil, *args, &block)
          return @root.public_send(method, path, *args, &block) if @root.respond_to?(method) && root?(path)

          raise Errno::ENOTSUP if FuseOperations.path_callbacks.include?(method)

          super
        end

        def respond_to_missing?(method, private = false)
          (FuseOperations.fuse_callbacks.include?(method) && @root.respond_to?(method, false)) || super
        end

        # subclass only call super for root path
        def map_path(path)
          raise ArgumentError, "map_path received non root path #{path}" unless root?(path)

          [path, @root]
        end
      end
    end
  end
end
