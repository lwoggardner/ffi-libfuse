# frozen_string_literal: true

require 'pathname'

module FFI
  module Libfuse
    module Adapter
      # Wrapper module to convert first path argument of callback methods to a {::Pathname}
      module Pathname
        # @!visibility private
        def fuse_wrappers(*wrappers)
          wrappers << {
            wrapper: proc { |_fuse_method, path, *args, &b| b.call(::Pathname.new(path), *args) },
            excludes: %i[init destroy]
          }
          return wrappers unless defined?(super)

          super
        end
      end
    end
  end
end
