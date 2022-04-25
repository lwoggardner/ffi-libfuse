# frozen_string_literal: true

require_relative 'fuse_version'
require_relative 'fuse_opt'
require_relative '../ruby_object'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    # struct fuse_args
    class FuseArgs < FFI::Struct
      layout :argc, :int, :argv, :pointer, :allocated, :int

      # Create a fuse_args struct from command line options
      # @param [Array<String>] argv command line args
      #
      #   first arg is expected to be program name
      # @return [FuseArgs]
      # @example
      #  FFI::Libfuse::FuseArgs.create($0,*ARGV)
      def self.create(*argv)
        new.fill(*argv)
      end

      # @!visibility private
      # noinspection RubyResolve
      def fill(*argv)
        # Keep the args allocated while in scope
        @arg_vector = FFI::MemoryPointer.new(:pointer, argv.size + 1)
        @argv_strings = argv.map { |k| FFI::MemoryPointer.from_string(k.to_s) }
        @arg_vector.write_array_of_pointer(@argv_strings)
        @arg_vector[argv.size].put_pointer(0, FFI::Pointer::NULL)
        self[:argv] = @arg_vector
        self[:argc] = argv.size
        self[:allocated] = 0
        self
      end

      # @!attribute [r] argc
      # @return [Integer] count of args
      def argc
        self[:argc]
      end

      # @!attribute [r] argv
      # @return [Array<String>] list of args
      def argv
        # noinspection RubyResolve
        self[:argv].get_array_of_pointer(0, argc).map(&:read_string)
      end

      # @!visibility private
      def allocated
        self[:allocated]
      end

      # @!visibility private
      def inspect
        "#{self.class.name} - #{%i[argc argv allocated].to_h { |m| [m, send(m)] }}"
      end

      # Add an arg to this arg list
      # @param [String] arg
      def add(arg)
        Libfuse.fuse_opt_add_arg(self, arg)
      end

      # Insert arg at pos in this struct via fuse_opt_insert_arg
      # @param [Integer] pos index to insert arg at
      # @param [String] arg
      def insert(pos, arg)
        Libfuse.fuse_opt_insert_arg(self, pos, arg)
      end

      #
      # Option parsing function
      #
      # Wraps fuse_opt_parse() in ruby sugar and safety
      #
      # @param [Hash<String,Symbol>] opts option schema
      #
      #  hash keys are a String template to match arguments against
      #
      #  1. "-x", "-foo", "--foo", "--foo-bar", etc.	These match only themselves.  Invalid values are "--" and anything
      #     beginning with "-o"
      #  2. "foo", "foo-bar", etc.  These match "-ofoo", "-ofoo-bar" or the relevant option in a comma separated option
      #     list
      #  3. "bar=", "--foo=", etc.  These are variations of 1) and 2) which have a parameter value
      #  4. '%' Formats Not Supported (or needed for Ruby!)
      #  5. "-x ", etc.  Matches either "-xparam" or "-x param" as two separate arguments
      #  6. '%' Formats Not Supported
      #
      #  hash values are the Symbol sent to the block for a matching argument
      #
      #  - :keep Argument is not passed to block, but behave as if the block returns :keep
      #  - :discard Argument is not passed to block, but behave as if the block returns :discard
      #  - any other value is yielded as 'key' property on matching argument
      #
      #  note that multiple templates can refer to the same key to support multiple option styles
      #
      # @param [Object] data an optional object that will be passed to the block
      # @param [Array<Symbol>|nil] ignore
      #   the keys in this list will be kept without being passed to the block. pass nil to observe all keys
      # @yield [key:, value:, match:, data:, out:]
      #   block is called for each remaining arg
      # @yieldparam [Symbol] key determines why the processing function was called
      #
      #  - :unmatched for arguments that *do not match* any supplied option
      #  - :non_option for non-option arguments (after -- or not beginning with -)
      #  - with appropriate value from opts hash for a matching argument
      # @yieldparam [String|Boolean] value the option value or true for option without a value
      # @yieldparam [String] match the matching template specification (ie a key in opts)
      # @yieldparam [Object] data
      # @yieldparam [FuseArgs] out can {add} or {insert} additional args as required
      #  eg. if one arg implies another
      #
      # @yieldreturn [Symbol] the argument action
      #
      #  - :error            an error, alternatively raise {Error}
      #  - :keep             retain the current argument for further processing
      #  - :handled,:discard remove the current argument from further processing
      # @return [nil|self] nil on error otherwise self
      def parse!(opts, data = nil, ignore: %i[non_option unmatched], &block)
        ignore ||= []

        # first create an array of unique symbols such that positive indexes are custom options and negative indexes are
        # special values (see fuse_opt.h), ie so we can turn the integer received in fuse_opt_proc back into a symbol
        symbols = opts.values.uniq + %i[discard keep non_option unmatched]

        # transform our symbol keys into integers suitable for FuseOpts
        int_opts = opts.transform_values do |v|
          %i[discard keep].include?(v) ? symbols.rindex(v) - symbols.size : symbols.index(v)
        end

        # keep track of opt templates by key so we extract parameter values from arg
        param_opts, bool_opts = opts.keys.partition { |t| t =~ /(\s+|=)$/ }.map do |opt_list|
          opt_list.group_by { |t| opts[t] }
        end

        fop = fuse_opt_proc(symbols, bool_opts, param_opts, ignore, &block)
        Libfuse.fuse_opt_parse(self, data, int_opts, fop).zero? ? self : nil
      end

      private

      # Valid return values from parse! block
      FUSE_OPT_PROC_RETURN = { error: -1, keep: 1, handled: 0, discard: 0 }.freeze

      def fuse_opt_proc(symbols, bool_opts, param_opts, ignore, &block)
        proc do |data, arg, key, out|
          key = symbols[key]
          next FUSE_OPT_PROC_RETURN.fetch(:keep) if ignore.include?(key)

          match, value =
            if %i[unmatched non_option].include?(key)
              [nil, arg]
            elsif bool_opts[key]&.include?(arg)
              [arg, true]
            elsif (opt = param_opts[key]&.detect { |t| arg.start_with?(t.rstrip) })
              # Contrary to fuse_opt.h the separating space is not always stripped from these options
              # https://github.com/libfuse/libfuse/issues/667
              [opt, arg[opt.rstrip.length..].lstrip]
            else
              warn "FuseOptProc error - Cannot match option for #{arg}"
              next -1
            end

          safe_opt_proc(key: key, value: value, match: match, data: data, out: out, &block)
        end
      end

      def safe_opt_proc(**args, &block)
        res = block.call(**args)
        res.is_a?(Integer) ? res : FUSE_OPT_PROC_RETURN.fetch(res)
      rescue KeyError => e
        warn "FuseOptProc error - Unknown result  #{e.key}"
        FUSE_OPT_PROC_RETURN.fetch(:error)
      rescue Error => e
        warn "#{e.message}: #{args.select { |k, _v| %i[key value].include?(k) }}\n#{argv}"
        FUSE_OPT_PROC_RETURN.fetch(:error)
      rescue StandardError, ScriptError => e
        warn "FuseOptProc error - #{e.class.name}:#{e.message}\n\t#{e.backtrace.join("\n\t")}"
        FUSE_OPT_PROC_RETURN.fetch(:error)
      end
    end

    # typedef int (*fuse_opt_proc_t)(void *data, const char *arg, int key, struct fuse_args *outargs);
    callback :fuse_opt_proc_t, [RubyObject, :string, :int, FuseArgs.by_ref], :int

    attach_function :fuse_opt_parse, [FuseArgs.by_ref, RubyObject, FuseOpt::OptList, :fuse_opt_proc_t], :int
    attach_function :fuse_opt_add_arg, [FuseArgs.by_ref, :string], :int
    attach_function :fuse_opt_insert_arg, [FuseArgs.by_ref, :int, :string], :int

    class << self
      # @!visibility private
      # @!method fuse_opt_parse
      # @!method fuse_opt_add_arg
      # @!method fuse_opt_insert_arg
    end
  end
end
