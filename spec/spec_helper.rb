# frozen_string_literal: true

require 'minitest/spec'
require 'minitest/autorun'

module Enumerable
  # generate clean keyword args from hashes
  def kw_each
    return to_enum(__method__) unless block_given?
    each { |h| yield(**h) }
  end
end