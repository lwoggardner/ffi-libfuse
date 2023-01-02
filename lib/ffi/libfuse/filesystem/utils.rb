# frozen_string_literal: true

require_relative '../fuse_context'

module FFI
  module Libfuse
    module Filesystem
      # RubySpace File Utilities
      #
      # This module provides utility methods for file operations in RubySpace which are useful for creating custom
      # entries prior to mounting, or otherwise manipulating the filesystem from within the Ruby process that is
      # running FUSE.
      #
      # **Note** You cannot generally call Ruby's {::File} and {::Dir} operations from within the same Ruby process
      #   as the mounted filesystem because MRI will not release the GVL to allow the Fuse callbacks to run.
      module Utils
        # Recursive mkdir
        # @param [:to_s] path
        # @param [Integer] mode permissions for any dirs that need to be created
        # @yieldparam [String] the path component being created
        # @yieldreturn [FuseOperations] optionally a filesystem to mount at path, if the path did not previously exist
        def mkdir_p(path, mode = (~FuseContext.get.umask & 0o0777), &mount_fs)
          return if root?(path) # nothing to make

          path.to_s.split('/')[1..].inject('') do |base_path, sub_dir|
            full_path = "#{base_path}/#{sub_dir}"
            err = Adapter::Safe.safe_callback(:mkdir) { mkdir(full_path, mode, &mount_fs) }
            unless [0, -Errno::EEXIST::Errno].include?(err)
              raise SystemCallError.new("Unexpected err #{err.abs} from mkdir #{full_path}", err.abs)
            end

            full_path
          end
          0
        end
        alias mkpath mkdir_p

        # @param [:to_s] path
        # @return [FFI::Stat]
        def stat(path)
          path = path.to_s
          stat_buf = FFI::Stat.new

          err = Adapter::Safe.safe_callback(:getattr) { getattr(path, stat_buf) }

          return nil if err == -Errno::ENOENT::Errno
          raise SystemCallError, "Unexpected error from #{fs}.getattr #{path}", err unless err.zero?

          stat_buf
        end

        # @param [:to_s] path
        # @return [Boolean] true if file or directory exists at path
        def exists?(path)
          stat(path) && true
        end

        # @param [:to_s] path
        # @return [Boolean] true if regular file exists at path
        def file?(path)
          stat(path)&.file? || false
        end

        # @param [:to_s] path
        # @return [Boolean] true if directory exists at path
        def directory?(path)
          stat(path)&.directory? || false
        end

        # @param [:to_s] path
        # @return [Boolean] File exists at path and has zero size
        def empty_file?(path)
          s = stat(path)
          (s&.file? && s.size.zero?) || false # rubocop:disable Style/ZeroLengthPredicate
        end

        # Check if a directory is empty
        # @param [String] path
        # @return [Boolean] true if an empty directory exists at path
        # @raise [Errno::ENOTDIR] if path does not point to a directory
        def empty_dir?(path)
          return false unless directory?(path)

          empty = true
          fake_filler = proc do |_buf, name, _stat = nil, _offset = 0, _fuse_flag = 0|
            next 0 if %w[. ..].include?(name)

            empty = false
            -1 # buf full don't send more entries!
          end
          readdir(path.to_s, nil, fake_filler, 0, nil, *(fuse3_compat? ? [] : [0]))
          empty
        end

        # @!visibility private
        def fuse3_compat?
          FUSE_MAJOR_VERSION >= 3
        end
      end
    end
  end
end
