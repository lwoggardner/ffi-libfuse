# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/ffi/libfuse/gem_version'

describe "FFI::Libfuse.gem_version" do

  matrix = [
    { name: 'VERSION for main branch', ref: 'heads/main', expected: FFI::Libfuse::VERSION },
    { name: 'prerelease branch', version: '99.1.0', ref: 'heads/myfix', expected: '99.1.0.myfix' },
    { name: 'branch with removed separators', version: '99.1.2', ref: 'heads/fix/me-_123', expected: '99.1.2.fixme123'},
    { name: 'version tag directly', ref: 'tags/v99.1.0', expected: '99.1.0'},
    { name: 'version tags/ref without index', ref: 'tags/v99.1.0', expected: '99.1.0'},
    { name: 'prerelease tag directly', ref: 'tags/v99.1.0.pre', expected: '99.1.0.pre'},
    { name: 'non version tag as pre-release', version: 'X.Y.Z', ref: 'tags/abc', expected: 'X.Y.Z.abc'},
    { name: 'non semver tag as pre-release', version: 'X.Y.Z', ref: 'tags/v1.2blah', expected: 'X.Y.Z.v1.2blah'},
    { name: 'pull request base_ref', version: '99.3.2', ref: 'pull/777/merge', base: 'xxx', expected: '99.3.2.xxx.merge777'},
  ]
  matrix.kw_each do |name:, ref:, base: '' ,expected:, **args |
    it "uses #{name}" do
      env = { 'GITHUB_REF' => "refs/#{ref}" }
      env['GITHUB_BASE_REF'] = base if base
      expect(FFI::Libfuse.gem_version(env: env, **args)).must_equal(expected)
    end
  end
end