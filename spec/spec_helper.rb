# frozen_string_literal: true

require 'minitest/spec'
require 'minitest/autorun'
require 'minitest/reporters'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new unless ENV.include?('RM_INFO')

module Enumerable
  # generate clean keyword args from hashes
  def kw_each
    return to_enum(__method__) unless block_given?
    each { |h| yield(**h) }
  end
end