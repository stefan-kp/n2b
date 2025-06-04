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

    def test_div_not_a_git_repository
      Dir.chdir(@tmp_dir) do
        cli_instance = N2B::CLI.new(['div'])
        # Ensure the instance uses the mocked methods
        cli_instance.stubs(:is_git_repository?).returns(false)

        ex = assert_raises(SystemExit) { cli_instance.execute }

        $stdout.rewind
        output = $stdout.string
        assert_match "Error: Not a git repository.", output
        assert_equal 1, ex.status
      end
    end

    def test_div_git_repository_no_changes
      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir) # Run git init in the temp dir

        cli_instance = N2B::CLI.new(['div'])
        cli_instance.stubs(:is_git_repository?).returns(true)
        cli_instance.stubs(:execute_git_diff).returns("") # No changes

        expected_llm_response = {
          "summary" => "No changes found in the diff.",
          "errors" => [],
          "improvements" => []
        }.to_json # Ensure it's a JSON string, as expected by analyze_diff

        cli_instance.expects(:call_llm_for_diff_analysis)
          .with(regexp_matches(/Diff:\n```\n\n```/m), @mock_config) # also check config is passed
          .returns(expected_llm_response)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:\nNo changes found in the diff.", actual_output
        assert_match "Potential Errors:\nNo errors identified.", actual_output
        assert_match "Suggested Improvements:\nNo improvements suggested.", actual_output
      end
    end

    def test_div_git_repository_with_changes
      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "initial content\n")
        system("git add test_file.txt && git commit -m 'initial commit' -q", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "modified content\n")

        sample_diff = "diff --git a/test_file.txt b/test_file.txt\nindex <hash_a>..<hash_b> 100644\n--- a/test_file.txt\n+++ b/test_file.txt\n@@ -1 +1 @@\n-initial content\n+modified content\n"

        cli_instance = N2B::CLI.new(['div'])
        cli_instance.stubs(:is_git_repository?).returns(true)
        cli_instance.stubs(:execute_git_diff).returns(sample_diff)

        llm_response = {
          "summary" => "Modified test_file.txt",
          "errors" => ["One potential error identified."],
          "improvements" => ["Consider adding comments."]
        }.to_json # JSON string

        cli_instance.expects(:call_llm_for_diff_analysis)
          .with(regexp_matches(/#{Regexp.escape(sample_diff)}/m), @mock_config)
          .returns(llm_response)

        cli_instance.execute
        $stdout.rewind
        actual_output = $stdout.string

        assert_match "Summary:\nModified test_file.txt", actual_output
        # For arrays, assert that each item is present if they are printed on separate lines or similar
        assert_match "Potential Errors:\n- One potential error identified.", actual_output
        assert_match "Suggested Improvements:\n- Consider adding comments.", actual_output
      end
    end

    def test_div_llm_api_error
      Dir.chdir(@tmp_dir) do
        system("git init -q .", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "initial content\n")
        system("git add test_file.txt && git commit -m 'initial commit' -q", chdir: @tmp_dir)
        File.write(File.join(@tmp_dir, "test_file.txt"), "modified content\n")

        sample_diff = "diff --git a/test_file.txt b/test_file.txt\nindex <hash_a>..<hash_b> 100644\n--- a/test_file.txt\n+++ b/test_file.txt\n@@ -1 +1 @@\n-initial content\n+modified content\n"

        cli_instance = N2B::CLI.new(['div'])
        cli_instance.stubs(:is_git_repository?).returns(true)
        cli_instance.stubs(:execute_git_diff).returns(sample_diff)

        # Simulate LlmApiError being raised from within call_llm_for_diff_analysis
        # The method itself will catch this, print a message, and return fallback JSON.
        # So, we mock the underlying llm.make_request (via the N2M::Llm::OpenAi/Claude new.make_request chain)
        # or more directly, mock `call_llm_for_diff_analysis` itself if it didn't have the rescue logic.
        # Since the rescue logic IS in `call_llm_for_diff_analysis`, we need to test that it behaves as expected.
        # We can mock the `llm.make_request` part that's *inside* `call_llm_for_diff_analysis`.

        # To do this, we expect N2M::Llm::OpenAi (or Claude, based on @mock_config) to be instantiated,
        # and its make_request method to be called.
        mock_llm_instance = mock('llm_instance')
        mock_llm_instance.expects(:make_request)
          .with(regexp_matches(/#{Regexp.escape(sample_diff)}/m))
          .raises(N2B::LlmApiError.new("Simulated API Error: Connection refused"))

        # Ensure the correct LLM class is instantiated and returns our mock LLM instance
        if @mock_config['llm'] == 'openai'
          N2M::Llm::OpenAi.expects(:new).with(@mock_config).returns(mock_llm_instance)
        else # claude
          N2M::Llm::Claude.expects(:new).with(@mock_config).returns(mock_llm_instance)
        end

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
  end
end
