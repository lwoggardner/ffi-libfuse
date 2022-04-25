# frozen_string_literal: true

require_relative 'accounting'
require_relative 'virtual_node'
require_relative 'virtual_file'
require_relative 'pass_through_file'
require_relative 'pass_through_dir'
require_relative 'mapped_dir'

module FFI
  module Libfuse
    module Filesystem
      # A Filesystem of Filesystems
      #
      # Implements a recursive Hash based directory of sub filesystems.
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
          @mounted = false
          super(accounting: accounting)
        end

        # @return [Boolean] true if this dir been mounted
        def mounted?
          @mounted
        end

        # @!endgroup

        # @!group FUSE Callbacks

        # For the root path provides this directory's stat information, otherwise passes on to the next filesystem
        def getattr(path, stat_buf = nil, _ffi = nil)
          return path_method(__method__, path, stat_buf) unless root?(path)

          stat_buf&.directory(**virtual_stat.merge({ nlink: entries.size + 2 }))
        end

        # Safely passes on file open to next filesystem
        #
        # @raise [Errno::EISDIR] for the root path since we are a directory rather than a file
        # @return [Object] the result of {#path_method} for the sub filesystem
        # @return [nil] for sub-filesystems that do not implement this callback or raise ENOTSUP or ENOSYS
        def open(path, *args)
          raise Errno::EISDIR if root?(path)

          path_method(__method__, path, *args, notsup: nil)
        rescue Errno::ENOTSUP, Errno::ENOSYS
          nil
        end

        # Safely handle file release
        #
        # Passes on to next filesystem, rescuing ENOTSUP or ENOSYS
        # @raise [Errno::EISDIR] for the root path since we are a directory rather than a file
        def release(path, *args)
          raise Errno::EISDIR if root?(path)

          path_method(__method__, path, *args, notsup: nil)
        rescue Errno::ENOTSUP, Errno::ENOSYS
          # do nothing
        end

        # Safely handles directory open to next filesystem
        #
        # @return [self] for the root path, which helps shortcut future operations. See {#readdir}
        # @return [Object] the result of {#path_method} for all other paths
        # @return [nil] for sub-filesystems that do not implement this callback or raise ENOTSUP or ENOSYS
        def opendir(path, ffi)
          return path_method(__method__, path, ffi, notsup: nil) unless root?(path)

          ffi.fh = self
        rescue Errno::ENOTSUP, Errno::ENOSYS
          nil
        end

        # Safely handles directory release
        #
        # Does nothing for the root path
        #
        # Otherwise safely passes on to next filesystem, rescuing ENOTSUP or ENOSYS
        def releasedir(path, *args)
          path_method(__method__, path, *args, notsup: nil) unless root?(path)
        rescue Errno::ENOTSUP, Errno::ENOSYS
          # do nothing
        end

        # If path is root fills the directory from the keys in {#entries}
        #
        # If ffi.fh is itself a filesystem then try to call its :readdir directly
        #
        # Otherwise passes to the next filesystem in path
        def readdir(path, buf, filler, offset, ffi, *flag)
          return %w[. ..].concat(entries.keys).each(&Adapter::Ruby::ReaddirFiller.new(buf, filler)) if root?(path)

          return ffi.fh.readdir('/', buf, filler, offset, ffi, *flag) if entry_fuse_respond_to?(ffi.fh, :readdir)

          path_method(:readdir, path, buf, filler, offset, ffi, *flag) unless root?(path)
        end

        # For root path validates we are empty and removes a node link from {#accounting}
        # For our entries, passes on the call to the entry (with path='/') and then removes the entry. If available
        #  :destroy will be called on the deleted entry
        # @raise [Errno::ENOTEMPTY] if path is root and our entries list is not empty
        # @raise [Errno::ENOENT] if the entry does not exist
        # @raise [Errno::ENOTDIR] if the entry does not respond to :readdir (ie: is not a directory)
        def rmdir(path)
          if root?(path)
            raise Errno::ENOTEMPTY unless entries.empty?

            accounting.adjust(0, -1)
            return
          end

          entry_key = entry_key(path)
          return path_method(__method__, path) unless entry_key

          dir = entries[entry_key]
          raise Errno::ENOENT unless dir
          raise Errno::ENOTDIR unless entry_fuse_respond_to?(dir, :readdir)

          entry_send(dir, :rmdir, '/')

          dir = entries.delete(entry_key)
          entry_send(dir, :destroy, init_results.delete(entry_key)) if dir && mounted?
        end

        # For our entries, validates the entry exists and is not a directory, then passes on unlink (with path = '/')
        #  and finally deletes.
        # @raise [Errno:EISDIR] if the request entry responds to :readdir
        def unlink(path)
          entry_key = entry_key(path)
          return path_method(__method__, path) unless entry_key

          entry = entries[entry_key]
          raise Errno::ENOENT unless entry
          raise Errno::EISDIR if entry_fuse_respond_to?(entry, :readdir)

          entry_send(entry, :unlink, '/')
          entries.delete(entry_key) && true
        end

        # For our entries, creates a new file
        # @raise [Errno::EISDIR] if the entry exists and responds_to?(:readdir)
        # @raise [Errno::EEXIST] if the entry exists
        # @yield []
        # @yieldreturn [Object] something that quacks with the FUSE Callbacks of a regular file
        #
        #   :create or :mknod + :open will be attempted with path = '/' on this file
        # @return [Object] the result of the supplied block, or if not given a new {VirtualFile}
        def create(path, mode = FuseContext.get.mask(0o644), ffi = nil, &file)
          file_name = entry_key(path)

          # fuselib will fallback to mknod on ENOSYS on a case by case basis
          return path_method(__method__, path, mode, ffi, notsup: Errno::ENOSYS, &file) unless file_name

          existing = entries[file_name]
          raise Errno::EISDIR if entry_fuse_respond_to?(existing, :readdir)
          raise Errno::EEXIST if existing

          # TODO: Strictly should understand setgid and sticky bits of this dir's mode when creating new files
          new_file = file ? file.call(name) : VirtualFile.new(accounting: accounting)
          if entry_fuse_respond_to?(new_file, :create)
            new_file.public_send(:create, '/', mode, ffi)
          else
            # TODO: generate a sensible device number
            entry_send(new_file, :mknod, '/', mode, 0)
            entry_send(new_file, :open, '/', ffi)
          end
          entries[file_name] = new_file
        end

        # Creates a new directory entry in this directory
        # @param [String] path
        # @param [Integer] mode
        # @yield []
        # @yieldreturn [Object] something that quacks with the FUSE Callbacks representing a directory
        # @return [Object] the result of the block if given, otherwise the newly created sub {VirtualDir}
        # @raise [Errno::EEXIST] if the entry already exists at path
        def mkdir(path, mode = FuseContext.get.mask(0o777), &dir)
          return init_node(mode) if root?(path)

          dir_name = entry_key(path)
          return path_method(__method__, path, mode, &dir) unless dir_name

          existing = entries[dir_name]
          raise Errno::EEXIST if existing

          new_dir = dir ? dir.call : VirtualDir.new(accounting: accounting)
          init_dir(dir_name, new_dir) if mounted?
          entry_send(new_dir, :mkdir, '/', mode)
          entries[dir_name] = new_dir
        end

        # Calls init on all current entries, keeping track of their init objects for use with {destroy}
        def init(*args)
          @mounted = true
          @init_args = args
          @init_results = {}
          entries.each_pair { |name, d| init_dir(name, d) }
          nil
        end

        # Calls destroy on all current entries
        def destroy(*_args)
          entries.each_pair { |name, d| entry_send(d, :destroy, init_results[name]) }
        end

        # @!endgroup

        # Looks up the first path component in {#entries} and then sends the remainder of the path to the callback
        # on that entry
        # @param [Symbol] callback a FUSE Callback
        # @param [String] path
        # @param [Array] args callback arguments
        # @param [Proc] invoke optional block to keep passing down. See {#mkdir}, {#create}
        # @param [Class<SystemCallError>] notsup
        # @raise [Errno:ENOENT] if the next entry does not exist
        # @raise [SystemCallError] error from notsup if the next entry does not respond to ths callback
        def path_method(callback, path, *args, notsup: Errno::ENOTSUP, &invoke)
          path = path.to_s
          # Fuse paths always start with a leading slash and never have a trailing slash
          sep_index = path.index('/', 1)
          entry_key = sep_index ? path[1..sep_index - 1] : path[1..]
          entry = entries[entry_key]

          raise Errno::ENOENT unless entry

          responds = entry_fuse_respond_to?(entry, callback)
          return unless responds || notsup
          raise notsup unless responds

          if mounted? && (init_obj = init_results[entry_key])
            FuseContext.get.overrides.merge!(private_data: init_obj)
          end

          # Pass remaining path components to the next filesystem
          next_path = sep_index ? path[sep_index..] : '/'
          entry.public_send(callback, next_path, *args, &invoke)
        end

        private

        attr_reader :init_args, :init_results

        def method_missing(method, *args, &invoke)
          return super unless FuseOperations.path_callbacks.include?(method)

          raise Errno::ENOTSUP if root?(args.first)

          path_method(method, *args, &invoke)
        end

        def respond_to_missing?(method, inc_private = false)
          return true if FuseOperations.path_callbacks.include?(method)

          super
        end

        def entry_key(path)
          path[1..] unless path.index('/', 1)
        end

        def init_dir(name, dir)
          init_result = entry_fuse_respond_to?(dir, :init) ? dir.init(*init_args) : nil
          init_results[name] = init_result if init_result
        end

        def entry_fuse_respond_to?(entry_fs, method)
          return entry_fs.fuse_respond_to?(method) if entry_fs.respond_to?(:fuse_respond_to?)

          entry_fs.respond_to?(method)
        end

        def entry_send(entry, callback, *args)
          return unless entry_fuse_respond_to?(entry, callback)

          entry.public_send(callback, *args)
        end
      end
    end
  end
end
