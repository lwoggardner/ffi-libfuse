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
    attach_function :fuse_loop, [:fuse], :int
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

        native ? run_native(**options) : run_ruby(**options)
      rescue Errno => e
        -e.errno
      rescue StandardError, ScriptError => e
        warn "#{e}\n#{e.backtrace.join("\n")}"
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
      def run_ruby(foreground: true, single_thread: true, traps: {}, remember: false, **options)
        Ackbar.trap(default_traps.merge(traps)) do |signals|
          daemonize unless foreground

          # Monitor for signals (and cache cleaning if required)
          signals.monitor { fuse_cache_timeout(remember) }

          single_thread ? fuse_loop(**options) : fuse_loop_mt(**options)
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
      #    * connot use fuse_context (because the ruby thread is not the native thread)
      #
      # @api private
      # @param [Boolean] foreground
      # @param [Boolean] single_thread
      def run_native(foreground: true, single_thread: true, **options)
        raise 'Cannot run daemonized native multi-thread fuse_loop' if !single_thread && !foreground

        clear_default_traps
        (se = session) && Libfuse.fuse_set_signal_handlers(se)

        Libfuse.fuse_daemonize(foreground ? 1 : 0)
        single_thread ? Libfuse.fuse_loop(@fuse) : native_fuse_loop_mt(**options)
      ensure
        (se = session) && Libfuse.fuse_remove_signal_handlers(se)
      end

      # Ruby implementation of fuse default traps
      # @see Ackbar
      def default_traps
        exproc = ->(signame) { exit(signame) }
        @default_traps ||= { INT: exproc, HUP: exproc, TERM: exproc, TSTP: exproc, PIPE: 'IGNORE' }
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
      def fuse_loop(**_options)
        safe_fuse_process until fuse_exited?
      end

      # @api private
      # Ruby implementation of multi threaded fuse loop
      #
      # We cannot simulate the clone_fd behaviour of fuse_loop_mt as the required fd is not exposed in the low level
      # fuse api.
      #
      # @see ThreadPool ThreadPool for the mechanism that controls creation and termination of worker threads
      def fuse_loop_mt(max_idle_threads: 10, max_threads: nil, **_options)
        ThreadPool.new(name: 'FuseThread', max_idle: max_idle_threads.to_i, max_active: max_threads&.to_i) do
          raise StopIteration if fuse_exited?

          safe_fuse_process
        end.join
      end

      # @!visibility private

      def safe_fuse_process
        # sometimes we get null on unmount, and exit needs a chance to finish to avoid hangs
        fuse_process || (sleep(0.1) && false)
      end

      def teardown
        return unless @fuse

        self.exit&.join

        Libfuse.fuse_destroy(@fuse) if @fuse
        @fuse = nil
      ensure
        ObjectSpace.undefine_finalizer(self)
      end

      # Starts a thread to unmount the filesystem and stop the processing loop.
      # generally expected to be called from a signal handler
      # @return [Thread] the unmount thread
      def exit(_signame = nil)
        return unless @fuse

        # Unmount/exit in a separate thread so the main fuse thread can keep running.
        @exit ||= Thread.new do
          unmount

          # without this sleep before exit, MacOS does not complete unmounting
          sleep 0.2 if mac_fuse?

          Libfuse.fuse_exit(@fuse)
          true
        end
      end

      private

      def fuse_cache_timeout(remember)
        remember ? fuse_clean_cache : nil
      end

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

      def mac_fuse?
        FFI::Platform::IS_MAC
      end
    end
  end
end
