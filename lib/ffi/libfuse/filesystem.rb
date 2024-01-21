# frozen_string_literal: true

require_relative 'filesystem/virtual_fs'

module FFI
  module Libfuse
    # This module namespace contains classes and modules to assist with building and composing filesystems
    #
    # ### Virtual Filesystems
    # Classes to help compose in-memory filesystems {VirtualFS}, {VirtualDir}, {VirtualFile}, {VirtualLink}
    #
    # ### Mapped Filesystem
    # Modules to map paths in the fuse filesystem to either real files or other filesystem objects
    # {MappedFiles}, {MappedDir}
    #
    # ### Pass-through filesystems
    # Classes using the mapped modules above to pass fuse callbacks directly to an underlying file/directory
    # {PassThroughDir}, {PassThroughFile}
    #
    # ### Utilities
    # {Utils} similar to FileUtils to operate directly on filesystem objects, eg to build up initial content
    module Filesystem
    end
  end
end
