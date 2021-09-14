# frozen_string_literal: true

require_relative 'fuse_version'
require_relative 'fuse_operations'
require_relative 'fuse_args'
require_relative 'fuse_common'
require_relative '../ruby_object'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    raise "Cannot load Fuse2 for #{FUSE_VERSION}" unless FUSE_MAJOR_VERSION == 2

    typedef :pointer, :chan
    typedef :pointer, :cmd

    attach_function :fuse_parse_cmdline2, :fuse_parse_cmdline, [FuseArgs.by_ref, :pointer, :pointer, :pointer], :int
    attach_function :fuse_mount2, :fuse_mount, [:string, FuseArgs.by_ref], :chan
    attach_function :fuse_new2, :fuse_new, [:chan, FuseArgs.by_ref, FuseOperations.by_ref, :size_t, RubyObject], :fuse
    attach_function :fuse_chan_fd, [:chan], :int
    attach_function :fuse_read_cmd, [:fuse], :cmd, blocking: true
    attach_function :fuse_process_cmd, %i[fuse cmd], :void, blocking: true
    attach_function :fuse_exited2, :fuse_exited, [:fuse], :int
    attach_function :fuse_unmount2, :fuse_unmount, %i[string chan], :void
    attach_function :fuse_loop_mt2, :fuse_loop_mt, [:fuse], :int, blocking: true

    class << self
      # @!visibility private
      # @!method fuse_parse_cmdline2
      # @!method fuse_mount2
      # @!method fuse_new2
      # @!method fuse_chan_fd
      # @!method fuse_read_cmd
      # @!method fuse_process_cmd
      # @!method fuse_exited2
      # @!method fuse_unmount2
      # @!method fuse_loop_mt2
    end

    # Helper class to managed a mounted fuse filesystem
    # @!visibility private
    class Fuse2 < FuseCommon
      class << self
        def parse_cmdline(args, handler: nil)
          # This also handles -h to print help information on stderr
          # Parse mountpoint, -f , -s from args
          # @return [Array<(String,Boolean,Boolean)>|nil]
          #     mountpoint, multi_thread, foreground options from args if available
          #     nil if no mountpoint, or options is requesting help or version information
          mountpoint_ptr = FFI::MemoryPointer.new(:pointer, 1)
          multi_thread_ptr = FFI::MemoryPointer.new(:int, 1)
          foreground_ptr = FFI::MemoryPointer.new(:int, 1)

          return nil unless Libfuse.fuse_parse_cmdline2(args, mountpoint_ptr, multi_thread_ptr, foreground_ptr).zero?

          # noinspection RubyResolve
          mp_data_ptr = mountpoint_ptr.get_pointer(0)

          mountpoint = mp_data_ptr.read_string unless mp_data_ptr.null?

          multi_thread = multi_thread_ptr.get(:int, 0) == 1
          foreground = foreground_ptr.get(:int, 0) == 1

          result = { mountpoint: mountpoint, single_thread: !multi_thread, foreground: foreground }
          args.parse!(Main::STANDARD_OPTIONS, [result, handler]) { |*proc_args| fuse_opt_proc(*proc_args) }
          result
        end

        # Handle standard custom args
        def fuse_opt_proc(custom, _arg, key, _outargs)
          return :keep if %i[unmatched non_option].include?(key)

          run_args, handler = custom
          case key
          when :show_help
            warn Main::HELP
            if handler.respond_to?(:fuse_help) && (help = handler.fuse_help)
              warn help
            end
          when :debug
            handler.fuse_debug(true) if handler.respond_to?(:fuse_debug)
          when :show_version
            warn Main.version
            if handler.respond_to?(:fuse_version) && (version = handler.fuse_version)
              warn version
            end
          else
            return :keep
          end
          run_args[key] = true
          :keep
        end

        def finalize_fuse(fuse, mountpoint, fuse_ch)
          proc do
            Libfuse.fuse_unmount2(mountpoint, fuse_ch) if fuse_ch
            Libfuse.fuse_destroy(fuse) if fuse
          end
        end
      end

      attr_reader :mountpoint

      # Have we requested an unmount (note not actually checking if OS sees the fs as mounted)
      def mounted?
        @fuse && Libfuse.fuse_exited2(@fuse).zero?
      end

      def initialize(mountpoint, args, operations, private_data)
        super()
        @mountpoint = mountpoint

        # Hang on to our ops and private data
        @operations = operations

        # Note this outputs the module args.
        @ch = Libfuse.fuse_mount2(@mountpoint, args)
        @ch = nil if @ch&.null?
        if @ch
          @fuse = Libfuse.fuse_new2(@ch, args, @operations, @operations.size, private_data)
          @fuse = nil if @fuse&.null?
        end
      ensure
        # if we unmount/destroy in the finalizer then the private_data object cannot be used in destory
        # as it's weakref will have been GC'd
        ObjectSpace.define_finalizer(self, self.class.finalize_fuse(@fuse, @mountpoint, @ch))
      end

      # [IO] /dev/fuse file descriptor for use with IO.select
      def io
        # The FD is created (and destroyed?) by FUSE so we don't want ruby to do anything with it during GC
        @io ||= ::IO.for_fd(Libfuse.fuse_chan_fd(@ch), 'r', autoclose: false)
      end

      def process
        cmd = Libfuse.fuse_read_cmd(@fuse)
        Libfuse.fuse_process_cmd(@fuse, cmd) if cmd && !cmd.null?

        # return true unless fuse has exited.
        Libfuse.fuse_exited2(@fuse).zero?
      end

      private

      def native_fuse_loop_mt(**_options)
        Libfuse.fuse_loop_mt2(@fuse)
      end

      def unmount
        c = @ch
        @ch = nil
        Libfuse.fuse_unmount2(mountpoint, c) if c
      end
    end

    # @!visibility private
    Fuse = Fuse2
  end
end
