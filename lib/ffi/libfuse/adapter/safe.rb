# frozen_string_literal: true

module FFI
  module Libfuse
    module Adapter
      # Safe callbacks convert return values into integer responses, and rescues errors
      module Safe
        # @!visibility private
        def fuse_wrappers(*wrappers)
          wrappers << {
            wrapper: proc { |fm, *args, **_, &b| safe_integer_callback(fm, *args, default_errno: default_errno, &b) },
            excludes: FuseOperations::VOID_RETURN + FuseOperations::MEANINGFUL_RETURN
          }
          wrappers << {
            wrapper: proc { |fm, *args, **_, &b|
                       safe_meaningful_integer_callback(fm, *args, default_errno: default_errno, &b)
                     },
            includes: FuseOperations::MEANINGFUL_RETURN
          }
          wrappers << {
            wrapper: proc { |fm, *args, **_, &b| safe_void_callback(fm, *args, &b) },
            includes: FuseOperations::VOID_RETURN
          }
          return wrappers unless defined?(super)

          super(*wrappers)
        end

        # @return [Integer] the default errno to return for rescued errors.  ENOTRECOVERABLE unless overridden
        def default_errno
          defined?(super) ? super : Errno::ENOTRECOVERABLE::Errno
        end

        module_function

        # Process the result of yielding to the fuse callback to provide a safe return value to libfuse
        #
        # For callbacks in {FuseOperations.VOID_RETURN}
        #
        #   * the return value and any unexpected errors raised are ignored
        #
        # For callbacks in {FuseOperations.MEANINGFUL_RETURN}
        #
        #    * should raise appropriate `Errno` error for expected errors (eg `Errno::ENOENT`)
        #    * must return a value convertable to an integer (via :to_i) - either a positive meaningful value
        #      or a negative errno value which will be returned directly
        #    * otherwise default_errno is returned
        #
        # For remaining path callbacks
        #
        #    * should raise appropriate `Errno` error for expected errors (eg `Errno::ENOENT`)
        #    * may return a negative Integer (equivalent to raising the corresponding `SystemCallError`)
        #    * any other value returned is considered success and 0 is returned
        #    * unexpected errors raised are rescued and default_errno is returned
        #
        # @param [Integer] default_errno
        #    value to return for any unexpected errors
        #
        # @return [nil]
        #   For void callbacks
        # @return [Integer]
        #   For path callbacks,  either 0 for success or a negative errno value
        def safe_callback(fuse_method, *args, default_errno: Errno::ENOTRECOVERABLE::Errno)
          if FuseOperations::MEANINGFUL_RETURN.include?(fuse_method)
            safe_meaningful_integer_callback(fuse_method, *args, default_errno: default_errno)
          elsif FuseOperations::VOID_RETURN.include?(fuse_method)
            safe_void_callback(fuse_method, *args)
          else
            safe_integer_callback(fuse_method, *args, default_errno: default_errno)
          end
        end

        private

        def safe_integer_callback(_, *args, default_errno: Errno::ENOTRECOVERABLE::Errno)
          safe_errno(default_errno) do
            result = yield(*args)
            result.is_a?(Integer) && result.negative? ? result : 0
          end
        end

        def safe_meaningful_integer_callback(_, *args, default_errno: Errno::ENOTRECOVERABLE::Errno)
          safe_errno(default_errno) do
            yield(*args).to_i
          end
        end

        def safe_errno(default_errno)
          yield
        rescue SystemCallError => e
          -e.errno
        rescue StandardError, ScriptError
          -default_errno.abs
        end

        # Process callbacks that return void, simply by swallowing unexpected errors
        def safe_void_callback(_, *args)
          yield(*args)
          nil
        rescue StandardError, ScriptError
          # Swallow unexpected exceptions
          nil
        end
      end
    end
  end
end
