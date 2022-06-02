# frozen_string_literal: true

require_relative '../fuse_helper'

describe 'NoFS' do

  include FFI::Libfuse::TestHelper

  let(:fs) { 'sample/no_fs.rb' }

  %w[--help -h].each do |help_arg|
    it "prints help with #{help_arg}" do
      stdout, stderr, status = run_filesystem(fs, help_arg)
      output = FFI::Libfuse::FUSE_MAJOR_VERSION >= 3 ? stdout : stderr
      expect(status).must_equal(0)
      expect(output).must_match(/NoFS options/)
    end
  end

  it 'prints version with -V' do
    stdout, stderr, status = run_filesystem(fs, '-V')
    output = FFI::Libfuse::FUSE_MAJOR_VERSION >= 3 ? stdout : stderr
    expect(status).must_equal(0)
    expect(output).must_match(/NoFS: Version/)
    expect(output).must_match(/Fuse3Compat=false/)
  end

  [
    { name: 'single threaded foreground', args: %w[-f -s], stderr: '' },
    { name: 'single threaded debug', args: %w[-s -d], stderr: [/:single_thread=>true/,/NoFS.*readdir/,/NoFS: DEBUG enabled/] },
    { name: 'multi thread foreground', args: %w[-f], stderr: '' },
    { name: 'single thread daemonized', args: %w[-s], stderr: '' },
    { name: 'multi thread daemonized', args: %w[-d], stderr: '' },
    { name: 'native loop single threaded foreground', args: %w[-f -s -o native], stderr: '' },
    { name: 'native loop single threaded debug', args: %w[-s -d -o native], stderr: [/:single_thread=>true/,/NoFS.*readdir/,/NoFS: DEBUG enabled/] },
    { name: 'native loop multi thread foreground', args: %w[-f -o native], stderr: '' },
    { name: 'native loop single thread daemonized', args: %w[-s -o native], stderr: '' },
    { name: 'native loop multi thread daemonized', args: %w[-o native], stderr: '', skip_msg: 'TODO: why does this hang?' },
  ].kw_each do |name:, args:, stderr:, skip_msg: false|
    it name do
      skip skip_msg if skip_msg

      act_stdout, act_stderr, status = run_filesystem(fs, *args) do |mnt|
        expect(Dir.exist?(mnt)).must_equal(true, "#{mnt} will exist")
        expect(Dir.exist?("#{mnt}/other")).must_equal(false,"#{mnt}/other won't exist")
        entries = Dir.entries("#{mnt}")
        expect(entries.size).must_equal(2)
      end
      expect(status).must_equal(0,'status zero')
      expect(act_stdout).must_match('')
      stderr = [stderr] unless stderr.is_a?(Array)
      stderr.each do |se|
        expect(act_stderr).must_match(se,'stderr matches')
      end
    end
  end

end