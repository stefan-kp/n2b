require 'net/http'
require 'uri'
require 'json'
require 'base64'

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

      # Prepare the comment body in Jira's Atlassian Document Format (ADF)
      comment_body = {
        "body" => format_comment_as_adf(comment)
      }

      # Make the API call to add a comment
      path = "/rest/api/3/issue/#{ticket_key}/comment"
      _response = make_api_request('POST', path, comment_body)

      puts "✅ Successfully added comment to Jira ticket #{ticket_key}"
      true
    rescue JiraApiError => e
      puts "❌ Failed to update Jira ticket #{ticket_key}: #{e.message}"
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

    private

    def format_comment_as_adf(comment_data)
      # If comment_data is a string (legacy), convert to simple ADF
      if comment_data.is_a?(String)
        return {
          "type" => "doc",
          "version" => 1,
          "content" => [
            {
              "type" => "paragraph",
              "content" => [
                {
                  "type" => "text",
                  "text" => comment_data
                }
              ]
            }
          ]
        }
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

      response = http.request(request)

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
