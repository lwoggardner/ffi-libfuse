# frozen_string_literal: true

require_relative '../../../lib/ffi/libfuse'

# Fuse filesystem over a minitest Mock
class MockFS
  attr_reader :mock
  attr_accessor :paths

  include FFI::Libfuse::Adapter::Debug


  def initialize(debug: false, paths: {})
    @mock = Minitest::Mock.new
    @paths = paths
  end

  def fuse_respond_to?(method)
    respond_to?(method) || mock.respond_to?(method)
  end

  def fuse_wrappers(*wrappers)
    wrappers << proc { |fuse_method, *args| fuse_mock(fuse_method, *args) }
    super(*wrappers)
  end

  def init(*_args)
    nil
  end

  def destroy(_obj)
    mock.verify
  end

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

  def expect_stat(expected_path, &stat_proc)
    mock.expect(:getattr, 0) do |path, stat, _ffi = nil|
      next false unless path == expected_path

      stat_proc.call(stat) && true
    end
  end

  def expect_file(expected_path, mode: 0o777, size: 0, **stat_args)
    expect_stat(expected_path) { |s| s.file(mode: mode, size: size, **stat_args) }
  end

  def expect_dir(expected_path, mode: 0o755, **stat_args)
    expect_stat(expected_path) { |s| s.dir(mode: mode, **stat_args) }
  end

  def expect_symlink(expected_path, **stat_args)
    expect_stat(expected_path) { |s| s.symlink(**stat_args) }
  end

  def fuse_mock(fuse_method, *args)
    return send(fuse_method, *args) if respond_to?(fuse_method)

    read_path_method, _= FFI::Libfuse::FuseOperations.path_arg_methods(fuse_method)
    path = args.send(read_path_method)
    raise Errno::ENOSYS unless test_path?(path)

    mock.send(fuse_method, *args)
  rescue SystemCallError
    # Expected errors, continue silently
    raise
  rescue Minitest::Assertion, StandardError => err
    # Wrap assertion errors so they can be rescued by Safe
    err = Errno::ENOTRECOVERABLE if err.is_a?(Minitest::Assertion) || err.is_a?(MockExpectationError)
    # Log unexpected errors even if we aren't generally debugging callbacks.
    debug_callback(fuse_method, *args, prefix: 'MockFS ERROR') { |*_| raise err } unless debug?
    raise err
  end

  def error_message(err)
    return super unless err.is_a?(Minitest::Assertion)

    "#{err.class.name}: #{err.result_label} at #{err.location}\n#{err.message}"
  end

  def test_path?(path)
    path.to_s =~ %r{^/test}
  end
end
