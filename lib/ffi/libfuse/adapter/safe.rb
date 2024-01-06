# frozen_string_literal: true

module FFI
  module Libfuse
    module Adapter
      # Safe callbacks convert return values into integer responses, and rescues errors
      #
      # Applies to all callbacks except :init, :destroy
      module Safe
        # @!visibility private
        def fuse_wrappers(*wrappers)
          wrappers << {
            wrapper: proc { |fm, *args, **_, &b| Safe.safe_callback(fm, *args, default_errno: default_errno, &b) },
            excludes: %i[init destroy]
          }
          return wrappers unless defined?(super)

          super(*wrappers)
        end

        # @return [Integer] the default errno.  ENOTRECOVERABLE unless overridden
        def default_errno
          defined?(super) ? super : Errno::ENOTRECOVERABLE::Errno
        end

        module_function


        # Process the results of yielding *args for the fuse_method callback
        #
        # @yieldreturn [SystemCallError] expected callback errors rescued to return equivalent -ve errno value
        # @yieldreturn [StandardError,ScriptError] unexpected callback errors are rescued
        #   to return -ve {default_errno} after emitting backtrace to #warn
        #
        # @yieldreturn [Integer]
        #
        #   * -ve values returned directly
        #   * +ve values returned directly for fuse_methods in {FuseOperations.MEANINGFUL_RETURN} list
        #   * otherwise returns 0
        #
        # @yieldreturn [Object] always returns 0 if no exception is raised
        #
        def safe_callback(fuse_method, *args, default_errno: Errno::ENOTRECOVERABLE::Errno)
          result = yield(*args)

          return result.to_i if FuseOperations.meaningful_return?(fuse_method)

          0
        rescue SystemCallError => e
          -e.errno
        rescue StandardError, ScriptError
          -default_errno.abs
        end
      end
    end
  end
end
