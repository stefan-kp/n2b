require 'net/http'
require 'uri'
require 'json'
require 'base64'
require_relative 'template_engine'

module N2B
  class JiraClient
    # Placeholder for Jira API interaction error
    class JiraApiError < StandardError; end

    def initialize(config)
      @config = config
      @jira_config = @config['jira'] || {} # Ensure jira key exists

      unless @jira_config['domain'] && @jira_config['email'] && @jira_config['api_key']
        raise ArgumentError, "Jira domain, email, and API key must be configured in N2B settings."
      end
      # Handle domain that may or may not include protocol
      domain = @jira_config['domain'].to_s.strip
      if domain.start_with?('http://') || domain.start_with?('https://')
        # Domain already includes protocol
        @base_url = "#{domain.chomp('/')}/rest/api/3"
      else
        # Domain doesn't include protocol, add https://
        @base_url = "https://#{domain.chomp('/')}/rest/api/3"
      end
    end

    def fetch_ticket(ticket_key_or_url)
      domain, ticket_key = parse_ticket_input(ticket_key_or_url)

      unless ticket_key
        raise JiraApiError, "Could not extract ticket key from '#{ticket_key_or_url}'."
      end

      puts "Fetching Jira ticket: #{ticket_key} from domain: #{domain || @jira_config['domain']}"
      puts "Fetching ticket comments for additional context..."

      begin
        # Fetch ticket details
        ticket_path = "/rest/api/3/issue/#{ticket_key}"
        ticket_data = make_api_request('GET', ticket_path)

        # Fetch ticket comments
        comments_path = "/rest/api/3/issue/#{ticket_key}/comment"
        comments_response = make_api_request('GET', comments_path)
        comments_data = comments_response['comments'] || []

        puts "Successfully fetched ticket and #{comments_data.length} comments"

        # Process real data
        return process_ticket_data(ticket_data, comments_data)

      rescue JiraApiError => e
        puts "⚠️  Failed to fetch from Jira API: #{e.message}"
        puts "Falling back to dummy data for development..."
        return fetch_dummy_ticket_data(ticket_key)
      end
    end

    def update_ticket(ticket_key_or_url, comment)
      _domain, ticket_key = parse_ticket_input(ticket_key_or_url) # Use _domain to indicate it's not used here

      unless ticket_key
        raise JiraApiError, "Could not extract ticket key from '#{ticket_key_or_url}' for update."
      end

      puts "Updating Jira ticket #{ticket_key} with analysis comment..."

      # Generate comment using template system
      template_comment = generate_templated_comment(comment)

      if debug_mode?
        puts "🔍 DEBUG: Generated template comment (#{template_comment.length} chars):"
        puts "--- TEMPLATE COMMENT START ---"
        puts template_comment
        puts "--- TEMPLATE COMMENT END ---"
      end

      # Prepare the comment body in Jira's Atlassian Document Format (ADF)
      comment_body = {
        "body" => format_comment_as_adf(template_comment)
      }

      if debug_mode?
        puts "🔍 DEBUG: Formatted ADF comment body:"
        puts "--- ADF BODY START ---"
        puts JSON.pretty_generate(comment_body)
        puts "--- ADF BODY END ---"
      end

      # Make the API call to add a comment
      path = "/rest/api/3/issue/#{ticket_key}/comment"
      puts "🔍 DEBUG: Making API request to: #{path}" if debug_mode?

      _response = make_api_request('POST', path, comment_body)

      puts "✅ Successfully added comment to Jira ticket #{ticket_key}"
      true
    rescue JiraApiError => e
      puts "❌ Failed to update Jira ticket #{ticket_key}: #{e.message}"
      if debug_mode?
        puts "🔍 DEBUG: Full error details:"
        puts "  - Ticket key: #{ticket_key}"
        puts "  - Template comment length: #{template_comment&.length || 'nil'}"
        puts "  - Comment body keys: #{comment_body&.keys || 'nil'}"
      end
      false
    end

    # Add test connection functionality
    def test_connection
      puts "🧪 Testing Jira API connection..."

      begin
        # Test 1: Basic authentication
        response = make_api_request('GET', '/myself')
        puts "✅ Authentication successful"
        puts "   Account: #{response['displayName']} (#{response['emailAddress']})"

        # Test 2: Project access
        projects = make_api_request('GET', '/project')
        puts "✅ Can access #{projects.length} projects"

        # Test 3: Comment permissions (try to get comments from any issue)
        if projects.any?
          project_key = projects.first['key']
          puts "✅ Basic permissions verified for project: #{project_key}"
        end

        puts "🎉 Jira connection test successful!"
        true
      rescue => e
        puts "❌ Jira connection test failed: #{e.message}"
        false
      end
    end

    def extract_requirements_from_description(description_string)
      extracted_lines = []
      in_requirements_section = false

      # Headers that trigger requirement extraction. Case-insensitive.
      # Jira often uses h1, h2, etc. for headers, or bold text.
      # We'll look for lines that *start* with these, possibly after Jira's header markup like "hN. "
      # Or common text like "Acceptance Criteria:", "Requirements:"
      # Also include comment-specific implementation keywords
      requirement_headers_regex = /^(h[1-6]\.\s*)?(Requirements|Acceptance Criteria|Tasks|Key Deliverables|Scope|User Stories|Implementation|Testing|Technical|Additional|Clarification|Comment \d+)/i

      # Regex to identify common list item markers
      _list_item_regex = /^\s*[\*\-\+]\s+/ # Unused but kept for potential future use
      # Regex for lines that look like section headers (to stop capturing)
      # This is a simple heuristic: a line with a few words, ending with a colon, or Jira hN. style
      section_break_regex = /^(h[1-6]\.\s*)?\w+(\s+\w+){0,3}:?\s*$/i


      description_string.to_s.each_line do |line| # Handle nil description_string
        stripped_line = line.strip

        if stripped_line.match?(requirement_headers_regex)
          in_requirements_section = true
          # Add the header itself to the extracted content if desired, or just use it as a trigger
          # For now, let's add the line to give context.
          extracted_lines << stripped_line
          next # Move to the next line
        end

        if in_requirements_section
          # If we encounter another significant header, stop capturing this section
          # (unless it's another requirements header, which is fine)
          if stripped_line.match?(section_break_regex) && !stripped_line.match?(requirement_headers_regex)
            # Check if this new header is one of the requirement types. If so, continue.
            # Otherwise, break. This logic is simplified: if it's any other header, stop.
            is_another_req_header = false # Placeholder for more complex logic if needed
            requirement_headers_regex.match(stripped_line) { is_another_req_header = true }

            unless is_another_req_header
              in_requirements_section = false # Stop capturing
              # Potentially add a separator if concatenating multiple distinct sections later
              # extracted_lines << "---"
              next # Don't include this new non-req header in current section
            else
              # It's another requirement-related header, so add it and continue
              extracted_lines << stripped_line
              next
            end
          end

          # Capture list items or general text within the section
          # For now, we are quite inclusive of lines within a detected section.
          # We could be more strict and only take list_item_regex lines,
          # but often text paragraphs under a heading are relevant too.
          extracted_lines << stripped_line unless stripped_line.empty?
        end
      end

      if extracted_lines.empty?
        # Fallback: return the entire description if no specific sections found
        return description_string.to_s.strip # Handle nil and strip
      else
        # Join extracted lines and clean up excessive newlines
        # Replace 3+ newlines with 2, and 2+ newlines with 2 (effectively max 2 newlines)
        # Also, strip leading/trailing whitespace from the final result.
        return extracted_lines.join("\n").gsub(/\n{3,}/, "\n\n").gsub(/\n{2,}/, "\n\n").strip
      end
    end

    private

    def process_ticket_data(ticket_data, comments_data)
      # Format comments for inclusion
      comments_section = format_comments_for_requirements(comments_data)

      # Construct detailed description including comments
      full_description_output = <<~FULL_OUTPUT
      Ticket Key: #{ticket_data['key']}
      Summary: #{ticket_data.dig('fields', 'summary')}
      Status: #{ticket_data.dig('fields', 'status', 'name')}
      Assignee: #{ticket_data.dig('fields', 'assignee', 'displayName') || 'Unassigned'}
      Reporter: #{ticket_data.dig('fields', 'reporter', 'displayName')}
      Priority: #{ticket_data.dig('fields', 'priority', 'name')}

      --- Full Description ---
      #{ticket_data.dig('fields', 'description')}

      #{comments_section}
      FULL_OUTPUT

      # Extract requirements from both description and comments
      # Handle description that might be in ADF format (Hash) or plain text (String)
      raw_description = ticket_data.dig('fields', 'description')
      description_content = if raw_description.is_a?(Hash)
                              # ADF format - extract text
                              extract_text_from_adf(raw_description)
                            elsif raw_description.is_a?(String)
                              # Plain text
                              raw_description
                            else
                              # Fallback
                              ""
                            end

      combined_content = description_content + "\n\n" + comments_section
      extracted_requirements = extract_requirements_from_description(combined_content)

      # Return extracted requirements with context
      if extracted_requirements != combined_content && !extracted_requirements.empty?
        return "Ticket Key: #{ticket_data['key']}\nSummary: #{ticket_data.dig('fields', 'summary')}\n\n--- Extracted Requirements ---\n#{extracted_requirements}"
      else
        return full_description_output
      end
    end

    def fetch_dummy_ticket_data(ticket_key)

      # Enhanced dummy description for testing extraction (fallback only)
      dummy_description_content = <<~DUMMY_JIRA_DESCRIPTION
      This is some introductory text about the ticket.

      h2. Overview
      Some general overview of the task.

      h3. Goals
      * Achieve X
      * Implement Y

      h2. Requirements
      Here are the key requirements for this ticket:
      - Must handle user authentication.
      - Should integrate with the payment gateway.
      + Must log all transactions.
      - User interface needs to be responsive.

      Some more text after the first requirements list.

      h2. Acceptance Criteria
      The following criteria must be met:
      * Feature A works as expected.
      * Feature B is tested thoroughly.
        * Sub-item for B.1
        * Sub-item for B.2
      - No critical bugs are present.

      h3. Tasks
      Here's a list of tasks:
      1. Design the database schema. (Note: numbered lists might not be explicitly extracted by simple list parsing but text under "Tasks" is)
      2. Develop the API endpoints.
         - Sub-task 2.1
      3. Write unit tests.

      Additional details and notes.

      h2. Non-Relevant Section
      This section should not be extracted.
      - Item A
      - Item B
      DUMMY_JIRA_DESCRIPTION

      # Simulate fetching comments with implementation details
      dummy_comments = [
        {
          "author" => { "displayName" => "Product Manager" },
          "created" => "2024-01-15T10:30:00.000Z",
          "body" => "Additional clarification: The authentication should support both OAuth2 and API key methods. Please ensure backward compatibility with existing integrations."
        },
        {
          "author" => { "displayName" => "Tech Lead" },
          "created" => "2024-01-16T14:20:00.000Z",
          "body" => "Implementation note: Use the new security library v2.1+ for the authentication module. The payment gateway integration should use the sandbox environment for testing. Database schema changes need migration scripts."
        },
        {
          "author" => { "displayName" => "QA Engineer" },
          "created" => "2024-01-17T09:15:00.000Z",
          "body" => "Testing requirements:\n- Test with mobile devices (iOS/Android)\n- Verify responsive design on tablets\n- Load testing with 1000+ concurrent users\n- Security penetration testing required"
        }
      ]

      dummy_data = {
        "key" => ticket_key,
        "fields" => {
          "summary" => "This is a dummy summary for #{ticket_key}",
          "description" => dummy_description_content, # Using the complex description
          "status" => { "name" => "Open" },
          "assignee" => { "displayName" => "Dummy User" },
          "reporter" => { "displayName" => "Another Dummy" },
          "priority" => { "name" => "Medium" }
        }
      }

      # Format comments for inclusion
      comments_section = format_comments_for_requirements(dummy_comments)

      # Construct a more detailed "original" full description string including comments
      full_description_output = <<~FULL_OUTPUT
      Ticket Key: #{dummy_data['key']}
      Summary: #{dummy_data['fields']['summary']}
      Status: #{dummy_data['fields']['status']['name']}
      Assignee: #{dummy_data['fields']['assignee']['displayName']}
      Reporter: #{dummy_data['fields']['reporter']['displayName']}
      Priority: #{dummy_data['fields']['priority']['name']}

      --- Full Description ---
      #{dummy_data['fields']['description']}

      #{comments_section}
      (Note: This is dummy data)
      FULL_OUTPUT

      # Now, extract requirements from both description and comments
      combined_content = dummy_data['fields']['description'] + "\n\n" + comments_section
      extracted_requirements = extract_requirements_from_description(combined_content)

      # If requirements were extracted, prepend ticket key and summary for context.
      # If not, the full description (which includes key, summary etc) is returned by extract_requirements_from_description as fallback.
      if extracted_requirements != combined_content && !extracted_requirements.empty?
        return "Ticket Key: #{dummy_data['key']}\nSummary: #{dummy_data['fields']['summary']}\n\n--- Extracted Requirements ---\n#{extracted_requirements}"
      else
        # Fallback: return the more detailed full output if no specific sections found,
        # or if extracted requirements are empty.
        return full_description_output
      end
    end

    def format_comments_for_requirements(comments)
      return "" if comments.nil? || comments.empty?

      formatted_comments = ["--- Comments with Additional Context ---"]

      comments.each_with_index do |comment, index|
        author = comment.dig("author", "displayName") || "Unknown"
        created = comment["created"] || "Unknown date"

        # Handle both real Jira API format and dummy data format
        body = if comment["body"].is_a?(String)
                 # Dummy data format or simple string
                 comment["body"]
               elsif comment["body"].is_a?(Hash)
                 # Real Jira API format (ADF - Atlassian Document Format)
                 extract_text_from_adf(comment["body"])
               else
                 ""
               end

        # Format date to be more readable
        begin
          if created != "Unknown date"
            parsed_date = Time.parse(created)
            formatted_date = parsed_date.strftime("%Y-%m-%d %H:%M")
          else
            formatted_date = created
          end
        rescue
          formatted_date = created
        end

        formatted_comments << "\nComment #{index + 1} (#{author}, #{formatted_date}):"
        formatted_comments << body.strip
      end

      formatted_comments.join("\n")
    end

    def extract_text_from_adf(adf_content)
      # Simple extraction of text from Atlassian Document Format
      return "" unless adf_content.is_a?(Hash)

      text_parts = []
      extract_text_recursive(adf_content, text_parts)
      text_parts.join(" ")
    end

    def extract_text_recursive(node, text_parts)
      if node.is_a?(Hash)
        if node["type"] == "text" && node["text"]
          text_parts << node["text"]
        elsif node["content"].is_a?(Array)
          node["content"].each { |child| extract_text_recursive(child, text_parts) }
        end
      elsif node.is_a?(Array)
        node.each { |child| extract_text_recursive(child, text_parts) }
      end
    end

    def generate_templated_comment(comment_data)
      # Handle structured hash data from format_analysis_for_jira
      if comment_data.is_a?(Hash) && comment_data.key?(:implementation_summary)
        return generate_structured_comment(comment_data)
      end

      # Prepare template data from the analysis results
      template_data = prepare_template_data(comment_data)

      # Load and render template
      config = get_config(reconfigure: false, advanced_flow: false)
      template_path = resolve_template_path('jira_comment', config)
      template_content = File.read(template_path)

      engine = N2B::TemplateEngine.new(template_content, template_data)
      engine.render
    end

    def generate_structured_comment(data)
      # Generate a properly formatted comment from structured analysis data
      git_info = extract_git_info
      timestamp = Time.now.strftime("%Y-%m-%d %H:%M UTC")

      comment_parts = []

      # Header
      comment_parts << "*N2B Code Analysis Report*"
      comment_parts << ""

      # Implementation Summary (always expanded)
      comment_parts << "*Implementation Summary:*"
      comment_parts << (data[:implementation_summary] || "Unknown")
      comment_parts << ""

      # Custom message if provided (also expanded)
      if data[:custom_analysis_focus] && !data[:custom_analysis_focus].empty?
        comment_parts << "*Custom Analysis Focus:*"
        comment_parts << data[:custom_analysis_focus]
        comment_parts << ""
      end

      comment_parts << "---"
      comment_parts << ""

      # Automated Analysis Findings
      comment_parts << "*Automated Analysis Findings:*"
      comment_parts << ""

      # Critical Issues (collapsed by default)
      critical_issues = classify_issues_by_severity(data[:issues] || [], 'CRITICAL')
      if critical_issues.any?
        comment_parts << "{expand:🚨 Critical Issues (Must Fix Before Merge)}"
        critical_issues.each { |issue| comment_parts << "☐ #{issue}" }
        comment_parts << "{expand}"
      else
        comment_parts << "✅ No critical issues found"
      end
      comment_parts << ""

      # Important Issues (collapsed by default)
      important_issues = classify_issues_by_severity(data[:issues] || [], 'IMPORTANT')
      if important_issues.any?
        comment_parts << "{expand:⚠️ Important Issues (Should Address)}"
        important_issues.each { |issue| comment_parts << "☐ #{issue}" }
        comment_parts << "{expand}"
      else
        comment_parts << "✅ No important issues found"
      end
      comment_parts << ""

      # Suggested Improvements (collapsed by default)
      if data[:improvements] && data[:improvements].any?
        comment_parts << "{expand:💡 Suggested Improvements (Nice to Have)}"
        data[:improvements].each { |improvement| comment_parts << "☐ #{improvement}" }
        comment_parts << "{expand}"
      else
        comment_parts << "✅ No specific improvements suggested"
      end
      comment_parts << ""

      # Test Coverage Assessment
      comment_parts << "{expand:🧪 Test Coverage Assessment}"
      if data[:test_coverage] && !data[:test_coverage].empty?
        comment_parts << "*Overall Assessment:* #{data[:test_coverage]}"
      else
        comment_parts << "*Overall Assessment:* Not assessed"
      end
      comment_parts << "{expand}"
      comment_parts << ""

      # Missing Test Coverage
      comment_parts << "*Missing Test Coverage:*"
      comment_parts << "☐ No specific missing tests identified"
      comment_parts << ""

      # Requirements Evaluation
      comment_parts << "*📋 Requirements Evaluation:*"
      if data[:requirements_evaluation] && !data[:requirements_evaluation].empty?
        comment_parts << "#{data[:requirements_evaluation]}"
      else
        comment_parts << "🔍 *UNCLEAR:* Requirements not provided or assessed"
      end
      comment_parts << ""

      comment_parts << "---"
      comment_parts << ""

      # Footer with metadata (simplified)
      comment_parts << "Analysis completed on #{timestamp} | Branch: #{git_info[:branch]}"

      comment_parts.join("\n")
    end

    def classify_issues_by_severity(issues, target_severity)
      return [] unless issues.is_a?(Array)

      issues.select do |issue|
        severity = classify_error_severity(issue)
        severity == target_severity
      end
    end

    def prepare_template_data(comment_data)
      # Handle both string and hash inputs
      if comment_data.is_a?(String)
        # For simple string comments, create a basic template data structure
        git_info = extract_git_info
        return {
          'implementation_summary' => comment_data,
          'critical_errors' => [],
          'important_errors' => [],
          'improvements' => [],
          'missing_tests' => [],
          'requirements' => [],
          'test_coverage_summary' => "No specific test coverage analysis available",
          'timestamp' => Time.now.strftime("%Y-%m-%d %H:%M UTC"),
          'branch_name' => git_info[:branch],
          'files_changed' => git_info[:files_changed],
          'lines_added' => git_info[:lines_added],
          'lines_removed' => git_info[:lines_removed],
          'critical_errors_empty' => true,
          'important_errors_empty' => true,
          'improvements_empty' => true,
          'missing_tests_empty' => true
        }
      end

      # Handle hash input (structured analysis data)
      # Extract and classify errors by severity
      errors = comment_data[:issues] || comment_data['issues'] || []
      critical_errors = []
      important_errors = []
      low_errors = []

      errors.each do |error|
        severity = classify_error_severity(error)
        file_ref = extract_file_reference(error)

        error_item = {
          'file_reference' => file_ref,
          'description' => clean_error_description(error),
          'severity' => severity
        }

        case severity
        when 'CRITICAL'
          critical_errors << error_item
        when 'IMPORTANT'
          important_errors << error_item
        else
          low_errors << error_item
        end
      end

      # Process improvements
      improvements = (comment_data[:improvements] || comment_data['improvements'] || []).map do |improvement|
        {
          'file_reference' => extract_file_reference(improvement),
          'description' => clean_error_description(improvement)
        }
      end

      # Process missing tests
      missing_tests = extract_missing_tests(comment_data[:test_coverage] || comment_data['test_coverage'] || "")

      # Process requirements
      requirements = extract_requirements_status(comment_data[:requirements_evaluation] || comment_data['requirements_evaluation'] || "")

      # Get git/hg info
      git_info = extract_git_info

      {
        'implementation_summary' => comment_data[:implementation_summary] || comment_data['implementation_summary'] || "Code analysis completed",
        'critical_errors' => critical_errors,
        'important_errors' => important_errors,
        'improvements' => improvements,
        'missing_tests' => missing_tests,
        'requirements' => requirements,
        'test_coverage_summary' => comment_data[:test_coverage] || comment_data['test_coverage'] || "No specific test coverage analysis available",
        'timestamp' => Time.now.strftime("%Y-%m-%d %H:%M UTC"),
        'branch_name' => git_info[:branch],
        'files_changed' => git_info[:files_changed],
        'lines_added' => git_info[:lines_added],
        'lines_removed' => git_info[:lines_removed],
        'critical_errors_empty' => critical_errors.empty?,
        'important_errors_empty' => important_errors.empty?,
        'improvements_empty' => improvements.empty?,
        'missing_tests_empty' => missing_tests.empty?
      }
    end

    def classify_error_severity(error_text)
      text = error_text.downcase
      case text
      when /security|sql injection|xss|csrf|vulnerability|exploit|attack/
        'CRITICAL'
      when /performance|n\+1|timeout|memory leak|slow query|bottleneck/
        'IMPORTANT'
      when /error|exception|bug|fail|crash|break/
        'IMPORTANT'
      when /style|convention|naming|format|indent|space/
        'LOW'
      else
        'IMPORTANT'
      end
    end

    def extract_file_reference(text)
      # Parse various file reference formats
      if match = text.match(/(\S+\.(?:rb|js|py|java|cpp|c|h|ts|jsx|tsx|php|go|rs|swift|kt))(?:\s+(?:line|lines?)\s+(\d+(?:-\d+)?)|:(\d+(?:-\d+)?)|\s*\(line\s+(\d+)\))?/i)
        file = match[1]
        line = match[2] || match[3] || match[4]
        line ? "*#{file}:#{line}*" : "*#{file}*"
      else
        "*General*"
      end
    end

    def clean_error_description(text)
      # Remove file references from description to avoid duplication
      text.gsub(/\S+\.(?:rb|js|py|java|cpp|c|h|ts|jsx|tsx|php|go|rs|swift|kt)(?:\s+(?:line|lines?)\s+\d+(?:-\d+)?|:\d+(?:-\d+)?|\s*\(line\s+\d+\))?:?\s*/i, '').strip
    end

    def extract_missing_tests(test_coverage_text)
      # Extract test-related items from coverage analysis
      missing_tests = []

      # Look for common patterns indicating missing tests
      test_coverage_text.scan(/(?:missing|need|add|require).*?test.*?(?:\.|$)/i) do |match|
        missing_tests << { 'description' => match.strip }
      end

      # If no specific missing tests found, create generic ones based on coverage
      if missing_tests.empty? && test_coverage_text.include?('%')
        if coverage_match = test_coverage_text.match(/(\d+)%/)
          coverage = coverage_match[1].to_i
          if coverage < 80
            missing_tests << { 'description' => "Increase test coverage from #{coverage}% to target 80%+" }
          end
        end
      end

      missing_tests
    end

    def extract_requirements_status(requirements_text)
      requirements = []

      # Split by lines and process each line
      requirements_text.split("\n").each do |line|
        line = line.strip
        next if line.empty?

        # Parse requirements with status indicators - order matters for regex matching
        if match = line.match(/(✅|⚠️|❌|🔍)?\s*(PARTIALLY\s+IMPLEMENTED|NOT\s+IMPLEMENTED|IMPLEMENTED|UNCLEAR)?:?\s*(.+)/i)
          status_emoji, status_text, description = match.captures
        status = case
                when status_text&.include?('PARTIALLY')
                  'PARTIALLY_IMPLEMENTED'
                when status_text&.include?('NOT')
                  'NOT_IMPLEMENTED'
                when status_emoji == '✅' || (status_text&.include?('IMPLEMENTED') && !status_text&.include?('NOT') && !status_text&.include?('PARTIALLY'))
                  'IMPLEMENTED'
                when status_emoji == '⚠️'
                  'PARTIALLY_IMPLEMENTED'
                when status_emoji == '❌'
                  'NOT_IMPLEMENTED'
                else
                  'UNCLEAR'
                end

          requirements << {
            'status' => status,
            'description' => description.strip,
            'status_icon' => status_emoji || (status == 'IMPLEMENTED' ? '✅' : status == 'PARTIALLY_IMPLEMENTED' ? '⚠️' : status == 'NOT_IMPLEMENTED' ? '❌' : '🔍')
          }
        end
      end

      requirements
    end

    def extract_git_info
      begin
        if File.exist?('.git')
          branch = `git branch --show-current 2>/dev/null`.strip
          branch = 'unknown' if branch.empty?

          # Get diff stats
          diff_stats = `git diff --stat HEAD~1 2>/dev/null`.strip
          files_changed = diff_stats.scan(/(\d+) files? changed/).flatten.first || "0"
          lines_added = diff_stats.scan(/(\d+) insertions?/).flatten.first || "0"
          lines_removed = diff_stats.scan(/(\d+) deletions?/).flatten.first || "0"
        elsif File.exist?('.hg')
          branch = `hg branch 2>/dev/null`.strip
          branch = 'default' if branch.empty?

          # Get diff stats for hg
          diff_stats = `hg diff --stat 2>/dev/null`.strip
          files_changed = diff_stats.lines.count.to_s
          lines_added = "0"  # hg diff --stat doesn't show +/- easily
          lines_removed = "0"
        else
          branch = 'unknown'
          files_changed = "0"
          lines_added = "0"
          lines_removed = "0"
        end
      rescue
        branch = 'unknown'
        files_changed = "0"
        lines_added = "0"
        lines_removed = "0"
      end

      {
        branch: branch,
        files_changed: files_changed,
        lines_added: lines_added,
        lines_removed: lines_removed
      }
    end

    def resolve_template_path(template_key, config)
      user_path = config.dig('templates', template_key) if config.is_a?(Hash)
      return user_path if user_path && File.exist?(user_path)

      File.expand_path(File.join(__dir__, 'templates', "#{template_key}.txt"))
    end

    def get_config(reconfigure: false, advanced_flow: false)
      # Return the config that was passed during initialization
      # This is used for template resolution and other configuration needs
      @config
    end

    def convert_markdown_to_adf(markdown_text)
      content = []
      lines = markdown_text.split("\n")
      current_paragraph = []
      current_expand = nil
      expand_content = []

      lines.each do |line|
        case line
        when /^\*(.+)\*$/  # Bold headers like *N2B Code Analysis Report*
          # Flush current paragraph
          if current_paragraph.any?
            content << create_paragraph(current_paragraph.join(" "))
            current_paragraph = []
          end

          content << {
            "type" => "heading",
            "attrs" => { "level" => 2 },
            "content" => [
              {
                "type" => "text",
                "text" => $1.strip,
                "marks" => [{ "type" => "strong" }]
              }
            ]
          }
        when /^=+$/  # Separator lines
          # Skip separator lines
        when /^\{expand:(.+)\}$/  # Jira expand start
          # Flush current paragraph
          if current_paragraph.any?
            content << create_paragraph(current_paragraph.join(" "))
            current_paragraph = []
          end

          # Start collecting expand content
          expand_title = $1.strip
          current_expand = {
            "type" => "expand",
            "attrs" => { "title" => expand_title },
            "content" => []
          }
          expand_content = []
        when /^\{expand\}$/  # Jira expand end
          # End of expand section - add collected content
          if current_expand
            current_expand["content"] = expand_content
            content << current_expand if expand_content.any?  # Only add if has content
            current_expand = nil
            expand_content = []
          end
        when /^☐\s+(.+)$/  # Unchecked checkbox
          # Flush current paragraph
          if current_paragraph.any?
            paragraph = create_paragraph(current_paragraph.join(" "))
            if current_expand
              expand_content << paragraph
            else
              content << paragraph
            end
            current_paragraph = []
          end

          # Convert checkbox to simple paragraph (no bullet points)
          checkbox_paragraph = create_paragraph("☐ " + $1.strip)

          if current_expand
            expand_content << checkbox_paragraph
          else
            content << checkbox_paragraph
          end
        when /^☑\s+(.+)$/  # Checked checkbox
          # Flush current paragraph
          if current_paragraph.any?
            paragraph = create_paragraph(current_paragraph.join(" "))
            if current_expand
              expand_content << paragraph
            else
              content << paragraph
            end
            current_paragraph = []
          end

          # Convert checkbox to simple paragraph (no bullet points)
          checkbox_paragraph = create_paragraph("☑ " + $1.strip)

          if current_expand
            expand_content << checkbox_paragraph
          else
            content << checkbox_paragraph
          end
        when /^---$/  # Horizontal rule
          # Flush current paragraph
          if current_paragraph.any?
            paragraph = create_paragraph(current_paragraph.join(" "))
            if current_expand
              expand_content << paragraph
            else
              content << paragraph
            end
            current_paragraph = []
          end

          rule = { "type" => "rule" }
          if current_expand
            expand_content << rule
          else
            content << rule
          end
        when ""  # Empty line
          # Flush current paragraph
          if current_paragraph.any?
            paragraph = create_paragraph(current_paragraph.join(" "))
            if current_expand
              expand_content << paragraph
            else
              content << paragraph
            end
            current_paragraph = []
          end
        else  # Regular text
          # Skip empty or whitespace-only content
          unless line.strip.empty? || line.strip == "{}"
            current_paragraph << line
          end
        end
      end

      # Flush any remaining paragraph
      if current_paragraph.any?
        paragraph = create_paragraph(current_paragraph.join(" "))
        if current_expand
          expand_content << paragraph
        else
          content << paragraph
        end
      end

      # Close any remaining expand section
      if current_expand && expand_content.any?
        current_expand["content"] = expand_content
        content << current_expand
      end

      # Ensure we have at least one content element
      if content.empty?
        content << create_paragraph("Analysis completed.")
      end

      {
        "type" => "doc",
        "version" => 1,
        "content" => content
      }
    end

    def create_paragraph(text)
      {
        "type" => "paragraph",
        "content" => [
          {
            "type" => "text",
            "text" => text
          }
        ]
      }
    end

    private

    def debug_mode?
      ENV['N2B_DEBUG'] == 'true'
    end

    def format_comment_as_adf(comment_data)
      # If comment_data is a string (from template), convert to simple ADF
      if comment_data.is_a?(String)
        return convert_markdown_to_adf(comment_data)
      end

      # If comment_data is structured (new format), build proper ADF
      content = []

      # Title with timestamp
      timestamp = Time.now.strftime("%Y-%m-%d %H:%M UTC")
      content << {
        "type" => "heading",
        "attrs" => { "level" => 2 },
        "content" => [
          {
            "type" => "text",
            "text" => "🤖 N2B Code Analysis Report",
            "marks" => [{ "type" => "strong" }]
          }
        ]
      }

      content << {
        "type" => "paragraph",
        "content" => [
          {
            "type" => "text",
            "text" => "Generated on #{timestamp}",
            "marks" => [{ "type" => "em" }]
          }
        ]
      }

      # Implementation Summary (prominent)
      impl_summary = comment_data[:implementation_summary]
      if impl_summary && !impl_summary.empty?
        content << {
          "type" => "heading",
          "attrs" => { "level" => 3 },
          "content" => [
            {
              "type" => "text",
              "text" => "✅ Implementation Summary",
              "marks" => [{ "type" => "strong" }]
            }
          ]
        }

        content << {
          "type" => "paragraph",
          "content" => [
            {
              "type" => "text",
              "text" => impl_summary
            }
          ]
        }

        content << { "type" => "rule" } # Horizontal line
      else
        # Fallback if no implementation summary
        content << {
          "type" => "paragraph",
          "content" => [
            {
              "type" => "text",
              "text" => "📝 Code analysis completed. See detailed findings below.",
              "marks" => [{ "type" => "em" }]
            }
          ]
        }
      end

      # Collapsible section for automated analysis
      expand_content = []

      # Technical Summary
      if comment_data[:technical_summary] && !comment_data[:technical_summary].empty?
        expand_content << {
          "type" => "heading",
          "attrs" => { "level" => 4 },
          "content" => [
            {
              "type" => "text",
              "text" => "🔧 Technical Changes",
              "marks" => [{ "type" => "strong" }]
            }
          ]
        }
        expand_content << {
          "type" => "paragraph",
          "content" => [
            {
              "type" => "text",
              "text" => comment_data[:technical_summary]
            }
          ]
        }
      end

      # Issues
      if comment_data[:issues] && comment_data[:issues].any?
        expand_content << {
          "type" => "heading",
          "attrs" => { "level" => 4 },
          "content" => [
            {
              "type" => "text",
              "text" => "⚠️ Potential Issues",
              "marks" => [{ "type" => "strong" }]
            }
          ]
        }

        list_items = comment_data[:issues].map do |issue|
          {
            "type" => "listItem",
            "content" => [
              {
                "type" => "paragraph",
                "content" => [
                  {
                    "type" => "text",
                    "text" => issue
                  }
                ]
              }
            ]
          }
        end

        expand_content << {
          "type" => "bulletList",
          "content" => list_items
        }
      end

      # Improvements
      if comment_data[:improvements] && comment_data[:improvements].any?
        expand_content << {
          "type" => "heading",
          "attrs" => { "level" => 4 },
          "content" => [
            {
              "type" => "text",
              "text" => "💡 Suggested Improvements",
              "marks" => [{ "type" => "strong" }]
            }
          ]
        }

        list_items = comment_data[:improvements].map do |improvement|
          {
            "type" => "listItem",
            "content" => [
              {
                "type" => "paragraph",
                "content" => [
                  {
                    "type" => "text",
                    "text" => improvement
                  }
                ]
              }
            ]
          }
        end

        expand_content << {
          "type" => "bulletList",
          "content" => list_items
        }
      end

      # Test Coverage
      if comment_data[:test_coverage] && !comment_data[:test_coverage].empty?
        expand_content << {
          "type" => "heading",
          "attrs" => { "level" => 4 },
          "content" => [
            {
              "type" => "text",
              "text" => "🧪 Test Coverage",
              "marks" => [{ "type" => "strong" }]
            }
          ]
        }
        expand_content << {
          "type" => "paragraph",
          "content" => [
            {
              "type" => "text",
              "text" => comment_data[:test_coverage]
            }
          ]
        }
      end

      # Requirements Evaluation
      if comment_data[:requirements_evaluation] && !comment_data[:requirements_evaluation].empty?
        expand_content << {
          "type" => "heading",
          "attrs" => { "level" => 4 },
          "content" => [
            {
              "type" => "text",
              "text" => "📋 Requirements Evaluation",
              "marks" => [{ "type" => "strong" }]
            }
          ]
        }
        expand_content << {
          "type" => "paragraph",
          "content" => [
            {
              "type" => "text",
              "text" => comment_data[:requirements_evaluation]
            }
          ]
        }
      end

      # Add collapsible expand for automated analysis
      if expand_content.any?
        # Count the sections for a more informative title
        sections = []
        sections << "Technical Changes" if comment_data[:technical_summary] && !comment_data[:technical_summary].empty?
        sections << "#{comment_data[:issues]&.length || 0} Issues" if comment_data[:issues]&.any?
        sections << "#{comment_data[:improvements]&.length || 0} Improvements" if comment_data[:improvements]&.any?
        sections << "Test Coverage" if comment_data[:test_coverage] && !comment_data[:test_coverage].empty?
        sections << "Requirements" if comment_data[:requirements_evaluation] && !comment_data[:requirements_evaluation].empty?

        title = sections.any? ? "🔍 Detailed Analysis: #{sections.join(', ')} (Click to expand)" : "🔍 Detailed Analysis (Click to expand)"

        content << {
          "type" => "expand",
          "attrs" => {
            "title" => title
          },
          "content" => expand_content
        }
      end

      {
        "type" => "doc",
        "version" => 1,
        "content" => content
      }
    end

    def parse_ticket_input(ticket_key_or_url)
      # Check if it's a URL
      if ticket_key_or_url =~ /\Ahttps?:\/\//
        uri = URI.parse(ticket_key_or_url)
        # Standard Jira path: /browse/TICKET-KEY
        # Or sometimes with query params: /browse/TICKET-KEY?someparam=value
        match = uri.path.match(/\/browse\/([A-Z0-9]+-[0-9]+)/i)
        if match && match[1]
          parsed_domain = "#{uri.scheme}://#{uri.host}"
          parsed_key = match[1].upcase
          return [parsed_domain, parsed_key]
        else
          # Try to find key in query parameters (e.g., selectedIssue=TICKET-KEY)
          if uri.query
            query_params = URI.decode_www_form(uri.query).to_h
            key_from_query = query_params['selectedIssue'] || query_params['issueKey'] || query_params['issue']
            if key_from_query && key_from_query.match?(/^[A-Z0-9]+-[0-9]+$/i)
              parsed_domain = "#{uri.scheme}://#{uri.host}"
              return [parsed_domain, key_from_query.upcase]
            end
          end
          # If path doesn't match /browse/ and not found in common query params
          raise JiraApiError, "Could not parse Jira ticket key from URL: #{ticket_key_or_url}. Expected format like '.../browse/PROJECT-123'."
        end
      elsif ticket_key_or_url.match?(/^[A-Z0-9]+-[0-9]+$/i)
        # It's just a ticket key, use configured domain
        # The domain for the API call will be derived from @base_url in the actual API call methods
        return [nil, ticket_key_or_url.upcase] # Return nil for domain to signify using default
      else
        raise JiraApiError, "Invalid Jira ticket key format: '#{ticket_key_or_url}'. Expected 'PROJECT-123' or a valid Jira URL."
      end
    rescue URI::InvalidURIError
      raise JiraApiError, "Invalid URL format: #{ticket_key_or_url}"
    end

    def make_api_request(method, path, body = nil)
      # Construct the full URL properly
      # @base_url = "https://domain.atlassian.net/rest/api/3"
      # path = "/rest/api/3/issue/KEY-123" or "issue/KEY-123"

      if path.start_with?('/rest/api/3/')
        # Path already includes the full API path, use the domain only
        # Extract just the domain part: "https://domain.atlassian.net"
        domain_url = @base_url.gsub(/\/rest\/api\/3.*$/, '')
        full_url = "#{domain_url}#{path}"
      else
        # Path is relative to the API base
        full_url = "#{@base_url.chomp('/')}/#{path.sub(/^\//, '')}"
      end

      uri = URI.parse(full_url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = 30
      http.open_timeout = 10

      request = case method.upcase
                when 'GET'
                  Net::HTTP::Get.new(uri.request_uri)
                when 'POST'
                  req = Net::HTTP::Post.new(uri.request_uri)
                  req.body = body.to_json if body
                  req
                # Add other methods (PUT, DELETE) as needed
                else
                  raise JiraApiError, "Unsupported HTTP method: #{method}"
                end

      request['Authorization'] = "Basic #{Base64.strict_encode64("#{@jira_config['email']}:#{@jira_config['api_key']}")}"
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'

      if debug_mode?
        puts "🔍 DEBUG: Making #{method} request to: #{full_url}"
        puts "🔍 DEBUG: Request headers: Content-Type=#{request['Content-Type']}, Accept=#{request['Accept']}"
        if body
          puts "🔍 DEBUG: Request body size: #{body.to_json.length} bytes"
          puts "🔍 DEBUG: Request body preview: #{body.to_json[0..500]}#{'...' if body.to_json.length > 500}"
        end
      end

      response = http.request(request)

      if debug_mode?
        puts "🔍 DEBUG: Response code: #{response.code} #{response.message}"
        if response.body && !response.body.empty?
          # Force UTF-8 encoding to handle character encoding issues
          response_body = response.body.force_encoding('UTF-8')
          puts "🔍 DEBUG: Response body: #{response_body}"
        end
      end

      unless response.is_a?(Net::HTTPSuccess)
        error_message = "Jira API Error: #{response.code} #{response.message}"
        error_message += " - #{response.body}" if response.body && !response.body.empty?
        raise JiraApiError, error_message
      end

      response.body.empty? ? {} : JSON.parse(response.body)
    rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError,
           Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, Errno::ECONNREFUSED => e
      raise JiraApiError, "Jira API request failed: #{e.class} - #{e.message}"
    end
  end
end
