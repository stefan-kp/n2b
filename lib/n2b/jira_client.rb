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
      @base_url = "https://#{@jira_config['domain']}/rest/api/3" # Using API v3
    end

    def fetch_ticket(ticket_key_or_url)
      domain, ticket_key = parse_ticket_input(ticket_key_or_url)

      unless ticket_key
        raise JiraApiError, "Could not extract ticket key from '#{ticket_key_or_url}'."
      end

      # For now, return a dummy description
      # In the future, this will make an API call to:
      # GET "#{domain || @base_url}/issue/#{ticket_key}"
      puts "Fetching Jira ticket: #{ticket_key} from domain: #{domain || @jira_config['domain']}"

      # Simulate fetching data
      # Enhanced dummy description for testing extraction
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

      # Construct a more detailed "original" full description string
      full_description_output = <<~FULL_OUTPUT
      Ticket Key: #{dummy_data['key']}
      Summary: #{dummy_data['fields']['summary']}
      Status: #{dummy_data['fields']['status']['name']}
      Assignee: #{dummy_data['fields']['assignee']['displayName']}
      Reporter: #{dummy_data['fields']['reporter']['displayName']}
      Priority: #{dummy_data['fields']['priority']['name']}

      --- Full Description ---
      #{dummy_data['fields']['description']}
      (Note: This is dummy data)
      FULL_OUTPUT

      # Now, extract requirements from the dummy_data's description field
      extracted_requirements = extract_requirements_from_description(dummy_data['fields']['description'])

      # If requirements were extracted, prepend ticket key and summary for context.
      # If not, the full description (which includes key, summary etc) is returned by extract_requirements_from_description as fallback.
      if extracted_requirements != dummy_data['fields']['description'] && !extracted_requirements.empty?
        return "Ticket Key: #{dummy_data['key']}\nSummary: #{dummy_data['fields']['summary']}\n\n--- Extracted Requirements ---\n#{extracted_requirements}"
      else
        # Fallback: return the more detailed full output if no specific sections found,
        # or if extracted requirements are empty.
        return full_description_output
      end
    end

    def extract_requirements_from_description(description_string)
      extracted_lines = []
      in_requirements_section = false

      # Headers that trigger requirement extraction. Case-insensitive.
      # Jira often uses h1, h2, etc. for headers, or bold text.
      # We'll look for lines that *start* with these, possibly after Jira's header markup like "hN. "
      # Or common text like "Acceptance Criteria:", "Requirements:"
      requirement_headers_regex = /^(h[1-6]\.\s*)?(Requirements|Acceptance Criteria|Tasks|Key Deliverables|Scope|User Stories)/i

      # Regex to identify common list item markers
      list_item_regex = /^\s*[\*\-\+]\s+/
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

    def update_ticket(ticket_key_or_url, comment)
      _domain, ticket_key = parse_ticket_input(ticket_key_or_url) # Use _domain to indicate it's not used here

      unless ticket_key
        raise JiraApiError, "Could not extract ticket key from '#{ticket_key_or_url}' for update."
      end

      # For now, just print that it would update the ticket
      # In the future, this will make an API call like:
      # POST "#{domain || @base_url}/issue/#{ticket_key}/comment"
      # with body: { "body": { "type": "doc", "version": 1, "content": [ { "type": "paragraph", "content": [ { "type": "text", "text": comment } ] } ] } }
      puts "JiraClient: Would attempt to update ticket '#{ticket_key}' on domain '#{@jira_config['domain']}' with comment: '#{comment}'"
      true # Simulate successful update
    end

    private

    def parse_ticket_input(ticket_key_or_url)
      # Check if it's a URL
      if ticket_key_or_url =~ URI::regexp(%w[http https])
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

    # Placeholder for actual API request logic (to be implemented later)
    # def make_api_request(method, path, body = nil)
    #   uri = URI.join(@base_url, path)
    #   http = Net::HTTP.new(uri.host, uri.port)
    #   http.use_ssl = (uri.scheme == 'https')
    #
    #   request = case method.upcase
    #             when 'GET'
    #               Net::HTTP::Get.new(uri.request_uri)
    #             when 'POST'
    #               req = Net::HTTP::Post.new(uri.request_uri)
    #               req.body = body.to_json if body
    #               req
    #             # Add other methods (PUT, DELETE) as needed
    #             else
    #               raise JiraApiError, "Unsupported HTTP method: #{method}"
    #             end
    #
    #   request['Authorization'] = "Basic #{Base64.strict_encode64("#{@jira_config['email']}:#{@jira_config['api_key']}")}"
    #   request['Content-Type'] = 'application/json'
    #   request['Accept'] = 'application/json'
    #
    #   response = http.request(request)
    #
    #   unless response.is_a?(Net::HTTPSuccess)
    #     error_message = "Jira API Error: #{response.code} #{response.message}"
    #     error_message += " - #{response.body}" if response.body && !response.body.empty?
    #     raise JiraApiError, error_message
    #   end
    #
    #   response.body.empty? ? {} : JSON.parse(response.body)
    # rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError,
    #        Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, Errno::ECONNREFUSED => e
    #   raise JiraApiError, "Jira API request failed: #{e.class} - #{e.message}"
    # end
  end
end
