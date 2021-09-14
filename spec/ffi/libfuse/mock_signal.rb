# frozen_string_literal: true

# quacks like class Signal
class MockSignal
  attr_reader :traps

  def trap(sig, trap = nil, &block)
    @traps ||= {}
    prev = @traps[sig]
    @traps[sig] = trap || block
    prev || 'DEFAULT'
  end

  def self.signame(signo)
    Signal.signame(signo)
  end

  def signame(signo)
    self.class.signame(signo)
  end

  def signal(sig)
    signo = Signal.list[sig]
    t = @traps[sig]
    return t unless t.respond_to?(:call)

    t.arity == 0 ? t.call : t.call(signo)
  end
end
