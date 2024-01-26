# frozen_string_literal: true

require_relative 'fuse_common'
require_relative 'fuse_args'
require_relative 'fuse_operations'

module FFI
  module Libfuse
    # Controls the main run loop for a FUSE filesystem
    module Main
      class << self
        # Builds default argument list for #{fuse_main} regardless of being called directly or from mount.fuse3
        #
        # @param [Array<String>] extra_args additional arguments to add to $0 and *ARGV
        # @return [Array<String>]
        # @see https://github.com/libfuse/libfuse/issues/621
        def default_args(*extra_args)
          args = ARGV.dup

          # If called from mount.fuse3 we already have a 'source' argument which should go at args[0]
          args.unshift($0) unless args.size >= 2 && args[0..1].all? { |a| !a.start_with?('-') }
          args.concat(extra_args)
        end

        # Main function of FUSE
        #
        # - parses command line options - see {fuse_parse_cmdline}
        # - calls {#fuse_configure} if implemented by operations
        # - creates a fuse handle see {fuse_create}
        # - returns 0 if help or version options were processed (ie after all messages have been printed by libfuse)
        # - returns 2 if fuse handle is not successfully mounted
        # - calls {#fuse_traps} if implemented by operations
        # - calls run on the fuse handle with options from previous steps- see {FuseCommon#run}
        #
        # @param [Array<String>] argv mount.fuse arguments
        #   expects progname, mountpoint, options....
        # @param [FuseArgs|Array<String>] args
        #   alternatively constructed args
        # @param [Object|FuseOperations] operations
        #  something that responds to the fuse callbacks and optionally our abstract configuration methods
        # @param [Object] private_data
        #  any data to be made available to the {FuseOperations#init} callback
        #
        # @return [Integer] suitable for process exit code
        def fuse_main(*argv, operations:, args: argv.any? ? argv : default_args, private_data: nil)
          run_args = fuse_parse_cmdline(args: args, handler: operations)

          fuse_args = run_args.delete(:args)
          mountpoint = run_args.delete(:mountpoint)

          show_only = run_args[:show_help] || run_args[:show_version]

          return 3 if !show_only && !fuse_configure(operations)

          warn "FuseCreate: mountpoint: #{mountpoint}, args: [#{fuse_args.argv.join(' ')}]" if run_args[:debug]
          warn "FuseRun: #{run_args}" if run_args[:debug]

          fuse = fuse_create(mountpoint, args: fuse_args, operations: operations, private_data: private_data)

          return 0 if show_only
          return 2 if !fuse || !mountpoint

          run_args[:traps] = operations.fuse_traps if operations.respond_to?(:fuse_traps)
          fuse.run(**run_args)
        end
        alias main fuse_main

        # Parse command line arguments
        #
        # - parses standard command line options (-d -s -h -V)
        #   will call {fuse_debug}, {fuse_version}, {fuse_help} if implemented by handler
        # - calls {fuse_options} for custom option processing if implemented by handler
        # - parses standard fuse mount options
        #
        # @param [Array<String>] argv mount.fuse arguments
        #   expects progname, mountpoint, options....
        # @param [FuseArgs] args
        #   alternatively constructed args
        # @param [Object] handler
        #   something that responds to our abstract configuration methods
        # @return [Hash<Symbol,Object>]
        #   * mountpoint [String]: the mountpoint argument
        #   * args [FuseArgs]: remaining fuse_args to pass to {fuse_create}
        #   * show_help [Boolean]: -h or --help
        #   * show_version [Boolean]: -v or --version
        #   * debug [Boolean]: -d
        #   * others are options to pass to {FuseCommon#run}
        # @return [nil] if args are not parsed successfully
        def fuse_parse_cmdline(*argv, args: argv.any? ? argv : default_args, handler: nil)
          args = fuse_init_args(args)

          # Parse args and print cmdline help
          run_args = Fuse.parse_cmdline(args, handler: handler)

          handler.fuse_options(args) if handler.respond_to?(:fuse_options)

          parse_run_options(args, run_args)

          run_args[:args] = args
          run_args
        rescue Error
          nil
        end

        # @return [FuseCommon] the mounted filesystem handle
        # @return [nil] if not mounted (eg due to --help or --version, or an error)
        def fuse_create(mountpoint, *argv, operations:, args: nil, private_data: nil)
          args = fuse_init_args(args || argv)

          operations = FuseOperations.new(delegate: operations) unless operations.is_a?(FuseOperations)

          fuse = Fuse.new(mountpoint.to_s, args, operations, private_data)
          fuse if fuse.mounted?
        end

        # @!visibility private
        def fuse_configure(operations)
          return true unless operations.respond_to?(:fuse_configure)

          # Provide sensible values for FuseContext in case this is referenced during configure
          FFI::Libfuse::FuseContext.overrides do
            operations.fuse_configure
            true
          rescue Error => e
            warn e.message
            false
          rescue StandardError, ScriptError => e
            warn "#{e.class.name}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
            false
          end
        end

        # @!visibility private
        def version
          "#{name}: #{VERSION}"
        end

        private

        def fuse_init_args(args)
          if args.is_a?(Array)
            warn "FuseArgs: #{args.join(' ')}" if args.include?('-d')
            args = FuseArgs.create(*args)
          end

          return args if args.is_a?(FuseArgs)

          raise ArgumentError "fuse main args: must be Array<String> or #{FuseArgs.class.name}"
        end

        def parse_run_options(args, run_args)
          args.parse!(RUN_OPTIONS) do |key:, value:, **|
            run_args[key] = value
            next :keep if (STANDARD_OPTIONS.values + %i[remember]).include?(key)

            :discard
          end
        end
      end

      # @!group Abstract Configuration

      # @!method fuse_options(args)
      #  @abstract
      #  Called to allow filesystem to handle custom options and observe standard mount options #
      #  @param [FuseArgs] args
      #  @raise [Error] if there is an error parsing the options
      #  @return [void]
      #  @see FuseArgs#parse!
      #  @example
      #    OPTIONS = { 'config=' => :config, '-c ' => :config }
      #    def fuse_options(args)
      #       args.parse!(OPTIONS) do |key:, value:, out:, **opts|
      #
      #          # raise errors for invalid config
      #          raise FFI::Libfuse::Error, "Invalid config" unless valid_config?(key,value)
      #
      #          # Configure the file system
      #          @config = value if key == :config
      #
      #          #Optionally manipulate other arguments for fuse_mount() based on the current argument and state
      #          out.add('-oopt=val')
      #
      #          # Custom options must be marked :handled otherwise fuse_mount() will fail with unknown arguments
      #          :handled
      #       end
      #    end

      # @!method fuse_traps
      #  @abstract
      #  Passed to {FuseCommon#run} to allow filesystem to handle custom signal traps. These traps
      #  are merged over those from {FuseCommon#default_traps}. A nil value can be used to avoid a default trap
      #  being set.
      #  @return [Hash<String|Symbol|Integer,String|Proc|nil>]
      #    map of signal name or number to signal handler as per Signal.trap
      #  @example
      #    def fuse_traps
      #      {
      #         HUP: ->() { reload() },
      #         INT: nil
      #      }
      #    end

      # @!method fuse_version
      #  @abstract
      #  Called as part of generating output for the -V option
      #  @return [String] a custom version string to output with -V option

      # @!method fuse_help
      #  @abstract
      #  Called as part of generating output for the -h option
      #  @return [String] help text to explain custom options

      # @!method fuse_debug(enabled)
      #  @abstract
      #  Called to indicate to the filesystem whether debugging option is in use.
      #  @param [Boolean] enabled if -d option is in use
      #  @return [void]

      # @!method fuse_configure
      #  @abstract
      #  Called immediately before the filesystem is mounted, after options have been parsed
      #  (eg to validate required options)
      #
      #  @raise [Error] to prevent the mount from proceeding
      #  @return [void]

      # @!endgroup

      # @!visibility private

      # Standard help options
      STANDARD_OPTIONS = {
        '-h' => :show_help, '--help' => :show_help,
        '-d' => :debug, 'debug' => :debug,
        '-V' => :show_version, '--version' => :show_version
      }.freeze

      # Custom options that control how the fuse loop runs
      RUN_OPTIONS = STANDARD_OPTIONS.merge(
        {
          'native' => :native, # Use native libfuse functions for the process loop, primarily for testing
          'max_threads=' => :max_active,
          'remember=' => :remember
        }
      ).freeze

      # Help text
      HELP = <<~END_HELP
        #{name} options:
            -o max_threads         maximum number of worker threads
      END_HELP
    end
  end
end
