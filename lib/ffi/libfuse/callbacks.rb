# frozen_string_literal: true

module FFI
  module Libfuse
    # Methods to register callbacks and wrappers
    module Callbacks
      # Registers block as a callback method
      #
      # @note wrappers are defined in inside out order
      #
      # @param [Symbol] method the callback being registered
      # @param [Array<Proc,Hash<:wrapper,:excludes>,Object>] wrappers with each entry being
      #
      #  - a Proc(method, *args, &block)
      #
      #      either handling the callback itself or yielding *args (possibly after manipulation) onwards to &block.
      #       Do not include method in the yield args!
      #  - a Hash with keys
      #
      #      - wrapper: [Proc] as above
      #      - excludes: [Array<Symbol>] names of methods that the proc should not apply to. Useful when registering
      #        the same list of wrappers for many methods
      #  - an Object responding to #method(*args,&block)
      #
      # @param [Proc] block if provided is used as the innermost block to handle the callback - equivalent to
      #  being the first entry in wrappers list
      def register(method, wrappers = [], &block)
        callback = wrappers.each.inject(block) do |b, w|
          next wrap_callback(method, **w, &b) if w.is_a?(Hash)

          wrap_callback(method, w, &b)
        end
        send(:[]=, method, callback)
      end

      private

      def initialize_callbacks(callbacks, delegate:, wrappers: [])
        callbacks.select { |m| respond_to_callback?(m, delegate) }.each do |m|
          register(m, wrappers) { |*f_args| delegate.public_send(m, *f_args) }
        end
      end

      def respond_to_callback?(method, delegate)
        delegate.respond_to?(method)
      end

      def wrap_callback(method, proc_wrapper = nil, wrapper: proc_wrapper, excludes: [], &block)
        return block if excludes.include?(method)

        # Wrapper proc takes fuse_method as first arg, but the resulting proc only takes the callback args
        # ie so wrappers should not yield the fuse_method onwards!!
        return proc { |*args| wrapper.call(method, *args, &block) } if wrapper.is_a?(Proc)

        return proc { |*args| wrapper.send(method, *args, &block) } if wrapper.respond_to?(method)

        block
      end
    end
  end
end
