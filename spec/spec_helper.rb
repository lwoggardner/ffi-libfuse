# frozen_string_literal: true

require 'minitest/spec'
require 'minitest/autorun'
require 'minitest/reporters'

unless ENV.key?('RM_INFO')
  options = {}
  options[:color] = true if ENV.include?('GITHUB_JOB')
  Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new(**options)
end

module Enumerable
  # generate clean keyword args from hashes
  def kw_each
    return to_enum(__method__) unless block_given?
    each { |h| yield(**h) }
  end
end