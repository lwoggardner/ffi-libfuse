# frozen_string_literal: true

require_relative '../fuse_helper'

describe "MemoryFS #{FFI::Libfuse::FUSE_VERSION}" do

  include LibfuseHelper

  let(:fs) { 'memory_fs.rb' }

  %w[--help -h].each do |help_arg|
    it "prints help with #{help_arg}" do
      stdout, stderr, status = run_sample(fs, help_arg)
      output = FFI::Libfuse::FUSE_MAJOR_VERSION >= 3 ? stdout : stderr
      expect(output).must_match(/FUSE options/)
      expect(status).must_equal(0)
    end
  end

  it 'prints version with -V' do
    stdout, stderr, status = run_sample(fs, '-V')
    output = FFI::Libfuse::FUSE_MAJOR_VERSION >= 3 ? stdout : stderr
    expect(output).must_match(/MemoryFS/)
    expect(status).must_equal(0)
  end

  [
    { name: 'single threaded foreground', args: %w[-f -s] },
    { name: 'multi thread foreground', args: %w[-f] },
    { name: 'single thread daemonized', args: %w[-s] },
    { name: 'multi thread daemonized', args: [],},
    { name: 'native loop single threaded foreground', args: %w[-f -s -o native]},
    { name: 'native loop multi thread foreground', args: %w[-f -o native]},
    { name: 'native loop single thread daemonized', args: %w[-s -o native]},
    { name: 'native loop multi thread deamonized', args: %w[-o native], skip_msg: 'TODO: Why does this hang?'},
    { name: 'no_buf', args: %w[-o no_buf]},
  ].kw_each do |name:, args:, skip_msg: false|
    it name do
      skip skip_msg if skip_msg
      act_stdout, act_stderr, status = run_sample(fs, *args, env: { 'MEMORY_FS_SKIP_DEFAULT_ARGS' => 'Y'}) do |mnt|
        d = Pathname.new("#{mnt}/testdir")
        f = d + 'file.txt'
        expect(d.exist?).must_equal(false,"#{d} won't exist")

        d.mkdir

        expect(d.children.size).must_equal(0, "#{d} exists with no children")

        FileUtils.touch(f)

        expect(f.exist?).must_equal(true,"#{f} exist")
        expect(f.stat.zero?).must_equal(true,"#{f} has size zero")

        expect(d.children.size).must_equal(1, "#{d} contains 1 child file")
        expect(d.children).must_include(f)


        expect(f.write("hello world\n")).must_equal(12,"#{f} write returns bytes written")

        expect(f.read).must_equal("hello world\n")

        expect(proc { d.rmdir }).must_raise(Errno::ENOTEMPTY)

        f.delete

        expect(f.exist?).must_equal(false,"#{f} wont exist after delete")

        d.delete

        expect(d.exist?).must_equal(false,"#{d} won't exist after rmdir")
      end
      expect(status).must_equal(0,'status zero')
      expect(act_stdout).must_match('')
      warn act_stderr
    end
  end

end