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

GEM_CMD_ARGS = {
  tag: %w[-p],
  release: %w[-k RUBYGEMS_API_KEY],
  bump: %w[-v patch -p --skip-ci].push('-m', 'chore: patch bump %<name>s %<skip_ci>')
}.freeze

# Via release-please workflow_call (release-please has already tagged) - release and bump
# Manual call or workflow-dispatch on a branch - tag and bump - release will run again via github action
# Call on a tag (manually, workflow-dispatch, or push to semver tag) - just release (can't bump a tag)

# NOTE: bump only happens on non prerelease - ie main branch
#   if we lock the branch we won't be able to mini-bump (until github allows action to bypass branch protection)
#   or we need to use a personal access token (as a secret) - just for the release job
#   (while still using github token for release-please)
desc 'Tag (if required), Release to rubygems, Bump patch version'
task :release, %i[options] => %i[version] do |_t, args|
  ref_type = FFI::Libfuse::GIT_REF_TYPE
  ref_name = FFI::Libfuse::GIT_REF_NAME
  expected_tag = "v#{FFI::Libfuse::GEM_VERSION}"
  event_name = ENV.fetch('GITHUB_EVENT_NAME', 'workflow-dispatch')
  rp_tag_name = ENV.fetch('RELEASE_PLEASE_TAG_NAME', '')

  raise "Cannot release from git ref: #{ref_type}/#{ref_name}" unless %i[branch tag].include?(ref_type)

  # workflow call from release-please PR merge, release-please has already tagged, make sure it matches
  if ref_type == :branch && event_name != 'workflow-dispatch' && rp_tag_name != expected_tag
    raise "Unexpected release-please tag #{rp_tag_name} vs #{expected_tag}"
  end

  # Tag must be a sem-ver tag matching gem version
  raise "Unexpected tag #{ref_name} vs #{expected_tag}" if ref_type == :tag &&  ref_name == expected_tag

  # If this is a manual call on a branch we just tag which will re-invoke release via github action
  actions = [ref_type == :branch && event_name == 'workflow-dispatch' ? :tag : :release]
  result << :bump if ref_type == :branch && !Gem::Version.new(FFI::Libfuse::GEM_VERSION).prerelease?

  args.with_defaults(options: '--pretend') # use [--no-verbose] to force
  options = args[:options].split(/\s+/)
  Bundler.with_unbundled_env do
    actions.each do |a|
      cmd = ['gem', a.to_s].concat(GEM_CMD_ARGS[a]).concat(options)
      puts "Calling #{cmd}"
      system(*cmd, exception: true)
    end
  end
end
