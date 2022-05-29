# frozen_string_literal: true

require 'ffi'

module FFI
  # DataConverter for reading/writing encoded strings
  class Encoding
    include DataConverter

    attr_reader :encoding

    # Create a dataconverter for the specified encoding
    # @example
    #   module MyFFIModule
    #     extend FFI::Library
    #     typedef FFI::Encoding.for('utf8'), :utf8_string
    #   end
    def self.for(encoding)
      new(encoding)
    end

    def from_native(value, _ctx)
      value.force_encoding(encoding)
    end

    def to_native(value, _ctx)
      value.encode(encoding)
    end

    def native_type(_type = nil)
      FFI::Type::STRING
    end

    def initialize(encoding)
      @encoding = encoding
    end
  end
end
