# frozen_string_literal: true

require_relative '../fuse_operations'

module FFI
  module Libfuse
    module Test
      # A FuseOperations that holds callback procs in a Hash rather than FFI objects and allows for direct invocation of
      # callback methods
      # @!parse FuseOperations
      class Operations
        include FuseCallbacks

        def initialize(delegate:, fuse_wrappers: [])
          @callbacks = {}
          initialize_callbacks(delegate: delegate, wrappers: fuse_wrappers)
        end

        # @!visibility private
        def [](member)
          @callbacks[member]
        end

        # @!visibility private
        def []=(member, value)
          @callbacks[member] = value
        end

        # @!visibility private
        def members
          FuseOperations.members
        end

        private

        # Allow the fuse operations to be called directly - useful for testing
        # @todo some fancy wrapper to convert tests using Fuse2 signatures when Fuse3 is the loaded library
        #   and vice-versa
        def method_missing(method, *args)
          callback = callback?(method) && self[method]
          return super unless callback

          callback.call(*args)
        end

        def respond_to_missing?(method, _private = false)
          self[method] && callback?(method)
        end

        def callback?(method)
          callback_members.include?(method)
        end
      end
    end
  end
end
