# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/ffi/stat_vfs'
require 'sys-filesystem'

describe 'FFI::StatVfs' do

  it 'maps the statvfs struct same as Sys::Filesystem' do
    stat = FFI::StatVfs.from(__FILE__)
    rstat = Sys::Filesystem.stat(__FILE__)
    common_members = FFI::StatVfs.ffi_attr_readers.select { |m| rstat.respond_to?(m) }
    expect(common_members).wont_be_empty
    common_members.each do |m|
      expect(stat.public_send(m)).must_equal(rstat.public_send(m),"statvfs[:#{m}]")
    end
  end
end