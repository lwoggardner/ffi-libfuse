# frozen_string_literal: true

require 'bundler/gem_tasks'

require 'rake/clean'

CLOBBER.include ['pkg/', 'doc/']

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

RELEASE_BRANCH = 'main'
desc 'Release ffi-libfuse'
task :release, [:options] => %i[clobber default] do |_t, args|
  args.with_defaults(options: '--pretend') # use [--no-verbose] to force
  branch = `git rev-parse --abbrev-ref HEAD`.strip
  raise "Cannot release from #{branch}, only #{RELEASE_BRANCH}" unless branch == RELEASE_BRANCH

  Bundler.with_unbundled_env do
    raise 'Tag failed' unless system({ 'FFI_LIBFUSE_RELEASE' => 'Y' }, "gem tag -p #{args[:options]}".strip)
    raise 'Bump failed' unless system("gem bump -v patch -p #{args[:options]}".strip)
  end
end
