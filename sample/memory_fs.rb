#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ffi/libfuse'
require 'ffi/libfuse/filesystem/virtual_fs'

# A simple in-memory filesystem defined with hashes.
class MemoryFS < FFI::Libfuse::Filesystem::VirtualFS; end

# Set this to test multi-threading etc...
main_class = ENV.fetch('MEMORY_FS_SKIP_DEFAULT_ARGS', 'N') == 'Y' ? FFI::Libfuse::Main : FFI::Libfuse

exit(main_class.fuse_main(operations: MemoryFS.new)) if __FILE__ == $0
