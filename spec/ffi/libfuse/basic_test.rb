# frozen_string_literal: true


require_relative '../../fuse_helper'
require_relative 'mock_fs'
require 'sys/filesystem'

# These test that
# * FFI::Libfuse structs are correctly mapped
# * We understand how Fuse maps file operations to filesystem callbacks
# * Other bugs and errors
# It is not intended to test that Fuse itself works
describe "MockFS #{FFI::Libfuse::FUSE_VERSION}" do

  include FFI::Libfuse::TestHelper

  let(:mock_fs) { MockFS.new }
  let(:mock) { mock_fs.mock }
  let(:file_stat) { FFI::Stat.file(mode: 0o777, size: 0) }
  let(:dir_stat) { FFI::Stat.directory(mode: 0o755) }
  let(:stat_as_file) { ->(s) { s.file(mode: 0o777, size: 0) } }
  let(:stat_as_dir) { ->(s) { s.directory(mode: 0o755) } }
  after { mock.verify }

  describe 'directories' do

    it 'should make directories' do

      mock_fs.expect_not_exists('/testDirectory')
      mock_fs.expect(:getattr, 0) do |path, stat, _ffi = nil|
        expect(path).must_equal('/testDirectory')
        stat.directory(mode: 0o755)
      end

      mock_fs.expect(:mkdir, 0, ['/testDirectory', Integer])
      with_fuse(mock_fs) do |mp|
        Dir.mkdir("#{mp}/testDirectory")
      end

    end

    it 'should list directories' do
      mock_fs.paths = { '/testDirectory' => stat_as_dir }

      mock_fs.expect(:readdir, 0) do |path, buf, fuse_fill_dir, _off, _ffi, _flags = 0|
        raise "Expected #{path} to be /testDirectory" unless path == '/testDirectory'

        { '.' => nil, '..' => nil, 'hello' => file_stat, 'world' => file_stat }.each_pair do |f, stat|
          fill_args = [buf, f, stat, 0]
          fill_args << 0 if FFI::Libfuse::FUSE_MAJOR_VERSION >= 3
          fuse_fill_dir.call(*fill_args)
        end
      end

      with_fuse(mock_fs) do |mp|
        entries = Dir.entries("#{mp}/testDirectory")
        expect(entries.size).must_equal(4)
        expect(entries).must_include('hello')
        expect(entries).must_include('world')
      end

    end
  end

  describe 'permissions' do
    before do
      mock_fs.paths =
        {
          '/testDirectory' => stat_as_dir,
          '/testDirectory/myPerms' => stat_as_file
        }
    end

    it 'should process chmod' do

      mock.expect(:chmod, 0) do |path, mode, _ffi = nil|
        _(path).must_equal('/testDirectory/myPerms')
        _(mode).must_equal(FFI::Stat::S_IFREG | 0o644)
      end

      with_fuse(mock_fs) do |mountpoint|
        _(File.chmod(0o644, "#{mountpoint}/testDirectory/myPerms")).must_equal(1)
      end
    end
  end

  describe 'links' do
    before do
      mock_fs.paths = { '/testDirectory' => stat_as_dir }
    end

    it 'should create and resolve symbolic links' do
      mock_fs.expect_not_exists('/testDirectory/sym.link')
      mock_fs.expect_stat('/testDirectory/sym.link') { |s| s.symlink(size: 10)}

      mock_fs.expect(:symlink, 0, %w[test /testDirectory/sym.link])
      mock_fs.expect(:readlink, 0) do |_path, buf, size|
        expect(size).must_be(:>=, 10,'readlink buffer size')
        buf.put_string(0, 'test.file') # with NULL terminator.
      end

      with_fuse(mock_fs) do |mountpoint|
        File.symlink("test","#{mountpoint}/testDirectory/sym.link")
        _(File.readlink("#{mountpoint}/testDirectory/sym.link")).must_equal('test.file')
      end
    end

    it 'should create and resolve hard links' do
      mock_fs.paths['/testDirectory/test.file'] = stat_as_file
      mock_fs.expect_not_exists('/testDirectory/hard.link')
      mock_fs.expect_file('/testDirectory/hard.link', nlink: 2)
      mock_fs.expect(:link, 0, %w[/testDirectory/test.file /testDirectory/hard.link])
      with_fuse(mock_fs) do |mountpoint|
        File.link("#{mountpoint}/testDirectory/test.file", "#{mountpoint}/testDirectory/hard.link")
      end
    end
  end

  describe 'timestamps' do
    before do
      mock_fs.paths = { '/testDirectory' => stat_as_dir }
    end

    it 'should support stat with nanosecond resolution' do

      atime, mtime, ctime = [11, 22, 33].map { |inc| Time.at(946684800, 123456700 + inc, :nsec) }

      set_stat = ->(s) { s.file(mode: 0o777, size: 0, atime: atime, mtime: mtime, ctime: ctime) }

      mock_fs.paths['/testDirectory/testns'] = set_stat

      with_fuse(mock_fs) do |mountpoint|
        stat = File.stat("#{mountpoint}/testDirectory/testns")
        expect(stat.atime).must_equal(atime)
        expect(stat.ctime).must_equal(ctime)
        expect(stat.mtime).must_equal(mtime)
      end
    end

    it 'should set file access and modification times' do
      exp_atime, exp_mtime = [88, 99].map { |inc| Time.at(946684800, 123456700 + inc, :nsec) }

      mock_fs.paths['/testDirectory/utime'] = stat_as_file

      mock_fs.expect(:utimens, 0) do |path, times, _ffi|
        _(path).must_equal('/testDirectory/utime')
        atime, mtime = times
        _(atime.tv_sec).must_equal(exp_atime.tv_sec, 'atime sec')
        _(atime.nsec).must_equal(exp_atime.nsec, 'atime nsec')
        _(mtime.sec).must_equal(exp_mtime.tv_sec, 'mtime sec')
        _(mtime.nsec).must_equal(exp_mtime.nsec, 'mtime nsec')
      end

      with_fuse(mock_fs) do |mp|
        File.utime(exp_atime, exp_mtime, "#{mp}/testDirectory/utime")
      end
    end

  end

  describe 'file io' do
    it 'should create files' do
      mock_fs.paths = { '/testDirectory' => stat_as_dir }
      mock_fs.expect_not_exists('/testDirectory/newfile')
      mock_fs.expect_file('/testDirectory/newfile')
      mock_fs.expect(:mknod, 0) do |path, mode, _dev|
        expect(path).must_equal('/testDirectory/newfile')
        expect(mode).must_equal(FFI::Stat::S_IFREG | 0o644)
      end

      with_fuse(mock_fs) do |mp|
        File.open("#{mp}/testDirectory/newfile", 'w', 0o644) { |_f|  }
      end
    end

    it 'should create special device files'

    it 'should read files' do
      mock_fs.paths = { '/testDir' => stat_as_dir }
      mock_fs.expect_file('/testDir/testFile', size: 12)
      mock_fs.expect(:read, 12) { |_path, buf, _size, _offset, _ffi| buf.write_bytes("hello\000world\000") }

      with_fuse(mock_fs) do |mountpoint|
        File.open("#{mountpoint}/testDir/testFile") do |f|
          val = f.gets
          expect(val).must_equal("hello\000world\000")
        end
      end
    end

    it 'should read files with direct_io' do
      mock_fs.paths = { '/testDir' => stat_as_dir }
      mock_fs.expect_file('/testDir/testFile', size: 12)

      content = "hello\000world\000"
      content.chars.to_a.each_slice(2).to_a.map(&:join).each do |chunk|
        mock_fs.expect(:read, chunk.size) { |_path, buf, _size, _offset, _ffi| buf.write_bytes(chunk) }
      end
      mock_fs.expect(:read, 0, [String, FFI::Pointer, Integer, 12, FFI::Libfuse::FuseFileInfo])

      if FFI::Libfuse::FUSE_MAJOR_VERSION >= 3
        def mock_fs.init(_conn_info, config)
          config.direct_io = true
          super
        end
      end

      expect(mock_fs.fuse_respond_to?(:read)).must_equal(true)

      args = FFI::Libfuse::FUSE_MAJOR_VERSION == 2 ? %w[-o direct_io] : %w[]
      with_fuse(mock_fs, *args) do |mountpoint|
        File.open("#{mountpoint}/testDir/testFile") do |f|
          val = f.gets
          expect(val).must_equal("hello\000world\000")
        end
      end
    end

    it 'should read via FuseBuf vectors' do
      mock_fs.paths = { '/testDir' => stat_as_dir }
      mock_fs.expect_file('/testDir/testFile', size: 12)

      content = "hello\000world\000"
      # bufp,size,offset,fuse_file_info
      mock_fs.expect(:read_buf, 0) do |_path, bufp, size, offset, _ffi|
        expect(offset).must_equal(0)
        FFI::Libfuse::FuseBufVec.create(content, size, offset).store_to(bufp)
      end
      mock_fs.expect(:read_buf, 0) do |_path, bufp, _size, offset, _ffi|
        expect(offset).must_equal(12)
        # Default is an empty bufvec
        FFI::Libfuse::FuseBufVec.init(autorelease: false).store_to(bufp)
      end

      expect(mock_fs.fuse_respond_to?(:read_buf)).must_equal(true)

      args = []
      if FFI::Libfuse::FUSE_MAJOR_VERSION >= 3
        def mock_fs.init(_conn_info, config)
          config.direct_io = true
          super
        end
      else
        args.push('-o', 'direct_io')
      end

      with_fuse(mock_fs, *args) do |mountpoint|
        File.open("#{mountpoint}/testDir/testFile") do |f|
          val = f.gets
          expect(val).must_equal("hello\000world\000")
        end
      end
    end
  end


  describe 'filesystem statistics' do
    let(:statvfs) do
      { bsize: 2048, 'frsize' => 1024, 'blocks' => 9999, 'bfree' => 8888, 'bavail' => 7777, 'files' => 6000, 'ffree' => 5555 }
    end

    it 'should report filesystem statistics' do
      # TODO: on MacOS statfs always applies to the root path
      #       and there is the statfs_x function that uses 64 bit inode structure
      skip 'MacOS todo statvfs' if mac_fuse?

      mock_fs.paths = { '/testDir' => stat_as_dir }
      mock_fs.expect_file('/testDir/statfs', size: 12)

      mock_fs.expect(:statfs, 0) do |_path, statfs|
        statfs.fill(**statvfs)
        0
      end

      expect(mock_fs.fuse_respond_to?(:statfs)).must_equal(true)

      with_fuse(mock_fs) do |mountpoint|
        results = Sys::Filesystem.stat("#{mountpoint}/testDir/statfs")
        expect(results.block_size).must_equal(2048)
        expect(results.fragment_size).must_equal(1024)
        expect(results.blocks).must_equal(9999)
        expect(results.blocks_available).must_equal(7777)
        expect(results.blocks_free).must_equal(8888)
        expect(results.files).must_equal(6000)
        expect(results.files_available).must_equal(5555)
      end
    end
  end
end


