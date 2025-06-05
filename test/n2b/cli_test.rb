require_relative '../test_helper' # Assumes test_helper.rb exists and sets up load paths correctly
require 'n2b/cli'
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

      # Centralized config stubbing for all tests
      @mock_config = {
        'llm' => 'openai',
        'privacy' => {
          'send_current_directory' => false,
          'send_llm_history' => false,
          'send_shell_history' => false
        },
        'append_to_shell_history' => false,
        # Ensure any other expected keys by N2B::CLI's get_config/config usage are present
      }
      # Stub get_config for any instance of CLI that might be created.
      # This avoids issues if Base#get_config is more complex or if CLI overrides it.
      N2B::CLI.any_instance.stubs(:get_config).returns(@mock_config)
    end

    # Helper methods to check if VCS tools are available
    def git_available?
      system('git --version > /dev/null 2>&1')
    end

    def hg_available?
      system('hg --version > /dev/null 2>&1')
    end

    def teardown
      FileUtils.rm_rf(@tmp_dir)
      $stdout = @original_stdout
      $stderr = @original_stderr
    end

    def test_diff_not_a_vcs_repository # Renamed
      Dir.chdir(@tmp_dir) do
        cli_instance = N2B::CLI.new(['diff'])
        cli_instance.stubs(:get_vcs_type).returns(:none) # Updated stub

        ex = assert_raises(SystemExit) { cli_instance.execute }

        $stdout.rewind
        output = $stdout.string
        assert_match "Error: Not a git or hg repository.", output # Updated message
        assert_equal 1, ex.status
      end
    end

    def test_diff_git_repository_no_changes
      skip "Git not available" unless git_available?

      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir)

        cli_instance = N2B::CLI.new(['diff'])
        cli_instance.stubs(:get_vcs_type).returns(:git)
        cli_instance.stubs(:execute_vcs_diff).with(:git).returns("")

        expected_llm_response = {
          "summary" => "No changes found in the diff.",
          "errors" => [],
          "improvements" => []
        }.to_json

        # Mock the LLM client with a simple expectation (no complex regex)
        mock_llm_instance = mock('llm_instance')
        mock_llm_instance.expects(:analyze_code_diff).with(anything).returns(expected_llm_response)
        N2M::Llm::OpenAi.expects(:new).with(@mock_config).returns(mock_llm_instance)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:", actual_output
        assert_match "No changes found in the diff.", actual_output
      end
    end

    def test_diff_git_repository_with_changes
      skip "Git not available" unless git_available?

      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "initial content\n")
        system("git add test_file.txt && git commit -m 'initial commit' -q", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "modified content\n")

        sample_diff = "diff --git a/test_file.txt b/test_file.txt\nindex <hash_a>..<hash_b> 100644\n--- a/test_file.txt\n+++ b/test_file.txt\n@@ -1 +1 @@\n-initial content\n+modified content\n"

        cli_instance = N2B::CLI.new(['diff'])
        cli_instance.stubs(:get_vcs_type).returns(:git)
        cli_instance.stubs(:execute_vcs_diff).with(:git).returns(sample_diff)

        llm_response = {
          "summary" => "Modified test_file.txt",
          "errors" => ["One potential error identified."],
          "improvements" => ["Consider adding comments."]
        }.to_json

        # Mock the LLM client with a simple expectation (no complex regex)
        mock_llm_instance = mock('llm_instance')
        mock_llm_instance.expects(:analyze_code_diff).with(anything).returns(llm_response)
        N2M::Llm::OpenAi.expects(:new).with(@mock_config).returns(mock_llm_instance)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:", actual_output
        assert_match "Modified test_file.txt", actual_output
      end
    end

    def test_diff_llm_api_error
      skip "Git not available" unless git_available?

      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "initial content\n")
        system("git add test_file.txt && git commit -m 'initial commit' -q", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "modified content\n")

        sample_diff = "diff --git a/test_file.txt b/test_file.txt\nindex <hash_a>..<hash_b> 100644\n--- a/test_file.txt\n+++ b/test_file.txt\n@@ -1 +1 @@\n-initial content\n+modified content\n"

        cli_instance = N2B::CLI.new(['diff'])
        cli_instance.stubs(:get_vcs_type).returns(:git)
        cli_instance.stubs(:execute_vcs_diff).with(:git).returns(sample_diff)

        # Mock the LLM to raise an API error
        mock_llm_instance = mock('llm_instance')
        mock_llm_instance.expects(:analyze_code_diff)
          .with(anything)
          .raises(N2B::LlmApiError.new("Simulated API Error: Connection refused"))

        N2M::Llm::OpenAi.expects(:new).with(@mock_config).returns(mock_llm_instance)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        # Check for the user-friendly message printed when LlmApiError is rescued
        assert_match "Error communicating with the LLM:", actual_output
        assert_match "Summary:", actual_output
      end
    end

    def test_diff_hg_repository_no_changes
      skip "Mercurial (hg) not available" unless hg_available?

      Dir.chdir(@tmp_dir) do
        system("hg init -q", chdir: @tmp_dir)
        # For hg, an initial commit is needed for `hg diff` to not error or show all files as added.
        # Add a dummy file and commit it.
        File.write(File.join(@tmp_dir, "dummy.txt"), "init\n")
        system("hg add dummy.txt && hg commit -m 'initial commit' -q", chdir: @tmp_dir)

        cli_instance = N2B::CLI.new(['diff'])
        cli_instance.stubs(:get_vcs_type).returns(:hg)
        cli_instance.stubs(:execute_vcs_diff).with(:hg).returns("")

        expected_llm_response = {
          "summary" => "No changes found in the hg diff.",
          "errors" => [],
          "improvements" => []
        }.to_json

        # Mock the LLM client with a simple expectation (no complex regex)
        mock_llm_instance = mock('llm_instance')
        mock_llm_instance.expects(:analyze_code_diff).with(anything).returns(expected_llm_response)
        N2M::Llm::OpenAi.expects(:new).with(@mock_config).returns(mock_llm_instance)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:", actual_output
        assert_match "No changes found in the hg diff.", actual_output
      end
    end

    def test_diff_hg_repository_with_changes
      skip "Mercurial (hg) not available" unless hg_available?

      Dir.chdir(@tmp_dir) do
        system("hg init -q", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "initial hg content\n")
        system("hg add test_file.txt && hg commit -m 'initial hg commit' -q", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "modified hg content\n")

        # A simplified hg diff output for testing purposes
        sample_hg_diff = "diff -r <rev_hash> test_file.txt\n--- a/test_file.txt\n+++ b/test_file.txt\n@@ -1 +1 @@\n-initial hg content\n+modified hg content\n"

        cli_instance = N2B::CLI.new(['diff'])
        cli_instance.stubs(:get_vcs_type).returns(:hg)
        cli_instance.stubs(:execute_vcs_diff).with(:hg).returns(sample_hg_diff)

        llm_response = {
          "summary" => "Modified test_file.txt in hg",
          "errors" => ["Potential hg error."],
          "improvements" => ["Consider hg comments."]
        }.to_json

        # Mock the LLM client with a simple expectation (no complex regex)
        mock_llm_instance = mock('llm_instance')
        mock_llm_instance.expects(:analyze_code_diff).with(anything).returns(llm_response)
        N2M::Llm::OpenAi.expects(:new).with(@mock_config).returns(mock_llm_instance)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:", actual_output
        assert_match "Modified test_file.txt in hg", actual_output
      end
    end

    def test_diff_with_user_prompt_addition
      skip "Git not available" unless git_available?

      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "initial content\n")
        system("git add test_file.txt && git commit -m 'initial commit' -q", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "modified content for security review\n")

        sample_diff_for_security = "diff --git a/test_file.txt b/test_file.txt\n--- a/test_file.txt\n+++ b/test_file.txt\n@@ -1 +1 @@\n-initial content\n+modified content for security review\n"
        user_prompt_text = "focus on security aspects"

        # Simulate CLI arguments: n2b diff "focus on security aspects"
        cli_instance = N2B::CLI.new(['diff', user_prompt_text])
        cli_instance.stubs(:get_vcs_type).returns(:git)
        cli_instance.stubs(:execute_vcs_diff).with(:git).returns(sample_diff_for_security)

        expected_llm_response = {
          "summary" => "Security focused review of test_file.txt",
          "errors" => ["Potential SQL injection vector."],
          "improvements" => ["Sanitize user inputs."]
        }.to_json

        # Mock the LLM client with a simple expectation (no complex regex)
        # We just verify that the LLM is called with some prompt that includes the user's text
        mock_llm_instance = mock('llm_instance')
        mock_llm_instance.expects(:analyze_code_diff).with(includes(user_prompt_text)).returns(expected_llm_response)
        N2M::Llm::OpenAi.expects(:new).with(@mock_config).returns(mock_llm_instance)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:", actual_output
        assert_match "Security focused review of test_file.txt", actual_output
      end
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
      # Expect get_config to be called with reconfigure: true on the instance
      N2B::CLI.any_instance.expects(:get_config).with(reconfigure: true).returns(mock_config_for_reconfigure_test).once

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

    private

    def create_dummy_requirements_file(filename: "reqs.txt", content: "Default requirement: The code must be efficient.")
      req_path = File.join(@tmp_dir, filename)
      File.write(req_path, content)
      req_path
    end



  end
end
