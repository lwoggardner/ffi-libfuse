# frozen_string_literal: true

module FFI
  module Libfuse
    # Helpers for reading/writing to io like objects
    module IO
      class << self
        # Helper to convert a ruby object to size bytes required by {FuseOperations#read}
        # @param [#pread, #seek & #read, #to_s] io the source to read from, either...
        #
        #   * an {::IO} like object via :pread(size, offset) or :seek(offset) then :read(size)
        #   * or the String from :to_s
        #
        # @param [Integer] size
        # @param [Integer, nil] offset
        #   if nil the io is assumed to be already positioned
        # @return [String] the extracted data
        def read(io, size, offset = nil)
          return io.pread(size, offset) if offset && io.respond_to?(:pread)

          if (offset ? %i[seek read] : %i[read]).all? { |m| io.respond_to?(m) }
            io.seek(offset) if offset
            return io.read(size)
          end

          io.to_s[offset || 0, size] || ''
        end

        # Helper to write date to {::IO} or {::String} like objects for use with #{FuseOperations#write}
        # @param [#pwrite, #seek & #write, #[]=] io an object that accepts String data via...
        #
        #   * ```ruby io.pwrite(data, offset)```
        #   * ```ruby io.seek(offset) ; io.write(data)```
        #   * ```ruby io[offset, data.size] = data```
        # @param [String] data
        # @param [nil, Integer] offset
        #   if not nil start start writing at this position in io
        # @return [Integer] number of bytes written
        # @raise [Errno::EBADF] if io does not support the requisite methods
        def write(io, data, offset = nil)
          if offset && io.respond_to?(:pwrite)
            io.pwrite(data, offset)
          elsif (offset ? %i[seek write] : %i[write]).all? { |m| io.respond_to?(m) }
            io.seek(offset) if offset
            io.write(data)
          elsif io.respond_to?(:[]=) # eg String
            io[offset || 0, data.size] = data
            data.size
          else
            raise "cannot :pwrite or :write to #{io}", Errno::EBADF
          end
        end
      end
    end
  end
end
