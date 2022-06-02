# frozen_string_literal: true

require_relative '../../../lib/ffi/libfuse'

# Fuse filesystem over a minitest Mock
class MockFS
  attr_reader :mock
  attr_accessor :paths

  def initialize(debug: false, paths: {})
    @mock = Minitest::Mock.new
    @paths = paths
    @debug = debug
  end

  def fuse_respond_to?(method)
    respond_to?(method) || mock.respond_to?(method)
  end

  def fuse_wrappers(*wrappers)
    wrappers << proc { |fuse_method, *args| fuse_mock(fuse_method, *args) }
    wrappers << proc { |fm, *args, &b| FFI::Libfuse::Adapter::Debug.debug_callback(fm, *args, &b) } if @debug
    wrappers << {
      wrapper: proc { |fm, *args, &b| FFI::Libfuse::Adapter::Safe.safe_callback(fm, *args, &b) },
      excludes: %i[init destroy]
    }
    wrappers << proc { |fm, *args, &b| expectation_callback(fm, *args, &b) }

    wrappers
  end

  def expectation_callback(fuse_method, *args)
    yield(*args)
  rescue Minitest::Assertion => e
    warn "Assertion failed in #{fuse_method}: #{e.message}"
    -Errno::ENOTRECOVERABLE::Errno
  end

  def fuse_debug(enabled)
    @debug = enabled
  end

  def init(*_args)
    nil
  end

  def destroy(_obj); end

  def getattr(path, stat, ffi = nil)

    if path == '/'
      stat.directory(mode: 0o777)
      return 0
    end

    # ignore OS generated calls
    raise Errno::ENOENT unless test_path?(path)

    res =
      if @paths.key?(path)
        @paths[path].call(stat)
      else
        mock.getattr(path, stat, ffi)
      end

    raise SystemCallError.new(nil, -res) if res.is_a?(Integer) && res.negative?
    0
  end

  # ignore OS generated calls (on MacOs)
  def statfs(path, statvfs)
    return 0 if path == '/'
    return Errno::ENOENT unless test_path?(path)

    mock.statfs(path,statvfs)
  end

  def expect(*args, &blk)
    mock.expect(*args, &blk)
  end

  def stub(method, &blk)
    define_singleton_method(method, &blk)
  end

  def expect_not_exists(path)
    mock.expect(:getattr, -Errno::ENOENT::Errno) { |p, s, _ffi = nil| path == p && s.is_a?(FFI::Stat) }
  end

  def expect_file(expected_path, mode: 0o777, size: 0, **stat_args)
    mock.expect(:getattr, 0) do |path, stat, _ffi = nil|
      raise "Expected #{expected_path}, got #{path}" unless path == expected_path

      stat.file(mode: mode, size: size, **stat_args) && true
    end
  end

  def expect_dir(expected_path, mode: 0o755, **stat_args)
    mock.expect(:getattr, 0) do |path, stat, _ffi = nil|
      raise "Expected #{expected_path}, got #{path}" unless path == expected_path

      stat.dir(mode: mode, **stat_args) && true
    end
  end

  def fuse_mock(fuse_method, *args)
    return send(fuse_method, *args) if respond_to?(fuse_method)

    path = args.shift
    raise Errno::ENOSYS unless test_path?(path)

    mock.send(fuse_method, path, *args)
  end

  def test_path?(path)
    path.to_s =~ %r{^/test}
  end
end
