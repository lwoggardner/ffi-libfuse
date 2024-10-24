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
              super
            end

            def truncate(path, size, fuse_file_info = nil)
              super
            end

            def init(fuse_conn_info, fuse_config = nil)
              super
            end

            def chown(path, uid, gid, fuse_file_info = nil)
              super
            end

            def chmod(path, mode, fuse_file_info = nil)
              super
            end

            def utimens(path, times, fuse_file_info = nil)
              super
            end

            def readdir(path, buffer, filler, offset, fuse_file_info, fuse_readdir_flag = 0)
              f3_fill = proc { |buf, name, stat, off = 0, _fuse_fill_dir_flag = 0| filler.call(buf, name, stat, off) }
              super(path, buffer, f3_fill, offset, fuse_file_info, fuse_readdir_flag)
            end

            def fuse_respond_to?(fuse_method)
              # getdir is never supported here anyway
              # fgetattr and ftruncate already fallback to the respective basic method
              return false if %i[getdir fgetattr ftruncate].include?(fuse_method)

              super
            end

            def fuse_options(args)
              super if defined?(super)
              return unless respond_to?(:init_fuse_config)

              FUSE_CONFIG_ONLY_ATTRIBUTES.each do |opt|
                args.add("-o#{opt}") if fuse_config.send(opt)
              end
            end

            def fuse_flags
              res = defined?(super) ? super : []
              return res unless respond_to?(:init_fuse_config)

              FUSE_CONFIG_FLAGS.each { |opt| res << opt if fuse_config.send(opt) }
              res
            end

            private

            def fuse_config
              @fuse_config ||= begin
                fuse_config = FuseConfig.new
                init_fuse_config(fuse_config, :fuse2) if respond_to?(:init_fuse_config)
                fuse_config
              end
            end

          else
            def init(*args)
              init_fuse_config(args.detect { |a| a.is_a?(FuseConfig) }, :fuse3) if respond_to?(:init_fuse_config)
              super if defined?(super)
            end
          end
        end

        # Attributes in Fuse3 config that cannot be set by Fuse3 options. If set via {init_fuse_config} the
        # equivalent options will be force set under Fuse 2
        FUSE_CONFIG_ONLY_ATTRIBUTES = %i[hard_remove use_ino readdir_ino direct_io].freeze

        # Attributes in Fuse3 config that were {FuseOperations#fuse_flags} in Fuse2. If set via {init_fuse_config} the
        # equivalent flags will be added
        FUSE_CONFIG_FLAGS = %i[nullpath_ok].freeze

        # @!visibility private
        def self.included(mod)
          mod.prepend(Prepend) if FUSE_MAJOR_VERSION < 3
        end

        # @!method init_fuse_config(fuse_config,compat)
        # @abstract
        # Define this method to configure the {FuseConfig} object so that under Fuse2 the config options
        # can be converted to appropriate flags or options
        #
        # @param [FuseConfig] fuse_config the fuse config object
        # @param [Symbol] compat either :fuse2 or :fuse3
      end
    end
  end
end
