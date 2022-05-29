# frozen_string_literal: true

module FFI
  # Converter generator for different sizes ints as boolean
  class BooleanInt
    include DataConverter
    attr_reader :native_type

    def initialize(int_type)
      @native_type = FFI.find_type(int_type)
    end

    # Falsey = 0, Truthy = 1
    def to_native(obj, _context)
      obj ? 1 : 0
    end

    # Not Zero
    def from_native(object_id, _context)
      !object_id.zero?
    end

    %i[char short int long int8 int16 int32 int64].each do |t|
      FFI.typedef(BooleanInt.new(t), "bool_#{t}".to_sym)
    end
  end
end
