# frozen_string_literal: true

module FFI
  module Libfuse
    # This namespace contains helper Modules that alter the signature or behaviour of the native {FuseOperations}
    # callbacks
    #
    # There are two types of Adapters
    #
    # 1) Wrap many fuse methods in a proc that manipulates the arguments in a consistent way
    #
    #    These will implement {FuseOperations#fuse_wrappers} to add the proc which can then...
    #
    #    * populate thread local information - eg. ({Context})
    #    * wrap common arguments - eg. ({Pathname})
    #    * handle return values/exceptions - eg. ({Safe})
    #    * or just wrap the underlying block - eg. ({Debug})
    #
    # 2) Override specific callback methods to change their signatures
    #
    #    These will prepend an internal module that implements the callback methods,  manipulating the
    #    argument list and passing on to super and then manipulating the result.
    #
    #    The prepend module must include Adapter so that the module methods themselves do not register as
    #    callbacks unless there is an implementation by the including class.
    #
    #    eg. {Ruby}, {Fuse2Compat}, {Fuse3Support}
    module Adapter
      # Does something other than an adapter (ie the underlying filesystem itself) implement fuse_method.
      #
      # Can be called by custom implementations of fuse_respond_to? to confirm that the implementing module
      # is not a type 2 Adapter (which itself will call super)
      def fuse_super_respond_to?(fuse_method)
        return false unless respond_to?(fuse_method)

        m = method(fuse_method)
        m = m.super_method while m && Adapter.include?(m.owner)

        m && true
      end

      # @!visibility private

      # Use {#fuse_super_respond_to?} if no super implementation
      def fuse_respond_to?(fuse_method)
        return super if defined?(super)

        fuse_super_respond_to?(fuse_method)
      end

      class << self
        # @!visibility private

        # is mod an Adapter
        def include?(mod)
          adapters.include?(mod)
        end

        def included(mod)
          adapters << mod
        end

        def adapters
          # Avoid Kernel#open being considered a fuse callback
          @adapters ||= [Kernel, Object, BasicObject]
        end
      end
    end
  end
end

require_relative 'adapter/context'
require_relative 'adapter/debug'
require_relative 'adapter/ruby'
require_relative 'adapter/interrupt'
require_relative 'adapter/pathname'
require_relative 'adapter/fuse3_support'
require_relative 'adapter/fuse2_compat'
