# FFI::Libfuse

Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)

## Writing a FUSE Filesystem

Create a class that implements the abstract methods of {FFI::Libfuse::Main} and {FFI::Libfuse::FuseOperations}

Call {FFI::Libfuse.fuse_main} to start the filesystem

```ruby
require 'ffi/libfuse'

class MyFS
  # include helpers to abstract away from the native C callbacks to more idiomatic Ruby
  include FFI::Libfuse::Adapter::Ruby
  
  # ... FUSE callbacks .... quacks like a FFI:Libfuse::FuseOperations
  def getattr(*args)
    #...  
  end
  
  def readdir(*args)
    #...
  end
  
end

FFI::Libfuse::fuse_main(operations: MyFS.new) if __FILE__ == $0
```

# Fuse2/Fuse3 compatibility

FFI::Libfuse will prefer Fuse3 over Fuse2 by default. See {FFI::Libfuse::LIBFUSE}

For writing filesystems with backwards/forwards compatibility between fuse version see
{FFI::Libfuse::Adapter::Fuse2Compat} and {FFI::Libfuse::Adapter::Fuse3Support}

## MACFuse

[macFUSE](https://osxfuse.github.io/) (previously OSXFuse) supports a superset of the Fuse2 api so FFI::Libfuse is
 intended to work in that environment.

# Multi-threading

Most Ruby filesystems are unlikely to benefit from multi-threaded operation so
{FFI::Libfuse.fuse_main} as shown above injects the '-s' (single-thread) option by default.

Pass the original options in directly if multi-threaded operation is desired for your filesystem

```ruby
FFI::Libfuse::fuse_main($0,*ARGV, operations: MyFS.new) if __FILE__ == $0
```

The {FFI::Libfuse::ThreadPool} can be configured with `-o max_threads=<n>,max_idle_threads=<n>` options

Callbacks that are about to block (and release the GVL for MRI) should call {FFI::Libfuse::ThreadPool.busy}.

A typical scenario would be a filesystem where some callbacks are blocking on network IO.

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

## Under the hood

FFI::Libfuse tries to provide raw access to the underlying libfuse but there some constraints imposed by Ruby.

The functions fuse_main(), fuse_daemonize() and fuse_loop<_mt>() are re-implemented in Ruby so we can provide

 * dynamic compatibility between Fuse2 and Fuse3
 * integrated support for multi-threading under MRI (see {FFI::Libfuse::ThreadPool})
 * signal handling in ruby filesystem (eg HUP to reload)

Sending `-o native' will used the native C functions but this exists to assist with testing that FFI::Libfuse has
similar behaviour to libfuse itself.

See {FFI::Libfuse::Main} and {FFI::Libfuse::FuseCommon}

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/lwoggardner/ffi-libfuse. 

### TODO
  * Include a MetaFS, PathMapperFS etc (possibly a separate library)
  * Build a filesystem that can make use of multi-threaded operations
  * Test with macFUSE

## License

The gem is available under the terms of the [MIT](https://opensource.org/licenses/MIT) License.

