# frozen_string_literal: true

require 'weakref'
require 'ffi'

module FFI
  # FFI::DataConverter to pass ruby objects as void*
  #
  # Objects are held in a global map of object id to WeakRef of the object.
  #
  # ie caller that puts a RubyObject into a library is responsible for keeping that object from the GC.
  #
  # Note this relies on the GVL to be threadsafe(ish)
  module RubyObject
    # Convert to cast ruby object *long to arbitrary integer type
    # @!visibility private
    class CastAsInt
      include DataConverter
      attr_reader :native_type

      def initialize(int_type)
        @native_type = FFI.find_type(int_type)
      end

      def to_native(obj, context)
        return 0 if obj.nil?

        RubyObject.to_native(obj, context).get(:long, 0)
      end

      def from_native(object_id, _context)
        return nil if object_id.zero?

        _ptr, obj = RubyObject.cache[object_id]
        obj = obj.__getobj__ if obj.is_a?(WeakRef)
        obj
      end
    end

    extend FFI::DataConverter
    native_type FFI::Type::POINTER

    # rubocop:disable Lint/HashCompareByIdentity
    class << self
      # Store a ruby object reference in an integer type
      # @param [FFI::Type] int_type
      def by_object_id(int_type = :long)
        CastAsInt.new(int_type)
      end

      # @!visibility private

      # convert pointer to ruby object
      def to_native(obj, _context)
        return FFI::Pointer::NULL if obj.nil?

        # return previous pointer if we've stored this object already
        # not threadsafe!
        ptr, _ref = cache[obj.object_id] ||= store(obj)
        # Keep the pointer address as a type safety check, so we don't read memory we didn't store
        cache[ptr.address.object_id] = true
        ptr
      end

      def from_native(ptr, _context)
        return nil if ptr.null?
        raise TypeError, "No RubyObject stored at #{ptr.address}" unless cache.key?(ptr.address.object_id)

        _ptr, obj = cache[ptr.get(:long, 0)]
        # unwrap as the object gets used
        obj = obj.__getobj__ if obj.is_a?(WeakRef)
        obj
      end

      def cache
        @cache ||= {}
      end

      def finalizer(*keys)
        proc { keys.each { |k| cache.delete(k) } }
      end

      def store(obj)
        ptr = FFI::MemoryPointer.new(:long)
        ptr.put(:long, 0, obj.object_id)

        unless obj.frozen?
          # Clean the cache when obj is finalised
          ObjectSpace.define_finalizer(obj, finalizer(obj.object_id, ptr.address.object_id))
          obj = WeakRef.new(obj)
        end

        [ptr, obj]
      end
    end
    # rubocop:enable Lint/HashCompareByIdentity
  end
end
