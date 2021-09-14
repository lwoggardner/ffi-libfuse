# frozen_string_literal: true

require_relative 'fuse_version'
require_relative 'thread_pool'
require_relative 'ackbar'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    typedef :pointer, :fuse
    typedef :pointer, :session

    attach_function :fuse_get_session, [:fuse], :session
    attach_function :fuse_set_signal_handlers, [:session], :int
    attach_function :fuse_remove_signal_handlers, [:session], :void
    attach_function :fuse_loop, [:fuse], :int, blocking: false
    attach_function :fuse_clean_cache, [:fuse], :int
    attach_function :fuse_exit, [:fuse], :void
    attach_function :fuse_destroy, [:fuse], :void
    attach_function :fuse_daemonize, [:int], :int

    class << self
      # @!visibility private
      # @!method fuse_get_session(fuse)
      # @!method fuse_set_signal_handlers(session)
      # @!method fuse_remove_signal_handlers(session)
      # @!method fuse_loop(fuse)
      # @!method fuse_clean_cache(fuse)
      # @!method fuse_exit(fuse)
      # @!method fuse_destroy(fuse) void
      # @!method fuse_daemonize(foreground) int
    end

    # @abstract Base class for Fuse, which itself is just a constant pointing to Fuse2 or Fuse3
    # @note This class documents the Ruby re-implementation of native fuse functions. It will not generally be used
    #  directly.
    class FuseCommon
      # Run the mounted filesystem until exit
      # @param [Boolean] native should we run the C native fuse_loop functions or the ruby implementation
      # @param [Hash<Symbol,Object>] options passed to {run_native} or {run_ruby}
      # @return [Integer] an exit code for the fuse process (0 for success)
      def run(native: false, **options)
        return false unless mounted?

        if native
          run_native(**options)
        else
          run_ruby(**options)
        end
      rescue Errno => e
        -e.errno
      rescue StandardError => e
        warn e
        warn e.backtrace.join("\n")
        -1
      ensure
        teardown
      end

      # @api private
      # @param [Boolean] foreground
      # @param [Boolean] single_thread
      # @param [Hash<String,Proc>] traps see {Ackbar.trap}
      #
      # Implement fuse loop in ruby
      #
      # Pros:
      #
      #    * multi-threading works
      #    * can set max_threads @see https://github.com/libfuse/libfuse/issues/203
      #    * can send signals to the FS (eg to reload)
      #    * daemonize works
      #
      # Cons:
      #
      #    * clone_fd is ignored
      #    * filesystem interrupts probably can't work
      def run_ruby(foreground: true, single_thread: true, traps: {}, **options)
        Ackbar.trap(default_traps.merge(traps)) do |signals|
          daemonize unless foreground

          if single_thread
            fuse_loop(signals: signals, **options)
          else
            fuse_loop_mt(signals: signals, **options)
          end
          0
        end
      end

      # Running fuse loop natively
      #
      #  Pros
      #
      #    * clone_fd will work
      #    * filesystem interrupts may work
      #
      #  Cons
      #
      #    * multi-threading will create a new ruby thread for every callback
      #    * cannot daemonize multi-threaded (hangs) TODO: Why - pthread_lock?, GVL?
      #    * cannot pass signals to the filesystem
      #
      # @api private
      # @param [Boolean] foreground
      # @param [Boolean] single_thread
      #
      def run_native(foreground: true, single_thread: true, **options)
        if !single_thread && !foreground
          warn 'Cannot run native multi-thread fuse_loop when daemonized. Using single_thread mode'
          single_thread = true
        end

        clear_default_traps
        (se = session) && Libfuse.fuse_set_signal_handlers(se)

        Libfuse.fuse_daemonize(foreground ? 1 : 0)

        if single_thread
          Libfuse.fuse_loop(@fuse)
        else
          native_fuse_loop_mt(**options)
        end
      ensure
        (se = session) && Libfuse.fuse_remove_signal_handlers(se)
      end

      # Tell the processing loop to stop and force unmount the filesystem which is unfortunately required to make
      # the processing threads, which are mostly blocked on io reads from /dev/fuse fd, to exit.
      def exit
        Libfuse.fuse_exit(@fuse) if @fuse
        # Force threads blocked reading on #io to finish
        unmount
      end

      # Ruby implementation of fuse default traps
      # @see Ackbar
      def default_traps
        @default_traps ||= { INT: -> { exit }, HUP: -> { exit }, TERM: -> { exit }, PIPE: 'IGNORE' }
      end

      # @api private
      # Ruby implementation of fuse_daemonize which does not work under MRI probably due to the way ruby needs to
      # understand native threads.
      def daemonize
        raise 'Cannot daemonize without support for fork' unless Process.respond_to?(:fork)

        # pipe to wait for fork
        pr, pw = ::IO.pipe

        if Process.fork
          # rubocop:disable Style/RescueModifier
          status = pr.read(1).unpack1('c') rescue 1
          Kernel.exit!(status)
          # rubocop:enable Style/RescueModifier
        end

        begin
          Process.setsid

          Dir.chdir '/'

          # close/redirect file descriptors
          $stdin.close

          [$stdout, $stderr].each { |io| io.reopen('/dev/null', 'w') }

          pw.write([0].pack('c'))
        ensure
          pw.close
        end
      end

      # @api private
      # Keep track of time until next cache clean for the caching performed by libfuse itself
      def fuse_clean_cache
        now = Time.now
        @next_cache_clean ||= now
        return @next_cache_clean - now unless now >= @next_cache_clean

        delay = Libfuse.fuse_clean_cache(@fuse)
        @next_cache_clean = now + delay
        delay
      end

      # @api private
      # Ruby implementation of single threaded fuse loop
      def fuse_loop(signals:, remember: false, **_options)
        loop do
          break unless mounted?

          timeout = remember ? fuse_clean_cache : nil

          ready, _ignore_writable, errors = ::IO.select([io, signals.pr], [], [io], timeout)

          next unless ready || errors

          raise 'FUSE error' unless errors.empty?

          break if ready.include?(io) && !process

          break if ready.include?(signals.pr) && !signals.next
        rescue Errno::EBADF
          raise if mounted? # This will occur on exit
        end
      end

      # @api private
      # Ruby implementation of multi threaded fuse loop
      #
      # We cannot simulate the clone_fd behaviour of fuse_loop_mt as the required fd is not exposed in the low level
      # fuse api.
      #
      # @see ThreadPool ThreadPool for the mechanism that controls creation and termination of worker threads
      def fuse_loop_mt(signals:, max_idle_threads: 10, max_threads: nil, remember: false, **_options)
        # Monitor for signals (and cache cleaning if required)

        signals.monitor { remember ? fuse_clean_cache : nil }
        ThreadPool.new(name: 'FuseThread', max_idle: max_idle_threads.to_i, max_active: max_threads) { process }.join
      end

      # @!visibility private
      def teardown
        return unless @fuse

        unmount
        Libfuse.fuse_destroy(@fuse)
        ObjectSpace.undefine_finalizer(self)
        @fuse = nil
      end

      # @!visibility private
      def session
        return nil unless @fuse

        @session ||= Libfuse.fuse_get_session(@fuse)
        @session.null? ? nil : @session
      end

      # Allow fuse to handle default signals
      def clear_default_traps
        %i[INT HUP TERM PIPE].each do |sig|
          prev = Signal.trap(sig, 'SYSTEM_DEFAULT')
          Signal.trap(sig, prev) unless prev == 'DEFAULT'
        end
      end
    end
  end
end
