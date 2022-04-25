# frozen_string_literal: true

require_relative 'mapped_files'

module FFI
  module Libfuse
    module Filesystem
      # A abstract directory of {MappedFiles}
      #
      # Subclasses must implement {#entries} and {#map_path}
      module MappedDir
        include MappedFiles

        # Default fills stat wth mode 750 and nlinks from size of entries
        # @param [FFI::Stat] stat to be filled with attributes for this directory
        # @return [void]
        def dir_stat(stat)
          stat.directory(mode: 0o0750, nlink: entries.size + 1)
        end

        # @!method entries
        #  @abstract
        #  @return [Enumerable] set of entries in this directory (excluding '.' and '..')

        # @!group Fuse Callbacks

        # For root path sets stat to {#dir_stat}, otherwise pass on to super {MappedFiles#getattr}
        # @return [self]
        def getattr(path, stat = nil, _ffi = nil)
          return super unless root?(path)

          dir_stat(stat) if stat
          self
        end

        # For root path enumerates {#entries}
        # @raise [Errno::ENOTDIR] unless root path
        def readdir(path, *_args, &block)
          return path_method(__method__, path, *args, block: block) { |_rp| Errno::ENOTDIR } unless root?(path)

          %w[. ..].each(&block)
          entries.each(&block)
        end

        # @return [self]
        # @raise [Errno::ENOTDIR] unless root path
        def opendir(path, *_args)
          return self if root?(path) # Help virtual dir get to us quickly

          path_method(__method__, path, *args) { |_rp| Errno::ENOTDIR }
        end

        # @!endgroup
      end
    end
  end
end
