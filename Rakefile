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

# Inject known working Hello World sample into readme
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

# Force samples
task :samples do |_t|
  FileList['sample/*.rb'].each { |f| touch f }
end

desc 'Regenerate documentation'
task doc: %i[samples yard]

task default: %i[version rubocop bundle:audit:check test doc]

# CI/CD actions
#   push/PR to branch runs default task against a matrix of OS, ruby versions and Fuse2/Fuse3
#   push to tag vX.Y.Z(.*) publish to ruby gems
#   bump patch version
#   reject changes to lib/ffi/libfuse/version.rb except on main
#   reject changes to changelog except on main

# Manual flow
# * Merge PRs
# * Update ChangeLog
# * Bump major/minor version if necessary
# * Tag + Release to ruby gems
# * Bump patch version

# Testing Release workflow (any branch other than main)

# Update major/minor version in lib/ffi-libfuse/version.rb if necessary (as per semantic versioning)
# Commit/Push and ensure CI builds are passing
# rake tag  to check, rake tag --no-verbose
# gem install gem-release
# TODO: Make ^^ a workflow-dispatch (manual from github console) action

# Run from 'Tag' workflow (which is workflow-dispatch type - ie run manually) against a branch
# options are space separated rake tag[--no-verbose --color]
task :tag, [:options] => %i[clobber default] do |_t, args|
  # Expect to tag from a branch
  args.with_defaults(options: '--pretend')
  options = args[:options].strip.split(/\s+/)
  Bundler.with_unbundled_env do
    # tag is derived from GEM_VERSION
    system("gem tag -p #{options.uniq.join(' ')}") || raise('Tag failed')
    # bump uses VERSION (and directly updates lib/<gem>/version.rb)
    options << '--skip-ci' # we don't need to rerun tests on this bump
    options << '--pretend' unless GEM::Version.new(FFI::Libfuse::GEM_VERSION).prerelease?
    system("gem bump -v patch -p --skip-ci #{options.uniq.join(' ')}") || raise('Bump failed')
  end
end

# Run from the 'Publish' workflow run against tags matching v\d.\d.\d[.pre]
task :publish, [:options] => %i[version] do |_t, args|
  # Expect to publish from a tag ref
  # If publishing from a branch then we want to fail?
  # No point including a build number since the tag commit includes everything used to release the gem
  args.with_defaults(options: ENV['GITHUB_WORKFLOW'] == 'Publish' ? '--no-verbose' : '--pretend')
  options = args[:options].strip

  Bundler.with_unbundled_env do
    system("gem release #{options}") || raise('Release failed')
  end
end

desc 'Version info'
task :version do
  require_relative 'lib/ffi/libfuse/gem_version'
  v = Gem::Version.new(FFI::Libfuse::VERSION)
  gv = Gem::Version.new(FFI::Libfuse::GEM_VERSION)

  msg = "FFI::Libfuse - VERSION='#{v}' GEM_VERSION='#{gv}', prerelease=#{gv.prerelease?}"
  raise "Mismatched versions - #{msg}" unless gv.release == v

  puts msg
end
