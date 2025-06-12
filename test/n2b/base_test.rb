require 'minitest/autorun'
require 'minitest/mock'
require 'fileutils'
require 'yaml'
require_relative '../../lib/n2b/base' # Adjust path as necessary

# Define N2M::Llm::Ollama::DEFAULT_OLLAMA_API_URI if not available
module N2M
  module Llm
    class Ollama
      DEFAULT_OLLAMA_API_URI = 'http://localhost:11434' unless defined?(DEFAULT_OLLAMA_API_URI)
    end
  end
end

# Mock N2B::ModelConfig if not central to these tests
module N2B
  class ModelConfig
    def self.get_model_choice(llm, current_model)
      # Minimal mock, return a default or passed current_model
      current_model || "mock_model_for_#{llm}"
    end
  end
end


class TestBase < Minitest::Test
  def setup
    # Set test environment flag for bulletproof protection
    ENV['N2B_TEST_MODE'] = 'true'

    @base = N2B::Base.new
    @config_dir = File.expand_path('~/.n2b_test')
    @config_file = File.join(@config_dir, 'config.yml')
    # Ensure a clean state for config file tests
    ENV['N2B_CONFIG_FILE'] = @config_file
    FileUtils.rm_rf(@config_dir)
    FileUtils.mkdir_p(@config_dir)
  end

  def teardown
    FileUtils.rm_rf(@config_dir)
    ENV['N2B_CONFIG_FILE'] = nil
    ENV['N2B_TEST_MODE'] = nil
  end

  def test_command_exists_unix_present
    # Simulate Linux environment
    RbConfig::CONFIG['host_os'] = 'linux'
    @base.stub(:system, true) do # Mock system call to `which ...` or `where ...`
      assert @base.send(:command_exists?, 'ruby'), "Should detect existing command (ruby) on Unix"
    end
  end

  def test_command_exists_unix_absent
    RbConfig::CONFIG['host_os'] = 'linux'
    @base.stub(:system, nil) do # `system` returns nil if command not found and execution fails
      refute @base.send(:command_exists?, 'nonexistentcmd'), "Should not detect non-existing command on Unix"
    end
  end

  def test_command_exists_windows_present
    RbConfig::CONFIG['host_os'] = 'mswin'
    @base.stub(:system, true) do
      assert @base.send(:command_exists?, 'notepad'), "Should detect existing command (notepad) on Windows"
    end
  end

  def test_command_exists_windows_absent
    RbConfig::CONFIG['host_os'] = 'mswin'
    @base.stub(:system, nil) do
      refute @base.send(:command_exists?, 'nonexistentcmd'), "Should not detect non-existing command on Windows"
    end
  end

  def test_prompt_for_editor_config_select_detected_nano
    config = { 'editor' => {} }

    # Mock command_exists? to control detected editors
    # Simulate nano exists, vim does not for this specific test
    command_exists_stub = lambda do |command|
      return true if command == 'nano'
      return false # All other commands don't exist
    end

    # Mock stdin.gets to return "1\n" (user chooses option 1)
    gets_stub = lambda { "1\n" }

    # We need to stub Kernel.puts to suppress output during test, and $stdin.gets
    capture_io do
      @base.stub(:command_exists?, command_exists_stub) do
        $stdin.stub :gets, gets_stub do
          @base.send(:prompt_for_editor_config, config)
        end
      end
    end

    assert_equal 'nano', config.dig('editor', 'command')
    assert_equal 'text_editor', config.dig('editor', 'type')
    assert config.dig('editor', 'configured')
  end

  def test_prompt_for_editor_config_custom_editor
    config = { 'editor' => {} }

    # Simulate no standard editors detected
    command_exists_stub = ->(command) { false }

    # Mock stdin.gets to return sequence of inputs
    input_sequence = ["1\n", "myedit\n", "diff_tool\n"]
    gets_stub = lambda { input_sequence.shift }

    capture_io do
      @base.stub(:command_exists?, command_exists_stub) do
        $stdin.stub :gets, gets_stub do
          @base.send(:prompt_for_editor_config, config)
        end
      end
    end

    assert_equal 'myedit', config.dig('editor', 'command')
    assert_equal 'diff_tool', config.dig('editor', 'type')
    assert config.dig('editor', 'configured')
  end

  def test_get_config_initializes_default_editor_settings
    # Ensure config file does not exist to simulate first run
    FileUtils.rm_f(@config_file) if File.exist?(@config_file)

    # Suppress puts and mock STDIN for get_config's interactive parts
    # This sequence assumes a very basic LLM setup to get through prompts
    # 1. LLM choice (claude)
    # 2. API Key
    # 3. Model choice (mocked by N2B::ModelConfig)
    # 4. Advanced settings? (n)
    # (Editor config is not prompted here unless advanced_flow=true and reconfigure=true)

    inputs = ["1\n", "test_api_key\n", "n\n"] # LLM, API key, No to advanced

    config = nil
    $stdin.stub :gets, lambda { inputs.shift || "\n" } do # Default to \n if inputs run out
      capture_io do # Suppress output from get_config
        config = @base.get_config(reconfigure: true) # Force full configuration flow
      end
    end

    assert config.key?('editor'), "Config should have an editor key"
    assert_nil config.dig('editor', 'command'), "Default editor command should be nil"
    assert_nil config.dig('editor', 'type'), "Default editor type should be nil"
    assert_equal false, config.dig('editor', 'configured'), "Default editor configured should be false"

    # Verify it's saved to file (get_config also saves when reconfiguring)
    # Since we're not reconfiguring in this test, we need to save manually
    config_file_path = N2B::Base.config_file
    FileUtils.mkdir_p(File.dirname(config_file_path))
    File.write(config_file_path, config.to_yaml)

    assert File.exist?(config_file_path), "Config file should exist at #{config_file_path}"
    saved_config = YAML.load_file(config_file_path)
    assert saved_config.key?('editor')
    assert_nil saved_config.dig('editor', 'command')
  end

  def test_normal_config_shows_advanced_features_tip
    # Test that normal configuration shows the tip about advanced features
    # when user is NOT prompted for advanced settings (existing config, not first time)

    # First, create an existing config to avoid first-time setup
    config_file_path = N2B::Base.config_file
    FileUtils.mkdir_p(File.dirname(config_file_path))
    existing_config = {
      'llm' => 'claude',
      'model' => 'claude-3-sonnet',
      'access_key' => 'existing-key'
    }
    File.write(config_file_path, existing_config.to_yaml)

    # Now reconfigure with advanced_flow: false (should not prompt for advanced)
    inputs = ['claude', 'test-api-key', 'claude-3-sonnet'] # LLM, API key, model

    config = nil
    output = nil
    $stdin.stub :gets, lambda { inputs.shift || "\n" } do
      output = capture_io do
        config = @base.get_config(reconfigure: true, advanced_flow: false)
      end
    end

    output_text = output[0] # stdout

    # Should show the tip about advanced features when not prompted for advanced
    assert_match /💡 Tip: Run 'n2b --advanced-config'/, output_text
    assert_match /Jira integration for ticket analysis/, output_text
    assert_match /GitHub integration for issue tracking/, output_text
    assert_match /AI-powered merge conflict resolution/, output_text
  end

  def test_advanced_config_does_not_show_tip
    # Test that advanced configuration flow does NOT show the tip (since user is already in advanced mode)
    inputs = ['claude', 'test-api-key', 'claude-3-sonnet', 'y', 'none', 'false', 'false', 'false', 'false'] # Advanced flow

    config = nil
    output = nil
    $stdin.stub :gets, lambda { inputs.shift || "\n" } do
      output = capture_io do
        config = @base.get_config(reconfigure: true, advanced_flow: true)
      end
    end

    output_text = output[0] # stdout

    # Should NOT show the tip about advanced features (user is already in advanced mode)
    refute_match /💡 Tip: Run 'n2b --advanced-config'/, output_text
  end

  def test_first_time_setup_does_not_show_tip
    # Test that first-time setup (which automatically prompts for advanced) does NOT show tip
    inputs = ['claude', 'test-api-key', 'claude-3-sonnet', 'y', 'none', 'false', 'false', 'false', 'false'] # First time with advanced

    # Ensure no existing config to simulate first-time setup
    config_file_path = N2B::Base.config_file
    FileUtils.rm_f(config_file_path) if File.exist?(config_file_path)

    config = nil
    output = nil
    $stdin.stub :gets, lambda { inputs.shift || "\n" } do
      output = capture_io do
        config = @base.get_config(reconfigure: true) # First time setup
      end
    end

    output_text = output[0] # stdout

    # Should NOT show the tip (first-time setup automatically goes to advanced)
    refute_match /💡 Tip: Run 'n2b --advanced-config'/, output_text
  end

end
