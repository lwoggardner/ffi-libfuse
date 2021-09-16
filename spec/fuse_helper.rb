# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/ffi/libfuse'
require 'open3'

# utilities for running tests with fuse filesystems
module LibfuseHelper
  # rubocop:disable Metrics/AbcSize

  # Runs the single threaded fuse loop
  # on a pre configured mock fuse filesystem
  # Executes fork block to perform filesystem operations in a separate process that is expected to return success
  def with_fuse(operations, *args, **options)
    raise 'Needs block' unless block_given?

    safe_fuse do |mnt|
      fuse = FFI::Libfuse::Main.fuse_create(mnt, *args, operations: operations)
      _(fuse).wont_be_nil
      _(fuse).must_be(:mounted?)
      _(mounted?(mnt) && true).must_equal(true)
      # Rake owns INT
      fuse.default_traps.delete(:TERM)
      fuse.default_traps.delete(:INT)

      fpid = Kernel.fork { yield mnt }
      t = Thread.new { fuse.run(foreground: true, **options) }
      _pid, block_result = Process.waitpid2(fpid)
      fuse.exit
      run_result = t.value
      _(fuse).wont_be(:mounted?)
      _(block_result).must_equal(0, 'File operations')
      _(run_result).must_equal(0, 'Fuse run')
    end
  end
  # rubocop:enable Metrics/AbcSize

  def mounted?(mnt, filesystem = nil)
    mounts = File.readlines('/proc/mounts')
    mounts.detect do |line|
      line_fs, line_mnt, = line.split(/\s+/)
      (!filesystem || line_fs == filesystem) && line_mnt == mnt
    end
  end

  # Runs a filesystem in a separate process via Open3.capture3
  # if we daemonize then we will not capture any output
  def run_sample(filesystem, *args)
    safe_fuse do |mnt|
      t = Thread.new do
        Bundler.with_unbundled_env do
          Open3.capture3('bundle', 'exec', "sample/#{filesystem}", mnt, *args, binmode: true)
        end
      end
      sleep 1

      begin
        if block_given?
          raise "#{filesystem} not mounted at #{mnt}" unless mounted?(mnt, filesystem)

          yield mnt
        end
        unmount(mnt) if mounted?(mnt, filesystem)
        o, e, s = t.value
        [o, e, s.exitstatus]
      rescue StandardError, Minitest::Assertion
        unmount(mnt) if mounted?(mnt, filesystem)
        o, e, _s = t.value
        warn "Errors\n#{e}" unless e.empty?
        warn "Output\n#{o}" unless o.empty?
        raise
      end
    end
  end

  def unmount(mnt)
    system("fusermount -zu #{mnt} >/dev/null 2>&1")
  end

  def safe_fuse
    Dir.mktmpdir('ffi-libfuse-spec') do |mountpoint|
      yield mountpoint
    ensure
      unmount(mountpoint)
    end
  end
end
