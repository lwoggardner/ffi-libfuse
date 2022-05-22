# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/ffi/stat'

describe 'FFI::Stat' do
  it 'sets file mode'

  it 'sets directory mode' do

  end

  it 'sets timestamps from ruby Time values' do
    increments = { atime: 11, mtime: 22, ctime: 33 }
    times = increments.transform_values { |inc| Time.at(Time.now.sec, 123456700 + inc, :nsec) }
    stat = FFI::Stat.file(mode: 0o777, size: 0, **times)
    times.each_pair do |sym, exp_time|
      expect(stat[sym]).must_be_kind_of(FFI::Stat::TimeSpec)
      expect(stat[sym].tv_sec).must_equal(exp_time.tv_sec)
      expect(stat[sym].tv_nsec).must_equal(exp_time.tv_nsec)
    end
  end

  it 'maps the stat struct same as File.stat' do
    stat = FFI::Stat.stat(__FILE__)
    rstat = File.stat(__FILE__)
    common_members = FFI::Stat.ffi_attr_readers.keys.select { |m| rstat.respond_to?(m) }
    expect(common_members).wont_be_empty
    common_members.each do |m|
      expect(stat.public_send(m)).must_equal(rstat.public_send(m),"stat[:#{m}]")
    end
  end
end