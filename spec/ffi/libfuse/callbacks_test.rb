# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative 'mock_operation'

describe 'Callbacks' do

  describe '#register' do
    let(:callbacks) { MockOperation.new }

    it 'registers a callback method' do
      callbacks.register(:the_callback) { :y }
      expect(callbacks.the_callback).must_equal(:y)
    end

    it 'wraps procs' do
      p = proc { |_fm, i, &b| "#{b.call(i)}proc" }
      callbacks.register(:cb, [p]) { |i| "x#{i}x" }
      expect(callbacks.cb('zzz')).must_equal('xzzzxproc')
    end

    it 'wraps objects responding to the method' do
      o = Object.new
      def o.cb(i)
        yield "ooo#{i}ooo"
      end
      callbacks.register(:cb, [o]) { |i| "x#{i}x" }
      expect(callbacks.cb('yyy')).must_equal('xoooyyyooox')
    end

    it 'does not wrap object not responding to method' do
      o = Object.new
      callbacks.register(:cb, [o]) { |i| "x#{i}x" }
      expect(callbacks.cb('yyy')).must_equal('xyyyx')
    end

    it 'calls wrappers inside out' do
      o = Object.new
      def o.cb(i)
        yield "ooo#{i}ooo"
      end
      p = { wrapper: ->(_m, i, &b) { b.call("p#{i}p") } }
      w = { wrapper: o }
      callbacks.register(:cb, [p,w]) { |i| "x#{i}x" }
      expect(callbacks.cb('yyy')).must_equal('xpoooyyyooopx')
    end

    it 'excludes methods' do
      o = Object.new
      def o.cb(i)
        yield "ooo#{i}ooo"
      end
      p = { wrapper: ->(i) { "p#{i}p" }, excludes: %i[cb] }
      w = { wrapper: o, excludes: %i[cb] }
      callbacks.register(:cb, [w, p]) { |i| "x#{i}x" }
      expect(callbacks.cb('yyy')).must_equal('xyyyx')
    end
  end

  describe '#initialize_callbacks' do
    it 'registers callbacks for a delegate object' do
      ops = MockOperation.new

      def ops.respond_to_callback?(method,_delegate)
        %i[cb2 cb3].include?(method)
      end

      d = Object.new
      def d.cb2
        'cb2'
      end

      def d.cb3(i)
        "cb3:#{i}"
      end

      w = { wrapper: ->(_m, i, &b) { b.call("w#{i}w") }, excludes: %i[cb2] }

      callbacks = %i[cb1 cb2 cb3]
      ops.send(:initialize_callbacks, callbacks, delegate: d, wrappers: [w])

      _(ops.callbacks).must_include(:cb2)
      _(ops.callbacks).must_include(:cb3)
      _(ops.callbacks).wont_include(:cb1)

      _(ops.cb2).must_equal('cb2')
      _(ops.cb3('333')).must_equal('cb3:w333w')

    end
  end
end
