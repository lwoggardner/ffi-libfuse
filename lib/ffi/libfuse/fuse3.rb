# frozen_string_literal: true

require_relative 'fuse_common'
require_relative 'fuse_cmdline_opts'
require_relative 'fuse_loop_config'
require_relative 'fuse_args'
require_relative 'fuse_operations'
require_relative '../ruby_object'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    raise "Cannot load Fuse3 for #{FUSE_VERSION}" unless FUSE_MAJOR_VERSION == 3

    attach_function :fuse_parse_cmdline3,
                    :fuse_parse_cmdline, [FuseArgs.by_ref, FuseCmdlineOpts.by_ref], :int
    attach_function :fuse_cmdline_help, [], :void
    attach_function :fuse_lowlevel_help, [], :void
    attach_function :fuse_lib_help, [FuseArgs.by_ref], :void
    attach_function :fuse_pkgversion, [], :string
    attach_function :fuse_lowlevel_version, [], :void
    attach_function :fuse_new3,
                    :fuse_new, [FuseArgs.by_ref, FuseOperations.by_ref, :size_t, RubyObject], :fuse
    attach_function :fuse_mount3, :fuse_mount, %i[fuse string], :int
    attach_function :fuse_loop_mt3,
                    :fuse_loop_mt, [:fuse, FuseLoopConfig.by_ref], :int, blocking: true
    attach_function :fuse_session_fd, [:session], :int
    attach_function :fuse_session_exit, [:session], :void
    attach_function :fuse_session_exited, [:session], :int
    attach_function :fuse_unmount3, :fuse_unmount, %i[fuse], :void, blocking: true
    attach_function :fuse_session_receive_buf, [:session, FuseBuf.by_ref], :int, blocking: true
    attach_function :fuse_session_process_buf, [:session, FuseBuf.by_ref], :void, blocking: true

    class << self
      # @!visibility private
      # @!method fuse_parse_cmdline3
      # @!method fuse_cmdline_help
      # @!method fuse_lowlevel_help
      # @!method fuse_lib_help
      # @!method fuse_pkgversion
      # @!method fuse_lowlevel_version
      # @!method fuse_new3
      # @!method fuse_mount3
      # @!method fuse_loop_mt3
      # @!method fuse_session_fd
      # @!method fuse_session_exit
      # @!method fuse_session_exited
      # @!method fuse_unmount3
      # @!method fuse_session_receive_buf
      # @!method fuse_session_process_buf
    end

    # Helper class to managed a mounted fuse filesystem
    # @!visibility private
    class Fuse3 < FuseCommon
      class << self
        def parse_cmdline(args, handler: nil)
          cmdline_opts = FuseCmdlineOpts.new
          return nil unless Libfuse.fuse_parse_cmdline3(args, cmdline_opts).zero?

          handler&.fuse_debug(cmdline_opts.debug) if handler.respond_to?(:fuse_debug)

          # mimics fuse_main which exits after printing version info, even if -h
          if cmdline_opts.show_version
            show_version(handler)
          elsif cmdline_opts.show_help
            show_help(args, handler)
          end

          cmdline_opts.to_h
        end

        def show_version(handler)
          $stdout.puts "FUSE library version #{Libfuse.fuse_pkgversion}"
          Libfuse.fuse_lowlevel_version
          $stdout.puts Main.version
          $stdout.puts handler.fuse_version if handler.respond_to?(:fuse_version)
        end

        def show_help(args, handler)
          $stdout.puts "usage: #{args.argv.first} [options] <mountpoint>\n\n"
          $stdout.puts "FUSE options:\n"
          Libfuse.fuse_cmdline_help
          Libfuse.fuse_lib_help(args)
          $stdout.puts "\n"
          $stdout.puts Main::HELP
          $stdout.puts "\n#{handler.fuse_help}" if handler.respond_to?(:fuse_help)
        end

        def finalize_fuse(fuse, mounted)
          proc do
            if fuse
              Libfuse.fuse_unmount3(fuse) if mounted
              Libfuse.fuse_destroy(fuse)
            end
          end
        end
      end

      attr_reader :mountpoint

      # Have we requested an unmount (note not actually checking if OS sees the fs as mounted)
      def mounted?
        session && !fuse_exited? && @mounted
      end

      def initialize(mountpoint, args, operations, private_data)
        super()
        warn 'No mountpoint provided' unless mountpoint
        return unless mountpoint

        @mountpoint = mountpoint

        # Hang on to our ops and private data
        @operations = operations

        @fuse = Libfuse.fuse_new3(args, @operations, @operations.size, private_data)
        @fuse = nil if @fuse&.null?

        @mounted = @fuse && Libfuse.fuse_mount3(@fuse, @mountpoint).zero?
      ensure
        define_finalizer
      end

      def fuse_exited?
        !Libfuse.fuse_session_exited(session).zero?
      end

      def fuse_process
        se = session
        buf = Thread.current[:fuse_buffer] ||= FuseBuf.new
        res = Libfuse.fuse_session_receive_buf(se, buf)

        return false unless res.positive?

        Libfuse.fuse_session_process_buf(se, buf)
        true
      end

      # [IO] /dev/fuse file descriptor for use with IO.select
      def io
        # The FD is created (and destroyed?) by FUSE so we don't want ruby to do anything with it during GC
        @io ||= ::IO.for_fd(Libfuse.fuse_session_fd(session), 'r', autoclose: false)
      end

      private

      def native_fuse_loop_mt(max_idle_threads: 10, **_options)
        Libfuse.fuse_loop_mt3(@fuse, FuseLoopConfig.new.fill(max_idle: max_idle_threads))
      end

      def unmount
        return unless @mounted && @fuse && !@fuse.null?

        Libfuse.fuse_unmount3(@fuse)
        @mounted = false
      ensure
        define_finalizer
      end

      def define_finalizer
        # if we unmount/destroy in the finalizer then the private_data object cannot be used in destroy
        # as it's weakref will have been GC'd
        ObjectSpace.undefine_finalizer(self)
        ObjectSpace.define_finalizer(self, self.class.finalize_fuse(@fuse, @mounted))
      end
    end

    # @!visibility private
    Fuse = Fuse3
  end
end
