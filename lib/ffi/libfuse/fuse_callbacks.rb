# frozen_string_literal: true

require_relative 'callbacks'

module FFI
  module Libfuse
    # Methods to register callbacks and wrappers
    module FuseCallbacks
      include Callbacks

      # @!group Configuration

      # @!method fuse_wrappers(*wrappers)
      #  @abstract
      #  Wrappers change the behaviour/signature of the abstract fuse callback methods
      #
      #  @param [Array] wrappers
      #    An initial list of wrappers
      #  @return [Array] the final list of wrappers.
      #    Implementations should append or prepend to the input wrappers as appropriate
      #
      #    See {register} for what constitutes a valid wrapper

      # @!method fuse_respond_to?(fuse_method)
      #   @abstract
      #   @param [Symbol] fuse_method a fuse callback method
      #   @return [Boolean] true if the fuse method should be registered

      # @!endgroup
      private

      def initialize_callbacks(delegate:, wrappers: [])
        wrappers = delegate.fuse_wrappers(*wrappers) if delegate.respond_to?(:fuse_wrappers)
        super(callback_members, delegate: delegate, wrappers: wrappers)
      end

      def respond_to_callback?(method, delegate)
        return delegate.fuse_respond_to?(method) if delegate.respond_to?(:fuse_respond_to?)

        super
      end

      def callback_members
        members - [:flags]
      end
    end
  end
end
