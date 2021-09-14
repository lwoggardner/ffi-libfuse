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
        #   and exits immediately if help or version options were processed
        # - installs signal handlers for INT, HUP, TERM to unmount and exit filesystem
        # - installs custom signal handlers if operations implements {fuse_traps}
        # - creates a fuse handle mounted with registered operations - see {fuse_create}
        # - calls either the single-threaded (option -s) or the multi-threaded event loop - see {FuseCommon#run}
        #
        # @param [Array<String>] argv mount.fuse arguments
        #   expects progname, mountpoint, options....
        # @param [FuseArgs] args
        #   alternatively constructed args
        # @param [Object|FuseOperations] operations
        #  something that responds to the fuse callbacks and optionally our abstract configuration methods
        # @param [Object] private_data
        #  any data to be made available to the {FuseOperations#init} callback
        #
        # @return [Integer] suitable for process exit code
        def fuse_main(*argv, operations:, args: argv, private_data: nil)
          run_args = fuse_parse_cmdline(args: args, handler: operations)
          return 2 unless run_args

          fuse_args = run_args.delete(:args)
          mountpoint = run_args.delete(:mountpoint)

          fuse = fuse_create(mountpoint, args: fuse_args, operations: operations, private_data: private_data)

          return 0 if run_args[:show_help] || run_args[:show_version]
          return 2 if !fuse || !mountpoint

          return unless fuse

          warn run_args.to_s if run_args[:debug]

          fuse.run(**run_args)
        end

        # Parse command line arguments
        #
        # - parses standard command line options (-d -s -h -V)
        #   will call {fuse_debug}, {fuse_version}, {fuse_help} if implemented by handler
        # - parses custom options if handler implements {fuse_options} and {fuse_opt_proc}
        # - records signal handlers if operations implements {fuse_traps}
        # - parses standard fuse mount options
        #
        # @param [Array<String>] argv mount.fuse arguments
        #   expects progname, [fsname,] mountpoint, options.... from mount.fuse3
        # @param [FuseArgs] args
        #   alternatively constructed args
        # @param [Object] handler
        #   something that responds to our abstract configuration methods
        # @param [Object] private_data passed to handler.fuse_opt_proc
        #
        # @return [Hash<Symbol,Object>]
        #   * fsname [String]: the fsspec from /etc/fstab
        #   * mountpoint [String]: the mountpoint argument
        #   * args [FuseArgs]: remaining fuse_args to pass to {fuse_create}
        #   * show_help [Boolean]: -h or --help
        #   * show_version [Boolean]: -v or --version
        #   * debug [Boolean]: -d
        #   * others are options to pass to {FuseCommon#run}
        def fuse_parse_cmdline(*argv, args: argv, handler: nil, private_data: nil)
          args = fuse_init_args(args)

          # Parse args and print cmdline help
          run_args = Fuse.parse_cmdline(args, handler: handler)

          # process custom options
          if %i[fuse_options fuse_opt_proc].all? { |m| handler.respond_to?(m) }
            parse_ok = args.parse!(handler.fuse_options, private_data) do |*p_args|
              handler.fuse_opt_proc(*p_args)
            end
            return unless parse_ok
          end

          run_args[:traps] = handler.fuse_traps if handler.respond_to?(:fuse_traps)

          args.parse!(RUN_OPTIONS, run_args) { |*opt_args| hash_opt_proc(*opt_args, discard: %i[native max_threads]) }

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

        # Helper fuse_opt_proc function to capture options into a hash
        #
        # See {FuseArgs.parse!}
        def hash_opt_proc(hash, arg, key, _out, discard: [])
          return :keep if %i[unmatched non_option].include?(key)

          hash[key] = arg =~ /=/ ? arg.split('=', 2).last : true
          discard.include?(key) ? :discard : :keep
        end

        # @!visibility private

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
            args = FuseArgs.create(*args)
          end

          return args if args.is_a?(FuseArgs)

          raise ArgumentError "fuse main args: must be Array<String> or #{FuseArgs.class.name}"
        end
      end

      # @!group Abstract Configuration

      # @!method fuse_options
      #  @abstract
      #  @return [Hash] custom option schema
      #  @see FuseArgs#parse!

      # @!method fuse_opt_proc(data,arg,key,out)
      #  @abstract
      #  Process custom options
      #  @see FuseArgs#parse!

      # @!method fuse_traps
      #  @abstract
      #  @return [Hash] map of signal name or number to signal handler as per Signal.trap

      # @!method fuse_version
      #  @abstract
      #  @return [String] a custom version string to output with -V option

      # @!method fuse_help
      #  @abstract
      #  @return [String] help text to explain custom options to show with -h option

      # @!method fuse_debug(enabled)
      #  @abstract
      #  Indicate to the filesystem whether debugging option is in use.
      #  @param [Boolean] enabled if -d option is in use
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
