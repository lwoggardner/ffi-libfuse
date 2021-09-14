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

      # Create an fuse_args struct from command line options
      # @param [Array<String>] argv command line args
      #   args[0] is expected to be program name
      # @return [FuseArgs]
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
      #  @return [Integer] count of args
      def argc
        self[:argc]
      end

      # @!attribute [r] argv
      #  @return [Array<String>]
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
        "#{self.class.name} - #{%i[argc argv allocated].map { |m| [m, send(m)] }.to_h}"
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
      # @param [Hash<String,Symbol>] opts option schema
      #
      #  hash keys are a String template to match arguments against
      #
      #  1. "-x", "-foo", "--foo", "--foo-bar", etc.	These match only themselves.  Invalid values are "--" and anything
      #     beginning with "-o"
      #  2. "foo", "foo-bar", etc.  These match "-ofoo", "-ofoo-bar" or the relevant option in a comma separated option
      #     list
      #  3. "bar=", "--foo=", etc.  These are variations of 1) and 2) which have a parameter
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
      # @param [Object] data an optional object that will be passed thru to the block
      #
      # @yieldparam [Object] data
      # @yieldparam [String] arg is the whole argument or option including the parameter if exists.
      #
      #  A two-argument option ("-x foo") is always converted to single argument option of the form "-xfoo" before this
      #  function is called.
      #
      #  Options of the form '-ofoo' are yielded without the '-o' prefix.
      #
      # @yieldparam [Symbol] key determines why the processing function was called
      #
      #  - :unmatched for arguments that *do not match* any supplied option
      #  - :non_option for non-option arguments (after -- or not beginning with -)
      #  - with appropriate value from opts hash for a matching argument
      #
      # @yieldparam [FuseArgs] outargs can {add} or {insert} additional args as required
      #
      #  eg. if one arg implies another
      #
      # @yieldreturn [Symbol] the argument action
      #
      #  - :error            an error
      #  - :keep             the current argument (to pass on further)
      #  - :handled,:discard success and discard the current argument (ie because it has been handled)
      #
      # @return [nil|FuseArgs] nil on error, self on success
      def parse!(opts, data = nil, &block)
        # turn option value symbols into integers including special negative values from fuse_opt.h
        symbols = opts.values.uniq + %i[discard keep non_option unmatched]

        int_opts = opts.transform_values do |v|
          %i[discard keep].include?(v) ? symbols.rindex(v) - symbols.size : symbols.index(v)
        end

        fop = proc { |d, arg, key, outargs| fuse_opt_proc(d, arg, symbols[key], outargs, &block) }
        result = Libfuse.fuse_opt_parse(self, data, int_opts, fop)

        result.zero? ? self : nil
      end

      private

      # Valid return values from parse! block
      FUSE_OPT_PROC_RETURN = { error: -1, keep: 1, handled: 0, discard: 0 }.freeze

      def fuse_opt_proc(data, arg, key, out, &block)
        res = block.call(data, arg, key, out)
        res.is_a?(Integer) ? res : FUSE_OPT_PROC_RETURN.fetch(res)
      rescue KeyError => e
        warn "FuseOptProc error - Unknown result  #{e.key}"
        -1
      rescue StandardError => e
        warn "FuseOptProc error - #{e.class.name}:#{e.message}"
        -1
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
