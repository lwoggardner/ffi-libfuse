# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/ffi/stat'

describe 'FFI::Stat::TimeSpec' do

  it 'supports UTIME_NOW' do
    now_spec = FFI::Stat::TimeSpec.now
    expect(now_spec.tv_nsec).must_equal(FFI::Stat::TimeSpec::UTIME_NOW)
    expect(now_spec).must_be :now?
    now_time = Time.at(946684800, 123456789, :nsec)
    expect(now_spec.time(now_time)).must_equal(now_time)
    expect(now_spec.nanos(now_time)).must_equal(946684800 * 10 ** 9 + 123456789)
  end

  it 'supports UTIME_OMIT' do
    omit_spec = FFI::Stat::TimeSpec.omit
    expect(omit_spec.time).must_be_nil
    expect(omit_spec.nanos).must_be_nil
  end
end
