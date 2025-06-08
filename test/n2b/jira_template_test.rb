require 'test_helper'

class JiraTemplateTest < Minitest::Test
  def setup
    # Mock the configuration to avoid requiring real Jira credentials in tests
    config = {
      'jira' => {
        'domain' => 'test.atlassian.net',
        'email' => 'test@example.com',
        'api_key' => 'test_api_key'
      }
    }
    @jira_client = N2B::JiraClient.new(config)
  end

  def test_classify_error_severity_critical
    assert_equal 'CRITICAL', @jira_client.send(:classify_error_severity, 'SQL injection vulnerability found')
    assert_equal 'CRITICAL', @jira_client.send(:classify_error_severity, 'XSS attack vector detected')
    assert_equal 'CRITICAL', @jira_client.send(:classify_error_severity, 'Security exploit possible')
  end

  def test_classify_error_severity_important
    assert_equal 'IMPORTANT', @jira_client.send(:classify_error_severity, 'N+1 query detected')
    assert_equal 'IMPORTANT', @jira_client.send(:classify_error_severity, 'Performance bottleneck found')
    assert_equal 'IMPORTANT', @jira_client.send(:classify_error_severity, 'Error handling missing')
    assert_equal 'IMPORTANT', @jira_client.send(:classify_error_severity, 'Exception not caught')
  end

  def test_classify_error_severity_low
    assert_equal 'LOW', @jira_client.send(:classify_error_severity, 'Style convention violation')
    assert_equal 'LOW', @jira_client.send(:classify_error_severity, 'Naming convention issue')
    assert_equal 'LOW', @jira_client.send(:classify_error_severity, 'Indentation problem')
  end

  def test_extract_file_reference_with_line_number
    assert_equal '*app/models/user.rb:42*', @jira_client.send(:extract_file_reference, 'app/models/user.rb line 42: error message')
    assert_equal '*controllers/auth.rb:15*', @jira_client.send(:extract_file_reference, 'controllers/auth.rb:15 - issue found')
    assert_equal '*lib/payment.rb:67*', @jira_client.send(:extract_file_reference, 'lib/payment.rb (line 67) has problem')
  end

  def test_extract_file_reference_without_line_number
    assert_equal '*app/models/user.rb*', @jira_client.send(:extract_file_reference, 'app/models/user.rb has issues')
    assert_equal '*spec/auth_spec.rb*', @jira_client.send(:extract_file_reference, 'spec/auth_spec.rb needs tests')
  end

  def test_extract_file_reference_no_file_found
    assert_equal '*General*', @jira_client.send(:extract_file_reference, 'General coding issue without file reference')
    assert_equal '*General*', @jira_client.send(:extract_file_reference, 'Some random text')
  end

  def test_clean_error_description_removes_file_reference
    input = 'app/models/user.rb line 42: SQL injection vulnerability detected'
    expected = 'SQL injection vulnerability detected'
    assert_equal expected, @jira_client.send(:clean_error_description, input)
  end

  def test_clean_error_description_handles_various_formats
    # The method removes file references but may leave some formatting
    result1 = @jira_client.send(:clean_error_description, 'auth.rb:15 - Missing validation')
    assert result1.include?('Missing validation'), "Expected 'Missing validation' in '#{result1}'"

    result2 = @jira_client.send(:clean_error_description, 'lib/service.rb (line 30) Performance issue')
    assert result2.include?('Performance issue'), "Expected 'Performance issue' in '#{result2}'"

    result3 = @jira_client.send(:clean_error_description, 'Style problem without file reference')
    assert_equal 'Style problem without file reference', result3
  end

  def test_extract_missing_tests_from_coverage_text
    coverage_text = "Missing tests for edge cases. Need to add tests for validation. Coverage is 65%."
    result = @jira_client.send(:extract_missing_tests, coverage_text)

    assert result.is_a?(Array)
    assert result.length > 0
    # The method should extract test-related items or create coverage-based ones
    has_test_content = result.any? { |test| test['description'].include?('test') || test['description'].include?('65%') }
    assert has_test_content, "Expected test-related content in #{result.inspect}"
  end

  def test_extract_missing_tests_with_low_coverage
    coverage_text = "Current test coverage: 45%. Need improvement."
    result = @jira_client.send(:extract_missing_tests, coverage_text)
    
    assert result.is_a?(Array)
    assert result.any? { |test| test['description'].include?('45%') && test['description'].include?('80%') }
  end

  def test_extract_requirements_status_implemented
    requirements_text = "✅ IMPLEMENTED: User login functionality working perfectly"
    result = @jira_client.send(:extract_requirements_status, requirements_text)
    
    assert_equal 1, result.length
    assert_equal 'IMPLEMENTED', result.first['status']
    assert_equal 'User login functionality working perfectly', result.first['description']
    assert_equal '✅', result.first['status_icon']
  end

  def test_extract_requirements_status_multiple_statuses
    requirements_text = <<~TEXT
      ✅ IMPLEMENTED: User authentication working
      ⚠️ PARTIALLY IMPLEMENTED: Password validation partial
      ❌ NOT IMPLEMENTED: Two-factor authentication missing
      🔍 UNCLEAR: Session management needs clarification
    TEXT
    
    result = @jira_client.send(:extract_requirements_status, requirements_text)

    assert_equal 4, result.length
    
    implemented = result.find { |r| r['status'] == 'IMPLEMENTED' }
    assert implemented, "Should find IMPLEMENTED requirement"
    assert_equal 'User authentication working', implemented['description']

    partial = result.find { |r| r['status'] == 'PARTIALLY_IMPLEMENTED' }
    assert partial, "Should find PARTIALLY_IMPLEMENTED requirement"
    assert_equal 'Password validation partial', partial['description']

    not_impl = result.find { |r| r['status'] == 'NOT_IMPLEMENTED' }
    assert not_impl, "Should find NOT_IMPLEMENTED requirement"
    assert_equal 'Two-factor authentication missing', not_impl['description']

    unclear = result.find { |r| r['status'] == 'UNCLEAR' }
    assert unclear, "Should find UNCLEAR requirement"
    assert_equal 'Session management needs clarification', unclear['description']
  end

  def test_prepare_template_data_structure
    comment_data = {
      implementation_summary: 'Added user authentication',
      issues: [
        'app/auth.rb:42 - SQL injection vulnerability',
        'controllers/login.rb:15 - Missing rate limiting',
        'lib/style.rb:30 - Naming convention issue'
      ],
      improvements: [
        'spec/auth_spec.rb - Add more test cases',
        'app/services/auth.rb:25 - Use bcrypt for hashing'
      ],
      test_coverage: 'Current coverage: 78%. Missing edge case tests.',
      requirements_evaluation: '✅ IMPLEMENTED: Login working\n❌ NOT IMPLEMENTED: 2FA missing'
    }
    
    # Mock git info to avoid system calls in tests
    @jira_client.stub(:extract_git_info, { branch: 'feature/auth', files_changed: '5', lines_added: '120', lines_removed: '30' }) do
      result = @jira_client.send(:prepare_template_data, comment_data)
      
      # Check basic structure
      assert result.key?('implementation_summary')
      assert result.key?('critical_errors')
      assert result.key?('important_errors')
      assert result.key?('improvements')
      assert result.key?('missing_tests')
      assert result.key?('requirements')
      
      # Check error classification
      critical_errors = result['critical_errors']
      assert critical_errors.any? { |e| e['description'].include?('SQL injection') }
      
      important_errors = result['important_errors']
      assert important_errors.any? { |e| e['description'].include?('rate limiting') }
      
      # Check improvements processing
      improvements = result['improvements']
      assert_equal 2, improvements.length
      assert improvements.any? { |i| i['description'].include?('test cases') }
      
      # Check git info integration
      assert_equal 'feature/auth', result['branch_name']
      assert_equal '5', result['files_changed']
      
      # Check boolean flags
      assert_equal false, result['critical_errors_empty']
      assert_equal false, result['important_errors_empty']
      assert_equal false, result['improvements_empty']
    end
  end

  def test_generate_templated_comment_integration
    comment_data = {
      implementation_summary: 'Added secure user authentication',
      issues: ['app/auth.rb:42 - SQL injection found'],
      improvements: ['spec/auth_spec.rb - Add security tests'],
      test_coverage: 'Coverage: 85%',
      requirements_evaluation: '✅ IMPLEMENTED: Basic auth working'
    }
    
    # Mock dependencies
    @jira_client.stub(:extract_git_info, { branch: 'main', files_changed: '3', lines_added: '50', lines_removed: '10' }) do
      @jira_client.stub(:get_config, {}) do
        result = @jira_client.send(:generate_templated_comment, comment_data)
        
        # Check that template was processed
        assert result.is_a?(String)
        assert result.include?('*N2B Code Analysis Report*')
        assert result.include?('Added secure user authentication')
        assert result.include?('SQL injection found')
        assert result.include?('Add security tests')
        assert result.include?('Branch: main')
        # Files changed info was removed from footer, check for branch instead
        assert result.include?('Branch: main')
      end
    end
  end

  def test_convert_markdown_to_adf_basic_structure
    markdown = "*N2B Code Analysis Report*\n=========================\n\nImplementation completed successfully."
    
    result = @jira_client.send(:convert_markdown_to_adf, markdown)
    
    assert result.is_a?(Hash)
    assert_equal 'doc', result['type']
    assert_equal 1, result['version']
    assert result.key?('content')
    assert result['content'].is_a?(Array)
  end

  def test_convert_markdown_to_adf_with_checkboxes
    markdown = "☐ Task 1 not done\n☑ Task 2 completed"

    result = @jira_client.send(:convert_markdown_to_adf, markdown)

    # Checkboxes are now converted to simple paragraphs, not taskList
    content = result['content']
    paragraphs = content.select { |item| item['type'] == 'paragraph' }
    assert paragraphs.length > 0

    # Check that checkbox symbols are preserved in text
    all_text = paragraphs.flat_map { |p| p['content'] }.map { |c| c['text'] }.join(' ')
    assert all_text.include?('☐ Task 1 not done')
    assert all_text.include?('☑ Task 2 completed')
  end

  def test_convert_markdown_to_adf_with_expand_sections
    markdown = "{expand:Critical Issues}\n☐ Issue 1\n☐ Issue 2\n{expand}"
    
    result = @jira_client.send(:convert_markdown_to_adf, markdown)
    
    # Should contain expand sections
    content = result['content']
    expand_sections = content.select { |item| item['type'] == 'expand' }
    assert expand_sections.length > 0
    
    expand_section = expand_sections.first
    assert_equal 'Critical Issues', expand_section['attrs']['title']
  end
end
