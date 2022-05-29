#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ffi/libfuse'

# Hello World!
class HelloFS
  include FFI::Libfuse::Adapter::Ruby
  include FFI::Libfuse::Adapter::Fuse2Compat

  # FUSE Configuration methods

  def fuse_options(args)
    args.parse!({ 'subject=' => :subject }) do |key:, value:, **|
      raise FFI::Libfuse::Error, 'subject option must be at least 2 characters' unless value.size >= 2

      @subject = value if key == :subject
      :handled
    end
  end

  def fuse_help
    '-o subject=<subject>   a target to say hello to'
  end

  def fuse_configure
    @subject ||= 'World!'
    @content = "Hello #{@subject}\n"
  end

  # FUSE callbacks

  def getattr(path, stat, *_args)
    case path
    when '/'
      stat.directory(mode: 0o550)
    when '/hello.txt'
      stat.file(mode: 0o440, size: @content.size)
    else
      raise Errno::ENOENT
    end
  end

  def readdir(_path, *_args)
    yield 'hello.txt'
  end

  def read(_path, *_args)
    @content
  end
end

# Start the file system
FFI::Libfuse.fuse_main(operations: HelloFS.new) if __FILE__ == $0
