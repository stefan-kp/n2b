require 'test_helper'

class TemplateEngineTest < Minitest::Test
  def setup
    @engine = N2B::TemplateEngine
  end

  def test_simple_variable_substitution
    template = "Hello {name}, welcome to {app}!"
    data = { 'name' => 'John', 'app' => 'N2B' }
    
    result = @engine.new(template, data).render
    assert_equal "Hello John, welcome to N2B!", result
  end

  def test_variable_substitution_with_symbols
    template = "Hello {name}, welcome to {app}!"
    data = { name: 'Jane', app: 'N2B' }
    
    result = @engine.new(template, data).render
    assert_equal "Hello Jane, welcome to N2B!", result
  end

  def test_missing_variables_become_empty
    template = "Hello {name}, welcome to {missing}!"
    data = { 'name' => 'John' }
    
    result = @engine.new(template, data).render
    assert_equal "Hello John, welcome to !", result
  end

  def test_simple_loop_with_strings
    template = "Items: {#each items}{.}, {/each}"
    data = { 'items' => ['apple', 'banana', 'cherry'] }
    
    result = @engine.new(template, data).render
    assert_equal "Items: apple, banana, cherry, ", result
  end

  def test_loop_with_hash_objects
    template = "{#each users}User: {name} ({email})\n{/each}"
    data = {
      'users' => [
        { 'name' => 'John', 'email' => 'john@example.com' },
        { 'name' => 'Jane', 'email' => 'jane@example.com' }
      ]
    }
    
    result = @engine.new(template, data).render
    expected = "User: John (john@example.com)\nUser: Jane (jane@example.com)\n"
    assert_equal expected, result
  end

  def test_empty_loop
    template = "Items: {#each items}{name}{/each}"
    data = { 'items' => [] }
    
    result = @engine.new(template, data).render
    assert_equal "Items: ", result
  end

  def test_missing_loop_array
    template = "Items: {#each missing}{name}{/each}"
    data = {}
    
    result = @engine.new(template, data).render
    assert_equal "Items: ", result
  end

  def test_simple_conditional_true
    template = "{#if show_message}Hello World!{/if}"
    data = { 'show_message' => true }
    
    result = @engine.new(template, data).render
    assert_equal "Hello World!", result
  end

  def test_simple_conditional_false
    template = "{#if show_message}Hello World!{/if}"
    data = { 'show_message' => false }
    
    result = @engine.new(template, data).render
    assert_equal "", result
  end

  def test_conditional_with_else_true
    template = "{#if logged_in}Welcome back!{#else}Please log in{/if}"
    data = { 'logged_in' => true }
    
    result = @engine.new(template, data).render
    assert_equal "Welcome back!", result
  end

  def test_conditional_with_else_false
    template = "{#if logged_in}Welcome back!{#else}Please log in{/if}"
    data = { 'logged_in' => false }
    
    result = @engine.new(template, data).render
    assert_equal "Please log in", result
  end

  def test_equality_conditional_true
    template = "{#if status == 'IMPLEMENTED'}✅ Done{/if}"
    data = { 'status' => 'IMPLEMENTED' }
    
    result = @engine.new(template, data).render
    assert_equal "✅ Done", result
  end

  def test_equality_conditional_false
    template = "{#if status == 'IMPLEMENTED'}✅ Done{/if}"
    data = { 'status' => 'PENDING' }
    
    result = @engine.new(template, data).render
    assert_equal "", result
  end

  def test_not_equal_conditional
    template = "{#if status != 'PENDING'}Ready{/if}"
    data = { 'status' => 'DONE' }
    
    result = @engine.new(template, data).render
    assert_equal "Ready", result
  end

  def test_conditional_inside_loop
    template = "{#each items}{#if status == 'ACTIVE'}✅ {name}{/if}{/each}"
    data = {
      'items' => [
        { 'name' => 'Task 1', 'status' => 'ACTIVE' },
        { 'name' => 'Task 2', 'status' => 'INACTIVE' },
        { 'name' => 'Task 3', 'status' => 'ACTIVE' }
      ]
    }
    
    result = @engine.new(template, data).render
    assert_equal "✅ Task 1✅ Task 3", result
  end

  def test_complex_jira_template_structure
    template = <<~TEMPLATE
      *Report*
      {#each critical_errors}
      ☐ {file_reference} - {description}
      {/each}
      
      Status: {#if all_done}Complete{#else}In Progress{/if}
    TEMPLATE
    
    data = {
      'critical_errors' => [
        { 'file_reference' => '*app.rb:42*', 'description' => 'SQL injection' },
        { 'file_reference' => '*auth.rb:15*', 'description' => 'Missing validation' }
      ],
      'all_done' => false
    }
    
    result = @engine.new(template, data).render
    
    assert_includes result, "☐ *app.rb:42* - SQL injection"
    assert_includes result, "☐ *auth.rb:15* - Missing validation"
    assert_includes result, "Status: In Progress"
  end

  def test_nested_conditionals_with_multiple_statuses
    template = <<~TEMPLATE
      {#each requirements}
      {#if status == 'IMPLEMENTED'}
      ☑ ✅ *IMPLEMENTED:* {description}
      {/if}
      {#if status == 'PARTIALLY_IMPLEMENTED'}
      ☐ ⚠️ *PARTIALLY IMPLEMENTED:* {description}
      {/if}
      {#if status == 'NOT_IMPLEMENTED'}
      ☐ ❌ *NOT IMPLEMENTED:* {description}
      {/if}
      {/each}
    TEMPLATE
    
    data = {
      'requirements' => [
        { 'status' => 'IMPLEMENTED', 'description' => 'User login working' },
        { 'status' => 'PARTIALLY_IMPLEMENTED', 'description' => 'Password validation partial' },
        { 'status' => 'NOT_IMPLEMENTED', 'description' => 'Two-factor auth missing' }
      ]
    }
    
    result = @engine.new(template, data).render
    
    assert_includes result, "☑ ✅ *IMPLEMENTED:* User login working"
    assert_includes result, "☐ ⚠️ *PARTIALLY IMPLEMENTED:* Password validation partial"
    assert_includes result, "☐ ❌ *NOT IMPLEMENTED:* Two-factor auth missing"
  end

  def test_special_characters_in_template
    template = "Symbols: {symbol} & {emoji} → {result}"
    data = { 'symbol' => '☐', 'emoji' => '🚀', 'result' => 'success' }
    
    result = @engine.new(template, data).render
    assert_equal "Symbols: ☐ & 🚀 → success", result
  end

  def test_multiline_template_with_mixed_content
    template = <<~TEMPLATE
      # Analysis Report
      
      ## Summary
      {summary}
      
      ## Issues ({issue_count})
      {#each issues}
      - {severity}: {description}
      {/each}
      
      ## Status
      {#if complete}All done!{#else}Work in progress{/if}
    TEMPLATE
    
    data = {
      'summary' => 'Code review completed',
      'issue_count' => 2,
      'issues' => [
        { 'severity' => 'HIGH', 'description' => 'Security vulnerability' },
        { 'severity' => 'LOW', 'description' => 'Style issue' }
      ],
      'complete' => true
    }
    
    result = @engine.new(template, data).render
    
    assert_includes result, "Code review completed"
    assert_includes result, "Issues (2)"
    assert_includes result, "HIGH: Security vulnerability"
    assert_includes result, "LOW: Style issue"
    assert_includes result, "All done!"
  end

  def test_merge_conflict_prompt_template_includes_line_numbers
    # Test that the merge conflict prompt template includes line number placeholders
    template_path = File.join(File.dirname(__FILE__), '../../lib/n2b/templates/merge_conflict_prompt.txt')

    assert File.exist?(template_path), "Merge conflict prompt template should exist"

    template_content = File.read(template_path)

    # Should include line number placeholders
    assert_includes template_content, '{start_line}', "Template should include {start_line} placeholder"
    assert_includes template_content, '{end_line}', "Template should include {end_line} placeholder"

    # Should include contextual line number instructions
    assert_includes template_content, 'Lines {start_line}-{end_line}', "Template should reference line range"
    assert_includes template_content, 'reference the specific line numbers', "Template should instruct LLM to reference line numbers"

    # Test that template can be rendered with line number data
    data = {
      'full_file_content' => "class Test\n  def method\n    puts 'hello'\n  end\nend",
      'start_line' => '2',
      'end_line' => '3',
      'context_before' => 'class Test',
      'base_label' => 'main',
      'base_content' => 'def method\n  puts "old"',
      'incoming_content' => 'def method\n  puts "new"',
      'incoming_label' => 'feature',
      'context_after' => 'end',
      'user_comment' => ''
    }

    result = N2B::TemplateEngine.new(template_content, data).render

    # Should contain the actual line numbers in the rendered output
    assert_includes result, 'Lines 2-3', "Rendered template should include actual line numbers"
    assert_includes result, 'line numbers (2-3)', "Rendered template should reference specific line numbers in instructions"
  end
end
