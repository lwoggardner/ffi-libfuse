# frozen_string_literal: true

source 'https://rubygems.org'

LOCAL_GEM_PATH = Bundler.settings['local.gem_path'] || '..'
LOCAL_GEMS = Bundler.settings['local.gems']&.split(/[,;]|\s+/) || []

def local_gem(gem_name, version = nil, transitive: true, **options)
  if LOCAL_GEMS.include?(gem_name) && File.exist?("#{LOCAL_GEM_PATH}/#{gem_name}/#{gem_name}.gemspec")
    options[:path] = "#{LOCAL_GEM_PATH}/#{gem_name}"
    warn "local gem #{LOCAL_GEM_PATH}/#{gem_name} - #{options}"
  end
  gem gem_name, version, **options unless transitive
end

local_gem 'ffi'

gemspec
