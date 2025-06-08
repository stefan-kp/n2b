require 'minitest/autorun'
require 'minitest/mock'
require 'fileutils'
require 'yaml'
require_relative '../../lib/n2b/base' # Adjust path as necessary

# Define N2M::Llm::Ollama::DEFAULT_OLLAMA_API_URI if not available
module N2M
  module Llm
    module Ollama
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

    # Mock STDIN for user input
    stdin_mock = Minitest::Mock.new
    stdin_mock.expect :gets, "1\n" # User chooses option 1

    # Mock command_exists? to control detected editors
    # Simulate nano exists, vim does not for this specific test
    command_exists_stub = lambda do |command|
      return true if command == 'nano'
      return false # All other commands don't exist
    end

    # We need to stub Kernel.puts to suppress output during test, and $stdin.gets
    out, err = capture_io do
      N2B::Base.stub(:command_exists?, command_exists_stub) do
        $stdin.stub :gets, stdin_mock do
          @base.send(:prompt_for_editor_config, config)
        end
      end
    end

    stdin_mock.verify # Ensure gets was called

    assert_equal 'nano', config.dig('editor', 'command')
    assert_equal 'text_editor', config.dig('editor', 'type')
    assert config.dig('editor', 'configured')
  end

  def test_prompt_for_editor_config_custom_editor
    config = { 'editor' => {} }

    stdin_mock = Minitest::Mock.new
    # User chooses "Custom" (assuming it's option 1 if no editors detected)
    # or the last option if some are detected.
    # Let's assume no editors detected, so custom is option 1.
    stdin_mock.expect :gets, "1\n" # Choose custom
    stdin_mock.expect :gets, "myedit\n" # Enter custom command
    stdin_mock.expect :gets, "diff_tool\n" # Enter type

    # Simulate no standard editors detected
    command_exists_stub = ->(command) { false }

    out, err = capture_io do
      N2B::Base.stub(:command_exists?, command_exists_stub) do
        $stdin.stub :gets, stdin_mock do
          @base.send(:prompt_for_editor_config, config)
        end
      end
    end

    stdin_mock.verify

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

    # Verify it's saved to file (get_config also saves)
    assert File.exist?(@config_file)
    saved_config = YAML.load_file(@config_file)
    assert saved_config.key?('editor')
    assert_nil saved_config.dig('editor', 'command')
  end

end
