# frozen_string_literal: true

require_relative 'fuse_common'
require_relative 'fuse_args'
require_relative 'fuse_operations'

module FFI
  module Libfuse
    # Controls the main run loop for a FUSE filesystem
    module Main
      class << self
        # Main function of FUSE
        #
        # This function:
        #
        # - parses command line options - see {fuse_parse_cmdline}
        #   exiting immediately if help or version options were processed
        # - calls {#fuse_debug}, {#fuse_options}, {#fuse_configure} if implemented by operations
        # - installs signal handlers for INT, HUP, TERM to unmount and exit filesystem
        # - installs custom signal handlers if operations implements {fuse_traps}
        # - creates a fuse handle mounted with registered operations - see {fuse_create}
        # - calls either the single-threaded (option -s) or the multi-threaded event loop - see {FuseCommon#run}
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
        def fuse_main(*argv, operations:, args: argv.any? ? argv : [$0, *ARGV], private_data: nil)
          run_args = fuse_parse_cmdline(args: args, handler: operations)
          return 2 unless run_args

          fuse_args = run_args.delete(:args)
          mountpoint = run_args.delete(:mountpoint)

          return 3 unless fuse_configure(operations: operations, **run_args)

          warn "FuseCreate: mountpoint: #{mountpoint}, args: [#{fuse_args.argv.join(' ')}]" if run_args[:debug]
          warn "FuseRun: #{run_args}" if run_args[:debug]

          fuse = fuse_create(mountpoint, args: fuse_args, operations: operations, private_data: private_data)

          return 0 if run_args[:show_help] || run_args[:show_version]
          return 2 if !fuse || !mountpoint

          return unless fuse

          fuse.run(**run_args)
        end
        alias main fuse_main

        # Parse command line arguments
        #
        # - parses standard command line options (-d -s -h -V)
        #   will call {fuse_debug}, {fuse_version}, {fuse_help} if implemented by handler
        # - calls {fuse_options} for custom option processing if implemented by handler
        # - records signal handlers if operations implements {fuse_traps}
        # - parses standard fuse mount options
        #
        # @param [Array<String>] argv mount.fuse arguments
        #   expects progname, [fsname,] mountpoint, options.... from mount.fuse3
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
        def fuse_parse_cmdline(*argv, args: argv, handler: nil)
          args = fuse_init_args(args)

          # Parse args and print cmdline help
          run_args = Fuse.parse_cmdline(args, handler: handler)
          return nil unless run_args

          return nil if handler.respond_to?(:fuse_options) && !handler.fuse_options(args)

          run_args[:traps] = handler.fuse_traps if handler.respond_to?(:fuse_traps)

          return nil unless parse_run_options(args, run_args)

          run_args[:args] = args
          run_args
        end

        # @return [FuseCommon|nil] the mounted filesystem or nil if not mounted
        def fuse_create(mountpoint, *argv, operations:, args: nil, private_data: nil)
          args = fuse_init_args(args || argv.unshift(mountpoint))

          operations = FuseOperations.new(delegate: operations) unless operations.is_a?(FuseOperations)

          fuse = Fuse.new(mountpoint, args, operations, private_data)
          fuse if fuse.mounted?
        end

        # @!visibility private

        def fuse_configure(operations:, show_help: false, show_version: false, **_)
          return true unless operations.respond_to?(:fuse_configure) && !show_help && !show_version

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

        # Version text
        def version
          "#{name}: #{VERSION}"
        end

        def fuse_init_args(args)
          if args.is_a?(Array)
            args = args.map(&:to_s) # handle mountpoint as Pathname etc..

            # https://github.com/libfuse/libfuse/issues/621 handle "source" field sent from /etc/fstab via mount.fuse3
            # if arg[1] and arg[2] are both non option fields then replace arg1 with -ofsname=<arg1>
            unless args.size <= 2 || args[1]&.start_with?('-') || args[2]&.start_with?('-')
              args[1] = "-ofsname=#{args[1]}"
            end
            warn "FuseArgs: #{args.join(' ')}" if args.include?('-d')
            args = FuseArgs.create(*args)
          end

          return args if args.is_a?(FuseArgs)

          raise ArgumentError "fuse main args: must be Array<String> or #{FuseArgs.class.name}"
        end

        private

        def parse_run_options(args, run_args)
          args.parse!(RUN_OPTIONS) do |key:, value:, **|
            run_args[key] = value
            next :discard if (RUN_OPTIONS.values - %i[remember]).include?(key)

            :keep
          end
        end
      end

      # @!group Abstract Configuration

      # @!method fuse_options(args)
      #  @abstract
      #  Called to allow filesystem to handle custom options and observe standard mount options #
      #  @param [FuseArgs] args
      #  @return [Boolean] true if args parsed successfully
      #  @see FuseArgs#parse!
      #  @example
      #    OPTIONS = { 'config=' => :config, '-c ' => :config }
      #    def fuse_options(args)
      #       args.parse!(OPTIONS) do |key:, value:, out:, **opts|
      #
      #          # raise errors for invalid config
      #          raise FFI::Libfuse::FuseArgs::Error, "Invalid config" unless valid_config?(key,value)
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
      #  @return [Hash<String|Symbol|Integer,String|Proc>]
      #    map of signal name or number to signal handler as per Signal.trap
      #  @example
      #    def fuse_traps
      #      { HUP: ->() { reload() }}
      #    end

      # @!method fuse_version
      #  @abstract
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
