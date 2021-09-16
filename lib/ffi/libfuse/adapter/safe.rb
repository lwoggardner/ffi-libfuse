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
            wrapper: proc { |fm, *args, **_, &b| Safe.safe_callback(fm, *args, &b) },
            excludes: %i[init destroy]
          }
          return wrappers unless defined?(super)

          super(*wrappers)
        end

        # Callbacks that are expected to return meaningful positive integers
        MEANINGFUL_RETURN = %i[read write write_buf lseek copy_file_range getxattr listxattr].freeze

        module_function

        # Process the results of yielding *args for the fuse_method callback
        #
        # @yieldreturn [SystemCallError] expected callback errors rescued to return equivalent -ve errno value
        # @yieldreturn [StandardError,ScriptError] unexpected callback errors are rescued
        #   to return -Errno::ENOTRECOVERABLE after emitting backtrace to #warn
        #
        # @yieldreturn [Integer]
        #
        #   * -ve values returned directly
        #   * +ve values returned directly for fuse_methods in {MEANINGFUL_RETURN} list
        #   * otherwise returns 0
        #
        # @yieldreturn [Object] always returns 0 if no exception is raised
        #
        def safe_callback(fuse_method, *args)
          result = yield(*args)

          return 0 unless result.is_a?(Integer)
          return 0 unless result.negative? || MEANINGFUL_RETURN.include?(fuse_method)

          result
        rescue SystemCallError => e
          -e.errno
        rescue StandardError, ScriptError => e
          # rubocop:disable Layout/LineLength
          warn ["FFI::Libfuse error in #{fuse_method}", *e.backtrace.reverse, "#{e.class.name}:#{e.message}"].join("\n\t")
          # rubocop:enable Layout/LineLength
          -Errno::ENOTRECOVERABLE::Errno
        end
      end
    end
  end
end
