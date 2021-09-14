# frozen_string_literal: true

require_relative '../accessors'
require_relative 'fuse_loop_config'
module FFI
  module Libfuse
    #
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
    # @!visibility private
    class FuseCmdlineOpts < FFI::Struct
      include(FFI::Accessors)

      layout(
        single_thread: :int,
        foreground: :int,
        debug: :int,
        nodefault_subtype: :int,
        mountpoint: :string,
        show_version: :int,
        show_help: :int,
        clone_fd: :int,
        max_idle_threads: :int
      )

      # int to booleans
      ffi_attr_reader(:single_thread, :foreground, :debug, :nodefault_subtype, :show_version, :show_help,
                      :clone_fd) do |v|
        v != 0
      end

      ffi_attr_reader(:max_idle_threads, :mountpoint)
    end
  end
end
