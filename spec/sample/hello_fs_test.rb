# frozen_string_literal: true

require_relative '../fuse_helper'

describe 'HelloFS' do
  include LibfuseHelper

  let(:fs) { 'hello_fs.rb' }
  let(:args) { %w[] }

  it 'says hello

' do
    act_stdout, act_stderr, status = run_sample(fs, *args) do |mnt|
      d = Pathname.new("#{mnt}")
      f = d + 'hello.txt'

      expect(d.exist?).must_equal(true, "#{d} will exist")
      expect(d.entries).must_include(f.basename, "#{f} will be listed in #{d}")
      expect(f.exist?).must_equal(true, "#{f} will exist")
      expect(f.read).must_equal("Hello World!\n")
    end
    expect(act_stdout).must_match('')
    expect(status).must_equal(0,"Expected 0 status. Errors...\n#{act_stderr}")
  end

end