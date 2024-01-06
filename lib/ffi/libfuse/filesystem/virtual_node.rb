# frozen_string_literal: true

require_relative 'accounting'
require_relative '../adapter/ruby'

module FFI
  module Libfuse
    module Filesystem
      module Ruby
        # Common FUSE Callbacks for a virtual inode representing a single filesystem object at '/'
        #
        # **Note** this module is used by both {VirtualFile} which is under {Adapter::Ruby::Prepend}
        #  and {VirtualDir} which passes on native {FuseOperations} calls
        module VirtualNode
          # @return [Hash<Symbol,Integer>] base file or directory stat information used for :getattr of this node
          attr_reader :virtual_stat

          # @return [Hash<String,String>] virtual extended attributes
          attr_reader :virtual_xattr

          # @return [Accounting|nil] file system statistcs accumulator
          attr_reader :accounting

          # @param [Accounting] accounting accumulator of filesystem statistics
          def initialize(accounting: Accounting.new)
            @accounting = accounting

            @virtual_xattr = {}
          end

          # @!method path_method(callback, *args)
          #   @abstract
          #   called if this node cannot handle the callback (ie path is not root or an entry in this directory)

          # @!group FUSE Callbacks

          def utimens(path, *args)
            return path_method(__method__, path, *args) unless root?(path)

            atime, mtime, *_fuse3 = args
            # if native fuse call atime will be Array<Stat::TimeSpec>
            atime, mtime = Stat::TimeSpec.fill_times(atime[0, 2], 2).map(&:time) if atime.is_a?(Array)
            virtual_stat[:atime] = atime if atime
            virtual_stat[:mtime] = mtime if mtime
            virtual_stat[:ctime] = mtime if mtime
          end

          def chmod(path, mode, *args)
            return path_method(__method__, path, mode, *args) unless root?(path)

            virtual_stat[:mode] = mode
            virtual_stat[:ctime] = Time.now
          end

          def chown(path, uid, gid, *args)
            return path_method(__method__, path, uid, gid, *args) unless root?(path)

            virtual_stat[:uid] = uid
            virtual_stat[:gid] = gid
            virtual_stat[:ctime] = Time.now
          end

          def statfs(path, statfs_buf)
            return path_method(__method__, path, statfs_buf) unless root?(path)
            raise Errno::ENOTSUP unless accounting

            accounting.to_statvfs(statfs_buf)
          end

          def getxattr(path, name, buf = nil, size = nil)
            return path_method(__method__, path, name, buf, size) unless root?(path)
            return virtual_xattr[name] unless buf

            Adapter::Ruby.getxattr(buf, size) { virtual_xattr[name] }
          end

          def listxattr(path, buf = nil, size = nil)
            return path_method(__method__, path) unless root?(path)
            return virtual_xattr.keys unless buf

            Adapter::Ruby.listxattr(buf, size) { virtual_xattr.keys }
          end

          # @!endgroup

          # Initialise the stat information for the node - should only be called once (eg from create or mkdir)
          def init_node(mode, ctx: FuseContext.get, now: Time.now)
            @virtual_stat =
              {
                mode: mode & ~ctx.umask, uid: ctx.uid, gid: ctx.gid,
                ctime: now, mtime: now, atime: now
              }
            accounting&.adjust(0, +1)
            self
          end

          private

          # @!visibility private
          def path_method(_method, *_args)
            raise Errno::ENOENT
          end

          def root?(path)
            path.to_s == '/'
          end
        end
      end

      # @abstract
      # Base class Represents a virtual inode
      class VirtualNode
        include Ruby::VirtualNode
      end
    end
  end
end
