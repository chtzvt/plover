# frozen_string_literal: true

module Plover
  require "shellwords"
  require "fileutils"

  VERSION = "1.0.0"

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

  class Builder
    class FlagError < PloverError; end

    class BuildError < PloverError; end

    class ArtifactError < BuildError; end

    module Common; end

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
        expected_flags: []
      },
      include_common: :none,
      artifacts: {
        setup: {},
        before_build: {},
        build: {},
        after_build: {},
        teardown: {}
      }
    }

    class << self
      attr_reader :configuration

      def inherited(subclass)
        auto_include_common
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
        return if configuration[:options][:common_include] == :none

        ObjectSpace.each_object(Module).select { |m| m&.name&.start_with?("Plover::Builder::Common::") }.each do |mod|
          next if mod.name.to_s.end_with?("::ClassMethods")

          next if configuration[:options][:common_include].is_a?(Array) && !configuration[:options][:common_include].any? { |m| m.end_with?("::#{mod.name}") }

          mod.apply_concern(self) if mod.respond_to?(:apply_concern) && !included_modules.include?(mod)
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

    def initialize(flags = {})
      self.class.auto_include_common
      @configuration = self.class.configuration
      @configuration[:options][:flags] = @configuration[:options][:flags].merge(flags).merge(self.class.env_flags)

      return unless @configuration[:options][:expected_flags].any?

      missing_flags = @configuration[:options][:expected_flags].reject { |sym| @configuration[:options][:flags].key?(sym) }
      raise BuildError.new("Missing required flags: #{missing_flags.join(", ")}") if missing_flags.any?
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
      raise FlagError.new(message) unless flag(name)
    end

    def push_artifact(name, value)
      return unless @current_phase
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
      raise ArtifactError.new(message) unless artifact(phase, name)
    end

    def fail_build(message)
      raise BuildError.new(message)
    end

    def run_phase(phase)
      @current_phase = phase
      @configuration[:steps][phase].each { |block| instance_exec(&block) }
      @current_phase = nil
    end

    def run
      run_phase(:setup)
      Dir.chdir(flag(:build_root) || ".") do
        run_phase(:before_build)
        run_phase(:build)
        run_phase(:after_build)
      end
      run_phase(:teardown)
    end
  end
end
