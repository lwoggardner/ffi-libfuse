# frozen_string_literal: true

# Load instead of require so bundler doesn't trash VERSION
require_relative 'lib/ffi/libfuse/version'

Gem::Specification.new do |spec|
  spec.name          = 'ffi-libfuse'
  spec.version       = FFI::Libfuse::VERSION
  spec.authors       = ['Grant Gardner']
  spec.email         = ['grant@lastweekend.com.au']

  spec.summary       = 'FFI Bindings for Libfuse'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.6.0')

  spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata['source_code_uri'] = 'http://github.com/lwoggardner/ffi-libfuse'
  spec.metadata['changelog_uri'] = 'http://github.com/lwoggardner/ffi-libfuse/CHANGELOG'

  spec.files         = Dir['lib/**/*.rb', 'sample/*.rb', '*.md', 'LICENSE', '.yardopts']
  spec.require_paths = ['lib']

  spec.add_dependency 'ffi'

  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'sys-filesystem'
  spec.add_development_dependency 'yard'
end
