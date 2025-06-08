require 'minitest/autorun'
require 'minitest/mock'
require 'fileutils'
require 'pathname' # Required for Pathname
require_relative '../../lib/n2b/merge_cli' # Adjust path as necessary
require_relative '../../lib/n2b/merge_conflict_parser' # Required for block_details

# Minimal N2B::Base mock for MergeCLI to inherit from
module N2B
  class Base
    # Mock necessary methods used by MergeCLI's initialization or tested methods
    def get_config(reconfigure: false, advanced_flow: false)
      {
        'editor' => { 'command' => nil, 'type' => nil, 'configured' => false },
        'merge_log_enabled' => false
        # Add other keys if MergeCLI constructor or methods use them
      }
    end

    # Add other methods if MergeCLI's direct calls need them
  end
end

# Mock N2B::VERSION if not available
module N2B
  VERSION = '0.0.test' unless defined?(N2B::VERSION)
end


class TestMergeCLI < Minitest::Test
  def setup
    # Provide dummy arguments for MergeCLI initialization
    # These might need to be adjusted if MergeCLI's constructor changes
    @merge_cli = N2B::MergeCLI.new(['dummy_file_path.txt'])
    @test_dir = File.join(__dir__, 'test_tmp_merge_cli') # Unique temp dir
    FileUtils.mkdir_p(@test_dir)

    # Mock @file_path for methods that use it directly
    @merge_cli.instance_variable_set(:@file_path, File.join(@test_dir, 'test_file.txt'))
    FileUtils.touch(@merge_cli.instance_variable_get(:@file_path))
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def test_get_language_class
    assert_equal 'ruby', @merge_cli.send(:get_language_class, 'test.rb')
    assert_equal 'javascript', @merge_cli.send(:get_language_class, 'test.js')
    assert_equal 'python', @merge_cli.send(:get_language_class, 'test.py')
    assert_equal 'xml', @merge_cli.send(:get_language_class, 'test.html')
    assert_equal 'css', @merge_cli.send(:get_language_class, 'test.css')
    assert_equal '', @merge_cli.send(:get_language_class, 'test.unknown')
    assert_equal 'yaml', @merge_cli.send(:get_language_class, 'config.yml')
  end

  def test_find_sub_content_lines_present
    full_content = "line1\nline2\nTARGET_START\nline4\nTARGET_END\nline6"
    sub_content = "TARGET_START\nline4\nTARGET_END"
    expected = { start: 3, end: 5 }
    assert_equal expected, @merge_cli.send(:find_sub_content_lines, full_content, sub_content)
  end

  def test_find_sub_content_lines_absent
    full_content = "line1\nline2\nline3"
    sub_content = "not_present"
    assert_nil @merge_cli.send(:find_sub_content_lines, full_content, sub_content)
  end

  def test_find_sub_content_lines_empty_sub_content
    full_content = "line1\nline2"
    sub_content = ""
    assert_nil @merge_cli.send(:find_sub_content_lines, full_content, sub_content)
  end

  def test_find_sub_content_lines_sub_content_multiple_lines_at_start
    full_content = "TARGET_START\nline2\nTARGET_END\nline4"
    sub_content = "TARGET_START\nline2\nTARGET_END"
    expected = { start: 1, end: 3 }
    assert_equal expected, @merge_cli.send(:find_sub_content_lines, full_content, sub_content)
  end

  def test_apply_hunk_to_full_content
    original = "<<<<<<< HEAD\nold_line1\nold_line2\n=======\nnew_line1\nnew_line2\n>>>>>>> feature"
    # Mocking a MergeConflictParser::ConflictBlock object
    block_details = N2B::MergeConflictParser::ConflictBlock.new(
      start_line: 1, end_line: 7, # Line numbers of the conflict markers themselves
      base_content: "old_line1\nold_line2",
      incoming_content: "new_line1\nnew_line2",
      base_label: "HEAD", incoming_label: "feature",
      context_before: "", context_after: ""
    )
    resolved_hunk = "resolved_line1\nresolved_line2"

    expected_output = "resolved_line1\nresolved_line2"

    actual_output = @merge_cli.send(:apply_hunk_to_full_content, original, block_details, resolved_hunk)
    assert_equal expected_output, actual_output
  end

  def test_apply_hunk_to_full_content_with_context
    original = "context_before\n<<<<<<< HEAD\nold_line\n=======\nnew_line\n>>>>>>> feature\ncontext_after"
    block_details = N2B::MergeConflictParser::ConflictBlock.new(
      start_line: 2, end_line: 6,
      base_content: "old_line", incoming_content: "new_line",
      base_label: "HEAD", incoming_label: "feature",
      context_before: "context_before", context_after: "context_after"
    )
    resolved_hunk = "resolved_line"

    expected_output = "context_before\nresolved_line\ncontext_after"
    actual_output = @merge_cli.send(:apply_hunk_to_full_content, original, block_details, resolved_hunk)
    assert_equal expected_output, actual_output
  end

  def test_generate_conflict_preview_html_structure
    block = N2B::MergeConflictParser::ConflictBlock.new(
      start_line: 2, end_line: 2, base_label: 'main', incoming_label: 'feature',
      base_content: "base line2", incoming_content: "incoming line2",
      suggestion: { 'merged_code' => "resolved line2" } # Suggestion is just the block
    )
    base_full = "base line1\nbase line2\nbase line3"
    incoming_full = "incoming line1\nincoming line2\nincoming line3"
    # current_resolution_content_full will be constructed by apply_hunk...
    # For this test, let's assume apply_hunk_to_full_content works and construct it manually.
    # Here, original_full_content_with_markers would be the file content in resolve_block.
    # Let's use a simplified version for this test's direct call to generate_..._html
    current_full_file_with_markers = "base line1\n<<<<<< base\nbase line2\n======\ninc line2\n>>>>>> inc\nbase line3"
    # block_for_apply_hunk would have start_line and end_line relative to current_full_file_with_markers
    # For this test, we pass the already resolved full content.
    resolved_full = "base line1\nresolved line2\nbase line3"

    # Mock find_sub_content_lines
    find_stub = ->(full_c, sub_c) do
      if full_c == base_full && sub_c == "base line2"; { start: 2, end: 2 };
      elsif full_c == incoming_full && sub_c == "incoming line2"; { start: 2, end: 2 };
      elsif full_c == resolved_full && sub_c == "resolved line2"; { start: 2, end: 2 };
      else nil; end
    end

    @merge_cli.stub(:find_sub_content_lines, find_stub) do
      html_path = @merge_cli.send(
        :generate_conflict_preview_html,
        block, base_full, incoming_full, resolved_full,
        'main', 'feature', @merge_cli.instance_variable_get(:@file_path)
      )

      assert File.exist?(html_path), "HTML preview file should be created: #{html_path}"
      html_content = File.read(html_path)

      assert_match /<title>Conflict Preview: test_file.txt<\/title>/, html_content
      assert_match /highlight\.min\.css/, html_content
      assert_match /highlight\.min\.js/, html_content # Added this check
      assert_match /hljs\.highlightAll\(\);/, html_content # Added this check
      assert_match /<div class="column">\s*<h3>Base \(main\)<\/h3>/, html_content
      assert_match /<div class="column">\s*<h3>Incoming \(feature\)<\/h3>/, html_content
      assert_match /<div class="column">\s*<h3>Current Resolution<\/h3>/, html_content
      assert_match /<pre><code class="ruby">/, html_content # Assuming .rb from setup

      # Check for escaped content and line numbers
      assert_match CGI.escapeHTML("base line1"), html_content
      assert_match /<span class="line-number">1<\/span><span class="line-content">#{CGI.escapeHTML("base line1")}<\/span>/, html_content

      # Check highlighting classes
      assert_match /class="line conflict-lines conflict-lines-base">#{CGI.escapeHTML("base line2")}<\/span>/, html_content
      assert_match /class="line conflict-lines conflict-lines-incoming">#{CGI.escapeHTML("incoming line2")}<\/span>/, html_content
      assert_match /class="line conflict-lines conflict-lines-resolution">#{CGI.escapeHTML("resolved line2")}<\/span>/, html_content

      FileUtils.rm_f(html_path)
    end
  end

  def test_open_html_in_browser_commands
    file_path = File.join(@test_dir, "test.html")
    FileUtils.touch(file_path) # Ensure file exists for File.absolute_path

    # Test macOS
    RbConfig::CONFIG.stub :[], 'darwin' do # Stub RbConfig
        @merge_cli.stub(:system, ->(cmd) { assert_match /^open file:\/\//, cmd; true }) do
            @merge_cli.send(:open_html_in_browser, file_path)
        end
    end

    # Test Linux (non-WSL)
    RbConfig::CONFIG.stub :[], 'linux' do
        ENV.stub :[], nil do # Mock ENV['WSL_DISTRO_NAME'] etc. to be nil
            File.stub :exist?, false do # Mock File.exist? for /proc/sys/fs/binfmt_misc/WSLInterop
                @merge_cli.stub(:system, ->(cmd) { assert_match /^xdg-open file:\/\//, cmd; true }) do
                    @merge_cli.send(:open_html_in_browser, file_path)
                end
            end
        end
    end

    # Test Windows
    RbConfig::CONFIG.stub :[], 'mswin' do
        @merge_cli.stub(:system, ->(cmd) { assert_match /^start "" "[a-zA-Z]:\\.+test\.html"/i, cmd; true }) do
            @merge_cli.send(:open_html_in_browser, file_path)
        end
    end
  end

  # Placeholder for get_file_content_from_vcs tests
  def test_get_file_content_from_vcs_git_success
    # Need to use a real file path for Pathname operations if they are added to get_file_content_from_vcs
    test_file_path_in_repo = "test_file.txt" # Relative to repo root
    FileUtils.touch(test_file_path_in_repo) # Ensure it exists for Pathname if used

    # Mock the backtick ` method directly on the object instance
    @merge_cli.define_singleton_method(:`) do |command|
      assert_match(/^git show main:#{Regexp.escape(test_file_path_in_repo)}/, command)
      "fake git content"
    end

    # Mock $? for success
    success_status_mock = Minitest::Mock.new.expect(:success?, true)

    # It's tricky to stub $? directly. A common way is to stub system calls that set it,
    # or abstract the system call + status check into its own method that can be stubbed.
    # Given current implementation of get_file_content_from_vcs uses backticks and then checks $?,
    # we'll assume $? reflects the last command. Minitest doesn't easily mock global state like $?.
    # This test will rely on the actual behavior of backticks if the command were to run.
    # For a more isolated test, `get_file_content_from_vcs` would need refactoring
    # to use something like Open3, whose components can be mocked.
    # For now, we can only verify the command and the processing of its return if $? was true.

    # To make this testable, let's assume if backticks return non-empty, it's a success for this mock.
    # And if we want to test failure, make backticks return empty and $? non-success.

    # This test is more of an integration test of the command string.
    # Proper mocking of $? is hard. We will assume if content is returned, $? was success.

    original_status = $? # Store original status if any test runner sets it.
    $? = success_status_mock # This is generally not advised but for simple cases.

    content = @merge_cli.send(:get_file_content_from_vcs, 'main', test_file_path_in_repo, :git)
    assert_equal "fake git content", content

    $? = original_status # Restore
    FileUtils.rm_f(test_file_path_in_repo)
  end

  def test_get_file_content_from_vcs_git_failure
    test_file_path_in_repo = "test_file.txt"
    FileUtils.touch(test_file_path_in_repo)

    @merge_cli.define_singleton_method(:`) do |command|
      assert_match(/^git show main:#{Regexp.escape(test_file_path_in_repo)}/, command)
      "" # Simulate empty output from git show on failure
    end

    # Simulate command failure by setting $? behavior
    # This is still tricky. A better way is to refactor get_file_content_from_vcs
    # to use Open3.popen3 and mock that.
    # For now, this test highlights the difficulty.
    # We'll assume the internal check `return content if $?.success?` is what we test.
    # If backticks return "" and we make $?.success? false, it should return nil.

    # Mocking $? is problematic. Let's assume the method's logic:
    # if $?.success? is true, it returns content. If false, it returns nil (after warning).
    # We can't easily set $?.success? to false after backticks run in a mock.
    # So, we test the nil return path by having the command return empty string,
    # and trust the $?.success? check in the original code.
    # The warning about "command failed or returned no content" should appear.

    # To properly test the $?.success? == false path, we'd need to mock the Process::Status object.
    # Minitest::Mock can create such an object.
    status_mock_failure = Minitest::Mock.new
    status_mock_failure.expect :success?, false
    status_mock_failure.expect :exitstatus, 128 # git often returns 128 for "not found"

    # This is a common pattern to allow setting $? for a block in testing
    original_process_status = $?
    begin
      $? = status_mock_failure
      content = nil
      out, err = capture_io do # Capture the warning
        content = @merge_cli.send(:get_file_content_from_vcs, 'main', test_file_path_in_repo, :git)
      end
      assert_nil content
      assert_match /Warning: VCS command .* failed or returned no content/, out
    ensure
      $? = original_process_status # Restore global variable
    end
    FileUtils.rm_f(test_file_path_in_repo)
  end

  # Basic integration test structure for resolve_block focusing on preview generation
  def test_resolve_block_calls_preview_generation_and_opening
    # Mock a conflict block
    block = N2B::MergeConflictParser::ConflictBlock.new(
      start_line: 1, end_line: 1, base_label: 'HEAD', incoming_label: 'MERGE_HEAD',
      base_content: "a", incoming_content: "b", suggestion: { 'merged_code' => 'c', 'reason' => 'test reason' }
    )
    config = @merge_cli.send(:get_config) # Get default config
    full_file_content = "a\n<<<<<<\nold\n======\nnew\n>>>>>>\nb"

    # Mock dependencies of resolve_block related to preview
    @merge_cli.stub(:get_vcs_type_for_file_operations, :git) do
      @merge_cli.stub(:get_file_content_from_vcs, "full file content") do
        # generate_conflict_preview_html and open_html_in_browser will be called.
        # We want to assert they are called.
        preview_path = "/tmp/fake_preview.html"
        generate_mock = Minitest::Mock.new
        generate_mock.expect :call, preview_path, [Object, String, String, String, String, String, String]

        open_mock = Minitest::Mock.new
        open_mock.expect :call, true, [String]

        # Mock request_merge_with_spinner to return a valid suggestion
        suggestion_data = { 'merged_code' => 'c', 'reason' => 'test reason' }
        @merge_cli.stub(:request_merge_with_spinner, suggestion_data) do
          # Mock user input to exit the loop, e.g., by accepting the suggestion
          $stdin.stub(:gets, "y\n") do
            capture_io do # Suppress other output from resolve_block
              @merge_cli.stub(:generate_conflict_preview_html, generate_mock) do
                @merge_cli.stub(:open_html_in_browser, open_mock) do
                   # Mock FileUtils.rm_f to check it's called for cleanup
                   file_utils_mock = Minitest::Mock.new
                   file_utils_mock.expect :call, nil, [String] # Expects path argument
                   FileUtils.stub(:rm_f, file_utils_mock) do
                     @merge_cli.send(:resolve_block, block, config, full_file_content)
                   end
                   file_utils_mock.verify
                end
              end
            end
          end
          generate_mock.verify
          open_mock.verify
        end
      end
    end
  end
end
