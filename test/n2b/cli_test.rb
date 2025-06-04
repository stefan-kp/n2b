require 'test_helper' # Assumes test_helper.rb exists and sets up load paths correctly
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
      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir)

        cli_instance = N2B::CLI.new(['diff'])
        cli_instance.stubs(:get_vcs_type).returns(:git) # Added stub for vcs_type
        cli_instance.stubs(:execute_vcs_diff).with(:git).returns("") # Updated stub for execute_vcs_diff

        expected_llm_response = {
          "summary" => "No changes found in the diff.",
          "errors" => [],
          "improvements" => []
        }.to_json # Ensure it's a JSON string, as expected by analyze_diff

        # Mock the specific LLM's analyze_code_diff method
        mock_llm_client(N2M::Llm::OpenAi, :analyze_code_diff,
                        regexp_matches(/You are a senior software developer.*Diff:\n```\n\n```.*Return your analysis as a JSON object/m),
                        expected_llm_response)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:\nNo changes found in the diff.", actual_output
        assert_match "Potential Errors:\nNo errors identified.", actual_output
        assert_match "Suggested Improvements:\nNo improvements suggested.", actual_output
      end
    end

    def test_diff_git_repository_with_changes
      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "initial content\n")
        system("git add test_file.txt && git commit -m 'initial commit' -q", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "modified content\n")

        sample_diff = "diff --git a/test_file.txt b/test_file.txt\nindex <hash_a>..<hash_b> 100644\n--- a/test_file.txt\n+++ b/test_file.txt\n@@ -1 +1 @@\n-initial content\n+modified content\n"

        cli_instance = N2B::CLI.new(['diff'])
        cli_instance.stubs(:get_vcs_type).returns(:git) # Added stub
        cli_instance.stubs(:execute_vcs_diff).with(:git).returns(sample_diff) # Updated stub

        llm_response = {
          "summary" => "Modified test_file.txt",
          "errors" => ["One potential error identified."],
          "improvements" => ["Consider adding comments."]
        }.to_json # JSON string

        mock_llm_client(N2M::Llm::OpenAi, :analyze_code_diff,
                        regexp_matches(/You are a senior software developer.*#{Regexp.escape(sample_diff)}.*Return your analysis as a JSON object/m),
                        llm_response)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:\nModified test_file.txt", actual_output
        # For arrays, assert that each item is present if they are printed on separate lines or similar
        assert_match "Potential Errors:\n- One potential error identified.", actual_output
        assert_match "Suggested Improvements:\n- Consider adding comments.", actual_output
      end
    end

    def test_diff_llm_api_error
      Dir.chdir(@tmp_dir) do
        # This test can remain VCS agnostic for the error itself, but we need a valid VCS setup
        # to get past the initial checks. Let's use git for simplicity here.
        system("git init -q .", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "initial content\n")
        system("git add test_file.txt && git commit -m 'initial commit' -q", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "modified content\n")

        sample_diff = "diff --git a/test_file.txt b/test_file.txt\nindex <hash_a>..<hash_b> 100644\n--- a/test_file.txt\n+++ b/test_file.txt\n@@ -1 +1 @@\n-initial content\n+modified content\n"

        cli_instance = N2B::CLI.new(['diff'])
        cli_instance.stubs(:get_vcs_type).returns(:git) # Added stub
        cli_instance.stubs(:execute_vcs_diff).with(:git).returns(sample_diff) # Updated stub

        # Simulate LlmApiError being raised from within call_llm_for_diff_analysis
        # The method itself will catch this, print a message, and return fallback JSON.
        # So, we mock the underlying llm.make_request (via the N2M::Llm::OpenAi/Claude new.make_request chain)
        # or more directly, mock `call_llm_for_diff_analysis` itself if it didn't have the rescue logic.
        # Since the rescue logic IS in `call_llm_for_diff_analysis`, we need to test that it behaves as expected.
        # We can mock the `llm.make_request` part that's *inside* `call_llm_for_diff_analysis`.

        # To do this, we expect the configured LLM's analyze_code_diff method to be called and raise an error.
        llm_class_to_mock = case @mock_config['llm']
                            when 'claude' then N2M::Llm::Claude
                            when 'gemini' then N2M::Llm::Gemini
                            else N2M::Llm::OpenAi # Default to OpenAi as per original test config
                            end

        mock_llm_instance = mock('llm_instance')
        mock_llm_instance.expects(:analyze_code_diff)
          .with(regexp_matches(/You are a senior software developer.*#{Regexp.escape(sample_diff)}.*Return your analysis as a JSON object/m))
          .raises(N2B::LlmApiError.new("Simulated API Error: Connection refused"))

        llm_class_to_mock.expects(:new).with(@mock_config).returns(mock_llm_instance)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        # Check for the user-friendly message printed when LlmApiError is rescued
        assert_match "Error communicating with the LLM: Simulated API Error: Connection refused", actual_output

        # Check for the fallback summary printed by analyze_diff after parsing the fallback JSON
        assert_match "Summary:\nError: Could not analyze diff due to LLM API error.", actual_output
        assert_match "Potential Errors:\nNo errors identified.", actual_output
        assert_match "Suggested Improvements:\nNo improvements suggested.", actual_output
      end
    end

    def test_diff_hg_repository_no_changes
      Dir.chdir(@tmp_dir) do
        system("hg init -q", chdir: @tmp_dir)
        # For hg, an initial commit is needed for `hg diff` to not error or show all files as added.
        # Add a dummy file and commit it.
        File.write(File.join(@tmp_dir, "dummy.txt"), "init\n")
        system("hg add dummy.txt && hg commit -m 'initial commit' -q", chdir: @tmp_dir)

        cli_instance = N2B::CLI.new(['diff'])
        cli_instance.stubs(:get_vcs_type).returns(:hg)
        cli_instance.stubs(:execute_vcs_diff).with(:hg).returns("") # No changes after initial commit

        expected_llm_response = {
          "summary" => "No changes found in the hg diff.",
          "errors" => [],
          "improvements" => []
        }.to_json

        mock_llm_client(N2M::Llm::OpenAi, :analyze_code_diff, # Assuming default mock_config is openai
                        regexp_matches(/You are a senior software developer.*Diff:\n```\n\n```.*Return your analysis as a JSON object/m),
                        expected_llm_response, use_claude_for_hg: false) # Specify not to use claude for hg if it's git

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:\nNo changes found in the hg diff.", actual_output
        assert_match "Potential Errors:\nNo errors identified.", actual_output
        assert_match "Suggested Improvements:\nNo improvements suggested.", actual_output
      end
    end

    def test_diff_hg_repository_with_changes
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

        # For HG tests, let's assume we might want to test with a different LLM, e.g. Claude
        # This requires a bit more flexibility or specific config for the test.
        # For now, let's stick to the default @mock_config['llm'] or make a helper.
        # We'll use a helper `mock_llm_client` that can be adapted if needed.
        mock_llm_client(N2M::Llm::Claude, :analyze_code_diff, # Example: testing hg with Claude
                        regexp_matches(/You are a senior software developer.*#{Regexp.escape(sample_hg_diff)}.*Return your analysis as a JSON object/m),
                        llm_response, use_claude_for_hg: true)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:\nModified test_file.txt in hg", actual_output
        assert_match "Potential Errors:\n- Potential hg error.", actual_output
        assert_match "Suggested Improvements:\n- Consider hg comments.", actual_output
      end
    end

    def test_diff_with_user_prompt_addition
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

        # Verify the prompt passed to call_llm_for_diff_analysis includes all parts
        expected_prompt_regex = Regexp.new(
          [
            Regexp.escape("You are a senior software developer"), # Default system prompt part
            Regexp.escape(sample_diff_for_security),             # The diff
            Regexp.escape("User Instructions:"),                 # User prompt section header
            Regexp.escape(user_prompt_text),                     # The user's actual prompt
            Regexp.escape("Return your analysis as a JSON object") # JSON instruction part
          ].map { |s| Regexp.escape(s) }.join(".*"), # Allow anything between parts
          Regexp::MULTILINE
        )

        # More precise regex for the prompt structure:
        # This checks for key phrases from each section in the correct order.
        prompt_check_regex = /You are a senior software developer.*?Diff:\n```\n#{Regexp.escape(sample_diff_for_security)}\n```.*?User Instructions:\n#{Regexp.escape(user_prompt_text)}.*?Return your analysis as a JSON object/m

        mock_llm_client(N2M::Llm::OpenAi, :analyze_code_diff, prompt_check_regex, expected_llm_response)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:\nSecurity focused review of test_file.txt", actual_output
        assert_match "Potential Errors:\n- Potential SQL injection vector.", actual_output
        assert_match "Suggested Improvements:\n- Sanitize user inputs.", actual_output
      end
    end

    private

    # Helper to mock the LLM client instantiation and method call
    def mock_llm_client(llm_class, method_to_mock, expected_prompt_regex, response_to_return, use_claude_for_hg: false)
      # This helper needs to be smart about the @mock_config
      # If use_claude_for_hg is true, we force Claude for this specific test expectation.
      # Otherwise, we use the LLM defined in @mock_config.

      effective_llm_class = llm_class # Default to passed llm_class

      # Special handling for HG tests if we want them to use a specific LLM (e.g. Claude)
      # This logic might need refinement based on how @mock_config is set for different test types.
      # For simplicity, this example assumes mock_config might be overridden or tests are specific.
      # The `llm_class_to_mock` in `test_diff_llm_api_error` is a good example of selecting the class.

      # Let's refine this: the test should set up its desired mock_config['llm'] if it wants a specific one.
      # This helper will then just use whatever is in @mock_config.

      configured_llm_class = case @mock_config['llm']
                             when 'claude' then N2M::Llm::Claude
                             when 'gemini' then N2M::Llm::Gemini
                             else N2M::Llm::OpenAi # Default
                             end

      mock_instance = mock("#{configured_llm_class.name} instance")
      mock_instance.expects(method_to_mock)
        .with(expected_prompt_regex)
        .returns(response_to_return)

      configured_llm_class.expects(:new).with(@mock_config).returns(mock_instance)
    end

  end
end
