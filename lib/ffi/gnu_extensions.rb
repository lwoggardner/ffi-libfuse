# frozen_string_literal: true

require 'ffi'

module FFI
  # Support versioned functions until https://github.com/ffi/ffi/issues/889
  #
  # @example
  #   require 'ffi'
  #
  #   module MyLibrary
  #     extend FFI::Library
  #
  #     if FFI::Platform::IS_GNU
  #       require 'ffi/gnu_extensions'
  #
  #       extend(FFI::GNUExtensions)
  #       # default versions for all functions
  #       ffi_lib_versions(%w[VERSION_X.3 VERSION_X.2])
  #     end
  #
  #     attach_function :func_one, [:int], :int
  #     # override default with specific version
  #     attach_function :func_two, [], :int, versions ['VERSION_X.Y']
  #
  #  end
  module GNUExtensions
    if FFI::Platform::IS_GNU
      extend FFI::Library
      ffi_lib 'libdl'

      # @!method dlopen(library,type)
      #   @return [FFI::Pointer] library address, possibly NULL
      attach_function :dlopen, %i[string int], :pointer
      # @!method dlvsym(handle)
      #   @return [FFI::Pointer] function address, possibly NULL
      attach_function :dlvsym, %i[pointer string string], :pointer
    end

    # @!visibility private
    def self.extended(mod)
      mod.extend(DLV) unless mod.respond_to?(:ffi_lib_versions)
    end

    # Override FFI::Library attach functions with support for dlvsym
    module DLV
      # Set the default version(s) for "{attach_function}" (GNU only)
      # @param [Array<String>|String] versions the default list of versions to search
      # @return [Array<String>|String]
      def ffi_lib_versions(versions)
        @versions = versions
      end

      # @!visibility private
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
      def attach_function(name, func, args, returns = nil, options = nil)
        versions = options.delete(:versions) if options.is_a?(Hash)

        return super unless FFI::Platform::IS_GNU

        # Hackety hack duplicated from FFI#attach_function
        # rubocop:disable Style/ParallelAssignment, Style/TernaryParentheses, Layout/LineLength
        mname, a2, a3, a4, a5 = name, func, args, returns, options
        cname, arg_types, ret_type, opts = (a4 && (a2.is_a?(String) || a2.is_a?(Symbol))) ? [a2, a3, a4, a5] : [mname.to_s, a2, a3, a4]
        # rubocop:enable Style/ParallelAssignment, Style/TernaryParentheses, Layout/LineLength

        versions ||= @versions if defined?(@versions)
        versions ||= []

        return super if versions.empty?

        function = versions.each do |v|
          f = find_function_version(cname, v)
          break f if f
        end

        # oh well, try the non-version function
        return super unless function

        arg_types = arg_types.map { |e| find_type(e) }
        ret_type = find_type(ret_type)

        invoker =
          if arg_types.length.positive? && arg_types[arg_types.length - 1] == FFI::NativeType::VARARGS
            VariadicInvoker.new(function, arg_types, ret_type, opts)
          else
            Function.new(ret_type, arg_types, function, opts)
          end
        invoker.attach(self, mname.to_s)
        invoker
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength

      # use dlvsym to find a function address
      # @param [String|Symbol] cname the function name
      # @param [String] version the version name
      # @return [FFI::Pointer] the function address
      # @return [false] if the function/version combination does not exist in any library
      def find_function_version(cname, version)
        ffi_libraries.map(&:name).each do |l|
          handle = GNUExtensions.dlopen(l, 1)
          next if handle.null?

          addr = GNUExtensions.dlvsym(handle, cname.to_s, version)

          next if addr.null?

          return addr
        end

        false
      end
    end
  end
end
