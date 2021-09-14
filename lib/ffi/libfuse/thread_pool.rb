# frozen_string_literal: true

require 'set'

module FFI
  module Libfuse
    # A self-expanding and self-limiting ThreadPool
    #
    # The first thread is created on ThreadPool.new and additional threads are added through ThreadPool.busy
    #   called from within a worker iteration
    #
    # A pool thread will end when
    #
    #   * a worker iteration returns false or nil
    #   * a worker thread raises an exception (silently for StopIteration)
    #   * max_idle_threads is exceeded
    class ThreadPool
      class << self
        # Starts a new thread if the current thread is a thread pool member and there are no other idle threads in the
        # pool. The thread is marked as busy for the duration of the yield.
        #
        # If the current thread is not a pool member then simply yields
        def busy(&block)
          if (tp = Thread.current[:tp])
            tp.busy(&block)
          elsif block_given?
            yield
          end
        end
      end

      # @return [ThreadGroup] the enclosed thread group to which the pool's threads are added
      attr_reader :group

      # Create a new ThreadPool
      #
      # @param [Integer] max_idle  The maximum number of idle threads (>= 0)
      # @param [Integer] max_active The maximum number of active threads (> 0)
      # @param [String] name A prefix used to set Thread.name for pool threads
      # @param [Proc] worker The worker called repeatedly within each pool thread
      # @see ThreadPool.busy
      def initialize(max_idle: nil, max_active: nil, name: nil, &worker)
        raise ArgumentError, "max_active #{max_active} must be > 0" if max_active && !max_active.positive?
        raise ArgumentError, "max_idle: #{max_idle} must be >= 0" if max_idle&.negative?
        raise ArgumentError, 'must have worker block but none given' unless worker

        @max_idle = max_idle
        @max_active = max_active
        @name = name
        @worker = worker
        @mutex = Mutex.new
        @size = 0
        @busy = 0
        @idle_death = Set.new
        @completed = Queue.new
        @group = ThreadGroup.new.add(synchronize { start_thread }).enclose
      end

      # Join the ThreadPool optionally handling thread completion
      # @return [void]
      # @yield (thread, error = nil)
      # @yieldparam [Thread] thread a Thread that has finished
      # @yieldparam [StandardError] error if thread raised an exception
      def join
        while (t = @completed.pop)
          begin
            t.join
            yield t if block_given?
          rescue StandardError => e
            yield t, e if block_given?
          end
        end
        self
      end

      # @!visibility private
      def busy
        mark_busy
        yield if block_given?
      ensure
        ensure_not_busy if block_given?
      end

      # @return [Array<Thread>,Array<Thread>] busy,idle threads
      def list
        group.list.partition { |t| t[:tp_busy] }
      end

      private

      def mark_busy
        return if Thread.current[:tp_busy]

        Thread.current[:tp_busy] = true
        synchronize { start_thread if (@busy += 1) == @size }
      end

      attr_reader :mutex, :worker, :name

      def start_thread
        return if @max_active && @size >= @max_active

        @size += 1
        Thread.new { worker_thread }
      end

      def worker_thread
        Thread.current.name = "#{name}-#{Thread.current.object_id.to_s(16)}" if name
        Thread.current[:tp] = self
        loop while invoke && !idle_limit_exceeded?
      ensure
        @completed << Thread.current
        @completed.close if decrement_size.zero?
      end

      def invoke
        worker.call
      ensure
        ensure_not_busy
      end

      def ensure_not_busy
        return unless Thread.current[:tp_busy]

        Thread.current[:tp_busy] = false
        synchronize { @busy -= 1 }
      end

      def decrement_size
        synchronize do
          @idle_death.delete(Thread.current)
          @size -= 1
        end
      end

      def idle_limit_exceeded?
        return false unless @max_idle

        synchronize { (@size - @busy - @idle_death.size - 1) > @max_idle && @idle_death << Thread.current }
      end

      def synchronize(&block)
        @mutex.synchronize(&block)
      end
    end
  end
end
