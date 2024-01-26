# frozen_string_literal: true

require_relative '../accessors'
require_relative '../boolean_int'
require_relative 'fuse_loop_config'
module FFI
  module Libfuse
    # struct fuse_cmdline_opts {
    #   int singlethread;
    #   int foreground;
    #   int debug;
    #   int nodefault_subtype;
    #   char *mountpoint;
    #   int show_version;
    #   int show_help;
    #   int clone_fd;
    #   unsigned int max_idle_threads;
    # };

    # Command line options
    # @!visibility private
    class FuseCmdlineOpts < FFI::Struct
      include(FFI::Accessors)

      spec = {
        single_thread: :bool_int,
        foreground: :bool_int,
        debug: :bool_int,
        nodefault_subtype: :bool_int,
        mountpoint: :string,
        show_version: :bool_int,
        show_help: :bool_int,
        clone_fd: :bool_int,
        max_idle_threads: :int
      }

      layout(spec)

      bool, = spec.partition { |_, v| v == :bool_int }
      ffi_attr_reader(*bool.map { |k, _| "#{k}?" })

      ffi_attr_reader(:max_idle_threads, :mountpoint)
    end
  end
end
