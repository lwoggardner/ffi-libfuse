# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative 'mock_signal'
require_relative '../../../lib/ffi/libfuse'

describe FFI::Libfuse::Ackbar do
  let(:traps) { {} }
  let(:mock_signal) { MockSignal.new }

  it 'traps signals with zero arity procs' do
    called = nil
    traps[:int] = -> { called = 'INT' }
    traps[:usr1] = -> { called = 'USER ONE' }
    ackbar = FFI::Libfuse::Ackbar.new(traps, signal: mock_signal)
    expect(mock_signal.traps).must_include('INT')
    expect(mock_signal.traps).must_include('USR1')
    mock_signal.signal('INT')
    ackbar.next
    expect(called).must_equal('INT')
    mock_signal.signal('USR1')
    ackbar.next
    expect(called).must_equal('USER ONE')
  end

  tests = [
    { sig: 'HUP', name: 'HUP' },
    { sig: :INT, name: 'INT' },
    { sig: 2, name: 'INT' },
    { sig: :sigint, name: 'INT' }
  ]
  tests.kw_each do |sig:, name:|
    it "traps signal #{sig}(#{sig.class.name}) for name #{name}" do
      traps[sig] = ->(signame) { signame }
      ackbar = FFI::Libfuse::Ackbar.new(traps, signal: mock_signal)
      expect(ackbar.signame(sig)).must_equal(name)
      mock_signal.signal(name)
      expect(ackbar.next).must_equal([name, name])
    end
  end

  it 'traps signals with string commands' do
    traps[:hup] = 'THECOMMAND'
    FFI::Libfuse::Ackbar.new(traps, signal: mock_signal)
    expect(mock_signal.traps['HUP']).must_equal('THECOMMAND')
  end

  it 'without force only overrides traps that are already DEFAULT' do
    mock_signal.trap('USR1', 'ALREADY_SET')
    traps['USR1'] = 'MYCOMMAND'
    FFI::Libfuse::Ackbar.new(traps, signal: mock_signal)
    expect(mock_signal.traps['USR1']).must_equal('ALREADY_SET')
  end

  it 'with force overrides all specified traps' do
    mock_signal.trap('USR1', 'ALREADY_SET')
    traps['USR1'] = 'MYCOMMAND'
    FFI::Libfuse::Ackbar.new(traps, force: true, signal: mock_signal)
    expect(mock_signal.traps['USR1']).must_equal('MYCOMMAND')
  end

  describe '#restore' do
    it 'restores traps to initial values and closes the pipe' do
      mock_signal.trap('USR1', 'NONDEFAULT')
      mock_signal.trap('HUP') { 'ORIGHUP' }
      traps['USR1'] = 'abusr1'
      traps['HUP'] = -> { :abhup }
      ackbar = FFI::Libfuse::Ackbar.new(traps, force: true, signal: mock_signal)
      ackbar.restore
      expect(mock_signal.signal('USR1')).must_equal('NONDEFAULT')
      expect(mock_signal.signal('HUP')).must_equal('ORIGHUP')
      expect(ackbar.next).must_equal(false)
      expect(ackbar.pr.closed?).must_equal(true)
    end
  end

  describe '#monitor' do
    it 'processes traps in a named thread' do
      called = false
      traps['HUP'] = -> { expect(Thread.current.name).must_equal('ItsATrap') }
      traps['USR1'] = -> { called = true }
      ackbar = FFI::Libfuse::Ackbar.new(traps, signal: mock_signal)

      m = ackbar.monitor(name: 'ItsATrap')
      t = Thread.new do
        mock_signal.signal('HUP')
        sleep(0.1)
        mock_signal.signal('INT')
        sleep(0.1)
        mock_signal.signal('USR1')
        sleep(0.1)
        ackbar.restore
      end
      t.join
      m.join
      expect(called).must_equal(true)
    end

    it 'yields to block before select' do
      ackbar = FFI::Libfuse::Ackbar.new(traps, signal: mock_signal)

      called = false
      m = ackbar.monitor(name: 'ItsATrap') do
        called = true
        nil
      end
      Thread.pass
      ackbar.close
      m.join
      expect(called).must_equal(true)
    end

    it 'times out IO.select using block result' do
      ackbar = FFI::Libfuse::Ackbar.new(traps, signal: mock_signal)

      count = 0
      m = ackbar.monitor(name: 'ItsATrap') do
        count += 1
        0.1
      end
      sleep(0.6)
      ackbar.close
      m.join
      expect(count).must_be :>=, 5
    end
  end

  describe 'real traps' do
    it 'handles traps' do
      pid = Kernel.fork
      unless pid
        count = 0
        stop = false
        traps['USR1'] = -> { count += 1 }
        traps['HUP'] = -> { stop = true }
        FFI::Libfuse::Ackbar.trap(traps, force: true) do |ackbar|
          ackbar.monitor
          until stop
            sleep(1.1)
          end
        end
        Kernel.exit!(count)
      end
      sleep(0.2)
      Process.kill('USR1', pid)
      sleep(0.05)
      Process.kill('USR1', pid)
      sleep(0.05)
      Process.kill('HUP', pid)

      # TODO: MacOS fork is borked.
      sleep 5 if RUBY_PLATFORM =~ /darwin/
      _pid, status = Process.waitpid2(pid)
      expect(status.exitstatus).must_equal(2)
    end
  end
end
