# frozen_string_literal: true

require_relative '../libfuse'
require 'open3'
require 'sys-filesystem'

# utilities for running tests with fuse filesystems
module FFI
  module Libfuse
    # Can be included test classes to assist with running/debugging filesystems
    module TestHelper
      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/MethodLength

      # Runs the fuse loop on a pre configured fuse filesystem
      # @param [FuseOperations] operations
      # @param [Array<String>] args to pass to  {FFI::Libfuse::Main.fuse_create}
      # @param [Hash] options to pass to {FFI::Libfuse::FuseCommon.run}
      # @yield [mnt]
      #   caller can execute and test file operations using mnt and ruby File/Dir etc
      #   the block is run in a forked process and is successful unless an exception is raised
      # @yieldparam [String] mnt the temporary direct used as the mount point
      # @raise [Error] if unexpected state is found during operations
      # @return [void]
      def with_fuse(operations, *args, **options)
        raise ArgumentError, 'Needs block' unless block_given?

        # ignore MacOS special files
        args << '-onoappledouble,noapplexattr' if mac_fuse?
        safe_fuse do |mnt|
          # Start the fork before loading fuse (for MacOS)
          fpid = Process.fork do
            sleep 2.5 # Give fuse a chance to start
            yield mnt
          end

          fuse = FFI::Libfuse::Main.fuse_create(mnt, *args, operations: operations)
          raise FFI::Libfuse::Error, 'No fuse object returned from fuse_create' unless fuse

          # Rake owns INT
          fuse.default_traps.delete(:TERM)
          fuse.default_traps.delete(:INT)

          raise FFI::Libfuse::Error, 'fuse object is not mounted?' unless fuse.mounted?

          t = Thread.new { fuse.run(foreground: true, **options) }

          # TODO: Work out why waitpid2 hangs on mac unless the process has already finished
          #       and on travis!!
          sleep 10 if mac_fuse?

          _pid, block_status = Process.waitpid2(fpid)
          block_exit = block_status.exitstatus
          fuse.exit('fuse_helper')&.join
          run_result = t.value

          raise FFI::Libfuse::Error, 'fuse is still mounted after fuse.exit' if fuse.mounted?
          raise FFI::Libfuse::Error, "forked file operations failed with #{block_exit}" unless block_exit.zero?
          raise FFI::Libfuse::Error, "fuse run failed #{run_result}" unless run_result.zero?

          if !mac_fuse? && mounted?(mnt)
            raise FFI::Libfuse::Error, "OS reports fuse is still mounted at #{mnt} after fuse.exit"
          end

          true
        end
      end

      # Runs a filesystem in a separate process
      # @param [String] filesystem path to filesystem executable
      # @param [Array<String>] args to pass the filesystem
      # @param [Hash<String,String>] env environment to run the filesystem under
      # @yield [mnt]
      #   caller can execute and test file operations using mnt and ruby File/Dir etc
      # @yieldparam [String] mnt the temporary direct used as the mount point
      # @raise [Error] if unexpected state is found during operations
      # @return [Array] stdout, stderr, exit code as captured by Open3.capture3
      # @note if the filesystem is configured to daemonize then no output will be captured
      def run_filesystem(filesystem, *args, env: {})
        fsname = File.basename(filesystem)
        safe_fuse do |mnt|
          t = Thread.new do
            if defined?(Bundler)
              Bundler.with_unbundled_env do
                Open3.capture3(env, 'bundle', 'exec', filesystem.to_s, mnt, "-ofsname=#{fsname}", *args, binmode: true)
              end
            else
              Open3.capture3(env, filesystem.to_s, mnt, "-ofsname=#{fsname}", *args, binmode: true)
            end
          end
          sleep 1

          begin
            if block_given?
              raise Error, "#{fsname} not mounted at #{mnt}" unless mounted?(mnt, fsname)

              yield mnt
            end
            # rubocop:disable Lint/RescueException
            # Minitest::Assertion and other test assertion classes are not derived from StandardError
          rescue Exception => _err
            # rubocop:enable Lint/RescueException
            unmount(mnt) if mounted?(mnt)
            o, e, _s = t.value
            warn "Errors\n#{e}" unless e.empty?
            warn "Output\n#{o}" unless o.empty?
            raise
          end

          unmount(mnt) if mounted?(mnt)
          o, e, s = t.value
          [o, e, s.exitstatus]
        end
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/MethodLength

      def mounted?(mnt, _filesystem = '.*')
        type, prefix = mac_fuse? ? %w[macfuse /private] : %w[fuse]
        mounts = Sys::Filesystem.mounts.select { |m| m.mount_type == type }
        mounts.detect { |m| m.mount_point == "#{prefix}#{mnt}" }
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
  end
end
