# frozen_string_literal: true

module FFI
  module Libfuse
    module Adapter
      # Debug callbacks
      #
      # When included in a filesystem class, and if debugging is enabled via {Main#fuse_debug}, then installs a wrapper
      #  via #{FuseCallbacks#fuse_wrappers} to log callbacks via #warn
      module Debug
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
          Debug.debug_format(:test_debug, [], :result, **conf)
          wrappers << proc { |fm, *args, &b| Debug.debug_callback(fm, *args, **conf, &b) } if debug?
          return wrappers unless defined?(super)

          super(*wrappers)
        end

        # @!visibility private
        def fuse_debug(enabled)
          super if defined?(super)
          @debug = enabled
        end

        module_function

        # Debug fuse method, args and result
        # @param [Symbol] fuse_method the callback name
        # @param [Array] args callback arguments
        # @param [Hash<Symbol,String>] options see {debug} for defaults
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
        def debug_callback(fuse_method, *args, **options)
          debug(fuse_method, args, yield(*args), **options)
        rescue SystemCallError => e
          # expected behaviour
          debug(fuse_method, args, "#{e.class.name}(errno=#{e.errno}): #{e.message}", **options)
          raise
        rescue StandardError, ScriptError => e
          # unexpected, debug with backtrace
          debug(fuse_method, args, (["#{e.class.name}: #{e.message}"] + e.backtrace).join("\n\t"), **options)
          raise
        end

        # @!visibility private
        def debug(fuse_method, args, result, **options)
          warn debug_format(fuse_method, args, result, **options)
          result
        end

        # @!visibility private
        def debug_format(fuse_method, args, result, prefix: 'DEBUG', strftime: '%FT%T%:z', format: DEFAULT_FORMAT)
          format(format,
                 p: prefix,
                 n: Time.now.strftime(strftime),
                 t: Thread.current.name || Thread.current,
                 m: fuse_method,
                 a: args.map(&:to_s).join(','),
                 r: result)
        end
      end
    end
  end
end
