# frozen_string_literal: true

require_relative 'safe'

module FFI
  module Libfuse
    module Adapter
      # Debug callbacks
      #
      # When included in a filesystem class, and if debugging is enabled via {Main#fuse_debug}, then installs a wrapper
      #  via #{FuseCallbacks#fuse_wrappers} to log callbacks.
      #
      # Simple format options can be handled by #{debug_config}, or override the **Module Functions** on an including
      # class for more programmatic control of output.
      #
      # @note {Debug} includes {Safe} as it expects to handle (and re-raise) exceptions.
      module Debug
        include Safe

        # Default format
        # @see debug_callback
        DEFAULT_FORMAT = "%<p>s %<n>s %<t>s %<m>s(%<a>s)\n\t=> %<r>s"

        # @return [Boolean] true if debug is enabled
        def debug?
          @debug
        end

        # Configure debug output
        # @abstract
        # @return [Hash<Symbol,String>] options to pass to {debug_callback}
        def debug_config
          {}
        end

        # @!visibility private
        def fuse_wrappers(*wrappers)
          conf = { prefix: self.class.name }.merge!(debug_config)
          # validate config for bad formats, strftime etc
          debug_format(:test_debug, [], :result, **conf)
          wrappers << proc { |fm, *args, &b| debug_callback(fm, *args, **conf, &b) } if debug?
          return wrappers unless defined?(super)

          super
        end

        # @!visibility private
        def fuse_debug(enabled)
          super if defined?(super)
          @debug = enabled
        end

        module_function

        # Debug fuse method, args and result of yielding args to the block
        #
        # @param [Symbol] fuse_method the callback name
        # @param [Array] args callback arguments
        # @param [Hash<Symbol,String>] options see {debug_format} for defaults
        # @option options [String] prefix
        # @option options [String] strftime a date time format
        # @option options [String] format  format string with fields
        #
        #   * %<n>: Time.now - use strftime option to control time format
        #   * %<t>: Thread name
        #   * %<m>: Fuse method
        #   * %<a>: Comma separate list of arguments
        #   * %<r>: Result of the method call (or any error raised)
        #   * %<p>: The value of prefix option
        # @raise [SystemCallError]
        #   expected Errors raised from callbacks are logged with their cause (if any)
        # @raise [StandardError,ScriptError]
        #   unexpected Errors raised from callbacks are logged with their backtrace
        def debug_callback(fuse_method, *args, **options)
          result = yield(*args)
          debug(fuse_method, args, result, **options)
          result
        rescue StandardError, ScriptError => e
          debug(fuse_method, args, error_message(e), **options)
          debug_error(e)
          raise
        end

        # @!group Module Functions

        # Logs the callback
        def debug(fuse_method, args, result, **options)
          warn debug_format(fuse_method, args, result, **options)
        end

        # @param [Exception] err
        # @return [String] the detailed error message for err
        def error_message(err)
          if err.is_a?(SystemCallError)
            "#{err.class.name}(errno=#{err.errno}): #{err.message}"
          else
            "#{err.class.name}: #{err.message}"
          end
        end

        # Log additional information for errors (cause/backtrace etc)
        # @see debug_callback
        def debug_error(err)
          if err.is_a?(SystemCallError)
            warn "Caused by #{error_message(err.cause)}" if err.cause
          else
            warn err.backtrace.join("\n\t")
          end
        end

        # @return [String] the formatted debug message
        # @see debug_callback
        def debug_format(fuse_method, args, result, prefix: 'DEBUG', strftime: '%FT%T%:z', format: DEFAULT_FORMAT)
          format(format,
                 p: prefix,
                 n: Time.now.strftime(strftime),
                 t: Thread.current.name || Thread.current,
                 m: fuse_method,
                 a: args.map(&:to_s).join(','),
                 r: result)
        end

        # @!endgroup
      end
    end
  end
end
