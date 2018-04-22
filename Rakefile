
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)
RSpec::Core::RakeTask.new(:mock) do |task|
  task.pattern = "spec/**{,/*/**}/*_mock.rb"
end

task default: :spec
