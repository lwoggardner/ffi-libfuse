# frozen_string_literal: true

require 'ffi'
require_relative '../../ffi/accessors'
require_relative 'version'

module FFI
  # Ruby FFI Binding for [libfuse](https://github.com/libfuse/libfuse)
  module Libfuse
    extend FFI::Library

    # The fuse library to load from 'LIBFUSE' environment variable if set, otherwise prefer Fuse3 over Fuse2
    LIBFUSE = ENV['LIBFUSE'] || %w[libfuse3.so.3 libfuse.so.2]
    ffi_lib(LIBFUSE)

    # @!scope class
    # @!method fuse_version()
    # @return [Integer] the fuse version
    # See {FUSE_VERSION} which captures this result in a constant

    attach_function :fuse_version, [], :int

    # prior to 3.10 this is Major * 10 + Minor, after 3.10 and later is Major * 100 + Minor
    # @return [Integer] the version of libfuse
    FUSE_VERSION = fuse_version

    fv_split = FUSE_VERSION >= 300 ? 100 : 10 # since 3.10

    # @return [Integer] the FUSE major version
    FUSE_MAJOR_VERSION = FUSE_VERSION / fv_split

    # @return [Integer] the FUSE minor version
    FUSE_MINOR_VERSION = FUSE_VERSION % fv_split

    if FUSE_MAJOR_VERSION == 2 && FFI::Platform::IS_GNU
      require_relative '../gnu_extensions'

      extend(GNUExtensions)
      # libfuse2 has busted symbols
      ffi_lib_versions(%w[FUSE_2.9.1 FUSE_2.9 FUSE_2.8 FUSE_2.7 FUSE_2.6 FUSE_2.5 FUSE_2.4 FUSE_2.3 FUSE_2.2])
    end
  end
end
