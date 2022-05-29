# frozen_string_literal: true

module FFI
  module Libfuse
    module Adapter
      # Wrapper module to assist filesystem written for Fuse3 to be compatible with Fuse2
      module Fuse2Compat
        # Wrapper shim for fuse methods to ensure compatibility with Fuse2
        module Prepend
          include Adapter

          if FUSE_MAJOR_VERSION == 2
            # @!visibility private
            def getattr(path, stat, fuse_file_info = nil)
              super(path, stat, fuse_file_info)
            end

            def truncate(path, size, fuse_file_info = nil)
              super(path, size, fuse_file_info)
            end

            def init(fuse_conn_info, fuse_config = nil)
              super(fuse_conn_info, fuse_config)
            end

            def chown(path, uid, gid, fuse_file_info = nil)
              super(path, uid, gid, fuse_file_info)
            end

            def chmod(path, mode, fuse_file_info = nil)
              super(path, mode, fuse_file_info)
            end

            def utimens(path, atime, mtime, fuse_file_info = nil)
              super(path, atime, mtime, fuse_file_info)
            end

            def readdir(path, buffer, filler, offset, fuse_file_info, fuse_readdir_flag = 0)
              f3_fill = proc { |buf, name, stat, off = 0, _fuse_fill_dir_flag = 0| filler.call(buf, name, stat, off) }
              super(path, buffer, f3_fill, offset, fuse_file_info, fuse_readdir_flag)
            end

            def fgetattr(path, stat, ffi)
              stat.clear # For some reason (at least on OSX) the stat is not clear when this is called.
              getattr(path, stat, ffi)
              0
            end

            def ftruncate(*args)
              truncate(*args)
            end

            def fuse_respond_to?(fuse_method)
              fuse_method = fuse_method[1..].to_sym if %i[fgetattr ftruncate].include?(fuse_method)
              super(fuse_method)
            end

            def fuse_flags
              res = defined?(super) ? super : []
              if respond_to?(:init_fuse_config)
                fuse_config = FuseConfig.new
                init_fuse_config(fuse_config, :fuse2)
                res << :nullpath_ok if fuse_config.nullpath_ok?
              end

              res
            end

          else
            def init(*args)
              init_fuse_config(args.detect { |a| a.is_a?(FuseConfig) }) if respond_to?(:init_fuse_config)
              super if defined?(super)
            end
          end
        end

        # @!visibility private
        def self.included(mod)
          mod.prepend(Prepend)
        end

        # @!method init_fuse_config(fuse_config,compat)
        # @abstract
        # Define this method to configure the fuse config object so that under Fuse2 the config options
        # can be converted to appropriate flags.
        #
        # @param [FuseConfig] fuse_config the fuse config object
        # @param [Symbol] compat either :fuse2 or :fuse3
      end
    end
  end
end
