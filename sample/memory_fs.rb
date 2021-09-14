#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ffi/libfuse'

# A simple in-memory filesystem defined with hashes.
#
# It is writable to the user that mounted it may create and edit files within it
#
# === Usage
#   root = Memory.new(files: { 'hello' => { 'world.txt' => 'Hello World'}})
#   root.mkdir("/hello")
#   root.("/hello/world","Hello World!\n")
#   root.write("/hello/everybody","Hello Everyone!\n")
#
#   Libfuse::fuse_main($0,ARGV,operations: root)
#
#
class MemoryFS
  # @return [Hash<String,Object>] list of file objects by path
  attr_reader :root

  include FFI::Libfuse::Adapter::Fuse3Support
  include FFI::Libfuse::Adapter::Ruby
  include FFI::Libfuse::Adapter::Pathname

  File = Struct.new(:mode, :content, :ctime, :atime, :mtime) do
    def dig(*_args)
      raise Errno::ENOTDIR
    end

    def fill_stat(stat = FFI::Stat.new)
      stat.file(mode: mode, ctime: ctime, atime: atime, mtime: mtime, size: content.size)
    end
  end

  # rubocop:disable Lint/StructNewOverride
  Dir = Struct.new(:mode, :entries, :ctime, :atime, :mtime) do
    def dig(*args)
      entries.dig(*args)
    end

    def fill_stat(stat = FFI::Stat.new)
      stat.directory(mode: mode, ctime: ctime, atime: atime, mtime: mtime)
    end
  end
  # rubocop:enable Lint/StructNewOverride

  def initialize(files: {}, max_size: 100_000, max_files: 1_000)
    now = Time.now
    @root = Dir.new(0x755, {}, now, now, now)
    @total_size = 0
    @total_files = 1
    @max_size = max_size
    @max_files = max_files

    build(files)
  end

  def build(files, path = ::Pathname.new('/'))
    files.each_pair do |basename, content|
      raise 'Initial file keys must be String' unless basename.is_a?(String)
      raise 'Initial file keys must not contain path separators' if basename =~ %r{[/\\]}

      entry_path = path + basename
      case content
      when String
        create(entry_path, 0x644)
        write(entry_path, content, 0)
      when Hash
        mkdir(entry_path, 0x755)
        build(content, entry_path)
      else
        raise 'Initial files must be String or Hash'
      end
    end
  end

  def fuse_version
    'MemoryFS: Version x.y.z'
  end

  def fuse_traps
    {
      HUP: -> { reload }
    }
  end

  def statfs(_path, statfs_buf)
    blocks = @total_size / 1_000
    statfs_buf.bsize    = 1 # block size (in Kb)
    statfs_buf.frsize   = 1 # fragment size pretty much always bsize
    statfs_buf.blocks   = @max_size
    statfs_buf.bfree    = @max_size - blocks
    statfs_buf.bavail   = @max_size - blocks
    statfs_buf.files    = @max_files
    statfs_buf.ffree    = @max_files - @total_files
    statfs_buf.favail   = @max_files - @total_files
    0
  end

  def getattr(path, stat_buf)
    entry = find(path)
    return -Errno::ENOENT::Errno unless entry

    entry.fill_stat(stat_buf)
    0
  end

  def readdir(path, _offset, _ffi)
    %w[. ..].each { |d| yield(d, nil) }
    dir = find(path)
    dir.entries.each_pair { |k, e| yield(k, e.fill_stat) }
  end

  def create(path, mode, _ffi)
    dir_entries = find(path.dirname).entries
    now = Time.now
    dir_entries[path.basename.to_s] = File.new(mode, String.new, now, now, now)
    @total_files += 1
    0
  end

  # op[:read] = [:pointer, :size_t, :off_t, FuseFileInfo.by_ref]
  def read(path, len, off, _ffi)
    file = find(path)
    file.atime = Time.now.utc
    FFI::Libfuse::ThreadPool.busy
    sleep 0.5
    file.content[off, len]
  end

  # write(const char* path, char *buf, size_t size, off_t offset, struct fuse_file_info* fi)
  def write(path, data, offset, _ffi)
    file = find(path)
    content = file.content
    @total_size -= content.size
    content[offset, data.length] = data
    @total_size += content.size
    file.mtime = Time.now.utc
  end

  def truncate(path, size)
    file = find(path)
    @total_size -= file.content.size
    file.content[size..-1] = ''
    file.mtime = Time.now.utc
    @total_size += file.content.size
    0
  end

  def unlink(path)
    dir = find(path.dirname)
    deleted = dir.entries.delete(path.basename.to_s)
    @total_files -= 1
    @total_size -= deleted.content.size if deleted.is_a?(File)
    0
  end

  def mkdir(path, mode)
    entries = find(path.dirname).entries
    now = Time.now
    entries[path.basename.to_s] = Dir.new(mode, {}, now, now, now)
  end

  def rmdir(path)
    dir = find(path)
    raise Errno::ENOTDIR unless dir.is_a?(Dir)
    raise Errno::ENOTEMPTY unless dir.entries.empty?

    find(path.dirname).entries.delete(path.basename.to_s)
    0
  end

  def utimens(path, atime, mtime)
    entry = find(path)
    entry.atime = atime if atime
    entry.mtime = mtime if mtime
    0
  end

  private

  def find(path)
    path.root? ? root : root.dig(*path.to_s.split('/')[1..])
  end
end

exit(FFI::Libfuse.fuse_main($0, *ARGV, operations: MemoryFS.new)) if __FILE__ == $0
