# frozen_string_literal: true

require "spec_helper"

require "shellwords"

class TestBuilder < Plover::Builder
  phase(:setup) do
    @setup_called = true
  end

  phase(:build) do
    @build_called = true
    push_artifact("test_artifact", "artifact_value")
  end

  def setup_called?
    @setup_called
  end

  def build_called?
    @build_called
  end
end

module Plover::Builder::Common::Failer
  extend Plover::Concern

  included do
    fail_build("Failer was included")
  end
end

module Plover::Builder::Common::Dummy
  extend Plover::Concern

  included do
    def dummy_instance_method
      "instance value"
    end
  end

  class_methods do
    def dummy_class_method
      "class value"
    end
  end
end

class ConcernTestBuilder < Plover::Builder; end

RSpec.describe Plover::Builder do
  describe ".env_flags" do
    before do
      ENV["PLOVER_FLAG_TEST"] = "foo"
    end

    after do
      ENV.delete("PLOVER_FLAG_TEST")
    end

    it "converts environment variables to flags hash" do
      flags = Plover::Builder.env_flags
      expect(flags).to include({test: "foo"})
    end
  end

  describe "expected flags" do
    it "raises BuildError if expected flags are missing" do
      TestBuilder.expect_flags(:required_flag)
      expect { TestBuilder.new({}) }.to raise_error(Plover::Builder::BuildError, /Missing required flags: required_flag/)
    end

    it "does not raise error if expected flags are provided" do
      TestBuilder.expect_flags(:required_flag)
      expect { TestBuilder.new(required_flag: "present") }.not_to raise_error
    end
  end

  describe "phase execution" do
    it "executes phase blocks in order" do
      builder = TestBuilder.new(build_root: ".")
      builder.run_phase(:setup)
      builder.run_phase(:build)
      expect(builder.setup_called?).to be true
      expect(builder.build_called?).to be true
    end
  end

  describe "artifact tracking" do
    it "pushes and retrieves artifacts" do
      builder = TestBuilder.new
      builder.instance_variable_set(:@current_phase, :build)
      builder.push_artifact("artifact1", "value1")
      expect(builder.artifact(:build, "artifact1")).to eq("value1")
    end
  end

  describe "#esc" do
    it "escapes strings properly" do
      builder = TestBuilder.new
      # Shellwords.escape should add a backslash before a space.
      expect(builder.esc("hello world")).to eq("hello\\ world")
    end
  end

  describe "Concern inclusion" do
    before do
      # Tell the builder to include the Dummy module.
      ConcernTestBuilder.common_include("Dummy")
      ConcernTestBuilder.auto_include_common
    end

    it "includes instance methods from the concern" do
      builder = ConcernTestBuilder.new
      expect(builder).to respond_to(:dummy_instance_method)
      expect(builder.dummy_instance_method).to eq("instance value")
    end

    it "adds class methods from the concern" do
      expect(ConcernTestBuilder).to respond_to(:dummy_class_method)
      expect(ConcernTestBuilder.dummy_class_method).to eq("class value")
    end

    it "includes only the expected concern" do
      expect(ConcernTestBuilder.included_modules).to include(Plover::Builder::Common::Dummy)
      expect(ConcernTestBuilder.included_modules).not_to include(Plover::Builder::Common::Failer)
    end
  end
end
