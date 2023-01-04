# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/ffi/libfuse/gem_version'

describe "FFI::Libfuse.gem_version" do

  matrix = [
    { name: 'VERSION for main branch', ref_name: 'main', expected: FFI::Libfuse::VERSION },
    { name: 'prerelease branch', version: '99.1.0', ref_name: 'myfix', expected: '99.1.0.myfix' },
    { name: 'branch with removed separators', version: '99.1.2', ref_name: 'fix/me-_123', expected: '99.1.2.fixme123'},
    { name: 'version tag directly', ref_type: 'tag', ref_name: 'v99.1.0', expected: '99.1.0'},
    { name: 'version tags/ref', ref_type: nil, ref_name: 'tags/v99.5.0^0', expected: '99.5.0'},
    { name: 'version tags/ref without index', ref_type: nil, ref_name: 'tags/v99.1.0', expected: '99.1.0'},
    { name: 'prerelease tag directly', ref_type: 'tag', ref_name: 'v99.1.0.pre', expected: '99.1.0.pre'},
    { name: 'non version tag as pre-release', version: 'X.Y.Z', ref_type: 'tag', ref_name: 'abc', expected: 'X.Y.Z.abc'},
    { name: 'non semver tag as pre-release', version: 'X.Y.Z', ref_type: 'tag', ref_name: 'v1.2blah', expected: 'X.Y.Z.v1.2blah'},
  ]
  matrix.kw_each do |name:, ref_name:, ref_type: 'branch', expected:, **args |
    it "uses #{name}" do
      env = { 'GITHUB_REF_NAME' => ref_name }
      env['GITHUB_REF_TYPE'] = ref_type if ref_type
      expect(FFI::Libfuse.gem_version(env: env, **args)).must_equal(expected)
    end
  end
end