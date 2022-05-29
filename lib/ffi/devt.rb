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
    attach_function :makedev, "#{prefix}makedev".to_sym, %i[int int], :int

    # @!method major(dev)
    #  @param [Integer] dev
    #  @return [Integer] the major component of dev
    attach_function :major, "#{prefix}major".to_sym, [:int], :int

    # @!method minor(dev)
    #  @param [Integer] dev
    #  @return [Integer] the minor component of dev
    attach_function :minor, "#{prefix}minor".to_sym, [:int], :int
  rescue FFI::NotFoundError
    case Platform::NAME
    when 'x86_64-darwin'
      # From https://github.com/golang/go/issues/8106 these functions are not defined on Darwin.
      class << self
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
      end
    else
      raise
    end
  end
end
