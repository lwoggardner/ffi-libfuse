# frozen_string_literal: true

require 'bundler/gem_tasks'

require 'rake/testtask'
Rake::TestTask.new do |t|
  t.test_files = FileList['spec/**/*_test.rb']
  t.warning = false
end

require 'yard'
YARD::Rake::YardocTask.new do |t|
  t.options << '--fail-on-warning'
end

require 'rubocop/rake_task'
RuboCop::RakeTask.new

task default: %i[rubocop test yard]
