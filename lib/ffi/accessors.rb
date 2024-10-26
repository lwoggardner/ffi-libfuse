# frozen_string_literal: true

require 'ffi'

module FFI
  # Syntax sugar for **FFI::Struct**
  #
  # Modules that include {Accessors} are automatically extended by {ClassMethods} which provides for defining reader and
  # writer methods over struct field members.
  #
  # Although designed around needs of **FFI::Struct**, eg the ability to map natural ruby names to struct field names,
  # this module can be used over anything that stores attributes in a Hash like structure.
  # It provides equivalent method definitions to *Module#attr_(reader|writer|accessor)* except using the index methods
  # *:[<member>]*, and *:[<member>]=* instead of managing instance variables.
  #
  # Additionally it supports boolean attributes with '?' aliases for reader methods, and keeps track of attribute
  # definitions to support {#fill},{#to_h} etc.
  #
  # Standard instance variable based attributes defined through *#attr_(reader|writer|accessor)*
  # also get these features.
  # @example
  #    class MyStruct < FFI::Struct
  #      include FFI::Accessors
  #
  #      layout(
  #        a: :int,
  #        b: :int,
  #        s_one: :string,
  #        enabled: :bool,
  #        t: TimeSpec,
  #        p: :pointer
  #      )
  #
  #      ## Attribute reader, writer, accessor over struct fields
  #
  #      # @!attribute [r] a
  #      #   @return [Integer]
  #      ffi_attr_reader :a
  #
  #      # @!attribute [w] b
  #      #   @return [Integer]
  #      ffi_attr_writer :b
  #
  #      # @!attribute [rw] one
  #      #   @return [String]
  #      ffi_attr_accessor({ one: :s_one }) # => [:one, :one=] reads/writes field :s_one
  #
  #      ## Boolean attributes!
  #
  #      # @!attribute [rw] enabled?
  #      #   @return [Boolean]
  #      ffi_attr_accessor(:enabled?) # => [:enabled, :enabled?, :enabled=]
  #
  #      ## Simple block converters
  #
  #      # @!attribute [rw] time
  #      #    @return [Time]
  #      ffi_attr_reader(time: :t) do |timespec|
  #        Time.at(timespec.tv_sec, timespec.tv_nsec) # convert TimeSpec struct to ruby Time
  #      end
  #
  #      ## Complex attribute methods
  #
  #      # writer for :time needs additional attributes
  #      ffi_attr_writer_method(time: :t) do |sec, nsec=0|
  #        sec, nsec = [sec.sec, sec.nsec] if sec.is_a?(Time)
  #        self[:t][tv_sec] = sec
  #        self[:t][tv_nsec] = nsec
  #        time
  #      end
  #
  #      # safe readers handling a NULL struct
  #      safe_attrs = %i[a b].to_h { |m| [:"#{m}_safe", m] } # =>{ a_safe: :a, b_safe: b }
  #      ffi_attr_reader_method(**safe_attrs) do |default: nil|
  #         next default if null?
  #
  #         _attr, member = ffi_reader(__method__)
  #         self[member]
  #      end
  #
  #      ## Standard accessors over for instance variables, still supports boolean, to_h, fill
  #
  #      # @!attribute [rw] debug?
  #      #   @return [Boolean]
  #      attr_accessor :debug?
  #
  #      ## Private accessors
  #
  #      private
  #
  #      ffi_attr_accessor(pointer: :p)
  #    end
  #
  #    # Fill from another MyStruct (or anything that quacks like a MyStruct with readers matching our writers)
  #    s = MyStruct.new.fill(other)
  #
  #    # Fill from hash...
  #    s = MyStruct.new.fill(b:2, one: 'str', time: Time.now, enabled: true, debug: false) # => s
  #    s.values #=> (FFI::Struct method) [ 0, 2, 'str', true, <TimeSpec>, FFI::Pointer::NULL ]
  #
  #    # Struct instance to hash
  #    s.to_h # => { a: 0, one: 'str', time: <Time>, enabled: true, debug: false }
  #
  #    # Attribute methods
  #    s.a                             # => 0
  #    s.b = 3                         # => 3
  #    s.enabled                       # => true
  #    s.enabled?                      # => true
  #    s.time= 0,50                    # => Time<50 nanoseconds after epoch>
  #    s.time= Time.now                # => Time<now>
  #    s.debug?                        # => false
  #    s.pointer                       # => NoMethodError, private method 'pointer' called for MyStruct
  #    s.send(:pointer=, some_pointer) # => some_pointer
  #    s.send(:pointer)                # => some_pointer
  #
  #    null_s = MyStruct.new(FFI::Pointer::NULL)
  #    null_s.b_safe(default: 10)      # => 10
  #
  # @see ClassMethods
  module Accessors
    # Class methods for defining struct member accessors
    module ClassMethods
      # Keep track of default visibility since define_method doesn't do this itself
      # @visibility private
      %i[public private protected].each do |visibility|
        define_method(visibility) do |*args|
          @default_visibility = visibility if args.empty?
          super(*args)
        end
      end

      # @visibility private
      def default_visibility
        @default_visibility ||= :public
      end

      # Standard instance variable based reader with support for boolean and integration with *to_h*, *inspect* etc..
      #
      # The *member* registered for each attribute will be its instance variable symbol (ie with a leading '@')
      # @return [Array<Symbol]
      def attr_reader(*args)
        super(*args.map { |a| a[-1] == '?' ? a[0..-2] : a })
        ffi_attr_reader_method(**args.to_h { |a| [a, :"@#{a[-1] == '?' ? a[0..-2] : a}"] })
      end

      # Standard instance variable based writer with support for booleans and integration with *fill* etc..
      #
      # The *member* registered for each attribute will be its instance variable symbol (ie with a leading '@')
      def attr_writer(*args)
        super(*args.map { |a| a[-1] == '?' ? a[0..-2] : a })
        ffi_attr_writer_method(**args.to_h { |a| [a, :"@#{a[-1] == '?' ? a[0..-2] : a}"] })
      end

      # Override instance variable based accessor to build our enhanced readers and writers
      def attr_accessor(*args)
        attr_reader(*args) + attr_writer(*args)
      end

      # @!group Accessor Definition

      # Define both reader and writer
      # @return [Array<Symbol] list of methods defined
      def ffi_attr_accessor(*attrs, **attrs_map)
        ffi_attr_reader(*attrs, **attrs_map) + ffi_attr_writer(*attrs, **attrs_map)
      end

      # Define reader methods for the given attributes
      #
      # @param [Array<Symbol>] attrs
      #   List of struct field members to treat as attributes
      #
      #   a trailing '?' in an attribute name indicates a boolean reader.
      #   eg. :debug? will define the reader method :debug and an alias method :debug? => :debug,
      #
      #   String values are converted to Symbol
      #
      # @param [Hash<Symbol,Symbol>] attrs_map
      #   Map of attribute name to struct field name - where field names don't fit natural ruby methods etc...
      #
      #   A Hash value in *attrs* is also treated as an *attrs_map*. String keys/values are transformed to Symbol.
      #
      # @param [Proc] block
      #   An optional block taking a single argument (the struct field value) to convert into something more useful.
      #
      #   This block is evaluated within the method using :instance_exec
      # @return [Array<Symbol>] list of methods defined
      def ffi_attr_reader(*attrs, **attrs_map, &block)
        ffi_attr_reader_method(*attrs, **attrs_map) do
          _attr, member = ffi_attr_reader_member(__method__)
          val = self[member]
          block ? instance_exec(val, &block) : val
        end
      end

      # Define reader methods directly from a block
      #
      # @param [Array<Symbol>] attrs see {ffi_attr_reader}
      # @param [Hash<Symbol,Symbol>] attrs_map
      # @param [Proc] block
      #    must allow zero arity, but can have additional optional arguments or keyword arguments.
      #
      #    the block is evaluated using :instance_exec
      #
      #    within block the attribute name is always the method name (`__method__`) and the associated struct field
      #    member name is from any attribute maps supplied; ie *attrs_map* or Hash value in *attrs*.
      #    They can be retrieved using {ffi_attr_reader_member}
      #
      #    `attr, member = ffi_attr_reader_member(__method__)`
      #
      #    if not supplied a reader will still be registered for each attribute and a boolean alias created if required
      # @return [Array<Symbol>] list of methods defined
      # @example Related struct members
      #   # uid/gid are only meaningful if corresponding set_ field is true
      #   layout(set_uid: :bool, uid: :uint, set_gid: :bool, gid: :uint)
      #
      #   # @!attribute [r] uid
      #   #   @return [Integer] the user id
      #   #   @return [nil] if uid has not been explicitly set
      #
      #   # @!attribute [r] gid
      #   #   @return [Integer] the group id
      #   #   @return [nil] if gid has not been explicitly set
      #
      #   ffi_attr_reader_method(:uid, :gid) do
      #     attr, member = ffi_attr_reader_member(__method__)
      #     setter = :"set_#{attr}"
      #     self[setter] ? self[:attr] : nil
      #   end # => [:uid :gid]
      def ffi_attr_reader_method(*attrs, **attrs_map, &block)
        attr_methods = map_attributes(attrs, attrs_map).flat_map do |attr, member, bool|
          ffi_attr_readers_map[attr] = member
          define_method(attr, &block) if block
          next attr unless bool

          bool_alias = :"#{attr}?"
          alias_method(bool_alias, attr)
          [attr, bool_alias]
        end
        send(default_visibility, *attr_methods)
        attr_methods
      end

      # Define struct attribute writers for the given attributes
      # @param [Array<Symbol>] attrs see {ffi_attr_reader}
      # @param [Hash<Symbol,Symbol>] attrs_map
      # @param [Proc<Object>] block
      #   An optional block taking a single argument to convert input value into a value to be placed in the underlying
      #   struct field
      #
      #   This block is evaluated within the method using :instance_exec
      # @return [Array<Symbol>] list of methods defined
      def ffi_attr_writer(*attrs, **attrs_map, &block)
        ffi_attr_writer_method(*attrs, **attrs_map) do |val|
          _attr, member = ffi_attr_writer_member(__method__)
          self[member] = block ? instance_exec(val, &block) : val
        end
      end

      # Define writer methods directly from a block
      # @param [Array<Symbol>] attrs see {ffi_attr_reader}
      # @param [Hash<Symbol,Symbol>] attrs_map
      # @param [Proc] block
      #    must allow arity = 1, but can have additional optional arguments or keyword arguments.
      #
      #    the block is evaluated using :instance_exec
      #
      #    within block the attribute name is always the method name stripped of its trailing '='
      #    (`:"#{__method__[0..-2]}"`) and the associated struct field member name is from any attribute maps
      #    supplied. ie *attrs_map* or Hash value in *attrs*. They can be retrieved using {ffi_attr_writer_member}
      #
      #    `attr, member = ffi_attr_writer_member(__method__)`
      #
      #    if not supplied a writer method is still registered for each attribute name
      # @return [Array<Symbol>] list of methods defined
      def ffi_attr_writer_method(*attrs, **attrs_map, &block)
        writer_methods = map_attributes(attrs, attrs_map) do |attr, member, _bool|
          ffi_attr_writers_map[attr] = member
          block ? define_method("#{attr}=", &block) : attr
        end
        send(default_visibility, *writer_methods)
        writer_methods
      end

      # Define individual flag accessors over a bitmask field
      # @return [Array<Symbol>] list of methods defined
      def ffi_bitflag_accessor(member, *flags)
        ffi_bitflag_reader(member, *flags)
        ffi_bitflag_writer(member, *flags)
      end

      # Define individual flag readers over a bitmask field
      # @param [Symbol] member the bitmask member
      # @param [Array<Symbol>] flags list of flags to define methods for. Each flag also gets a :flag? boolean alias
      # @return [Array<Symbol>] list of methods defined
      def ffi_bitflag_reader(member, *flags)
        bool_attrs = flags.to_h { |f| [:"#{f}?", member] }
        ffi_attr_reader_method(**bool_attrs) do
          flag_attr, member = ffi_attr_reader_member(__method__)
          self[member].include?(flag_attr)
        end
      end

      # Define individual flag writers over a bitmask field
      # @param [Symbol] member the bitmask member
      # @param [Array<Symbol>] flags list of flag attributes
      # @return [Array<Symbol>] list of methods defined
      def ffi_bitflag_writer(member, *flags)
        writers = flags.to_h { |f| [f, member] }
        ffi_attr_writer_method(**writers) do |v|
          flag_attr, member = ffi_attr_writer_member(__method__)
          v ? self[member] += [flag_attr] : self[member] -= flag
          v
        end
      end

      # @!endgroup
      # @!group Accessor Information

      # @return [Array<Symbol>]
      #  list of public attr accessor reader methods
      def ffi_public_attr_readers
        ffi_attr_readers & public_instance_methods
      end

      # @return [Array<Symbol>]
      #  list of accessor reader methods defined. (excludes boolean aliases)
      def ffi_attr_readers
        ffi_attr_readers_map.keys
      end

      # @return [Array<Symbol>]
      #  list of accessor writer methods (ie ending in '=')
      def ffi_attr_writers
        ffi_attr_writers_map.keys.map { |a| :"#{a}=" }
      end

      # @return [Array<Symbol>]
      #  list of public accessor writer methods (ie ending in '=')
      def ffi_public_attr_writers
        ffi_attr_writers & public_instance_methods
      end

      # @!endgroup

      # @!visibility private
      def ffi_attr_readers_map
        @ffi_attr_readers_map ||= {}
      end

      # @!visibility private
      def ffi_attr_writers_map
        @ffi_attr_writers_map ||= {}
      end

      private

      def map_attributes(attrs, attrs_map)
        return enum_for(__method__, attrs, attrs_map) unless block_given?

        attrs << attrs_map unless attrs_map.empty?

        attrs.flat_map do |attr_entry|
          case attr_entry
          when Symbol, String
            bool, attr = bool_attr(attr_entry)

            yield attr, attr, bool
          when Hash
            attr_entry.flat_map do |attr, member|
              bool, attr = bool_attr(attr)
              yield attr, member.to_sym, bool
            end
          else
            raise ArgumentError
          end
        end
      end

      def bool_attr(attr)
        attr[-1] == '?' ? [true, attr[..-2].to_sym] : [false, attr.to_sym]
      end
    end

    # @!parse extend ClassMethods
    # @!visibility private
    def self.included(mod)
      mod.extend(ClassMethods)
    end

    # Fill struct from another object or list of properties
    # @param [Object] from
    #    if from is a Hash then its is merged with args, otherwise look for corresponding readers on from, for our
    #    public writer attributes
    # @param [Hash<Symbol,Object>] args
    #   for each entry <attr,val> we call self.attr=(val)
    # @raise [ArgumentError] if args contains properties that do not have public writers
    # @return [self]
    def fill(from = nil, **args)
      ffi_attr_fill(from, writers: self.class.ffi_public_attr_writers, **args)
    end

    # Inspect attributes
    # @param [Array<Symbol>] readers list of attribute names to include in inspect, defaults to all readers
    # @return [String]
    def inspect(readers: self.class.ffi_public_attr_readers)
      "#{self.class.name} {#{readers.map { |r| "#{r}: #{send(r)} " }.join(',')}"
    end

    # Convert struct to hash
    # @param [Array<Symbol>] readers list of attribute names to include in hash, defaults to all public readers.
    # @return [Hash<Symbol,Object>] map of attribute name to value
    def to_h(readers: self.class.ffi_public_attr_readers)
      readers.to_h { |r| [r, send(r)] }
    end

    private

    # @!visibility public
    # *(private)* Fill struct from another object or list of properties
    # @param [Object] from
    # @param [Hash<Symbol>] args
    # @param [Array<Symbol>] writers list of allowed writer methods
    # @raise [ArgumentError] if args contains properties not included in writers list
    # @note This *private* method allows an including classes' instance method to
    #   fill attributes through any writer method (vs #{fill} which only sets attributes with public writers)
    def ffi_attr_fill(from, writers: self.class.ffi_attr_writers, **args)
      if from.is_a?(Hash)
        args.merge!(from)
      else
        writers.each do |w|
          r = w[0..-2] # strip trailing =
          send(w, from.public_send(r)) if from.respond_to?(r)
        end
      end
      args.transform_keys! { |k| :"#{k}=" }

      args.each_pair { |k, v| send(k, v) }
      self
    end

    def ffi_attr(method)
      %w[? =].include?(method[-1]) ? :"#{method[0..-2]}" : method
    end

    # @!group Private Accessor helpers

    # @!visibility public
    # *(private)* Takes `__method__` and returns the corresponding attr and struct member names
    # @param [Symbol] attr_method typically  `__method__` (or `__callee__`)
    # @param [Symbol] default default if method is not a reader method
    # @return [Array<Symbol,Symbol>] attr,member
    # @raise [KeyError] if method has not been defined as a reader and no default is supplied
    def ffi_attr_reader_member(attr_method, *default)
      attr = ffi_attr(attr_method)
      [attr, self.class.ffi_attr_readers_map.fetch(attr, *default)]
    end

    # @!visibility public
    # *(private)* Takes `__method__` and returns the corresponding attr and struct member names
    # @param [Symbol] attr_method typically `__method__` (or `__callee__`)
    # @param [Symbol|nil] default default if method is not a writer method
    # @return [Array<Symbol,Symbol>] attr,member
    # @raise [KeyError] if method has not been defined as a writer and no default is supplied
    def ffi_attr_writer_member(attr_method, *default)
      attr = ffi_attr(attr_method)
      [attr, self.class.ffi_attr_writers_map.fetch(attr, *default)]
    end

    # @!endgroup
  end
end
