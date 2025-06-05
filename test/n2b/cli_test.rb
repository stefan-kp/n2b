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
        # Ensure any other expected keys by N2B::CLI's get_config/config usage are present
      }
      # Stub get_config for any instance of CLI that might be created.
      # This avoids issues if Base#get_config is more complex or if CLI overrides it.
      N2B::CLI.any_instance.stubs(:get_config).returns(@mock_config)
      @mock_jira_client = mock('jira_client') # Common mock for JiraClient
    end

    # Helper methods to check if VCS tools are available
    def git_available?
      system('git --version > /dev/null 2>&1')
    end

    def hg_available?
      system('hg --version > /dev/null 2>&1')
    end

    def teardown
      # Restore the original CONFIG_FILE constant to protect user's config
      N2B::Base.send(:remove_const, :CONFIG_FILE) if N2B::Base.const_defined?(:CONFIG_FILE)
      N2B::Base.const_set(:CONFIG_FILE, @original_config_file)

      FileUtils.rm_rf(@tmp_dir)
      $stdout = @original_stdout
      $stderr = @original_stderr
    end

    def test_diff_not_a_vcs_repository # Renamed
      Dir.chdir(@tmp_dir) do
        cli_instance = N2B::CLI.new(['--diff'])
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

        cli_instance = N2B::CLI.new(['--diff'])
        cli_instance.stubs(:get_vcs_type).returns(:git)
        cli_instance.stubs(:execute_vcs_diff).with(:git, nil).returns("")

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

        cli_instance = N2B::CLI.new(['--diff'])
        cli_instance.stubs(:get_vcs_type).returns(:git)
        cli_instance.stubs(:execute_vcs_diff).with(:git, nil).returns(sample_diff)

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

        cli_instance = N2B::CLI.new(['--diff'])
        cli_instance.stubs(:get_vcs_type).returns(:git)
        cli_instance.stubs(:execute_vcs_diff).with(:git, nil).returns(sample_diff)

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

        cli_instance = N2B::CLI.new(['--diff'])
        cli_instance.stubs(:get_vcs_type).returns(:hg)
        cli_instance.stubs(:execute_vcs_diff).with(:hg, nil).returns("")

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

        cli_instance = N2B::CLI.new(['--diff'])
        cli_instance.stubs(:get_vcs_type).returns(:hg)
        cli_instance.stubs(:execute_vcs_diff).with(:hg, nil).returns(sample_hg_diff)

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

        # Simulate CLI arguments: n2b --diff "focus on security aspects"
        cli_instance = N2B::CLI.new(['--diff', user_prompt_text])
        cli_instance.stubs(:get_vcs_type).returns(:git)
        cli_instance.stubs(:execute_vcs_diff).with(:git, nil).returns(sample_diff_for_security)

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

    private

    def create_dummy_requirements_file(filename: "reqs.txt", content: "Default requirement: The code must be efficient.")
      req_path = File.join(@tmp_dir, filename)
      File.write(req_path, content)
      req_path
    end

    # --- Tests for new CLI options ---
    def test_cli_jira_options_parsing
      # Test -j <ticket_id>
      options = N2B::CLI.new(['-d', '-j', 'TEST-123']).instance_variable_get(:@options)
      assert_equal 'TEST-123', options[:jira_ticket]
      assert_nil options[:jira_update] # Default

      # Test -j <url>
      options = N2B::CLI.new(['-d', '-j', 'https://example.com/browse/TEST-456']).instance_variable_get(:@options)
      assert_equal 'https://example.com/browse/TEST-456', options[:jira_ticket]
      assert_nil options[:jira_update]

      # Test --jira-update
      options = N2B::CLI.new(['-d', '-j', 'TEST-123', '--jira-update']).instance_variable_get(:@options)
      assert_equal 'TEST-123', options[:jira_ticket]
      assert_equal true, options[:jira_update]

      # Test --jira-no-update
      options = N2B::CLI.new(['-d', '-j', 'TEST-123', '--jira-no-update']).instance_variable_get(:@options)
      assert_equal 'TEST-123', options[:jira_ticket]
      assert_equal false, options[:jira_update]

      # Test --advanced-config
      options = N2B::CLI.new(['--advanced-config']).instance_variable_get(:@options)
      assert_equal true, options[:advanced_config]
      assert_equal true, options[:config] # Should also trigger normal config mode

      # Test invalid: --jira-update without -j
      assert_raises(OptionParser::InvalidOption) do # Or check for exit and error message if that's the behavior
         N2B::CLI.new(['-d', '--jira-update']) # This should be caught by OptionParser logic in CLI
      end
    end

    # --- Tests for diff analysis with Jira integration ---
    def test_handle_diff_analysis_with_jira_ticket_fetch_success
      skip "Git not available" unless git_available?
      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir) # Basic git setup

        cli_instance = N2B::CLI.new(['--diff', '-j', 'PROJ-1'])
        # Stub VCS methods
        cli_instance.stubs(:get_vcs_type).returns(:git)
        cli_instance.stubs(:execute_vcs_diff).returns("sample diff")

        # Mock JiraClient
        N2B::JiraClient.expects(:new).with(@mock_config).returns(@mock_jira_client)
        @mock_jira_client.expects(:fetch_ticket).with('PROJ-1').returns("Jira ticket PROJ-1 description content.")

        # Mock LLM call for diff analysis
        mock_llm_instance = mock('llm_instance')
        mock_llm_instance.expects(:analyze_code_diff)
          .with(includes("Jira ticket PROJ-1 description content.")) # Ensure Jira content is in prompt
          .returns({ 'summary' => 'Analysis with Jira content', 'errors' => [], 'improvements' => [], 'ticket_implementation_summary' => 'Implemented based on Jira.' }.to_json)
        N2M::Llm::OpenAi.expects(:new).with(@mock_config).returns(mock_llm_instance) # Assuming OpenAi is default or configured

        cli_instance.execute

        $stdout.rewind
        output = $stdout.string
        assert_match "Fetching Jira ticket details...", output
        assert_match "Successfully fetched Jira ticket details.", output
        assert_match "Analysis with Jira content", output # Check LLM summary in output
        assert_match "Implemented based on Jira.", output # Check ticket_implementation_summary
      end
    end

    def test_handle_diff_analysis_with_jira_ticket_fetch_failure
      skip "Git not available" unless git_available?
      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir)

        cli_instance = N2B::CLI.new(['--diff', '-j', 'PROJ-2'])
        cli_instance.stubs(:get_vcs_type).returns(:git)
        cli_instance.stubs(:execute_vcs_diff).returns("sample diff")

        N2B::JiraClient.expects(:new).with(@mock_config).returns(@mock_jira_client)
        @mock_jira_client.expects(:fetch_ticket).with('PROJ-2').raises(N2B::JiraClient::JiraApiError.new("Failed to connect"))

        mock_llm_instance = mock('llm_instance')
        # Prompt should NOT contain Jira content
        mock_llm_instance.expects(:analyze_code_diff)
          .with(Not(includes("Jira ticket PROJ-2 description content.")))
          .returns({ 'summary' => 'Analysis without Jira content', 'errors' => [], 'improvements' => [], 'ticket_implementation_summary' => 'Standard implementation.' }.to_json)
        N2M::Llm::OpenAi.expects(:new).with(@mock_config).returns(mock_llm_instance)

        cli_instance.execute
        $stdout.rewind
        output = $stdout.string
        assert_match "Error fetching Jira ticket: Failed to connect", output
        assert_match "Proceeding with diff analysis without Jira ticket details.", output
        assert_match "Analysis without Jira content", output
      end
    end

    # --- Tests for Jira Update Flow ---
    def test_handle_diff_analysis_jira_update_flow
      skip "Git not available" unless git_available?
      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir)

        # Common setup for update flow tests
        analysis_result_hash = {
          'summary' => 'Test summary', 'errors' => [], 'improvements' => [],
          'test_coverage' => 'Good', 'ticket_implementation_summary' => 'Implemented feature X.'
        }
        formatted_jira_comment = N2B::CLI.new([]).send(:format_analysis_for_jira, analysis_result_hash) # Get an instance for formatting

        # Mock LLM part of analyze_diff to return our hash
        # We need to allow analyze_diff to be called, but control its output
        N2B::CLI.any_instance.stubs(:call_llm_for_diff_analysis).returns(analysis_result_hash.to_json)


        # Scenario 1: --jira-update flag
        cli_update = N2B::CLI.new(['--diff', '-j', 'PROJ-UP1', '--jira-update'])
        cli_update.stubs(:get_vcs_type).returns(:git)
        cli_update.stubs(:execute_vcs_diff).returns("diff for update")
        N2B::JiraClient.expects(:new).twice.with(@mock_config).returns(@mock_jira_client) # Once for fetch, once for update
        @mock_jira_client.expects(:fetch_ticket).with('PROJ-UP1').returns("Jira content for PROJ-UP1")
        @mock_jira_client.expects(:update_ticket).with('PROJ-UP1', formatted_jira_comment).returns(true)

        cli_update.execute
        $stdout.rewind
        assert_match "Jira ticket PROJ-UP1 updated successfully.", $stdout.string

        # Scenario 2: --jira-no-update flag
        @mock_jira_client.unstub(:update_ticket) # Clear previous expectation
        @mock_jira_client.expects(:update_ticket).never # Should not be called

        cli_no_update = N2B::CLI.new(['--diff', '-j', 'PROJ-NOUP', '--jira-no-update'])
        cli_no_update.stubs(:get_vcs_type).returns(:git)
        cli_no_update.stubs(:execute_vcs_diff).returns("diff for no update")
        # N2B::JiraClient.expects(:new).with(@mock_config).returns(@mock_jira_client) # Already expected for fetch
        @mock_jira_client.expects(:fetch_ticket).with('PROJ-NOUP').returns("Jira content for PROJ-NOUP")

        cli_no_update.execute
        $stdout.rewind
        assert_match "Jira ticket update skipped.", $stdout.string

        # Scenario 3: No update flag, user prompts 'y'
        @mock_jira_client.unstub(:update_ticket)
        @mock_jira_client.expects(:update_ticket).with('PROJ-PROMPT-Y', formatted_jira_comment).returns(true)

        cli_prompt_y = N2B::CLI.new(['--diff', '-j', 'PROJ-PROMPT-Y'])
        cli_prompt_y.stubs(:get_vcs_type).returns(:git)
        cli_prompt_y.stubs(:execute_vcs_diff).returns("diff for prompt y")
        # N2B::JiraClient.expects(:new).twice.with(@mock_config).returns(@mock_jira_client) # Fetch and update
        @mock_jira_client.expects(:fetch_ticket).with('PROJ-PROMPT-Y').returns("Jira content for PROJ-PROMPT-Y")

        mock_stdin_y = StringIO.new("y\n")
        original_stdin = $stdin
        $stdin = mock_stdin_y
        begin
          cli_prompt_y.execute
        ensure
          $stdin = original_stdin
        end
        $stdout.rewind
        assert_match "Would you like to update Jira ticket PROJ-PROMPT-Y", $stdout.string
        assert_match "Jira ticket PROJ-PROMPT-Y updated successfully.", $stdout.string

        # Scenario 4: No update flag, user prompts 'n'
        @mock_jira_client.unstub(:update_ticket)
        @mock_jira_client.expects(:update_ticket).never

        cli_prompt_n = N2B::CLI.new(['--diff', '-j', 'PROJ-PROMPT-N'])
        cli_prompt_n.stubs(:get_vcs_type).returns(:git)
        cli_prompt_n.stubs(:execute_vcs_diff).returns("diff for prompt n")
        # N2B::JiraClient.expects(:new).with(@mock_config).returns(@mock_jira_client) # Fetch only
        @mock_jira_client.expects(:fetch_ticket).with('PROJ-PROMPT-N').returns("Jira content for PROJ-PROMPT-N")

        mock_stdin_n = StringIO.new("n\n")
        $stdin = mock_stdin_n
        begin
          cli_prompt_n.execute
        ensure
          $stdin = original_stdin
        end
        $stdout.rewind
        assert_match "Jira ticket update skipped.", $stdout.string
      end
    end

    # --- Test for advanced_config flag being passed to get_config ---
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
      # We need to prevent execute from trying to run a command or diff analysis.
      # Since --advanced-config implies -c, ARGS will be empty, leading to interactive prompt.
      cli_instance.stubs(:process_natural_language_command) # Stub to prevent interactive input

      # Mock $stdin for the "Enter your natural language command:" prompt
      mock_stdin_empty_command = StringIO.new("do nothing\n")
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
