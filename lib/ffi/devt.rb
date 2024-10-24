# frozen_string_literal: true

require 'ffi'
module FFI
  # Calculate major/minor device numbers for use with mknod etc..
  # @see makedev(3)
  module Device
    extend FFI::Library
    ffi_lib FFI::Library::LIBC

    prefix = FFI::Platform::IS_GNU ? 'gnu_dev_' : ''

    # @!method makedev(major,minor)
    #  @param [Integer] major
    #  @param [Integer] minor
    #  @return [Integer] combined major/minor to a single value to pass to mknod etc
    attach_function :makedev, :"#{prefix}makedev", %i[int int], :int

    # @!method major(dev)
    #  @param [Integer] dev
    #  @return [Integer] the major component of dev
    attach_function :major, :"#{prefix}major", [:int], :int

    # @!method minor(dev)
    #  @param [Integer] dev
    #  @return [Integer] the minor component of dev
    attach_function :minor, :"#{prefix}minor", [:int], :int
  rescue FFI::NotFoundError

    class << self
      # rubocop:disable Naming/MethodParameterName
      case RUBY_PLATFORM
      when 'x86_64-darwin'
        # From https://github.com/golang/go/issues/8106 these functions are not defined on Darwin.

        # define	major(x)	((int32_t)(((u_int32_t)(x) >> 24) & 0xff))
        def major(dev)
          (dev >> 24) & 0xff
        end

        # define	minor(x)	((int32_t)((x) & 0xffffff))
        def minor(dev)
          (dev & 0xffffff)
        end

        # define	makedev(x,y) ((dev_t)(((x) << 24) | (y)))
        def makedev(major, minor)
          (major << 24) | minor
        end

      when 'x86_64-linux-musl' # eg alpine linux
        # #define major(x) \
        # 	((unsigned)( (((x)>>31>>1) & 0xfffff000) | (((x)>>8) & 0x00000fff) ))
        def major(x)
          ((x >> 31 >> 1) & 0xfffff000) | ((x >> 8) & 0x00000fff)
        end

        # #define minor(x) \
        # 	((unsigned)( (((x)>>12) & 0xffffff00) | ((x) & 0x000000ff) ))
        #
        def minor(x)
          ((x >> 12) & 0xffffff00) | (x & 0x000000ff)
        end

        # #define makedev(x,y) ( \
        #         (((x)&0xfffff000ULL) << 32) | \
        # 	(((x)&0x00000fffULL) << 8) | \
        #         (((y)&0xffffff00ULL) << 12) | \
        # 	(((y)&0x000000ffULL)) )
        def makedev(x, y)
          ((x & 0xfffff000) << 32) | ((x & 0x00000fff) << 8) | ((y & 0xffffff00) << 12) | (y & 0x000000ff)
        end
      else
        raise
      end
      # rubocop:enable Naming/MethodParameterName
    end
  end
end
