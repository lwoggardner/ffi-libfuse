# frozen_string_literal: true

require_relative 'fuse_version'

module FFI
  module Libfuse
    # Its a trap!
    #
    # Implements the self-pipe trick for handling signals in multi-threaded ruby programs
    class Ackbar
      # Read side of the self-pipe
      # @return [IO] for use with IO.select only
      # @see monitor
      # @see next
      attr_reader :pr

      class << self
        # Run a block with the given traps, restoring the original traps on completion
        # @param [Hash] traps map of signal to handler as per Signal.trap
        # @yieldparam [Ackbar] signals
        # @return [Object] the result of the block
        def trap(traps, force: false)
          signals = new(traps, force: force)
          yield signals
        ensure
          signals&.restore
        end
      end

      # @param [Hash<Symbol|String|Integer,String|Proc>] traps
      #   Map of signal or signo to signal handler as per Signal.trap
      # @param [Boolean] force
      #   If not set traps that are not currently set to 'DEFAULT' will be ignored
      def initialize(traps, force: false, signal: Signal)
        @signal = signal
        @traps = traps.transform_keys { |k| signame(k) }
        @pr, @pw = ::IO.pipe
        @monitor = nil
        @restore = @traps.map { |(sig, handler)| [sig, trap(sig, handler, force: force)] }.to_h
      end

      # Handle the next available signal on the pipe (without blocking)
      # @return [Boolean] false if pipe is closed, true if pipe would block
      # @return [Array<String,Object>] signal name, signal result when a signal has been processed
      def next
        signame = signal.signame(@pr.read_nonblock(1).unpack1('c'))
        t = @traps[signame]
        [signame, t.arity.zero? ? t.call : t.call(signame)]
      rescue EOFError
        # the signal pipe writer is closed - we are exiting.
        @pr.close
        false
      rescue Errno::EWOULDBLOCK, Errno::EAGAIN
        # oh well...
        true
      end

      # Restore traps as they were at #new and close the write side of the pipe
      def restore
        @restore.each_pair { |signame, handler| signal.trap(signame, handler) }
        @restore = nil
        @pw.close
        @monitor&.join
      end
      alias close restore

      # Start a thread to monitor for signals optionally yields between signals
      # @param [String] name The name of the monitor thread
      # @yieldreturn [Integer] timeout in seconds or nil to wait until signal or {restore}
      # @return [Thread] the monitor thread
      def monitor(name: 'SignalMonitor')
        @monitor ||= Thread.new do
          Thread.current.name = name
          loop do
            timeout = block_given? ? yield : nil

            ready, _ignore_writable, _errors = ::IO.select([@pr], [], [], timeout)

            break if ready&.include?(@pr) && !self.next
          end
        end
      end

      # @!visibility private
      # normalize signal identifiers to things that are keys in Signal.list
      def signame(sig)
        sig.is_a?(Integer) ? signal.signame(sig) : sig.to_s.upcase.sub(/^SIG/, '')
      end

      private

      attr_reader :signal

      def trap(signame, handler, force: false)
        prev =
          case handler
          when String, Symbol
            signal.trap(signame, handler.to_s)
          else
            signal.trap(signame) { |signo| send_signal(signo) }
          end

        signal.trap(signame, prev) unless force || prev == 'DEFAULT'
        prev
      end

      def send_signal(signo)
        @pw&.write([signo].pack('c')) unless @pw&.closed?
      end
    end
  end
end
