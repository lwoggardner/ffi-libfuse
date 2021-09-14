# frozen_string_literal: true

require_relative 'thread_pool'

module FFI
  module Libfuse
    # A JobPool is a ThreadPool whose worker threads are consuming from a Queue
    class JobPool
      # Create a Job Pool
      # @param [Hash<Symbol,Object>] options
      #  @see ThreadPool.new
      # @param [Proc] worker the unit of work that will be yielded the scheduled jobs
      def initialize(**options, &worker)
        @jq = Queue.new
        @tp = ThreadPool.new(**options) { (args = @jq.pop) && worker.call(*args) }
      end

      # Schedule a job
      # @param [Array<Object>] args
      # @return [self]
      def schedule(*args)
        @jq.push(args)
        self
      end
      alias << schedule
      alias push schedule

      # Close the JobPool
      # @return [self]
      def close
        @jq.close
        self
      end

      # Join the JobPool
      # @return [self]
      def join(&block)
        @tp.join(&block)
        self
      end

      # @see ThreadPool#list
      def list
        @tp.list
      end

      # @see ThreadPool#group
      def group
        @tp.group
      end
    end
  end
end
