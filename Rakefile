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

  msg = "FFI::Libfuse - VERSION='#{v}' GEM_VERSION='#{gv}', prerelease=#{gv.prerelease?}"
  raise "Mismatched versions - #{msg}" unless gv.release == v

  puts msg
  ENV.keys.grep(/^GITHUB_.*REF/).each do |k|
    puts "#{k}=#{ENV.fetch(k, nil)}"
  end
end

require 'bundler/gem_tasks'
task release: %i[version]
