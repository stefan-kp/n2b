require_relative '../test_helper'
require 'n2b/github_client'
require 'fileutils'

module N2B
  class TestGitHubClient < Minitest::Test
    def setup
      @tmp_dir = File.expand_path('./tmp_test_github_client_dir', Dir.pwd)
      FileUtils.mkdir_p(@tmp_dir)
      @test_config_file = File.join(@tmp_dir, 'config.yml')
      @original_config_file = N2B::Base::CONFIG_FILE
      N2B::Base.send(:remove_const, :CONFIG_FILE) if N2B::Base.const_defined?(:CONFIG_FILE)
      N2B::Base.const_set(:CONFIG_FILE, @test_config_file)

      @config = {
        'github' => {
          'repo' => 'owner/repo',
          'access_token' => 'token'
        },
        'llm' => 'claude',
        'model' => 'claude-3-opus'
      }
      @client = N2B::GitHubClient.new(@config)
    end

    def teardown
      N2B::Base.send(:remove_const, :CONFIG_FILE) if N2B::Base.const_defined?(:CONFIG_FILE)
      N2B::Base.const_set(:CONFIG_FILE, @original_config_file)
      FileUtils.rm_rf(@tmp_dir)
    end

    def make_public(instance, method)
      klass = instance.class
      klass.class_eval { public method }
      yield
    ensure
      klass.class_eval { private method }
    end

    def test_initialize_with_valid_config
      assert_instance_of N2B::GitHubClient, @client
    end

    def test_initialize_with_missing_config
      assert_raises(ArgumentError) { N2B::GitHubClient.new({}) }
    end

    def test_parse_issue_number
      make_public(@client, :parse_issue_input) do
        repo, num = @client.send(:parse_issue_input, '123')
        assert_equal 'owner/repo', repo
        assert_equal '123', num
      end
    end

    def test_parse_issue_url
      make_public(@client, :parse_issue_input) do
        repo, num = @client.send(:parse_issue_input, 'https://github.com/foo/bar/issues/42')
        assert_equal 'foo/bar', repo
        assert_equal '42', num
      end
    end
  end
end
