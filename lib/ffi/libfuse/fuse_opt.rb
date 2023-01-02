# frozen_string_literal: true

require_relative 'fuse_version'

module FFI
  module Libfuse
    # @!visibility private
    #
    # Option description
    #
    # @see Args#parse!
    class FuseOpt < FFI::Struct
      layout template: :pointer, #  Matching template and optional parameter formatting
             offset: :ulong, #  Unused in FFI::Libfuse (harder to prepare structs and offsets than just just call block)
             value: :int # Value to set the variable to, or to be passed as 'key' to the processing function.

      # @!method initialize(address=nil)

      def fill(template, value)
        str_ptr = FFI::MemoryPointer.from_string(template)
        self[:template] = str_ptr
        self[:offset] = (2**(FFI::Type::INT.size * 8)) - 1 # -(1U)  in a LONG!!
        self[:value] = value.to_i
        self
      end

      def null
        # NULL opt to terminate the list
        self[:template] = FFI::Pointer::NULL
        self[:offset] = 0
        self[:value] = 0
      end

      # @!visibility private
      # DataConverter for Hash<String,Integer> to Opt[] required by fuse_parse_opt
      module OptList
        extend FFI::DataConverter
        native_type FFI::Type::POINTER

        class << self
          def to_native(opts, _ctx)
            raise ArgumentError, "Opts #{opts} must be a Hash" unless opts.respond_to?(:each_pair)

            native = FFI::MemoryPointer.new(:char, FuseOpt.size * (opts.size + 1), false)
            opts.map.with_index { |(template, key), i| FuseOpt.new(native + (i * FuseOpt.size)).fill(template, key) }
            FuseOpt.new(native + (opts.size * FuseOpt.size)).null

            native
          end
        end
      end
    end
  end
end
