# frozen_string_literal: true

require_relative '../fuse_context'

module FFI
  module Libfuse
    module Adapter
      # Injects a wrapper via #{FuseCallbacks#fuse_wrappers} make the current {FuseContext} object available to
      #  callbacks (except :destroy) via thread local variable :fuse_context
      module Context
        # @!visibility private
        def fuse_wrappers(*wrappers)
          wrappers.unshift(
            {
              wrapper: proc { |_fm, *args, **_, &b| Context.thread_local_context(*args, &b) },
              excludes: %i[destroy]
            }
          )
          return wrappers unless defined?(super)

          super(*wrappers)
        end

        module_function

        # Capture {FuseContext} in thread local variable
        def fuse_context
          Thread.current[:fuse_context] ||= FuseContext.get
        end

        def thread_local_context(*args)
          yield(*args)
        ensure
          Thread.current[:fuse_context] = nil
        end
      end
    end
  end
end
