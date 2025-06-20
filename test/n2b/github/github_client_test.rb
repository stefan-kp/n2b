require_relative '../../test_helper'
require 'n2b/github_client'
require 'fileutils'

module N2B
  class TestGitHubClient < Minitest::Test
    def setup
      ENV['N2B_TEST_MODE'] = 'true'
      @tmp_dir = File.expand_path('./tmp_test_github_client_dir', Dir.pwd)
      FileUtils.mkdir_p(@tmp_dir)
      @test_config_file = File.join(@tmp_dir, 'config.yml')

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
      ENV['N2B_TEST_MODE'] = nil
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

    def test_generate_templated_comment_basic
      comment_data = {
        implementation_summary: 'Added feature',
        issues: ['app.rb:1 - bug'],
        improvements: ['lib/foo.rb - use foo'],
        test_coverage: 'Coverage 70%',
        requirements_evaluation: '✅ IMPLEMENTED: done'
      }

      @client.stub(:extract_git_info, { branch: 'main', files_changed: '1', lines_added: '10', lines_removed: '2' }) do
        result = @client.generate_templated_comment(comment_data)
        assert_includes result, 'Added feature'
        assert_includes result, 'app.rb:1'
        assert_includes result, 'bug'
        assert_includes result, 'use foo'
        assert_includes result, 'Increase test coverage'
        assert_includes result, '✅'
      end
    end
  end
end
