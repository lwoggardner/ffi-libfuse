# frozen_string_literal: true

# Load instead of require so bundler doesn't trash VERSION
require_relative 'lib/ffi/libfuse/version'

Gem::Specification.new do |spec|
  spec.name          = 'ffi-libfuse'

  # rubocop:disable Gemspec/DuplicatedAssignment
  spec.version       = FFI::Libfuse::VERSION
  # Only use the release version for actual deployment
  if ENV['TRAVIS_BUILD_STAGE_NAME']&.downcase == 'prerelease'
    spec.version = "#{spec.version}.#{ENV['TRAVIS_BRANCH']}#{ENV['TRAVIS_BUILD_NUMBER']}"
  elsif ENV['FFI_LIBFUSE_RELEASE'] || ENV['TRAVIS_BUILD_STAGE_NAME']&.downcase == 'deploy'
    # leave as is
  else
    spec.version = "#{spec.version}.pre"
  end
  # rubocop:enable Gemspec/DuplicatedAssignment

  spec.authors       = ['Grant Gardner']
  spec.email         = ['grant@lastweekend.com.au']

  spec.summary       = 'FFI Bindings for Libfuse'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.6.0')

  spec.metadata['source_code_uri'] = 'http://github.com/lwoggardner/ffi-libfuse'

  spec.files         = Dir['lib/**/*.rb', 'sample/*.rb', '*.md', 'LICENSE', '.yardopts']
  spec.require_paths = ['lib']

  spec.add_dependency 'ffi'

  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'sys-filesystem'
  spec.add_development_dependency 'yard'
end
