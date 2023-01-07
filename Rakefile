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

# Workflow: Build on push to any branch
task default: %i[version rubocop bundle:audit:check test doc]

desc 'Version info'
task :version do
  require_relative 'lib/ffi/libfuse/gem_version'
  v = Gem::Version.new(FFI::Libfuse::VERSION)
  gv = Gem::Version.new(FFI::Libfuse::GEM_VERSION)

  msg = "FFI::Libfuse: VERSION='#{v}' GEM_VERSION='#{gv}'"
  raise "Mismatched versions - #{msg}" unless gv.release == v

  puts msg
end

require 'bundler/gem_tasks'
task 'release:guard_clean' => %i[release_guard_tag]

task release_guard_tag: [:version] do
  gem_version = FFI::Libfuse::GEM_VERSION
  tag = "v#{gem_version}"
  git_ref_type = FFI::Libfuse::GIT_REF_TYPE
  git_ref_name = FFI::Libfuse::GIT_REF_NAME

  # If we're on a tag then tag must be THIS tag
  if git_ref_type == :tag && gem_version != "v#{git_ref_name}"
    raise "Checkout is tag #{git_ref_name} but does not match the gem version #{gem_version}"
  end

  # BASH expression - tag does not exist OR exists and points at HEAD
  cmd = '[ -z "$(git tag -l ${VERSION})" ] || git tag --points-at HEAD | grep "^${VERSION}$" > /dev/null'
  raise "Tag #{tag} exists but does not point at HEAD" unless system({ 'VERSION' => tag }, cmd)
end

