#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ffi/libfuse'
require 'ffi/libfuse/filesystem/virtual_fs'

class MemoryFS < FFI::Libfuse::Filesystem::VirtualFS; end

# A simple in-memory filesystem defined with hashes.
exit(FFI::Libfuse.fuse_main(operations: MemoryFS.new)) if __FILE__ == $0
