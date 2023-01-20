# frozen_string_literal: true

source 'https://rubygems.org'

AVAILABLE_LOCAL_GEMS = %w[ffi].freeze
LOCAL_GEM_PATH = ENV.fetch('LOCAL_GEM_PATH', '..')
LOCAL_GEMS = ENV.fetch('LOCAL_GEMS', AVAILABLE_LOCAL_GEMS.join(';')).split(/[,;]|\s+/)

def local_gem(gem_name, **options)
  options[:path] = "#{LOCAL_GEM_PATH}/#{gem_name}" if Dir.exist?("#{LOCAL_GEM_PATH}/#{gem_name}")
  gem gem_name, **options
end

(AVAILABLE_LOCAL_GEMS & LOCAL_GEMS).each { |g| local_gem(g) }

gemspec
