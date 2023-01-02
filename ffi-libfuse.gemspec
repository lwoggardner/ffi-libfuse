# frozen_string_literal: true

require_relative 'lib/ffi/libfuse/version'

Gem::Specification.new do |spec|
  spec.name          = 'ffi-libfuse'

  spec.version       =
    # Only use the release version for actual deployment
    if ENV.fetch('TRAVIS_BUILD_STAGE_NAME', nil)&.downcase == 'prerelease'
      "#{FFI::Libfuse::VERSION}.#{ENV.fetch('TRAVIS_BRANCH', nil)}#{ENV.fetch('TRAVIS_BUILD_NUMBER', nil)}"
    elsif ENV.fetch('RAKEFILE_TAG',
                    nil) || ENV.fetch('TRAVIS_BUILD_STAGE_NAME', nil)&.downcase == 'deploy'
      FFI::Libfuse::VERSION
    else
      "#{FFI::Libfuse::VERSION}.pre"
    end

  spec.authors       = ['Grant Gardner']
  spec.email         = ['grant@lastweekend.com.au']

  spec.summary       = 'FFI Bindings for Libfuse'
  spec.license       = 'MIT'

  spec.required_ruby_version = Gem::Requirement.new('>= 2.7.0') # update README.md, rubocop, travis, github

  spec.metadata['source_code_uri'] = 'https://github.com/lwoggardner/ffi-libfuse'

  spec.files         = Dir['lib/**/*.rb', 'sample/*.rb', '*.md', 'LICENSE', '.yardopts']
  spec.require_paths = ['lib']

  spec.add_dependency 'ffi', '~> 1'

  spec.add_development_dependency 'bundler-audit'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'minitest-reporters'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'sys-filesystem'
  spec.add_development_dependency 'yard'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
