# frozen_string_literal: true

require_relative 'utils'
require_relative 'virtual_dir'
require_relative 'accounting'
require 'pathname'

module FFI
  module Libfuse
    module Filesystem
      # A configurable main Filesystem that delegates FUSE Callbacks to another filesystem
      #
      # This class registers support for all available fuse callbacks, subject to the options below.
      #
      # Delegate filesystems like {VirtualDir} may raise ENOTSUP to indicate a callback is not handled at runtime
      #   although the behaviour of C libfuse varies in this regard.
      #
      # It is writable to the user that mounted it may create and edit files within it
      #
      # Filesystem options
      # ===
      #
      # Passed by -o options to {Libfuse.main}
      #
      #   * :max_space used for #{FuseOperations#statfs}. See {#accounting}
      #   * :max_nodes used for #{FuseOperations#statfs}. See {#accounting}
      #   * :no_buf do not register :read_buf, :write_buf
      #
      #       when set all filesystems must implement :read/:write
      #
      #       when not set all filesystems must implement :read_buf, :write_buf which enables C libfuse to handle
      #       file descriptor based io, eg. {MappedFiles}, but means Ruby FFI is doing memory allocations for string
      #       based io, eg. {VirtualFile}.
      #
      #       Note that {VirtualFile} and {MappedFiles} both prepend {Adapter::Ruby::Prepend} which implements
      #       the logic to fallback from :read/:write_buf to plain :read/:write as necessary to support this option.
      #
      # @example
      #   class MyFS < FFI::Libfuse::Filesystem::VirtualFS
      #     def fuse_configure
      #       build({ 'hello' => { 'world.txt' => 'Hello World'}})
      #       mkdir("/hello")
      #       create("/hello/world.txt").write("Hello World!\n")
      #       create("/hello/everybody").write("Hello Everyone!\n")
      #       symlink("/hello/link","everybody")`
      #     end
      #   end
      #
      #   exit(FFI::Libfuse.fuse_main(operations: MyFS.new))
      #
      class VirtualFS
        include Utils
        include Adapter::Context
        include Adapter::Safe
        include Adapter::Debug
        include Adapter::Fuse2Compat

        # @return [Object] the root filesystem that quacks like a {FuseOperations}
        attr_reader :root

        # @return [Hash{Symbol => String,Boolean}] custom options captured as defined by {fuse_options}
        attr_reader :options

        # @return [Accounting|:max_space=,:max_nodes=] an accumulator of filesystem statistics used to consume the
        #  max_space and max_nodes options
        def accounting
          @accounting ||= Accounting.new
        end

        # @param [FuseOperations] root the root filesystem
        # Subclasses can override the no-arg method and call super to pass in a different root.
        def fuse_configure(root = VirtualDir.new(accounting: accounting).mkdir('/'))
          @root = root
        end

        # @overload build(files)
        #  Adds files directly to the filesystem
        #  @param [Hash<String,:each_pair, :readdir,:getattr .:to_str] files map of paths to content generated
        #  according to the content implementing one of the methods below
        #
        #    * :each_pair is treated as a subdir of files
        #    * :readdir (eg {PassThroughDir}) is treated as a directory- sent via mkdir
        #    * :getattr (eg {PassThroughFile}) is treated as a file - sent via create
        #    * :to_str (eg {::String} ) is created a default file, with the string sent via write
        def build(files, base_path = Pathname.new('/'))
          files.each_pair do |path, content|
            path = (base_path + path).cleanpath
            @root.mkdir_p(path.dirname) unless path.dirname == base_path

            rt = %i[each_pair readdir getattr to_str].detect { |m| content.respond_to?(m) }
            raise "Unsupported initial content for #{self.class.name}: #{content.class.name}- #{content}" unless rt

            send("build_#{rt}", content, path)
          end
        end

        # @!group Fuse Configuration

        # TODO: Raise bug on libfuse (or fuse kernel module - ouch!) create to also fallback to mknod on ENOTSUP

        # Respond to all FUSE Callbacks except deprecated, noting that ..
        #
        #   * :read_buf, :write_buf can be excluded by the 'no_buf' mount option
        #   * :access already has a libfuse mount option (default_permissions)
        #   * :create falls back to :mknod on ENOSYS (as raised by {VirtualDir})
        #   * :copy_file_range can raise ENOTSUP to trigger glibc to fallback to inefficient copy
        def fuse_respond_to?(method)
          case method
          when :read_buf, :write_buf
            !no_buf
          else
            true
          end
        end

        # Default fuse options
        # Subclasses can override this method and call super with the additional options:
        # @param [Hash] opts additional options to parse into the {#options} attribute
        # @yield(key, value, **args)
        #   Called for each matching key in opts
        # @see FuseArgs#parse!
        def fuse_options(args, opts = {}, &block)
          @options = {}
          opts = opts.merge({ 'no_buf' => :no_buf }).merge(Accounting::OPTIONS)
          args.parse!(opts) do |key:, value:, **kwargs|
            case key
            when *Accounting::OPTIONS.values.uniq
              next accounting.fuse_opt_proc(key: key, value: value)
            when :no_buf
              @no_buf = true
            else
              next block.call(key, value, **kwargs) if block

              options[key] = value
            end
            :handled
          end
        end

        # Subclasses can override this method to add descriptions for additional options
        def fuse_help
          <<~END_HELP
            #{Accounting::HELP}
            #{self.class.name} options:
                -o no_buf              always use read, write instead of read_buf, write_buf
          END_HELP
        end

        # Subclasses can override to produce a nice version string for -V
        def fuse_version
          self.class.name
        end

        # @!visibility private
        def init_fuse_config(fuse_config, _fuse_version)
          fuse_config.use_ino = use_ino
        end

        # Configure whether entries in this filesystem provide useful inode values in #gettattr and #readdir
        #
        # Defaults to true since default Dir, File, Link all use {VirtualNode} which uses
        # Ruby object id as the inode value.
        #
        # Subclasses should override to false if some sub-filesystems will not provide inode values.
        # @return [Boolean]
        def use_ino
          true
        end
        # @!endgroup

        private

        def build_each_pair(content, path)
          build(content, path)
        end

        def build_readdir(content, path)
          @root.mkdir(path.to_s) { |_| content }
        end

        def build_getattr(content, path)
          @root.create(path.to_s) { |_| content }
        end

        def build_to_str(content, path)
          vf = @root.create(path.to_s)
          vf.write(content.to_str)
        end

        # Passes FUSE Callbacks on to the {#root} filesystem
        def method_missing(method, *args, &block)
          return @root.public_send(method, *args, &block) if @root.respond_to?(method)

          # This is not always reliable but better than raising NoMethodError
          return -Errno::ENOTSUP::Errno if FuseOperations.fuse_callbacks.include?(method)

          super
        end

        def respond_to_missing?(method, private = false)
          FuseOperations.fuse_callbacks.include?(method) || @root.respond_to?(method, private) || super
        end

        attr_reader :no_buf

        # This class does not implement any fuse methods, ensure they are passed to method missing.
        # eg Kernel.open
        FFI::Libfuse::FuseOperations.fuse_callbacks.each do |c|
          undef_method(c)
        rescue StandardError
          nil
        end
      end
    end
  end
end
