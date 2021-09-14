# frozen_string_literal: true

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    attach_function :fuse_notify_poll, [:pointer], :int
    attach_function :fuse_pollhandle_destroy, [:pointer], :void

    class << self
      # @!visibility private

      # @!method fuse_notify_poll(ph)
      # @!method fuse_pollhandle_destroy(ph)
    end

    # struct fuse_poll_handle
    # @todo build a filsystem that uses poll and implement an appropriate ruby interface
    # @see https://libfuse.github.io/doxygen/poll_8c.html
    class FusePollHandle
      extend FFI::DataConverter
      native_type :pointer

      class << self
        # @!visibility private
        def from_native(ptr, _ctx)
          # TODO: we may need a weakref cache on ptr.address so that we don't create different ruby ph for the same
          #  address, and call destroy on the first one that goes out of scope.
          new(ptr)
        end

        # @!visibility private
        def to_native(value, _ctx)
          value.ph
        end

        # @!visibility private
        def finalizer(pollhandle)
          proc { Libfuse.fuse_pollhandle_destroy(pollhandle) }
        end
      end

      # @!visibility private
      attr_reader :ph

      # @!visibility private
      def initialize(pollhandle)
        @ph = pollhandle
        ObjectSpace.define_finalizer(self, self.class.finalizer(pollhandle))
      end

      # @see FuseOperations#poll
      def notify_poll
        Libfuse.fuse_notify_poll(ph)
      end
      alias notify notify_poll
      alias fuse_notify_poll notify_poll
    end
  end
end
