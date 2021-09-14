# frozen_string_literal: true

require_relative '../../../lib/ffi/libfuse/job_pool'
require_relative '../../spec_helper'

describe 'FFI::Libfuse::ThreadPool' do

  it 'starts a new thread on busy' do
    jp = JobPoolWithStats.new(name: 'one busy job') { |_v| FFI::Libfuse::ThreadPool.busy { sleep 0.2 }}
    jp.schedule(1).close.join
    _(jp.job_count).must_equal(1, 'job count')
    _(jp.thread_count).must_equal(2,'thread count')
  end

  it 'joins successfully if first worker immediately returns false' do
    tp = FFI::Libfuse::ThreadPool.new { false }
    tp.join
  end

  it 'joins successfully if first worker raises exception' do
    tp = FFI::Libfuse::ThreadPool.new { Thread.current.report_on_exception = false; raise 'Oops' }
    count = 0
    tp.join do |_t,e|
      count += 1
      _(e.message).must_equal('Oops')
    end
    _(count).must_equal(1)
  end

  it 'does not start more threads if worker is never busy' do
    jp = JobPoolWithStats.new(name: 'one busy job') { |_v| sleep 0.2 }
    jp.schedule(1).close.join { |_t, e = nil| raise e if e }
    _(jp.job_count).must_equal(1, 'job count')
    _(jp.thread_count).must_equal(1,'thread count')
  end

  it 'does not start a new threads if the max_active is exceeded' do
    jp = JobPoolWithStats.new(max_active: 2) { |_v| FFI::Libfuse::ThreadPool.busy { sleep 0.2 } }
    5.times.each { |i| jp.schedule(i) }
    jp.close.join
    _(jp.job_count).must_equal(5, 'job count')
    _(jp.thread_count).must_equal(2,'thread count')
  end

  it 'keeps idle threads at max_idle_threads' do
    jp = JobPoolWithStats.new(max_idle: 5) do |_v|
      sleep 0.1
      FFI::Libfuse::ThreadPool.busy do
        sleep 0.1
      end
    end

    Thread.new do
      100.times.each { |i| jp.schedule(i); sleep 0.02 }
      jp.close
    end

    jp.join do |*a|
      _busy,idle = jp.list
      _(idle.size).must_be :<=, 6
    end

    _(jp.error_count).must_equal(0,'error_count')
    _(jp.job_count).must_equal(100, 'job count')
    _(jp.thread_count).must_be :>=, 5, 'thread_count'
  end

  it 'works max_idle 0' do
    jp = JobPoolWithStats.new(max_idle: 0) do |_v|
      sleep 0.1
      FFI::Libfuse::ThreadPool.busy { sleep 0.1 }
    end

    5.times.each { |i| jp.schedule(i) }
    jp.close.join do |*a|
      _busy,idle = jp.list
      _(idle.size).must_be :<=, 1
    end
    _(jp.job_count).must_equal(5, 'job count')
    _(jp.thread_count).must_equal(6,'thread count')
  end

  it 'names threads'  do
    jp = JobPoolWithStats.new(name: 'test-name') do |_v| sleep 0.1
    end

    jp.schedule(:x).close.join do |t|
      _(t.name).must_match(/^test-name/)
    end
    _(jp.error_count).must_equal(0, 'error count')
    _(jp.thread_count).must_equal(1,'thread count')
  end

  it 'encloses the thread group' do
    jp = JobPoolWithStats.new(name: 'test-name') { |_v| _(Thread.current.group).must_be :enclosed?, 'enclosed' }
    jp.close.join
    _(jp.error_count).must_equal(0, 'error count')
    _(jp.thread_count).must_equal(1,'thread count')
  end

  describe "#join" do
    it 'does not wait for threads started from worker to finish'
    it 'sends exceptions to the block'
    it 'sends completed thread names to block'
  end

  describe ".busy" do
    it 'yields the block if not in a thread pool' do
      run = false
      FFI::Libfuse::ThreadPool.busy { run = true }
      _(run).must_equal(true)
    end

    it 'handles busy inside a busy block' do
      run = false
      jp = JobPoolWithStats.new(name: 'one busy busy job') do |_v|
        FFI::Libfuse::ThreadPool.busy do
          sleep 0.1
          FFI::Libfuse::ThreadPool.busy { run = true }
        end
      end
      jp.schedule(1).close.join { |_t, e = nil| raise e if e }
      _(run).must_equal(true)
      _(jp.job_count).must_equal(1, 'job count')
      _(jp.thread_count).must_equal(2,'thread count')
    end

    it 'handles busy without a block' do
      run = false
      jp = JobPoolWithStats.new(name: 'one busy busy job') do |_v|
        sleep 0.1
        FFI::Libfuse::ThreadPool.busy
        run = true
        sleep 0.1
      end
      jp.schedule(1).close.join { |_t, e = nil| raise e if e }
      _(run).must_equal(true)
      _(jp.job_count).must_equal(1, 'job count')
      _(jp.thread_count).must_equal(2,'thread count')
    end
  end

end

#This needs to go after the describe block for RubyMine
class JobPoolWithStats < FFI::Libfuse::JobPool
  attr_reader :thread_count, :job_count, :error_count

  def initialize(**options)
    super(**options) do
      Thread.current[:jc] ||= 0
      Thread.current[:jc] += 1
      yield
    end
  end

  def join
    @thread_count= 0
    @error_count = 0
    @job_count = 0
    super do |t, e=nil|
      @thread_count += 1
      @error_count += 1 if e
      @job_count += t[:jc] || 0
      yield t, e if block_given?
    end
  end
end