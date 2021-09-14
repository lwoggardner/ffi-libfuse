# frozen_string_literal: true

require_relative '../fuse_context'

module FFI
  module Libfuse
    module Adapter
      # Wrapper module to inject {FuseContext} as first arg to each callback method (except :destroy)
      #
      # {ThreadLocalContext} may be a less intrusive means to make the context available to callbacks
      module Context
        # @!visibility private
        def fuse_wrappers(*wrappers)
          wrappers.unshift(
            {
              wrapper: proc { |_fm, *args, **_, &b| self.class.context_callback(*args, &b) },
              excludes: %i[destroy]
            }
          )
          return wrappers unless defined?(super)

          super(*wrappers)
        end

        module_function

        # @yieldparam [FuseContext] ctx
        # @yieldparam [Array] *args
        def context_callback(*args)
          ctx = FuseContext.get
          ctx = nil if ctx.null?
          yield ctx, *args
        end
      end
    end
  end
end
