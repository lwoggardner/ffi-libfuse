# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/ffi/libfuse'
require 'open3'
require 'sys-filesystem'

# utilities for running tests with fuse filesystems
module LibfuseHelper
  # rubocop:disable Metrics/AbcSize

  # Runs the single threaded fuse loop
  # on a pre configured mock fuse filesystem
  # Executes fork block to perform filesystem operations in a separate process that is expected to return success
  def with_fuse(operations, *args, **options)
    raise 'Needs block' unless block_given?

    # ignore MacOS special files
    args << '-onoappledouble,noapplexattr' if mac_fuse?
    safe_fuse do |mnt|

      # Start the fork before loading fuse (for MacOS)
      fpid = Process.fork do
        begin
          sleep 2.5 # Give fuse a chance to start
          yield mnt
        end
      end

      fuse = FFI::Libfuse::Main.fuse_create(mnt, *args, operations: operations)
      _(fuse).wont_be_nil
      _(fuse).must_be(:mounted?)
      #_(mounted?(mnt) && true).must_equal(true)
      # Rake owns INT
      fuse.default_traps.delete(:TERM)
      fuse.default_traps.delete(:INT)

      t = Thread.new { fuse.run(foreground: true, **options) }

      # TODO: Work out why waitpid2 hangs on mac unless the process has already finished
      #       and on travis!!
      sleep 10 if mac_fuse?

      _pid, block_status = Process.waitpid2(fpid)
      block_exit = block_status.exitstatus
      fuse.exit('fuse_helper')&.join
      run_result = t.value

      _(fuse).wont_be(:mounted?)
      _(block_exit).must_equal(0, 'File operations')
      _(run_result).must_equal(0, 'Fuse run')
      unless mac_fuse?
        _(mounted?(mnt) || false).must_equal(false, "Unmounted at OS level #{mnt}")
      end
    end
  end
  # rubocop:enable Metrics/AbcSize

  def mounted?(mnt, filesystem = '.*')
    type, prefix = mac_fuse? ? %w[macfuse /private] : %w[fuse]
    mounts = Sys::Filesystem.mounts.select { |m| m.mount_type == type }
    mounts.detect { |m| m.mount_point == "#{prefix}#{mnt}" }
  end

  # Runs a filesystem in a separate process via Open3.capture3
  # if we daemonize then we will not capture any output
  def run_sample(filesystem, *args, env: {})
    safe_fuse do |mnt|
      t = Thread.new do
        Bundler.with_unbundled_env do
          Open3.capture3(env, 'bundle', 'exec', "sample/#{filesystem}", mnt, "-ofsname=#{filesystem}", *args, binmode: true)
        end
      end
      sleep 1

      begin
        if block_given?
          raise "#{filesystem} not mounted at #{mnt}" unless mounted?(mnt, filesystem)

          yield mnt
        end
        unmount(mnt) if mounted?(mnt)
        o, e, s = t.value
        [o, e, s.exitstatus]
      rescue StandardError, Minitest::Assertion => _err
        unmount(mnt) if mounted?(mnt)
        o, e, _s = t.value
        warn "Errors\n#{e}" unless e.empty?
        warn "Output\n#{o}" unless o.empty?
        raise
      end
    end
  end

  def unmount(mnt)
    if mac_fuse?
      system("diskutil unmount force #{mnt} >/dev/null 2>&1")
    else
      system("fusermount -zu #{mnt} >/dev/null 2>&1")
    end
  end

  def safe_fuse
    Dir.mktmpdir('ffi-libfuse-spec') do |mountpoint|
      yield mountpoint
    ensure
      # Attempt to force unmount.
      unmount(mountpoint) if mounted?(mountpoint)
    end
  end

  def mac_fuse?
    FFI::Platform::IS_MAC
  end
end
