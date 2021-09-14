# frozen_string_literal: true

require_relative '../../../lib/ffi/libfuse/callbacks'

# a mock callback handler
class MockOperation
  include FFI::Libfuse::Callbacks

  attr_reader :callbacks

  def initialize
    @callbacks = {}
  end

  def []=(method, aproc)
    @callbacks[method] = aproc
  end

  def method_missing(method, *args)
    @callbacks.fetch(method).call(*args)
  end

  def respond_to_missing?(method)
    @callbacks.key?(method) || super
  end
end
