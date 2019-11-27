# frozen_string_literal: true

require "ostruct"

module Homebrew
  module CLI
    class Args < OpenStruct
      attr_accessor :processed_options
      # undefine tap to allow --tap argument
      undef tap

      def initialize(argv:)
        super
        @argv = argv
        @processed_options = []
      end

      def option_to_name(option)
        option.sub(/\A--?/, "")
              .tr("-", "_")
      end

      def cli_args
        return @cli_args if @cli_args

        @cli_args = []
        processed_options.each do |short, long|
          option = long || short
          switch = "#{option_to_name(option)}?".to_sym
          flag = option_to_name(option).to_sym
          if @table[switch] == true || @table[flag] == true
            @cli_args << option
          elsif @table[flag].instance_of? String
            @cli_args << option + "=" + @table[flag]
          elsif @table[flag].instance_of? Array
            @cli_args << option + "=" + @table[flag].join(",")
          end
        end
        @cli_args
      end

      def options_only
        @options_only ||= cli_args.select { |arg| arg.start_with?("-") }
      end

      def flags_only
        @flags_only ||= cli_args.select { |arg| arg.start_with?("--") }
      end

      def passthrough
        options_only - CLI::Parser.global_options.values.map(&:first).flatten
      end

      def downcased_unique_named
        # Only lowercase names, not paths, bottle filenames or URLs
        @downcased_unique_named ||= remaining.map do |arg|
          if arg.include?("/") || arg.end_with?(".tar.gz") || File.exist?(arg)
            arg
          else
            arg.downcase
          end
        end.uniq
      end

      def kegs
        require "keg"
        require "formula"
        require "missing_formula"

        @kegs ||= downcased_unique_named.map do |name|
          raise UsageError if name.empty?

          rack = Formulary.to_rack(name.downcase)

          dirs = rack.directory? ? rack.subdirs : []

          if dirs.empty?
            if (reason = Homebrew::MissingFormula.suggest_command(name, "uninstall"))
              $stderr.puts reason
            end
            raise NoSuchKegError, rack.basename
          end

          linked_keg_ref = HOMEBREW_LINKED_KEGS/rack.basename
          opt_prefix = HOMEBREW_PREFIX/"opt/#{rack.basename}"

          begin
            if opt_prefix.symlink? && opt_prefix.directory?
              Keg.new(opt_prefix.resolved_path)
            elsif linked_keg_ref.symlink? && linked_keg_ref.directory?
              Keg.new(linked_keg_ref.resolved_path)
            elsif dirs.length == 1
              Keg.new(dirs.first)
            else
              f = if name.include?("/") || File.exist?(name)
                Formulary.factory(name)
              else
                Formulary.from_rack(rack)
              end

              unless (prefix = f.installed_prefix).directory?
                raise MultipleVersionsInstalledError, rack.basename
              end

              Keg.new(prefix)
            end
          rescue FormulaUnavailableError
            raise <<~EOS
              Multiple kegs installed to #{rack}
              However we don't know which one you refer to.
              Please delete (with rm -rf!) all but one and then try again.
            EOS
          end
        end
      end
    end
  end
end
