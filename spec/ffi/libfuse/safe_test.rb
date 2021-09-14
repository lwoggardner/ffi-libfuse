# frozen_string_literal: true

require_relative '../../spec_helper'

describe 'Safe' do
  it 'rescues SystemCallErrors and returns negative errno values'
  it 'returns ENOTRECOVERABLE on ruby errors'
  it 'returns 0 for non integer callbacks'
  it 'returns 0 for positive integer callback except for meaningful return callbacks'
  it 'returns positive integers for meaningful return callbacks'
  it 'returns negative integers directly'
  it 'does not wrap init or destroy'
end

