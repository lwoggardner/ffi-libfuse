# frozen_string_literal: true

require 'ffi'

module FFI
  # Syntax sugar for FFI::Struct
  module Accessors
    # DSL methods for defining struct member accessors
    module ClassMethods
      # Define both a reader and a writer for members
      # @param [Array<Symbol>] attrs the attribute names
      # @param [String] format
      #   A format string containing a single %s to convert attr symbol to struct member
      # @return [void]
      def ffi_attr_accessor(*attrs, format: '%s')
        ffi_attr_reader(*attrs, format: format)
        ffi_attr_writer(*attrs, format: format)
      end

      #
      # Define a struct attribute reader for members
      # @param [Array<Symbol>]
      #   attrs the attribute names used as the reader method name
      #
      #   a trailing '?' will be stripped from attribute names for primary reader method name, and cause an
      #   boolean alias method to be created.
      # @param [Proc|String] format
      #   A Proc, or format string containing a single %s, to convert each attribute name to the corresponding
      #   struct member name
      # @param [Boolean] simple
      #   Controls how writer methods are defined using block
      # @param [Proc] block
      #   An optional block to convert the struct field value into something more useful
      #
      #   If simple is true then block takes the struct field value, otherwise method is defined directly from the block
      #   and should use __method__ to get the attribute name. and self.class.ffi_attr_readers[__method__] to get the
      #   member name if these are not available from enclosed variables.
      # @return [void]
      def ffi_attr_reader(*attrs, format: '%s', simple: true, &block)
        attrs.each do |attr|
          bool, attr = attr[-1] == '?' ? [true, attr[..-2]] : [false, attr]

          member = (format.respond_to?(:call) ? format.call(attr) : format % attr).to_sym
          ffi_attr_readers[attr.to_sym] = member
          if !block
            define_method(attr) { self[member] }
          elsif simple
            define_method(attr) { block.call(self[member]) }
          else
            define_method(attr, &block)
          end

          alias_method "#{attr}?", attr if bool
        end
      end

      # Define a struct attribute writer
      # @param [Array<Symbol>] attrs the attribute names
      #   trailing '?' will be stripped from attribute names
      # @param [String|Proc] format
      #   A format string containing a single %s to convert attr symbol to struct member
      # @param [Boolean] simple
      #   Controls how writer methods are defined using block
      # @param [Proc] block
      #   An optional block to set the input value into the struct field.
      #
      #   If simple is true then the struct field is set to the result of calling block with the input value,
      #   otherwise the method is defined directly from the block. Use __method__[0..-1] to get the attribute name
      #   and self.class.ffi_attr_writers[__method__[0..-1]] to get the struct member name
      # @return [void]
      def ffi_attr_writer(*attrs, format: '%s', simple: true, &block)
        attrs.each do |attr|
          attr = attr[..-2] if attr[-1] == '?'

          member = (format % attr).to_sym
          ffi_attr_writers[attr.to_sym] = member
          if !block
            define_method("#{attr}=") { |val| self[member] = val }
          elsif simple
            define_method("#{attr}=") { |val| self[member] = block.call(val) }
          else
            define_method("#{attr}=", &block)
          end
        end
      end

      # All defined readers
      # @return [Hash<Symbol,Symbol>] map of attr names to member names for which readers exist
      def ffi_attr_readers
        @ffi_attr_readers ||= {}
      end

      # All defined writers
      # @return [Hash<Symbol,Symbol>] map of attr names to member names for which writers exist
      def ffi_attr_writers
        @ffi_attr_writers ||= {}
      end

      # Define individual flag accessors over a bitmask field
      def ffi_bitflag_accessor(attr, *flags)
        ffi_bitflag_reader(attr, *flags)
        ffi_bitflag_writer(attr, *flags)
      end

      # Define individual flag readers over a bitmask field
      # @param [Symbol] attr the bitmask member
      # @param [Array<Symbol>] flags list of flags
      # @return [void]
      def ffi_bitflag_reader(attr, *flags)
        flags.each do |f|
          ffi_attr_reader(:"#{f}?", simple: false) { self[attr].include?(f) }
        end
      end

      # Define individual flag writers over a bitmask field
      # @param [Symbol] attr the bitmask member
      # @param [Array<Symbol>] flags list of flags
      # @return [void]
      def ffi_bitflag_writer(attr, *flags)
        flags.each do |f|
          ffi_attr_writer(f, simple: false) do |v|
            v ? self[attr] += [f] : self[attr] -= [f]
            v
          end
        end
      end
    end

    def self.included(mod)
      mod.extend(ClassMethods)
    end

    # Fill the native struct from another object or list of properties
    # @param [Object] from
    #    for each attribute we call self.attr=(from.attr)
    # @param [Hash<Symbol,Object>] args
    #   for each entry <attr,val> we call self.attr=(val)
    # @return [self]
    def fill(from = nil, **args)
      if from.is_a?(Hash)
        args.merge!(from)
      else
        self.class.ffi_attr_writers.each_key { |v| send("#{v}=", from.send(v)) if from.respond_to?(v) }
      end
      args.each_pair { |k, v| send("#{k}=", v) }
      self
    end

    def inspect
      "#{self.class.name} {#{self.class.ffi_attr_readers.keys.map { |r| "#{r}: #{send(r)} " }.join(',')}"
    end

    # Convert struct to hash
    # @return [Hash<Symbol,Object>] map of reader attribute name to value
    def to_h
      self.class.ffi_attr_readers.keys.each_with_object({}) { |r, h| h[r] = send(r) }
    end
  end
end
