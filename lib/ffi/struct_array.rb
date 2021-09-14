# frozen_string_literal: true

require 'ffi'

module FFI
  # Module to extend struct classes that are present in callbacks as fixed length arrays
  module StructArray
    # Generate a one way converter for a fixed size array of struct
    # @return [DataConverter]
    def array(size)
      ArrayConverter.new(self, size)
    end

    # @!visibility private
    # Helper to handle callbacks containing fixed length array of struct
    class ArrayConverter
      include DataConverter

      def initialize(type, size)
        @type = type
        @size = size
      end

      def native_type(_type = nil)
        FFI::Type::POINTER
      end

      def from_native(ptr, _ctx)
        return [] if ptr.null?

        Array.new(@size) { |i| @type.new(ptr + (i * @type.size)) }
      end

      def to_native(ary, _ctx)
        raise NotImplementedError, "#{self.class.name} Cannot convert #{ary} to pointer"
      end
    end
  end
end
