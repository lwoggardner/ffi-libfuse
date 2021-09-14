# frozen_string_literal: true

require_relative '../fuse_context'

module FFI
  module Libfuse
    module Adapter
      # Injects a wrapper via #{FuseCallbacks#fuse_wrappers} make the current {FuseContext} object available to
      #  callbacks (except :destroy) via thread local variable :fuse_context
      module ThreadLocalContext
        # @!visibility private
        def fuse_wrappers(*wrappers)
          wrappers.unshift(
            {
              wrapper: proc { |_fm, *args, **_, &b| self.class.thread_local_context(*args, &b) },
              excludes: %i[destroy]
            }
          )
          return wrappers unless defined?(super)

          super(*wrappers)
        end

        module_function

        # Stores {FuseContext} in thread local variable :fuse_context before yielding
        def thread_local_context(*args)
          Thread.current[:fuse_context] = FuseContext.get
          yield(*args)
        ensure
          Thread.current[:fuse_context] = nil
        end
      end
    end
  end
end
