# frozen_string_literal: true

module FFI
  module Libfuse
    module Adapter
      # Wrapper module to assist filesystem written for Fuse2 to be compatible with Fuse3
      #
      # @note there are some deprecated Fuse2 features that have no forwards compatibility in Fuse3
      #
      #  - flag nopath became fuse_config.nullpath_ok but it is not compatible since chmod/chown etc will now
      #    receive a null path but the filesystem cannot receive the new fuse_file_info arg
      #
      module Fuse3Support
        # The actual module methods that are prepended
        module Prepend
          include Adapter

          # Inner adapters received Fuse2 compatible args
          def fuse3_compat?
            false
          end

          def getattr(*args)
            fi = args.pop
            return fgetattr(*args, fi) if fi && fuse_super_respond_to?(:fgetattr)

            super(*args)
          end

          def truncate(*args)
            fi = args.pop
            return ftruncate(*args, fi) if fi && fuse_super_respond_to?(:ftruncate)

            super(*args)
          end

          def chown(*args)
            args.pop
            super(*args)
          end

          def chmod(*args)
            args.pop
            super(*args)
          end

          # TODO: Fuse3 deprecated flag utime_omit_ok - which meant that UTIME_OMIT and UTIME_NOW are passed through
          #  instead of ????
          #  Strictly if the flag is not set this compat shim should convert utime now values to Time.now
          #  but there is no way to handle OMIT
          def utimens(*args)
            args.pop
            super(*args) if defined?(super)
          end

          def init(*args)
            args.pop

            # TODO: populate FuseConfig with output from fuse_flags/FuseConnInfo where appropriate
            super(*args)
          end

          def readdir(*args, &block)
            # swallow the flag arg unknown to fuse 2
            args.pop

            args = args.map do |a|
              next a unless a.is_a?(FFI::Function)

              # wrap the filler proc for the extra flags argument
              proc { |buf, name, stat, off| a.call(buf, name, stat, off, 0) }
            end

            super(*args, &block)
          end

          def fuse_respond_to(fuse_callback)
            super || (%i[truncate getattr].include?(fuse_callback) && fuse_super_respond_to?("f#{fuse_callback}"))
          end
        end

        # @!visibility private
        def self.included(mod)
          # We prepend our shim module so caller doesn't have to call super
          mod.prepend(Prepend) if FUSE_MAJOR_VERSION > 2
        end
      end
    end
  end
end
