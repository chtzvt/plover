# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "logger"

class DummyLoggerClass < Plover::Builder
  def self.name
    "DummyLoggerClass"
  end
end

RSpec.configure do |config|
  config.before(:each) do
    if defined?(subject) && subject.respond_to?(:instance_variable_set)
      subject.instance_variable_set(:@logger, nil)
    end

    DummyLoggerClass.instance_variable_set(:@logger, nil)
  end
end

RSpec.describe Plover::Log do
  let(:dummy_instance) { DummyLoggerClass.new }

  describe "#logger" do
    context "when log sink is $stdout" do
      before do
        allow_any_instance_of(DummyLoggerClass)
          .to receive(:log_config)
          .and_return({level: :info, sink: :use_default})
      end

      it "returns a Logger instance with $stdout as sink" do
        logger = dummy_instance.logger
        expect(logger).to be_a(Logger)
        expect(logger.instance_variable_get(:@logdev).dev).to eq($stdout)
      end

      it "sets the progname based on the instance's class" do
        logger = dummy_instance.logger
        expect(logger.progname).to eq("<Plover/DummyLoggerClass>")
      end

      it "respects the log level" do
        dummy_instance.log_level :debug
        logger = dummy_instance.logger
        expect(logger.level).to eq(Logger::DEBUG)
      end
    end

    context "when log sink is a file path" do
      let(:temp_file) { "spec/tmp_log.txt" }
      before do
        File.delete(temp_file) if File.exist?(temp_file)
        allow_any_instance_of(DummyLoggerClass)
          .to receive(:log_config)
          .and_return({level: :info, sink: temp_file})
        DummyLoggerClass.instance_variable_set(:@logger, nil)
      end

      after do
        File.delete(temp_file) if File.exist?(temp_file)
      end

      it "creates a Logger that writes to the file" do
        logger = dummy_instance.logger
        logger.info("Test message")
        content = File.read(temp_file)
        expect(content).to include("Test message")
      end
    end

    context "when log sink is an IO stream" do
      let(:io) { StringIO.new.tap { |s| s.sync = true } }
      before do
        allow_any_instance_of(DummyLoggerClass)
          .to receive(:log_config)
          .and_return({level: :info, sink: io})
        DummyLoggerClass.instance_variable_set(:@logger, nil)
      end

      it "uses the provided IO stream" do
        logger = dummy_instance.logger
        logger.info("Hello IO")
        expect(io.string).to include("Hello IO")
      end
    end
  end

  describe "#log" do
    let(:io) { StringIO.new.tap { |s| s.sync = true } }
    before do
      allow_any_instance_of(DummyLoggerClass)
        .to receive(:log_config)
        .and_return({level: :debug, sink: io})
      DummyLoggerClass.instance_variable_set(:@logger, nil)
    end

    it "logs messages at the specified severity" do
      dummy_instance.log(:debug, "Debug message")
      dummy_instance.log(:info, "Info message")
      expect(io.string).to include("Debug message")
      expect(io.string).to include("Info message")
    end

    it "does not log messages when level is :none" do
      allow_any_instance_of(DummyLoggerClass)
        .to receive(:log_config)
        .and_return({level: :none, sink: io})
      dummy_instance.log(:debug, "This should not appear")
      expect(io.string).not_to include("This should not appear")
    end
  end

  describe "#log_level=" do
    let(:io) { StringIO.new.tap { |s| s.sync = true } }
    before do
      allow_any_instance_of(DummyLoggerClass)
        .to receive(:log_config)
        .and_return({level: :info, sink: io})
    end

    it "updates the logger level" do
      dummy_instance.log_level :debug
      expect(dummy_instance.logger.level).to eq(Logger::DEBUG)
    end
  end

  describe "class-level logging" do
    it "provides a logger on the class" do
      DummyLoggerClass.log_level :warn
      logger = DummyLoggerClass.logger
      expect(logger).to be_a(Logger)
      expect(logger.level).to eq(Logger::WARN)
    end

    it "sets the progname appropriately for the class" do
      logger = DummyLoggerClass.logger
      expect(logger.progname).to eq("<Plover/DummyLoggerClass>")
    end
  end
end
