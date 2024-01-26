# frozen_string_literal: true

require 'ffi'
require_relative 'accessors'

module FFI
  # Helper to wrap structs with ugly names and attribute clashes with FFI::Struct (eg size)
  #
  # @example
  #  class MyStruct
  #    include FFI::StructWrapper
  #    native_struct(MyNativeStruct)
  #
  #    #!@attribute [rw] field
  #    ffi_attr_accessor :field
  #  end
  #
  module StructWrapper
    # @!visibility private
    class ByReference < StructByReference
      def initialize(wrapper_class)
        super(wrapper_class.native_struct)
        @wrapper_class = wrapper_class
      end

      def to_native(value, ctx)
        return Pointer::NULL if value.nil?

        value = value.native if value.is_a?(StructWrapper)
        super(value, ctx)
      end

      def from_native(value, ctx)
        return nil if value.null?

        native = super(value, ctx)
        @wrapper_class.new(native)
      end
    end

    # Additional class methods for StructWrapper
    module ClassMethods
      # @!visibility private
      def from_native(value, _)
        new(value)
      end

      # @!visibility private
      def to_native(value, _)
        case value
        when native_type
          value
        when self
          value.native
        else
          new.fill(value).native
        end
      end

      # @!visibility private
      def native_struct(struct_class = nil)
        if struct_class
          native_type(struct_class.by_value)
          @struct_class = struct_class
        end
        @struct_class
      end

      # @return [Type] represents a pointer to the wrapped struct
      def by_ref
        @by_ref ||= ByReference.new(self)
      end

      # @return [Type] represents passing wrapped struct by value
      def by_value
        self
      end
    end

    class << self
      # @!visibility private
      def included(mod)
        mod.extend(DataConverter)
        mod.extend(ClassMethods)
        mod.include(Accessors)
      end
    end

    # @!parse extend ClassMethods
    # @!parse include Accessors
    # @!parse extend Accessors::ClassMethods

    # @return [FFI::Struct] the underlying native struct
    attr_reader :native

    # @!visibility private
    def initialize(native = self.class.native_struct.new)
      @native = native
    end

    # Get attribute
    def [](member_or_attr)
      _attr, member = ffi_attr_reader_member(member_or_attr, member_or_attr)
      @native[member]
    end

    # Set attribute
    def []=(member_or_attr, val)
      _attr, member = ffi_attr_writer_member(member_or_attr, member_or_attr)
      @native[member] = val
    end

    # Pass unimplemented methods on to {#native} underlying struct
    def method_missing(method, *args)
      @native.send(method, *args)
    end

    # @!visibility private
    def respond_to_missing?(method, private = false)
      @native.respond_to?(method, private)
    end
  end
end
