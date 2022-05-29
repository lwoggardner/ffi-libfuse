# frozen_string_literal: true

require 'ffi'
require 'ffi/struct_array'

module FFI
  class Stat
    # Timespec from stat.h
    class TimeSpec < FFI::Struct
      extend StructArray

      # Special nsec value representing the current time - see utimensat(2)
      UTIME_NOW = (1 << 30) - 1
      # Special nsec value representing a request to omit setting this time - see utimensat(2)
      UTIME_OMIT = (1 << 30) - 2

      class << self
        # A fixed TimeSpec representing the current time
        def now
          @now ||= new.set_time(0, UTIME_NOW)
        end

        # A fixed TimeSpec representing a request to omit setting this time
        def omit
          @omit ||= new.set_time(0, UTIME_OMIT)
        end

        # @param [Array<TimeSpec>] times
        # @param [Integer] size
        # @return [Array<TimeSpec>] list of times filled out to size with TimeSpec.now if times was empty,
        #   otherwise with TimeSpec.omit
        def fill_times(times, size = times.size)
          return times unless times.size < size
          return Array.new(size, now) if times.empty?

          times.dup.fill(omit, times.size..size - times.size) if times.size < size
        end
      end

      layout(
        tv_sec: :time_t,
        tv_nsec: :long
      )

      # @!attribute [r] tv_sec
      # @return [Integer] number of seconds since epoch
      def tv_sec
        self[:tv_sec]
      end
      alias sec tv_sec

      # @!attribute [r] tv_nsec
      # @return [Integer] additional number of nanoseconds
      def tv_nsec
        self[:tv_nsec]
      end
      alias nsec tv_nsec

      # @overload set_time(time)
      #  @param [Time] time
      #  @return [self]
      # @overload set_time(sec,nsec=0)
      #  @param [Integer] sec number of (nano/micro)seconds from epoch, precision depending on nsec
      #  @param [Symbol|Integer] nsec
      #   - :nsec to treat sec as number of nanoseconds since epoch
      #   - :usec to treat sec as number of microseconds since epoch
      #   - Integer to treat sec as number of seconds since epoch, and nsec as additional nanoseconds
      #  @return [self]
      def set_time(sec, nsec = 0)
        return set_time(sec.to_i, sec.nsec) if sec.is_a?(Time)

        case nsec
        when :nsec
          return set_time(sec / (10**9), sec % (10**9))
        when :usec
          return set_time(sec / (10**6), sec % (10**6))
        when Integer
          self[:tv_sec] = sec
          self[:tv_nsec] = nsec
        else
          raise ArgumentError, "Invalid nsec=#{nsec}"
        end

        self
      end
      alias :time= set_time

      # @return [Boolean] true if this value represents the special value {UTIME_NOW}
      def now?
        tv_nsec == UTIME_NOW
      end

      # @return [Boolean] true if this value represents the special value {UTIME_OMIT}
      def omit?
        tv_nsec == UTIME_OMIT
      end

      # Convert to Time
      # @param [Time|nil] now
      #   optional value to use if {now?} is true.  If not set then Time.now will be used
      # @return [nil] if {omit?} is true
      # @return [Time] this value as ruby Time in UTC
      def time(now = nil)
        return nil if omit?
        return (now || Time.now).utc if now?

        Time.at(sec, nsec, :nsec, in: 0).utc
      end

      def to_s(now = nil)
        time(now).to_s
      end

      # Convert to Integer
      # @param [Time|nil] now
      #   optional value to use if {now?} is true.  If not set then Time.now will be used
      # @return [nil] if {omit?} is true
      # @return [Integer] number of nanoseconds since epoch
      def nanos(now = nil)
        return nil if omit?

        t = now? ? (now || Time.now) : self
        (t.tv_sec * (10**9)) + t.tv_nsec
      end

      # Convert to Float
      # @param [Time|nil] now
      #   optional value to use if {now?} is true.  If not set then Time.now will be used
      # @return [nil] if {omit?} is true
      # @return [Float] seconds and fractional seconds since epoch
      def to_f(now = nil)
        return nil if omit?

        t = now? ? (now || Time.now) : self
        t.tv_sec.to_f + (t.tv_nsec.to_f / (10**9))
      end

      # @!visibility private
      def inspect
        ns =
          case nsec
          when UTIME_NOW
            'NOW'
          when UTIME_OMIT
            'OMIT'
          else
            nsec
          end
        "#{self.class.name}:#{sec}.#{ns}"
      end
    end
  end
end
