# frozen_string_literal: true

require 'rake/clean'

CLOBBER.include %w[pkg/ doc/]

require 'rake/testtask'

desc 'Unit Tests'
Rake::TestTask.new(:unit_test) do |t|
  t.test_files = FileList['spec/ffi/**/*_test.rb']
  t.warning = false # suppress minitest circular require warning
end

desc 'Sample Filesystem Tests'
Rake::TestTask.new(:sample_test) do |t|
  t.test_files = FileList['spec/sample/*_test.rb']
  t.warning = false # suppress minitest circular require warning
end

desc 'Run all tests'
task test: %i[unit_test sample_test]

require 'bundler/audit/task'
Bundler::Audit::Task.new

require 'yard'
YARD::Rake::YardocTask.new do |t|
  t.options << '--fail-on-warning'
end
task yard: ['README.md']

require 'rubocop/rake_task'
RuboCop::RakeTask.new

file('README.md' => ['sample/hello_fs.rb']) do |t|
  readme = File.read(t.name)
  t.prerequisites.each do |sample_file|
    sample_content = File.read(sample_file)
    sample_content = "\n*#{sample_file}*\n\n```ruby\n#{sample_content}\n```\n"
    unless readme.gsub!(/(<!-- SAMPLE BEGIN: #{sample_file} -->)(.*)(<!-- SAMPLE END: #{sample_file} -->)/im,
                        "\\1#{sample_content}\\3")
      raise "Did not find SAMPLE #{sample_file} in #{t.name}"
    end
  end
  File.write(t.name, readme)
end

task :samples do |_t|
  FileList['sample/*.rb'].each { |f| touch f }
end

desc 'Regenerate documentation'
task doc: %i[samples yard]

task default: %i[rubocop bundle:audit:check test doc]

# RELEASING
# CI
#   push/PR to branch runs default task against a matrix of OS, ruby versions and Fuse2/Fuse3
#   push to branch (or tag) prefixed with 'rc' will create pre-release using branch/tag and CI build number
#   push to tag vX.Y.Z (ie resulting from manually calling rake tag --no-verbose)

# Review changelog and ypdate CHANGES.md as necessary
# Update major/minor version in lib/ffi-libfuse/version.rb if necessary (as per semantic versioning)
# Commit/Push and ensure CI builds are passing
# rake tag  to check, rake tag --no-verbose
# gem install gem-release
# TODO: Make ^^ a workflow-dispatch (manual from github console) action
RELEASE_BRANCH = 'main'
desc 'Tag and bump to trigger release to rubygems'
task :tag, [:options] => %i[clobber default] do |_t, args|
  args.with_defaults(options: '--pretend') # use [--no-verbose] to force
  branch = `git rev-parse --abbrev-ref HEAD`.strip
  raise "Cannot release from #{branch}, only #{RELEASE_BRANCH}" unless branch == RELEASE_BRANCH

  Bundler.with_unbundled_env do
    raise 'Tag failed' unless system({ 'RAKEFILE_TAG' => 'Y' }, "gem tag -p #{args[:options]}".strip)
    raise 'Bump failed' unless system("gem bump -v patch -p #{args[:options]}".strip)
  end
end
