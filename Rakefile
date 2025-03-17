# frozen_string_literal: true

require "bundler/gem_tasks"

require "rspec/core/rake_task"

require "standard/rake"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.ruby_opts = %w[-w]
end

task test: %i[spec standard]
task default: %i[test]
