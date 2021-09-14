#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ffi/libfuse'

# An empty file system
class NoFS
  include FFI::Libfuse::Adapter::Context
  include FFI::Libfuse::Adapter::Fuse3Support
  include FFI::Libfuse::Adapter::Ruby

  OPTIONS = { 'log=' => :log }.freeze

  def fuse_options
    OPTIONS
  end

  def fuse_help
    <<~END_HELP
      NoFS options:
          -o log=NAME            the log file#{'     '}

    END_HELP
  end

  def fuse_version
    'NoFS: Version x.y.z'
  end

  def fuse_opt_proc(_data, arg, key, _outargs)
    case key
    when :log
      @logfile = arg[4..]
      return :handled
    end
    :keep
  end

  def getattr(_ctx, path, stat)
    raise Errno::ENOENT unless path == '/'

    stat.directory(mode: 0o555)
  end

  def readdir(_ctx, _path, _offset, _ffi)
    %w[. ..].each { |d| yield(d, nil) }
  end

  def log
    @log ||= File.open(@logfile || '/tmp/no_fs.out', 'a')
  end

  def init(ctx, conn, cfg = nil)
    log.puts("NoFS init ctx- #{ctx.inspect}") if ctx
    log.puts("NoFS init conn - #{conn.inspect}") if conn && !conn.null?
    log.puts "NoFS init cfg #{cfg.inspect}" if cfg && !cfg.null?
    warn 'NoFS: DEBUG enabled' if debug?
    log.flush
    'INIT_DATA'
  end

  def destroy(obj, *_rest)
    # If the fs is not cleanly unmounted the init data will have been GC'd by the time this is called
    log.puts("NoFS destroy- #{obj.inspect}") if !obj.is_a?(WeakRef) || obj.weakref_alive?
    log.puts "NoFS destroy- pid=#{Process.pid}"
  end
end

exit(FFI::Libfuse.fuse_main($0, *ARGV, operations: NoFS.new, private_data: 'MAIN_DATA')) if __FILE__ == $0
