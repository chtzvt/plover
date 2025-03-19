# frozen_string_literal: true

module Plover
  require "shellwords"
  require "fileutils"

  VERSION = "1.1.1"

  class PloverError < StandardError; end

  module Concern
    def self.extended(base)
      base.instance_variable_set(:@_included_blocks, [])
    end

    def included(base = nil, &block)
      return unless base.nil?

      @_included_blocks << block if block_given?
    end

    def class_methods(&block)
      const_set(:ClassMethods, Module.new(&block))
    end

    def apply_concern(base)
      base.extend(const_get(:ClassMethods)) if const_defined?(:ClassMethods)
      @_included_blocks.each { |blk| base.class_eval(&blk) }
      base.include(self)
    end
  end

  module Log
    require "logger"

    def log(severity, msg)
      logger.add(log_severity(severity), msg) unless log_config[:level] == :none
    end

    def log_level(severity)
      log_config[:level] = severity
      @logger = nil
      logger.level = log_severity(log_config[:level])
    end

    def log_severity(severity = nil)
      Logger::Severity.coerce(severity)
    rescue
      Logger::Severity.coerce(:unknown)
    end

    def logger
      sink = case log_config[:sink]
      when String
        f = File.open(log_config[:sink], "a")
        f.sync = true
        f
      when ->(s) { s.respond_to?(:write) }
        log_config[:sink]
      else $stdout
      end

      @logger ||= Logger.new(sink,
        progname: "<Plover/#{is_a?(Class) ? name : self.class.name}>",
        level: log_severity(log_config[:level]))
    end

    def log_config
      is_a?(Class) ? configuration[:options][:log] : @configuration[:options][:log]
    end
  end

  class Builder
    class FlagError < PloverError; end

    class BuildError < PloverError; end

    class ArtifactError < BuildError; end

    module Common; end

    include Log

    attr_reader :configuration

    @configuration = {
      steps: {
        setup: [],
        before_build: [],
        build: [],
        after_build: [],
        teardown: []
      },
      options: {
        flags: {},
        expected_flags: [],
        common_include: :none,
        log: {
          level: :info,
          sink: :stdout
        }
      },
      artifacts: {
        setup: {},
        before_build: {},
        build: {},
        after_build: {},
        teardown: {}
      }
    }

    class << self
      extend Log

      attr_reader :configuration

      def inherited(subclass)
        subclass.extend(Log)
        subclass.instance_variable_set(:@configuration, deep_copy(configuration))
      end

      def set_flag(name, value)
        configuration[:options][:flags][name.to_sym] = value
      end

      def expect_flags(*flags)
        configuration[:options][:expected_flags] = flags.map(&:to_sym)
      end

      def common_include_all
        configuration[:options][:common_include] = :all
      end

      def common_include_none
        configuration[:options][:common_include] = :none
      end

      def log_level(severity)
        configuration[:options][:log][:level] = severity.to_sym
      end

      def log_sink(sink)
        configuration[:options][:log][:sink] = sink
      end

      def common_include(*modules)
        configuration[:options][:common_include] = [] unless configuration[:options][:common_include].is_a?(Array)

        configuration[:options][:common_include].concat(modules)
      end

      def env_flags
        ENV.select { |key, _| key.start_with?("PLOVER_FLAG_") }
          .map { |key, value| [key.sub(/^PLOVER_FLAG_/, "").downcase.to_sym, value] }
          .to_h
      end

      def phase(phase, &block)
        configuration[:steps][phase] << block
      end

      def prepend_phase(phase, &block)
        configuration[:steps][phase].unshift(block)
      end

      def auto_include_common
        return if @configuration[:options][:common_include] == :none

        ObjectSpace.each_object(Module).select { |m| m&.name&.start_with?("Plover::Builder::Common::") }.each do |mod|
          next if mod.name.to_s.end_with?("::ClassMethods")

          next if @configuration[:options][:common_include].is_a?(Array) && !@configuration[:options][:common_include].any? { |m| m == mod.name.split("::").last }

          if mod.respond_to?(:apply_concern) && !included_modules.include?(mod)
            log(:debug, "Loading Common #{mod.name}")
            mod.apply_concern(self)
          end
        end
      end

      def deep_copy(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k] = deep_copy(v) }
        when Array
          obj.map { |e| deep_copy(e) }
        else
          obj
        end
      end
    end

    def initialize(flags = {}, use_env_flags: true)
      @configuration = self.class.configuration

      @configuration[:options][:log][:level] = flags[:log_level] || ENV["PLOVER_LOG_LEVEL"]&.to_sym || @configuration[:options][:log][:level] || :info
      @configuration[:options][:log][:sink] = flags[:log_sink] || ENV["PLOVER_LOG_SINK"] || @configuration[:options][:log][:sink] || :stdout

      @configuration[:options][:flags] = @configuration[:options][:flags].merge(flags).merge(use_env_flags ? self.class.env_flags : {})

      self.class.auto_include_common

      if @configuration[:options][:expected_flags].any?
        missing_flags = @configuration[:options][:expected_flags].reject { |sym| @configuration[:options][:flags].key?(sym) }
        fail_build("Missing required flags: #{missing_flags.join(", ")}") if missing_flags.any?
      end

      log :debug, "Initialized, options=#{@configuration[:options]}"
    end

    def prepend_phase(phase, &block)
      @configuration[:steps][phase].unshift(block)
    end

    def append_phase(phase, &block)
      @configuration[:steps][phase] << block
    end

    def esc(str)
      Shellwords.escape(str)
    end

    def flag(name)
      @configuration[:options][:flags][name.to_sym]
    end

    def esc_flag(name)
      flag(name) ? esc(flag(name)) : nil
    end

    def set_flag(name, value)
      @configuration[:options][:flags][name.to_sym] = value
    end

    def raise_unless_flag(name, message)
      unless flag(name)
        log :fatal, "Missing flag '#{name}': #{message}"
        raise FlagError.new(message)
      end
    end

    def push_artifact(name, value)
      return unless @current_phase
      log :debug, "Pushed artifact name='#{name}' value='#{value}'"
      @configuration[:artifacts][@current_phase][name] = value
    end

    def esc_artifact(phase, name)
      artifact = self.artifact(phase, name)
      artifact ? esc(artifact) : nil
    end

    def artifact(phase, name)
      @configuration[:artifacts][phase][name]
    end

    def artifacts(phase = nil)
      phase ? @configuration[:artifacts][phase] : @configuration[:artifacts]
    end

    def raise_unless_artifact(phase, name, message)
      unless artifact(phase, name)
        log :fatal, "Missing artifact '#{name}': #{message}"
        raise ArtifactError.new(message)
      end
    end

    def fail_build(message)
      log :fatal, "Build failure: #{message}"
      raise BuildError.new(message)
    end

    def run_phase(phase)
      log :debug, "\\/ #{phase.to_s.capitalize} Phase Starting \\/"
      @current_phase = phase
      @configuration[:steps][phase].each { |block| instance_exec(&block) }
      @current_phase = nil
      log :debug, "/\\ #{phase.to_s.capitalize} Phase Finished /\\"
    end

    def run
      run_phase(:setup)
      Dir.chdir(flag(:build_root) || ".") do
        run_phase(:before_build)
        run_phase(:build)
        run_phase(:after_build)
      end
      run_phase(:teardown)
      logger.close
    end
  end
end
