# frozen_string_literal: true

require_relative '../fuse_helper'

describe "MemoryFS #{FFI::Libfuse::FUSE_VERSION}" do

  include FFI::Libfuse::TestHelper

  let(:fs) { 'sample/memory_fs.rb' }

  %w[--help -h].each do |help_arg|
    it "prints help with #{help_arg}" do
      stdout, stderr, status = run_filesystem(fs, help_arg)
      output = FFI::Libfuse::FUSE_MAJOR_VERSION >= 3 ? stdout : stderr
      expect(output).must_match(/FUSE options/)
      expect(status).must_equal(0)
    end
  end

  it 'prints version with -V' do
    stdout, stderr, status = run_filesystem(fs, '-V')
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
      act_stdout, act_stderr, status = run_filesystem(fs, *args, env: { 'MEMORY_FS_SKIP_DEFAULT_ARGS' => 'Y'}) do |mnt|
        d = Pathname.new("#{mnt}/testdir")
        m = Pathname.new("#{mnt}/moved")
        f = d + 'file.txt'

        expect(d.exist?).must_equal(false,"#{d} won't exist")

        d.mkdir

        expect(d.children.size).must_equal(0, "#{d} exists with no children")

        FileUtils.touch(f)

        expect(f.exist?).must_equal(true,"#{f} exist")
        expect(f.stat.zero?).must_equal(true,"#{f} has size zero")

        expect(d.children.size).must_equal(1, "#{d} contains 1 file")
        expect(d.children).must_include(f)

        expect(f.write("hello world\n")).must_equal(12,"#{f} write returns bytes written")

        expect(f.read).must_equal("hello world\n")
        expect(f.stat.nlink).must_equal(1)

        # Hardlinks
        h = d + 'hardlink.txt'
        FileUtils.link(f, h)
        expect(d.children.size).must_equal(2, "#{d} contains 2 files")
        expect(d.children).must_include(h)
        expect(h.read).must_equal("hello world\n")
        expect(h.stat.nlink).must_equal(2)

        # Symlinks
        l = d + 'link.txt'
        FileUtils.symlink('file.txt',l)
        expect(d.children.size).must_equal(3, "#{d} contains 3 files")
        expect(d.children).must_include(l)
        expect(l.read).must_equal("hello world\n")

        expect(proc { d.rmdir }).must_raise(Errno::ENOTEMPTY)

        notdir = f + 'x.notdir'
        expect( proc { notdir.write('not a dir') }).must_raise(Errno::ENOTDIR)

        FileUtils.mv(d,m)
        expect(d.exist?).must_equal(false, "#{d} wont exist after rename")
        expect(m.children.size).must_equal(3, "#{m} contains all 3 files moved from #{d}")
        FileUtils.mv(m,d)

        l.delete
        expect(l.exist?).must_equal(false,"#{l} wont exist after delete")

        h.delete
        expect(h.exist?).must_equal(false,"#{h} wont exist after delete")
        expect(f.exist?).must_equal(true,"#{f} must exist after #{h} is deleted")

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