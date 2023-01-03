# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/ffi/libfuse/gem_version'

describe "FFI::Libfuse.gem_version" do

  matrix = [
    { name: 'VERSION for main branch', ref_name: 'main', expected: FFI::Libfuse::VERSION },
    { name: 'version tag directly', ref_type: 'tag', ref_name: 'v99.1.0', expected: '99.1.0'},
    { name: 'version tags/ref', ref_type: nil, ref_name: 'tags/v99.1.0^0', expected: '99.1.0.33'},
    { name: 'version tags/ref without index', ref_name: 'tags/v99.1.0', expected: '99.1.0'},
    { name: 'prerelease tag directly', ref_type: 'tag', ref_name: 'v99.1.0.pre', expected: '99.1.0.pre'},
    { name: 'non version tag as per-release', version: 'X.Y.Z', ref_type: 'tag', ref_name: 'abc', expected: 'X.Y.Z.abc.33'},
    { name: 'build_number for branches', ref_name: "xxx", build_number: '88', version: '99.2.3', expected: '99.2.3.xxx.88'},
    { name: 'build_number for tag', ref_type: 'tag', ref_name: "xxx", build_number: '88', version: '99.2.3', expected: '99.2.3.xxx.88'},
    { name: 'tags ref', ref_name: "tags/xxx", build_number: '88', version: '99.2.3', expected: '99.2.3.xxx.88'},
  ]
  matrix.kw_each do |name:, version: FFI::Libfuse::VERSION, ref_name:, ref_type: 'branch', build_number: '33', expected: |
    it "uses #{name}" do
      env = { 'GITHUB_REF_NAME' => ref_name }
      env['GITHUB_REF_TYPE'] = ref_type if ref_type
      env['GITHUB_RUN_NUMBER'] = build_number if build_number
      expect(FFI::Libfuse.gem_version(version: version,env: env)).must_equal(expected)
    end
  end
end