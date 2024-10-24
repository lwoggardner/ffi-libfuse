# frozen_string_literal: true

require_relative '../fuse_context'

module FFI
  module Libfuse
    module Adapter
      # Wrapper module to handle interrupts
      #
      # Include this module if you want all requests to check for interruption before processing
      #
      # To handle interrupts only for specific callbacks just call {Libfuse.raise_interrupt} or
      # {Libfuse.fuse_interrupted?} during callback processing rather than including this adapter
      module Interrupt
        # @!visibility private
        def fuse_wrappers(*wrappers)
          wrappers << {
            wrapper: proc { |_fuse_method, *args, &b| Interrupt.interrupt_callback(*args, &b) },
            excludes: %i[init destroy]
          }
          return wrappers unless defined?(super)

          super
        end

        module_function

        # @raise [Errno::EINTR] if the fuse request is marked as interrupted
        def interrupt_callback(*args)
          Libfuse.raise_interrupt

          yield(*args)
        end
      end
    end
  end
end
