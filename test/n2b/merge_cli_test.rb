require 'minitest/autorun'
require 'fileutils'
require 'stringio'
require_relative '../test_helper' # Should set up load paths
require 'n2b/merge_cli'
require 'n2b/jira_client'
require 'n2b/github_client'
require 'n2b/message_utils'
require 'mocha/minitest' # Ensure Mocha is available
require 'json' # For .to_json

# Stubbing N2M::Llm classes if not loaded via test_helper
if !defined?(N2M::Llm::OpenAi)
  module N2M; module Llm; class OpenAi; def initialize(config); end; def analyze_code_diff(prompt); ""; end; end; end; end
end
if !defined?(N2M::Llm::Claude)
  module N2M; module Llm; class Claude; def initialize(config); end; def analyze_code_diff(prompt); ""; end; end; end; end
end


class MergeCLITest < Minitest::Test
  def setup
    @tmp_dir = File.expand_path('./tmp_n2b_merge_cli_dir', Dir.pwd) # Unique name
    FileUtils.mkdir_p(@tmp_dir)
    @original_pwd = Dir.pwd
    Dir.chdir(@tmp_dir) # Change to tmp_dir to simulate repo operations

    @file_path = File.join(@tmp_dir, 'conflict.txt') # For merge conflict tests

    # Enhanced config for diff analysis features
    @mock_config = {
      'llm' => 'openai',
      'merge_log_enabled' => false,
      'issue_tracker' => 'jira', # Default issue tracker
      'github' => { 'repo' => 'test/repo', 'access_token' => 'gh_token_abc123' },
      'jira' => { 'domain' => 'test.jira.com', 'email' => 'test@example.com', 'api_key' => 'jira_key_xyz789' },
      'templates' => { # Assuming template paths might be needed by resolve_template_path
        'diff_system_prompt' => File.expand_path('../../lib/n2b/templates/diff_system_prompt.txt', __dir__),
        'diff_json_instruction' => File.expand_path('../../lib/n2b/templates/diff_json_instruction.txt', __dir__),
        'jira_comment' => File.expand_path('../../lib/n2b/templates/jira_comment.txt', __dir__),
        'github_comment' => File.expand_path('../../lib/n2b/templates/github_comment.txt', __dir__)
      },
      'privacy' => { 'send_current_directory' => false, 'send_llm_history' => false, 'send_shell_history' => false } # from cli.rb
    }
    # Stub get_config for any instance of MergeCLI
    N2B::MergeCLI.any_instance.stubs(:get_config).returns(@mock_config)

    # Mocks for external services (can be further customized in tests)
    @mock_llm = mock('llm_client')
    @mock_jira_client = mock('jira_client')
    @mock_github_client = mock('github_client')

    # Common stub for LLM instantiation within analyze_diff_with_spinner
    # This might need adjustment if different LLMs are tested
    N2M::Llm::OpenAi.stubs(:new).returns(@mock_llm)


    @original_stdout = $stdout
    $stdout = StringIO.new
    @original_stderr = $stderr
    $stderr = StringIO.new
  end

  def teardown
    Dir.chdir(@original_pwd) # Restore original working directory
    FileUtils.rm_rf(@tmp_dir)
    $stdout = @original_stdout
    $stderr = @original_stderr
    Mocha::Mockery.instance.teardown # Crucial for cleaning up Mocha expectations
    Mocha::Mockery.reset_instance
  end

  def write_conflict_file(content)
    File.write(@file_path, content)
  end

  # Helper to simulate a VCS environment
  def setup_git_repo_with_diff(file_name: "test_file.rb", initial_content: "def old_method\nend\n", new_content: "def new_method\n  puts 'hello'\nend\n", branch_name: "feature-branch")
    system("git init -q")
    system("git config user.email 'test@example.com' && git config user.name 'Test User'")
    File.write(file_name, initial_content)
    system("git add #{file_name} && git commit -m 'Initial commit' -q")
    # Simulate a feature branch or just make changes directly
    File.write(file_name, new_content)
    # `git diff HEAD` will show these changes if not staged.
    # For branch diff, we'd need to commit on a branch.
    # For simplicity, execute_vcs_diff will be mocked.
    "diff --git a/#{file_name} b/#{file_name}\nindex 123..456 100644\n--- a/#{file_name}\n+++ b/#{file_name}\n@@ -1,2 +1,3 @@\n-def old_method\n-end\n+def new_method\n+  puts 'hello'\n+end\n"
  end


  # --- Existing Merge Conflict Tests (adapted slightly if needed) ---
  def test_resolve_accept_merge_conflict_mode
    write_conflict_file(<<~TEXT)
      line1
      <<<<<<< HEAD
      foo = 1
      =======
      foo = 2
      >>>>>>> feature
      line2
    TEXT

    cli = N2B::MergeCLI.new([@file_path]) # No --analyze, so merge mode
    # Merge mode uses call_llm_for_merge, not analyze_code_diff
    cli.stubs(:call_llm_for_merge).returns('{"merged_code":"foo = 3","reason":"merge"}')

    input = StringIO.new("y\n")
    $stdin = input
    begin
      cli.execute
    ensure
      $stdin = STDIN
    end

    result = File.read(@file_path)
    assert_match 'foo = 3', result
  end

  def test_abort_keeps_file
    original = <<~TEXT
      line1
      <<<<<<< HEAD
      foo = 1
      =======
      foo = 2
      >>>>>>> feature
      line2
    TEXT
    write(original)

    cli = N2B::MergeCLI.new([@file_path]) # No --analyze
    cli.stubs(:call_llm_for_merge).returns('{"merged_code":"foo = 3","reason":"merge"}')

    input = StringIO.new("a\n")
    $stdin = input
    begin
      cli.execute
    ensure
      $stdin = STDIN
    end

    result = File.read(@file_path)
    assert_equal original, result
  end

  def test_execute_vcs_command_with_timeout_success
    cli = N2B::MergeCLI.new([]) # Args don't matter here as we are testing a private method directly

    result = cli.send(:execute_vcs_command_with_timeout, "echo 'test'", 5)

    assert result[:success]
    assert_equal "test\n", result[:stdout]
  end

  def test_execute_vcs_command_with_timeout_failure
    cli = N2B::MergeCLI.new([])

    result = cli.send(:execute_vcs_command_with_timeout, "false", 5)

    refute result[:success]
    assert_includes result[:error], "Command failed"
  end

  def test_execute_vcs_command_with_timeout_timeout
    cli = N2B::MergeCLI.new([])

    # Use a command that will definitely timeout
    result = cli.send(:execute_vcs_command_with_timeout, "sleep 10", 1)

    refute result[:success]
    assert_includes result[:error], "timed out"
  end

  # --- New Tests for Diff Analysis Functionality ---

  def test_analyze_mode_basic_git_diff
    sample_diff = setup_git_repo_with_diff # Sets up git repo in @tmp_dir

    cli = N2B::MergeCLI.new(['--analyze'])
    cli.stubs(:get_vcs_type).returns(:git) # Mock VCS type
    cli.stubs(:execute_vcs_diff).with(:git, 'auto').returns(sample_diff) # Mock diff generation

    @mock_llm.expects(:analyze_code_diff).with(any_parameters).returns('{"summary":"Basic analysis done","errors":[],"improvements":[]}').once

    cli.execute

    $stdout.rewind
    output = $stdout.string
    assert_match "Code Diff Analysis", output
    assert_match "Basic analysis done", output
  end

  def test_analyze_mode_with_branch
    sample_diff = setup_git_repo_with_diff

    cli = N2B::MergeCLI.new(['--analyze', '--branch', 'develop'])
    cli.stubs(:get_vcs_type).returns(:git)
    # Expect execute_vcs_diff to be called with the specified branch
    cli.expects(:execute_vcs_diff).with(:git, 'develop').returns(sample_diff)
    cli.stubs(:validate_git_branch_exists).with('develop').returns(true)


    @mock_llm.expects(:analyze_code_diff).returns('{"summary":"Branch analysis","errors":[],"improvements":[]}').once

    cli.execute
    $stdout.rewind
    assert_match "Branch analysis", $stdout.string
  end

  def test_analyze_mode_with_requirements_file
    sample_diff = setup_git_repo_with_diff
    req_file_path = File.join(@tmp_dir, "reqs.txt")
    File.write(req_file_path, "Requirement: Must be fast.")

    cli = N2B::MergeCLI.new(['--analyze', '--requirements', req_file_path])
    cli.stubs(:get_vcs_type).returns(:git)
    cli.stubs(:execute_vcs_diff).returns(sample_diff)

    # Check that the LLM prompt includes the requirement
    @mock_llm.expects(:analyze_code_diff).with(includes("Requirement: Must be fast.")).returns('{"summary":"Reqs analysis","errors":[],"improvements":[]}').once

    cli.execute
    $stdout.rewind
    assert_match "Reqs analysis", $stdout.string
    assert_match "Loading requirements from file: #{req_file_path}", $stdout.string
  end

  def test_analyze_mode_with_custom_message
    sample_diff = setup_git_repo_with_diff
    custom_msg = "Focus on security aspects."

    # Mock MessageUtils to ensure they are called
    N2B::MessageUtils.expects(:validate_message).with(custom_msg).returns(custom_msg)
    N2B::MessageUtils.expects(:sanitize_message).with(custom_msg).returns(custom_msg)
    N2B::MessageUtils.expects(:log_message).with(includes(custom_msg), :info)

    cli = N2B::MergeCLI.new(['--analyze', '-m', custom_msg])
    cli.stubs(:get_vcs_type).returns(:git)
    cli.stubs(:execute_vcs_diff).returns(sample_diff)

    # Check that the LLM prompt includes the custom message
    @mock_llm.expects(:analyze_code_diff).with(includes(custom_msg)).returns('{"summary":"Message analysis","errors":[],"improvements":[]}').once

    cli.execute
    $stdout.rewind
    assert_match "Message analysis", $stdout.string
    # Log message is asserted by the MessageUtils mock
  end

  def test_analyze_mode_with_jira_ticket_fetch_and_update_prompt_yes
    sample_diff = setup_git_repo_with_diff
    jira_ticket_id = "PROJ-123"
    jira_content = "This is the Jira ticket content for PROJ-123."
    analysis_summary = "Jira related analysis"

    cli = N2B::MergeCLI.new(['--analyze', '--jira', jira_ticket_id]) # No --update or --no-update, so should prompt
    cli.stubs(:get_vcs_type).returns(:git)
    cli.stubs(:execute_vcs_diff).returns(sample_diff)

    N2B::JiraClient.expects(:new).with(@mock_config).twice.returns(@mock_jira_client) # Once for fetch, once for update
    @mock_jira_client.expects(:fetch_ticket).with(jira_ticket_id).returns(jira_content)

    analysis_result_hash = {
      'summary' => analysis_summary, 'errors' => [], 'improvements' => [],
      'ticket_implementation_summary' => 'Implemented per PROJ-123.'
    }
    @mock_llm.expects(:analyze_code_diff)
      .with(includes(jira_content))
      .returns(analysis_result_hash.to_json)

    # format_analysis_for_jira will be called internally by handle_diff_analysis
    # We need to mock the actual update_ticket call
    formatted_comment_for_jira = { implementation_summary: analysis_result_hash[:ticket_implementation_summary] } # simplified for test
    cli.stubs(:format_analysis_for_jira).returns(formatted_comment_for_jira)
    @mock_jira_client.expects(:update_ticket).with(jira_ticket_id, formatted_comment_for_jira).returns(true)

    input = StringIO.new("y\n") # User says yes to update
    original_stdin = $stdin
    $stdin = input
    begin
      cli.execute
    ensure
      $stdin = original_stdin
    end

    $stdout.rewind
    output = $stdout.string
    assert_match "Fetching Jira ticket details...", output
    assert_match "Successfully fetched Jira ticket details.", output
    assert_match analysis_summary, output
    assert_match "Would you like to update Jira issue #{jira_ticket_id}", output
    assert_match "Jira ticket #{jira_ticket_id} updated successfully.", output
  end

  def test_analyze_mode_with_github_issue_and_no_update_flag
    sample_diff = setup_git_repo_with_diff
    github_issue_url = "test/repo/issues/42"
    github_content = "GitHub issue content for #42."

    cli = N2B::MergeCLI.new(['--analyze', '--github', github_issue_url, '--no-update'])
    cli.stubs(:get_vcs_type).returns(:git)
    cli.stubs(:execute_vcs_diff).returns(sample_diff)

    N2B::GitHubClient.expects(:new).with(@mock_config).returns(@mock_github_client)
    @mock_github_client.expects(:fetch_issue).with(github_issue_url).returns(github_content)

    @mock_llm.expects(:analyze_code_diff)
      .with(includes(github_content))
      .returns('{"summary":"GitHub analysis for no update","errors":[],"improvements":[]}').once

    @mock_github_client.expects(:update_issue).never # Should not be called due to --no-update

    cli.execute

    $stdout.rewind
    output = $stdout.string
    assert_match "Fetching GitHub issue details...", output
    assert_match "Successfully fetched GitHub issue details.", output
    assert_match "GitHub analysis for no update", output
    assert_match "Issue/Ticket update skipped.", output # Due to --no-update flag
  end

  def test_message_length_truncation_via_option_parsing
    long_message = "a" * 600
    truncated_length = N2B::MessageUtils::MAX_MESSAGE_LENGTH
    expected_message_after_validation = long_message[0...(truncated_length - N2B::MessageUtils::TRUNCATION_NOTICE.length)] + N2B::MessageUtils::TRUNCATION_NOTICE

    # We don't need to run full execute, just check options parsing
    # N2B::MessageUtils are real, not mocked here, to test their integration during parsing
    cli = N2B::MergeCLI.new(['--analyze', '-m', long_message])
    options = cli.instance_variable_get(:@options)

    # Validate that MessageUtils.validate_message was effectively called by parse_options
    # and then sanitize_message. The final message in options should be validated and sanitized.
    # For this test, we focus on the outcome of validation (truncation).
    # The sanitize step will also run (e.g. strip).
    assert_equal N2B::MessageUtils.sanitize_message(expected_message_after_validation), options[:custom_message]

    $stdout.rewind # parse_options might print warnings for truncation.
    # The warning "Warning: Custom message exceeds 500 characters. It will be truncated."
    # is currently in parse_options itself. Let's check for it.
    # This warning is printed *before* MessageUtils.log_message.
    # This test is primarily about option parsing, not the full execute flow.
    # The actual logging via MessageUtils happens later if the message isn't empty.
    # For this specific test, we are verifying the truncation logic called from parse_options.
    # The test_analyze_mode_with_custom_message already verifies MessageUtils.log_message.
  end

  def test_help_option_shows_help_and_exits
    ex = assert_raises(SystemExit) do
      N2B::MergeCLI.new(['-h']).execute # or .parse_options if execute isn't reached
    end
    assert_equal 0, ex.status
    $stdout.rewind
    output = $stdout.string
    assert_match "Usage: n2b-diff FILE", output
    assert_match "OR n2b-diff --analyze", output
    assert_match "Diff Analysis Options:", output
    assert_match "Merge Conflict Options:", output
  end

end
