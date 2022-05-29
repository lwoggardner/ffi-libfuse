#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ffi/libfuse'

# An empty file system
class NoFS
  include FFI::Libfuse::Adapter::Context
  include FFI::Libfuse::Adapter::Ruby
  include FFI::Libfuse::Adapter::Fuse3Support # must run outside of Adapter::Ruby

  OPTIONS = { 'log=' => :log }.freeze

  def fuse_options(args)
    args.parse!(OPTIONS) do |key:, value:, **|
      case key
      when :log
        @logfile = value
      else
        next :keep
      end
      :handled
    end
  end

  def fuse_help
    <<~END_HELP
      NoFS options:
          -o log=NAME            the log file#{'     '}

    END_HELP
  end

  def fuse_version
    "NoFS: Version x.y.z. Fuse3Compat=#{fuse3_compat?}"
  end

  def getattr(path, stat)
    raise Errno::ENOENT unless path == '/'

    stat.directory(mode: 0o555)
  end

  def readdir(_path, _offset, _ffi, &block)
    puts "NOFS Readdir: #{block}"
    %w[. ..].each(&block)
  end

  def log
    @log ||= File.open(@logfile || '/tmp/no_fs.out', 'a')
  end

  def init(_conn)
    ctx = FFI::Libfuse::Adapter::Context.fuse_context
    log.puts("NoFS init ctx- #{ctx.inspect}") if ctx
    warn 'NoFS: DEBUG enabled' if debug?
    log.flush
    'INIT_DATA'
  end

  def destroy(obj)
    # If the fs is not cleanly unmounted the init data will have been GC'd by the time this is called
    log.puts("NoFS destroy- #{obj.inspect}") if !obj.is_a?(WeakRef) || obj.weakref_alive?
    log.puts "NoFS destroy- pid=#{Process.pid}"
  end
end

exit(FFI::Libfuse::Main.fuse_main($0, *ARGV, operations: NoFS.new, private_data: 'MAIN_DATA')) if __FILE__ == $0
