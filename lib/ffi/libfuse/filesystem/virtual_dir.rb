# frozen_string_literal: true

require_relative 'accounting'
require_relative 'virtual_node'
require_relative 'virtual_file'
require_relative 'virtual_link'
require_relative 'pass_through_file'
require_relative 'pass_through_dir'
require_relative 'mapped_dir'

module FFI
  module Libfuse
    module Filesystem
      # A Filesystem of Filesystems
      #
      # Implements a simple Hash based directory of sub filesystems.
      #
      # FUSE Callbacks
      # ===
      #
      # If path is root ('/') then the operation applies to this directory itself
      #
      # If the path is a simple basename (with leading slash and no others) then the operation applies to an entry in
      #  this directory.  The operation is handled by the directory and then passed on to the entry itself
      #  (with path = '/')
      #
      # Otherwise it is passed on to the next entry via {#path_method}
      #
      # Constraints
      # ===
      #
      #   * Expects to be wrapped by {Adapter::Safe}
      #   * Passes on FUSE Callbacks to sub filesystems agnostic of {FUSE_MAJOR_VERSION}. Sub-filesystems should use
      #     {Adapter::Fuse2Compat} or {Adapter::Fuse3Support} as required
      #
      class VirtualDir < VirtualNode
        include Utils

        # @return [Hash<String,FuseOperations>] our directory entries
        attr_reader :entries

        def initialize(accounting: Accounting.new)
          @entries = {}
          super
        end

        # @!endgroup

        # @!group FUSE Callbacks

        # For the root path provides this directory's stat information, otherwise passes on to the next filesystem
        def getattr(path, stat_buf = nil, ffi = nil)
          if root?(path)
            stat_buf&.directory(nlink: entries.size + 2, **virtual_stat)
            return self
          end

          path_method(__method__, path, stat_buf, ffi, notsup: Errno::ENOSYS)
        end

        # Safely passes on file open to next filesystem
        #
        # @raise [Errno::EISDIR] for the root path since we are a directory rather than a file
        # @return [Object] the result of {#path_method} for the sub filesystem
        # @return [nil] for sub-filesystems that do not implement this callback or raise ENOTSUP or ENOSYS
        def open(path, *args)
          raise Errno::EISDIR if root?(path)

          path_method(__method__, path, *args, notsup: nil)
        end

        # Safely handle file release
        #
        # Passes on to next filesystem, rescuing ENOTSUP or ENOSYS
        # @raise [Errno::EISDIR] for the root path since we are a directory rather than a file
        def release(path, *args)
          raise Errno::EISDIR if root?(path)

          path_method(__method__, path, *args, notsup: nil)
        end

        # Safely handles directory open to next filesystem
        #
        # @return [self] for the root path, which helps shortcut future operations. See {#readdir}
        # @return [Object] the result of {#path_method} for all other paths
        # @return [nil] for sub-filesystems that do not implement this callback or raise ENOTSUP or ENOSYS
        def opendir(path, ffi)
          return (ffi.fh = self) if root?(path)

          path_method(__method__, path, ffi, notsup: nil)
        end

        # Safely handles directory release
        #
        # Does nothing for the root path
        #
        # Otherwise safely passes on to next filesystem, rescuing ENOTSUP or ENOSYS
        def releasedir(path, *args)
          return if root?(path)

          path_method(__method__, path, *args, notsup: nil)
        end

        # If path is root fills the directory from the keys in {#entries}
        #
        # If ffi.fh is itself a filesystem then try to call its :readdir directly
        #
        # Otherwise passes to the next filesystem in path
        def readdir(path, buf, filler, offset, ffi, *flag)
          return %w[. ..].concat(entries.keys).each(&Adapter::Ruby::ReaddirFiller.new(buf, filler)) if root?(path)

          return ffi.fh.readdir('/', buf, filler, offset, ffi, *flag) if dir_entry?(ffi.fh)

          path_method(:readdir, path, buf, filler, offset, ffi, *flag, notsup: Errno::ENOTDIR)
        end

        # For root path validates we are empty and removes a node link from {#accounting}
        # For our entries, passes on the call to the entry (with path='/') and then removes the entry.
        # @raise [Errno::ENOTEMPTY] if path is root and our entries list is not empty
        # @raise [Errno::ENOENT] if the entry does not exist
        # @raise [Errno::ENOTDIR] if the entry does not respond to :readdir (ie: is not a directory)
        def rmdir(path)
          if root?(path)
            raise Errno::ENOTEMPTY unless entries.empty?

            accounting.adjust(0, -1)
            return
          end

          path_method(__method__, path) do |entry_key, dir|
            raise Errno::ENOENT unless dir
            raise Errno::ENOTDIR unless dir_entry?(dir)

            entry_send(dir, :rmdir, '/')

            entries.delete(entry_key)
            dir
          end
        end

        # For our entries, creates a new file
        # @raise [Errno::EISDIR] if the entry exists and responds_to?(:readdir)
        # @raise [Errno::EEXIST] if the entry exists
        # @yield [String] filename the name of the file in this directory
        # @yieldreturn [:getattr] something that quacks with the FUSE Callbacks of a regular file
        #
        #   :create or :mknod + :open will be attempted with path = '/' on this file
        # @return the result of the supplied block, or if not given a new {VirtualFile}
        def create(path, mode = FuseContext.get.mask(0o644), ffi = nil, &file)
          raise Errno::EISDIR if root?(path)

          # fuselib will fallback to mknod on ENOSYS on a case by case basis
          path_method(__method__, path, mode, ffi, notsup: Errno::ENOSYS, block: file) do |name, existing|
            raise Errno::EISDIR if dir_entry?(existing)
            raise Errno::EEXIST if existing

            # TODO: Strictly should understand setgid and sticky bits of this dir's mode when creating new files
            new_file = file ? file.call(name) : new_file(name)
            if entry_fuse_respond_to?(new_file, :create)
              new_file.create('/', mode, ffi)
            else
              # TODO: generate a sensible device number
              entry_send(new_file, :mknod, '/', mode, 0)
              entry_send(new_file, :open, '/', ffi)
            end
            entries[name] = new_file
          end
        end

        # Method for creating a new file
        # @param  [String] _name
        # @return [FuseOperations] something representing a regular file
        def new_file(_name)
          VirtualFile.new(accounting: accounting)
        end

        # Creates a new directory entry in this directory
        # @param [String] path
        # @param [Integer] mode
        # @yield [String] name the name of the directory in this filesystem
        # @yieldreturn [Object] something that quacks with the FUSE Callbacks representing a directory
        # @return the result of the block if given, otherwise the newly created sub {VirtualDir}
        # @raise [Errno::EEXIST] if the entry already exists at path
        def mkdir(path, mode = FuseContext.get.mask(0o777), &dir)
          return init_node(mode) if root?(path)

          path_method(__method__, path, mode, block: dir) do |dir_name, existing|
            raise Errno::EEXIST if existing

            new_dir = dir ? dir.call(dir_name) : new_dir(dir_name)
            entry_send(new_dir, :mkdir, '/', mode)
            entries[dir_name] = new_dir
          end
        end

        # Method for creating a new directory, called from mkdir
        # @param [String] _name
        # @return [FuseOperations] something representing a directory
        def new_dir(_name)
          VirtualDir.new(accounting: accounting)
        end

        # Create a new hard link in this filesystem
        #
        # @param [String, nil] from_path
        # @param [String] to_path
        # @yield [existing]
        #   Used to retrieve the filesystem object at from_path to be linked at to_path
        #
        #   If not supplied, a proc wrapping #{new_link} is created and used or passed on to sub-filesystems
        # @yieldparam [FuseOperations] existing the object currently at to_path
        # @yieldreturn [FuseOperations] an object representing an inode to be linked at to_path
        # @raise [Errno::EISDIR] if this object is trying to be added as a link (since you can't hard link directories)
        # @see new_link
        def link(from_path, to_path, &linker)
          # Can't link to a directory
          raise Errno::EISDIR if root?(to_path)
          raise Errno::ENOSYS unless from_path || linker

          same_filesystem_method(__method__, from_path, to_path) do
            linker ||= proc { |replacing| new_link(from_path, replacing) }
            path_method(__method__, from_path, to_path, block: linker) do |link_name, existing|
              linked_entry = linker.call(existing)
              entries[link_name] = linked_entry
            end
          end
        end

        # Called from within #{link}
        #   Uses #{getattr}(from_path) to find the filesystem object at from_path.
        #   Calls #{link}(nil, '/') on this object to signal that a new link has been created to it.
        #   Filesystem objects that do not support linking should raise `Errno::EPERM` if the object should not be hard
        #   linked (eg directories)
        # @return [FuseOperations]
        # @raise Errno::EXIST if there is an existing object to replace
        # @raise Errno::EPERM if the object at from_path is not a filesystem (does not itself respond to #getattr)
        def new_link(from_path, replacing)
          raise Errno::EEXIST if replacing

          linked_entry = getattr(from_path)

          # the linked entry itself must represent a filesystem inode
          raise Errno::EPERM unless entry_fuse_respond_to?(linked_entry, :getattr)

          entry_send(linked_entry, :link, nil, '/')
          linked_entry
        end

        # For our entries validates the entry exists and calls unlink('/') on it to do any cleanup
        # before removing the entry from our entries list.
        #
        # If a block is supplied (eg #{rename}) it will be called before the entry is deleted
        #
        # @raise [Errno:EISDIR] if we are unlinking ourself (use rmdir instead)
        # @raise [Errno::ENOENT] if the entry does not exist at path (and no block is provided)
        # @return the unlinked filesystem object
        # @yield(file_name, entry)
        # @yieldparam [FuseOperations] entry a filesystem like object representing the file being unlinked
        # @yieldreturn [void]
        def unlink(path, &rename)
          raise Errno::EISDIR if root?(path)

          path_method(__method__, path, block: rename) do |entry_key, entry|
            if rename
              rename.call(entry)
            elsif entry
              entry_send(entry, :unlink, '/')
            else
              raise Errno::ENOENT
            end

            entries.delete(entry_key)
          end
        end

        # Rename is handled via #{link} and #{unlink} using their respective block arguments to handle validation
        # and retrieve the object at from_path. Intermediate directory filesystems are only required to pass on the
        # block, while the final directory target of from_path and to_path must call these blocks as this class does.
        #
        # If to_path is being replaced the existing entry will be signaled via #{unlink}('/'), or #{rmdir}('/')
        # @raise Errno::EINVAL if trying to rename the root object OR from_path is a directory prefix of to_path
        # @raise Errno::ENOENT if the filesystem at from_path does not exist
        # @raise Errno::ENOSYS if the filesystem at from_path or directory of to_path does not support rename
        # @raise Errno::EEXIST if the filesystem at to_path already exists and is not a symlink
        # @see POSIX rename(2)
        # @note As per POSIX raname(2) silently succeeds if from_path and to_path are hard links to the
        # same filesystem object (ie without unlinking from_path)
        def rename(from_path, to_path)
          return if from_path == to_path
          raise Errno::EINVAL if root?(from_path)

          same_filesystem_method(__method__, from_path, to_path, rescue_notsup: true) do
            # Can't rename into a subdirectory of itself
            raise Errno::EINVAL if to_path.start_with?("#{from_path}/")

            # POSIX rename(2) requires to silently abandon, without unlinking from_path,
            # if the inodes at from_path and to_path are the same object (ie hard linked to each other))
            catch :same_hard_link do
              link(nil, to_path) do |replacing|
                check_rename_unlink(from_path)
                unlink(from_path) do |source|
                  raise Errno::ENOENT unless source

                  throw :same_hard_link if source.equal?(replacing)
                  rename_cleanup_overwritten(replacing)
                end
              end
            end
          end
        end

        # Common between {#link} and {#rename} are callbacks that might have different semantics
        # if called within the same sub-filesystem.
        # While from_path and to_path have a common top level directory, we pass the callback on
        # to the entry at that directory
        def same_filesystem_method(callback, from_path, to_path, rescue_notsup: false)
          return yield unless from_path # no from_path to traverse

          to_dir, next_to_path = entry_path(to_path)
          return yield if root?(next_to_path) # target is our entry, no more directories to traverse

          from_dir, next_from_path = entry_path(from_path)
          return yield if from_dir != to_dir # from and to in different directories, we need to handle it ourself

          # try traverse into sub-fs, which must itself be a directory
          begin
            entry_send(
              entries[to_dir], callback,
              next_from_path, next_to_path,
              notsup: Errno::ENOSYS, notdir: Errno::ENOTDIR, rescue_notsup: rescue_notsup
            )
          rescue Errno::ENOSYS, Errno::ENOTSUP
            raise unless rescue_notsup

            yield
          end
        end

        # Creates a new symbolic link in this directory
        # @param [String] target - an absolute path for the operating system or relative to path
        # @param [String] path - the path to create the link at
        def symlink(target, path)
          path_method(__method__, target, path) do |link_name, existing|
            raise Errno::EEXIST if existing

            new_link = new_symlink(link_name)
            entry_send(new_link, :symlink, target, '/')
            entries[link_name] = new_link
          end
        end

        def new_symlink(_name)
          VirtualLink.new(accounting: accounting)
        end

        # @!endgroup

        # Finds the path argument of the callback and splits it into an entry in this directory and a remaining path
        #
        # If a block is given and there is no remaining path (ie our entry) the block is called and its value returned
        #
        # If the path is not our entry, the callback is passed on to the sub filesystem entry with the remaining path
        #
        # If the path is our entry, but not block is provided, the callback is passed to our entry with a path of '/'
        #
        # @param [Symbol] callback a FUSE Callback
        # @param [Array] args callback arguments (first argument is typically 'path')
        # @param [Errno] notsup an error to raise if this callback is not supported by our entry
        # @param [Proc] block optional block to keep passing down. See {#mkdir}, {#create}, {#link}
        # @raise [Errno:ENOENT] if the next entry does not exist
        # @raise [Errno::ENOTDIR] if the next entry must be a directory, but does not respond to :raaddir
        # @raise [SystemCallError] error from notsup if the next entry does not respond to ths callback
        # @yield(entry_key, entry)
        # @yieldparam [String,nil] entry_key the name of the entry in this directory or nil, if path is '/'
        # @yieldparam [FuseOperations,nil] entry the filesystem object currently stored at entry_key
        def path_method(callback, *args, notsup: Errno::ENOTSUP, block: nil)
          # Inside path_method
          _read_arg_method, path_arg_method, next_arg_method = FuseOperations.path_arg_methods(callback)
          path = args.send(path_arg_method)

          entry_key, next_path = entry_path(path)
          our_entry = root?(next_path)

          return yield entry_key, entries[entry_key] if block_given? && our_entry

          # Pass to our entry
          args.send(next_arg_method, next_path)

          notdir = Errno::ENOTDIR unless our_entry
          entry_send(entries[entry_key], callback, *args, notsup: notsup, notdir: notdir, &block)
        end

        private

        def method_missing(method, *args, &block)
          return super unless FuseOperations.path_callbacks.include?(method)

          path_method(method, *args, block: block)
        end

        def respond_to_missing?(method, inc_private = false)
          return true if FuseOperations.path_callbacks.include?(method)

          super
        end

        # Split path into an entry key and remaining path
        # @param [:to_s] path
        # @return [nil] if path is root (or nil)
        # @return [Array<String, String] entry_key and '/' if path refers to an entry in this directory
        # @return [Array<String, String>] entry key and remaining path when path refers to an entry in a sub-directory
        def entry_path(path)
          return nil unless path

          path = path.to_s
          return nil if root?(path)

          # Fuse paths always start with a leading slash and never have a trailing slash
          sep_index = path.index('/', 1)

          return [path[1..], '/'] unless sep_index

          [path[1..sep_index - 1], path[sep_index..]]
        end

        def entry_fuse_respond_to?(entry_fs, method)
          entry_fs.respond_to?(:fuse_respond_to?) ? entry_fs.fuse_respond_to?(method) : entry_fs.respond_to?(method)
        end

        def dir_entry?(entry)
          entry_fuse_respond_to?(entry, :readdir)
        end

        def entry_send(entry, callback, *args, notsup: nil, notdir: nil, rescue_notsup: notsup.nil?, &blk)
          raise Errno::ENOENT unless entry
          raise notdir if notdir && !dir_entry?(entry)

          responds = entry_fuse_respond_to?(entry, callback)
          return unless responds || notsup
          raise notsup unless responds

          entry.public_send(callback, *args, &blk)
        rescue Errno::ENOTSUP, Errno::ENOSYS
          raise unless rescue_notsup

          nil
        end

        def check_rename_unlink(from_path)
          # Safety check that the unlink proc is passed through to the final directory
          # to explicitly support our rename proc.
          rename_support = false
          unlink("#{from_path}.__unlink_rename__") do |source|
            rename_support = source.nil?
          end
          raise Errno::ENOSYS, 'rename via unlink not supported' unless rename_support
        end

        # Cleanup the object being overwritten, including potentially raising SystemCallError
        # to prevent the rename going ahead
        def rename_cleanup_overwritten(replacing)
          return unless replacing

          entry_send(replacing, dir_entry?(replacing) ? :rmdir : :unlink, '/')
        end

        def root?(path)
          path ? super : true
        end
      end
    end
  end
end
