#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ffi/libfuse'
require 'ffi/libfuse/filesystem/pass_through_dir'

# Pass Through Filesystem - over a base directory
class PassThroughFS < FFI::Libfuse::Filesystem::PassThroughDir
  def fuse_options(args)
    args.parse!({ 'base_dir=' => :base_dir }) do |key:, value:, **|
      next :keep unless key == :base_dir

      raise FFI::Libfuse::Error, "#{value} is not a directory" unless Dir.exist?(value)

      self.base_dir = value
      :handled
    end
  end

  def fuse_help
    '-o base_dir=<dir>'
  end

  def fuse_configure
    self.base_dir ||= Dir.pwd
    warn "Using #{self.base_dir} as base directory for file operations" if debug?
  end
end

exit(FFI::Libfuse.fuse_main(operations: PassThroughFS.new)) if __FILE__ == $0
