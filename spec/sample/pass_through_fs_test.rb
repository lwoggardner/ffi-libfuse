# frozen_string_literal: true

require_relative '../fuse_helper'

describe 'PassThroughFS' do
  include FFI::Libfuse::TestHelper

  let(:fs) { 'sample/pass_through_fs.rb' }
  let(:args) { %w[-obase_dir=fixture -d] }

  it 'lists a directory' # stat masked by 0o0222

  it 'reads a file' do
    act_stdout, act_stderr, status = run_filesystem(fs, *args) do |mnt|
      d = Pathname.new("#{mnt}/read")
      f = d + 'hello.txt'
      expect(d.exist?).must_equal(true, "#{d} will exist")
      expect(f.exist?).must_equal(true, "#{f} will exist")
      expect(f).wont_be(:writable?)
      expect(f.read).must_equal('Hello World!')
    end

    expect(status).must_equal(0,"Expected 0 status. Errors...\n#{act_stderr}")
    expect(act_stdout).must_match('')
  end

  it 'defaults to 0o0222 mask' # cannot write/mkdir

  describe 'with 777 stat mask' do
    it 'creates a file' #obeys umask of the calling process
    it 'creates a directory' # obeys umask of calling process
    it 'truncates a file'
    it 'deletes a file'
    it 'deletes a real directory'
    it 'does not delete a non-empty directory'
  end

end