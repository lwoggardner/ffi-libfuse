# FFI::Libfuse

Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)

## Requirements

  * Ruby 2.7
  * Linux: libfuse (Fuse2) or libfuse3 (Fuse3)
  * MacOS: macFuse (https://osxfuse.github.io/)

## Building a FUSE Filesystem

Install the gem

```bash
gem install ffi-libfuse
```

Create a filesystem class

* implement FUSE callbacks for filesystem operations satisfying {FFI::Libfuse::FuseOperations}
* recommend including {FFI::Libfuse::Adapter::Ruby} to add some ruby sugar and safety to the native FUSE Callbacks
* recommend including {FFI::Libfuse::Adapter::Fuse2Compat} for compatibility with Fuse2/macFuse
* implement {FFI::Libfuse::Main} configuration methods, eg to parse custom options with {FFI::Libfuse::FuseArgs#parse!}
  (as altered by any included adapters from {FFI::Libfuse::Adapter})
* Provide an entrypoint to start the filesystem using {FFI::Libfuse::Main.fuse_main}

{FFI::Libfuse::Filesystem} contains additional classes and modules to help build and compose filesystems 

<!-- SAMPLE BEGIN: sample/hello_fs.rb -->
*sample/hello_fs.rb*

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ffi/libfuse'

# Hello World!
class HelloFS
  include FFI::Libfuse::Adapter::Ruby
  include FFI::Libfuse::Adapter::Fuse2Compat

  # FUSE Configuration methods

  def fuse_options(args)
    args.parse!({ 'subject=' => :subject }) do |key:, value:, **|
      raise FFI::Libfuse::Error, 'subject option must be at least 2 characters' unless value.size >= 2

      @subject = value if key == :subject
      :handled
    end
  end

  def fuse_help
    '-o subject=<subject>   a target to say hello to'
  end

  def fuse_configure
    @subject ||= 'World!'
    @content = "Hello #{@subject}\n"
  end

  # FUSE callbacks

  def getattr(path, stat, *_args)
    case path
    when '/'
      stat.directory(mode: 0o550)
    when '/hello.txt'
      stat.file(mode: 0o440, size: @content.size)
    else
      raise Errno::ENOENT
    end
  end

  def readdir(_path, *_args)
    yield 'hello.txt'
  end

  def read(_path, *_args)
    @content
  end
end

# Start the file system
FFI::Libfuse.fuse_main(operations: HelloFS.new) if __FILE__ == $0

```
<!-- SAMPLE END: sample/hello_fs.rb -->

Mount the filesystem

```bash
hello_fs.rb -h # show help
hello_fs.rb /mnt/hello # run deamonized, mounted at /mnt/hello
```

Do file things

```bash
ls /mnt/hello
cat /mnt/hello/hello.txt
```

## Fuse2/Fuse3 compatibility

FFI::Libfuse will prefer Fuse3 over Fuse2 by default. See {FFI::Libfuse::LIBFUSE}

New filesystems should write for Fuse3 API and include {FFI::Libfuse::Adapter::Fuse2Compat} for backwards compatibility

Alternatively filesystems written against Fuse2 API can include {FFI::Libfuse::Adapter::Fuse3Support}

## MACFuse

[macFUSE](https://osxfuse.github.io/) (previously OSXFuse) supports a superset of the Fuse2 api

**TODO** Implement macFuse extensions


# Under the hood

{FFI::Libfuse} provides raw access to the underlying libfuse but there some constraints imposed by Ruby.

## Low-level functions re-implemented in Ruby

The C functions fuse_main(), fuse_daemonize() and fuse_loop<_mt>() are re-implemented to provide

* dynamic compatibility between Fuse2 and Fuse3
* support for multi-threading under MRI
* signal handling in ruby filesystem (eg HUP to reload)

The `-o native' option will use the native C functions but only exists to assist with testing that FFI::Libfuse has
similar behaviour to C libfuse.

See {FFI::Libfuse::Main} and {FFI::Libfuse::FuseCommon}

## Multi-threading

{FFI::Libfuse.fuse_main} forces the `-s` (single-thread) option to be set since most Ruby filesystems are
unlikely to benefit from the overhead caused by multi-threaded operation obtaining/releasing the GVL around each
callback.

{FFI::Libfuse::Main.fuse_main} does not pass any options by default and should be used in situations where
multi-threaded operations may be desirable.

```ruby
FFI::Libfuse::Main.fuse_main(operations: MyFS.new) if __FILE__ == $0
```

The multi-thread loop uses {FFI::Libfuse::ThreadPool} to control thread usage and can be configured with options
`-o max_threads=<n>,max_idle_threads=<n>`

Callbacks that are about to block (and release the GVL for MRI) should call {FFI::Libfuse::ThreadPool.busy} which will
spawn additional worker threads as required.

Note that uncaught exceptions in callbacks will kill the worker thread and if all worker threads are dead the
file system will stop and unmount. In particular if the first callback raises an exception

```ruby
def read(*args)
 # prep, validate args etc.. (MRI holding the GVL anyway)
 FFI::Libfuse::ThreadPool.busy
 # Now make some REST or other network call to read the data
end
```

**Note** Fuse itself has conditions under which filesystem callbacks will be serialized. In particular see
[this discussion](http://fuse.996288.n3.nabble.com/GetAttr-calls-being-serialised-td11741.html)
on the serialisation of `#getattr` and `#readdir` calls.

**TODO**  Build an example filesystem that makes use of multi-threading


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/lwoggardner/ffi-libfuse. 


## License

The gem is available under the terms of the [MIT](https://opensource.org/licenses/MIT) License.

