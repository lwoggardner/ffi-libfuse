# frozen_string_literal: true

require_relative '../libfuse'
require 'open3'
require 'sys-filesystem'

# utilities for running tests with fuse filesystems
module FFI
  module Libfuse
    # Can be included test classes to assist with running/debugging filesystems
    module TestHelper
      # Runs the fuse loop on a pre configured fuse filesystem
      # @param [FuseOperations] operations
      # @param [Array<String>] args to pass to  {FFI::Libfuse::Main.fuse_create}
      # @param [Hash] options to pass to {FFI::Libfuse::FuseCommon.run}
      # @yield [mnt]
      #   caller can execute and test file operations using mnt and ruby File/Dir etc
      #   the block is run in a forked process and is successful unless an exception is raised
      # @yieldparam [String] mnt the temporary directory used as the mount point
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

          run_fuse(mnt, *args, operations: operations, **options) do
            # TODO: Work out why waitpid2 hangs on mac unless the process has already finished
            sleep 10 if mac_fuse?

            _pid, block_status = Process.waitpid2(fpid)
            block_exit = block_status.exitstatus
            raise FFI::Libfuse::Error, "forked file operations failed with #{block_exit}" unless block_exit.zero?
          end
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

        t, err = safe_fuse do |mnt|
          t = Thread.new { open3_filesystem(args, env, filesystem, fsname, mnt) }
          sleep 1

          begin
            raise Error, "#{fsname} not mounted at #{mnt}" if block_given? && !mounted?(mnt, fsname)

            yield mnt if block_given?
            [t, nil]
          rescue Minitest::Assertion, StandardError => e
            [t, e]
          end
        end

        o, e, s = t.value
        return [o, e, s.exitstatus] unless err

        warn "Errors\n#{e}" unless e.empty?
        warn "Output\n#{o}" unless o.empty?
        raise err
      end

      def mounted?(mnt, _filesystem = '.*')
        type, prefix = mac_fuse? ? %w[macfuse /private] : %w[fuse]
        mounts = Sys::Filesystem.mounts.select { |m| m.mount_type == type }
        mounts.detect { |m| m.mount_point == "#{prefix}#{mnt}" }
      end

      def unmount(mnt)
        if mac_fuse?
          system("diskutil unmount force #{mnt} >/dev/null 2>&1")
        else
          system("fusermount#{FUSE_MAJOR_VERSION == 3 ? '3' : ''} -zu #{mnt} >/dev/null 2>&1")
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

      private

      def open3_filesystem(args, env, filesystem, fsname, mnt)
        if ENV['BUNDLER_GEMFILE']
            Open3.capture3(env, 'bundle', 'exec', filesystem.to_s, mnt, "-ofsname=#{fsname}", *args, binmode: true)
        else
          Open3.capture3(env, filesystem.to_s, mnt, "-ofsname=#{fsname}", *args, binmode: true)
        end
      end

      def run_fuse(mnt, *args, operations:, **options)
        fuse = mount_fuse(mnt, *args, operations: operations)
        begin
          t = Thread.new do
            Thread.current.name = 'Fuse Run'
            # Rake owns INT
            fuse.run(foreground: true, traps: { INT: nil, TERM: nil }, **options)
          end

          yield
        ensure
          fuse.exit('fuse_helper')&.join
          run_result = t.value

          raise FFI::Libfuse::Error, 'fuse is still mounted after fuse.exit' if fuse.mounted?
          raise FFI::Libfuse::Error, "fuse run failed #{run_result}" unless run_result.zero?

          if !mac_fuse? && mounted?(mnt)
            raise FFI::Libfuse::Error, "OS reports fuse is still mounted at #{mnt} after fuse.exit"
          end
        end
      end

      def mount_fuse(mnt, *args, operations:)
        operations.fuse_debug(args.include?('-d')) if operations.respond_to?(:fuse_debug)

        fuse = FFI::Libfuse::Main.fuse_create(mnt, *args, operations: operations)
        raise FFI::Libfuse::Error, 'No fuse object returned from fuse_create' unless fuse
        raise FFI::Libfuse::Error, 'fuse object is not mounted?' unless fuse.mounted?

        fuse
      end
    end
  end
end
