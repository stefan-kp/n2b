require_relative '../test_helper' # Assumes test_helper.rb exists and sets up load paths correctly
require 'n2b/cli'
require 'n2b/jira_client' # Added for JiraClient mocking
require 'minitest/autorun'
require 'mocha/minitest'
require 'fileutils'
require 'stringio' # To capture stdout
require 'json'     # For .to_json

# Stubbing dependent classes if not loaded by test_helper for robustness in testing environment.
# Ideally, test_helper.rb or the main library file (e.g., n2b.rb) would ensure all dependencies are loaded.
if !defined?(N2M::Llm::OpenAi)
  module N2M; module Llm; class OpenAi; def initialize(config); end; def make_request(prompt); ""; end; end; end; end
end
if !defined?(N2M::Llm::Claude)
  module N2M; module Llm; class Claude; def initialize(config); end; def make_request(prompt); ""; end; end; end; end
end
if !defined?(N2B::Base) # Assuming CLI inherits from Base or uses it.
  module N2B
    class Base
      # Define a basic get_config if CLI instances call it (e.g., super in initialize or directly)
      def get_config(reconfigure: false)
        {
          'llm' => 'openai', # Default mock
          'privacy' => {
            'send_current_directory' => false,
            'send_llm_history' => false,
            'send_shell_history' => false
          },
          'append_to_shell_history' => false
        }
      end
    end
  end
end


module N2B
  class CLITest < Minitest::Test
    def setup
      @tmp_dir = File.expand_path("./tmp_test_n2b_cli_dir", Dir.pwd) # Ensure tmp dir is uniquely named and local
      FileUtils.mkdir_p(@tmp_dir)

      @original_stdout = $stdout
      $stdout = StringIO.new
      @original_stderr = $stderr
      $stderr = StringIO.new

      # CRITICAL: Protect user's config file by using a test-specific config file
      @test_config_file = File.join(@tmp_dir, 'test_config.yml')
      @original_config_file = N2B::Base::CONFIG_FILE
      # Override the CONFIG_FILE constant for tests
      N2B::Base.send(:remove_const, :CONFIG_FILE) if N2B::Base.const_defined?(:CONFIG_FILE)
      N2B::Base.const_set(:CONFIG_FILE, @test_config_file)

      # Centralized config stubbing for all tests
      @mock_config = {
        'llm' => 'openai',
        'privacy' => {
          'send_current_directory' => false,
          'send_llm_history' => false,
          'send_shell_history' => false
        },
        'append_to_shell_history' => false,
        # 'issue_tracker' => 'jira', # Removed as CLI no longer directly handles issue trackers
        # Ensure any other expected keys by N2B::CLI's get_config/config usage are present
      }
      # Stub get_config for any instance of CLI that might be created.
      # This avoids issues if Base#get_config is more complex or if CLI overrides it.
      N2B::CLI.any_instance.stubs(:get_config).returns(@mock_config)
      # @mock_jira_client = mock('jira_client') # Removed as CLI no longer uses JiraClient directly
    end

    # Helper methods to check if VCS tools are available
    # def git_available? # Removed as no longer needed for CLI tests
    #   system('git --version > /dev/null 2>&1')
    # end

    # def hg_available? # Removed as no longer needed for CLI tests
    #   system('hg --version > /dev/null 2>&1')
    # end

    def teardown
      # Restore the original CONFIG_FILE constant to protect user's config
      N2B::Base.send(:remove_const, :CONFIG_FILE) if N2B::Base.const_defined?(:CONFIG_FILE)
      N2B::Base.const_set(:CONFIG_FILE, @original_config_file)

      FileUtils.rm_rf(@tmp_dir)
      $stdout = @original_stdout
      $stderr = @original_stderr
    end

    # New Test 1: Natural language command processing (not 'diff')
    def test_natural_language_command_processing
      command_text = "list all ruby files"
      cli_instance = N2B::CLI.new([command_text]) # Simulates `n2b "list all ruby files"`

      expected_llm_commands = {
        'commands' => ["find . -name '*.rb'"],
        'explanation' => "This command finds all files with the .rb extension in the current directory and its subdirectories."
      }

      # Mock the call_llm method itself, as it's the entry point for this type of command
      cli_instance.expects(:call_llm).with(command_text, @mock_config).returns(expected_llm_commands)

      @mock_config['append_to_shell_history'] = true
      cli_instance.expects(:add_to_shell_history).with(expected_llm_commands['commands'].join("\n")).once

      cli_instance.execute

      $stdout.rewind
      actual_output = $stdout.string

      assert_match "Translated #{cli_instance.send(:get_user_shell)} Commands:", actual_output
      assert_match "------------------------", actual_output
      assert_match expected_llm_commands['commands'].first, actual_output
      assert_match "Explanation:", actual_output
      assert_match expected_llm_commands['explanation'], actual_output
    end

    # New Test 2: Natural language command processing with -x (execute)
    def test_natural_language_command_processing_with_execute_option
      command_text = "create a temp dir"
      cli_instance = N2B::CLI.new(['-x', command_text])

      expected_llm_commands = {
        'commands' => ["mkdir /tmp/my_temp_dir"],
        'explanation' => "Creates a directory named my_temp_dir in /tmp."
      }

      cli_instance.expects(:call_llm).with(command_text, @mock_config).returns(expected_llm_commands)

      mock_stdin = StringIO.new
      mock_stdin.puts # Simulate user pressing Enter
      mock_stdin.rewind
      original_stdin = $stdin
      $stdin = mock_stdin

      cli_instance.expects(:system).with(expected_llm_commands['commands'].join("\n")).returns(true).once

      begin
        cli_instance.execute
      ensure
        $stdin = original_stdin
      end

      $stdout.rewind
      actual_output = $stdout.string

      assert_match "Translated #{cli_instance.send(:get_user_shell)} Commands:", actual_output
      assert_match expected_llm_commands['commands'].first, actual_output
      assert_match "Press Enter to execute these commands, or Ctrl+C to cancel.", actual_output
    end

    # New Test 3: Config option triggers get_config with reconfigure true
    def test_config_option_triggers_reconfigure
      N2B::CLI.any_instance.unstub(:get_config)

      mock_config_for_reconfigure_test = @mock_config.dup
      # Expect get_config to be called with reconfigure: true and advanced_flow: false on the instance
      N2B::CLI.any_instance.expects(:get_config).with(reconfigure: true, advanced_flow: false).returns(mock_config_for_reconfigure_test).once

      cli_instance = N2B::CLI.new(['-c'])

      # Stub process_natural_language_command because ARGV will be empty for command part,
      # leading to interactive input which we don't want in this specific test.
      cli_instance.stubs(:process_natural_language_command)
      # Also stub the $stdin.gets for the "Enter your natural language command:" prompt
      # that occurs if command.nil? && user_input.empty?
      mock_stdin_empty_command = StringIO.new
      mock_stdin_empty_command.puts "do nothing" # Provide some input to avoid blocking
      mock_stdin_empty_command.rewind
      original_stdin_empty = $stdin
      $stdin = mock_stdin_empty_command

      begin
        cli_instance.execute
      ensure
        $stdin = original_stdin_empty # Restore original $stdin
      end

      # Restore the general stub for other tests
      N2B::CLI.any_instance.unstub(:get_config)
      N2B::CLI.any_instance.stubs(:get_config).returns(@mock_config)
    end

    # private # create_dummy_requirements_file was here, removed as it's no longer used.

    # --- Test for advanced_config flag being passed to get_config ---
    # This test remains relevant as --advanced-config is still a valid option for n2b (cli.rb)
    def test_advanced_config_flag_passed_to_get_config
      # Unstub get_config for this specific test to verify its arguments
      N2B::CLI.any_instance.unstub(:get_config)

      # Expect get_config to be called with advanced_flow: true
      # The actual config process will be complex to mock here, so focus on param passing.
      N2B::CLI.any_instance.expects(:get_config)
        .with(reconfigure: true, advanced_flow: true) # --advanced-config implies reconfigure: true
        .returns(@mock_config) # Return the standard mock_config to allow execution to continue
        .once

      cli_instance = N2B::CLI.new(['--advanced-config'])
      # We need to prevent execute from trying to run a command.
      # Since --advanced-config implies -c, ARGS will be empty for the command part,
      # potentially leading to interactive prompt if not stubbed.
      cli_instance.stubs(:process_natural_language_command)

      # Mock $stdin for the "Enter your natural language command:" prompt that occurs
      # if command is nil and user_input is empty.
      mock_stdin_empty_command = StringIO.new("do nothing to prevent blocking\n")
      original_stdin_empty = $stdin
      $stdin = mock_stdin_empty_command

      begin
        cli_instance.execute
      ensure
        $stdin = original_stdin_empty
      end

      # Restore the general stub for other tests
      N2B::CLI.any_instance.stubs(:get_config).returns(@mock_config)
    end

  end
end
