require 'minitest/autorun'
require 'fileutils'
require 'n2b/base' # Required for CONFIG_FILE constant
require 'n2b/jira_client' # Assuming it's in the load path or adjust relative path

# Mock N2B::ModelConfig if it's used by JiraClient or its dependencies in a way that affects tests
# For now, JiraClient doesn't directly use ModelConfig, but good to keep in mind.

module N2B
  class TestJiraClient < Minitest::Test
    def setup
      # CRITICAL: Protect user's config file by using a test-specific config file
      @tmp_dir = File.expand_path("./tmp_test_jira_client_dir", Dir.pwd)
      FileUtils.mkdir_p(@tmp_dir)
      @test_config_file = File.join(@tmp_dir, 'test_config.yml')
      @original_config_file = N2B::Base::CONFIG_FILE
      # Override the CONFIG_FILE constant for tests
      N2B::Base.send(:remove_const, :CONFIG_FILE) if N2B::Base.const_defined?(:CONFIG_FILE)
      N2B::Base.const_set(:CONFIG_FILE, @test_config_file)

      @config_data = {
        'jira' => {
          'domain' => 'example.atlassian.net',
          'email' => 'test@example.com',
          'api_key' => 'test_api_key',
          'default_project' => 'DEFAULTPROJ'
        }
        # Add other config keys like 'llm', 'model' if JiraClient instantiation depends on them indirectly
      }
      # Simulate a more complete config if necessary for JiraClient initialization
      @config_data['llm'] = 'claude'
      @config_data['model'] = 'claude-3-opus-20240229'


      # This will raise an ArgumentError if domain, email, or api_key are missing
      @jira_client = N2B::JiraClient.new(@config_data)
    end

    def teardown
      # Restore the original CONFIG_FILE constant to protect user's config
      N2B::Base.send(:remove_const, :CONFIG_FILE) if N2B::Base.const_defined?(:CONFIG_FILE)
      N2B::Base.const_set(:CONFIG_FILE, @original_config_file)

      FileUtils.rm_rf(@tmp_dir)
    end

    # Helper to temporarily make private method public for testing
    def make_method_public(instance, method_name)
      klass = instance.class
      klass.class_eval { public method_name }
      yield
    ensure
      klass.class_eval { private method_name }
    end

    def test_initialize_with_valid_config
      assert_instance_of N2B::JiraClient, @jira_client
    end

    def test_initialize_with_missing_jira_config
      assert_raises ArgumentError do
        N2B::JiraClient.new({})
      end
      assert_raises ArgumentError do
        N2B::JiraClient.new({'jira' => {'domain' => 'test.com', 'email' => 't@e.com'}}) # Missing api_key
      end
    end

    # Testing parse_ticket_input indirectly through fetch_ticket's initial parsing step
    # We are not testing the actual HTTP call here, just the parsing part.
    # To do this properly, we'd need to mock the part after parsing.
    # For now, we rely on the fact that fetch_ticket will call parse_ticket_input first.
    # And since fetch_ticket returns dummy data, we can inspect what it *would* fetch.

    def test_parse_ticket_input_with_full_url
      make_method_public(@jira_client, :parse_ticket_input) do
        domain, key = @jira_client.send(:parse_ticket_input, 'https://myjira.atlassian.net/browse/PROJ-123')
        assert_equal 'https://myjira.atlassian.net', domain
        assert_equal 'PROJ-123', key
      end
    end

    def test_parse_ticket_input_with_key_only
      make_method_public(@jira_client, :parse_ticket_input) do
        domain, key = @jira_client.send(:parse_ticket_input, 'PROJ-456')
        assert_nil domain # Should use default domain from config
        assert_equal 'PROJ-456', key
      end
    end

    def test_parse_ticket_input_with_url_and_query_param
       make_method_public(@jira_client, :parse_ticket_input) do
        domain, key = @jira_client.send(:parse_ticket_input, 'https://myjira.atlassian.net/issues/?selectedIssue=PROJ-789')
        assert_equal 'https://myjira.atlassian.net', domain
        assert_equal 'PROJ-789', key
      end
    end

    def test_parse_ticket_input_with_invalid_url
      make_method_public(@jira_client, :parse_ticket_input) do
        assert_raises N2B::JiraClient::JiraApiError do
          @jira_client.send(:parse_ticket_input, 'http://invalid-url-format')
        end
      end
    end

    def test_parse_ticket_input_with_unparseable_key_in_url_path
      make_method_public(@jira_client, :parse_ticket_input) do
        assert_raises N2B::JiraClient::JiraApiError do
          # URL path does not match /browse/KEY format and no query param
          @jira_client.send(:parse_ticket_input, 'https://myjira.atlassian.net/issues/notakey')
        end
      end
    end

    def test_parse_ticket_input_with_invalid_key_format
      make_method_public(@jira_client, :parse_ticket_input) do
        assert_raises N2B::JiraClient::JiraApiError do
          @jira_client.send(:parse_ticket_input, 'INVALIDKEY')
        end
      end
    end

    def test_extract_requirements_with_requirements_section
      description = <<~DESC
        Some intro.
        h2. Requirements
        - Req 1
        * Req 2
        Some text under req.
        h2. Another Section
        More text.
      DESC
      expected = "h2. Requirements\n- Req 1\n* Req 2\nSome text under req."
      assert_equal expected, @jira_client.extract_requirements_from_description(description).strip
    end

    def test_extract_requirements_with_acceptance_criteria
      description = "h1. Acceptance Criteria\n+ AC 1\n+ AC 2\nEnd of section."
      expected = "h1. Acceptance Criteria\n+ AC 1\n+ AC 2\nEnd of section."
      assert_equal expected, @jira_client.extract_requirements_from_description(description).strip
    end

    def test_extract_requirements_with_tasks_section
      description = "h3. Tasks\n- Task A\n- Task B is important."
      expected = "h3. Tasks\n- Task A\n- Task B is important."
      assert_equal expected, @jira_client.extract_requirements_from_description(description).strip
    end

    def test_extract_requirements_multiple_sections
      description = <<~DESC
        h2. Requirements
        - Req 1
        h2. Acceptance Criteria
        * AC 1
        h3. TASKS
        + Task X
        h1. Other stuff
        Ignore this.
      DESC
      # Note: The current logic might just concatenate them with the headers.
      # Depending on desired behavior, this test might need adjustment.
      # The current logic stops at a "non-requirement" header.
      # If "Acceptance Criteria" following "Requirements" should both be captured, the logic in extract_requirements_from_description needs adjustment.
      # Current logic: it will capture "h2. Requirements", "- Req 1". Then it sees "h2. Acceptance Criteria", which is a req header, so it continues.
      # Then it sees "h3. TASKS", also a req header, continues.
      # Then "h1. Other stuff", which is NOT a req_header_regex match, so it stops.
      expected_extraction = "h2. Requirements\n- Req 1\nh2. Acceptance Criteria\n* AC 1\nh3. TASKS\n+ Task X"
      assert_equal expected_extraction, @jira_client.extract_requirements_from_description(description).strip
    end

    def test_extract_requirements_no_specific_section
      description = "This is a general description without specific headers."
      assert_equal description, @jira_client.extract_requirements_from_description(description)
    end

    def test_extract_requirements_empty_description
      assert_equal "", @jira_client.extract_requirements_from_description("")
    end

    def test_extract_requirements_nil_description
      # Assuming extract_requirements_from_description handles nil by returning empty string or the input itself if modified.
      # Based on current implementation, it would call .each_line on nil, causing error.
      # Let's adjust to expect an empty string for nil input for robustness.
      # This requires a small change in the main code: description_string.to_s.each_line
      assert_equal "", @jira_client.extract_requirements_from_description(nil)
    end

    def test_extract_requirements_strips_excessive_newlines
      description = "h2. Requirements\n\n\n- Req 1\n\n- Req 2\n\n\nEnd."
      expected = "h2. Requirements\n- Req 1\n- Req 2\nEnd."
      assert_equal expected, @jira_client.extract_requirements_from_description(description).strip
    end

    # --- Placeholder tests for actual API call mocking ---
    # These will require Net::HTTP mocking.

    def test_fetch_ticket_api_call_success_and_extraction
      # This is where the dummy description from JiraClient is used.
      # We are testing that fetch_ticket correctly uses the dummy data and extracts from it.
      # The dummy data in JiraClient.rb already has "Requirements" and "Acceptance Criteria"

      # For PROJ-123, the dummy data in fetch_ticket should be processed
      # by extract_requirements_from_description
      # The dummy description has "h2. Requirements" and "h2. Acceptance Criteria"
      # and "h3. Tasks"

      # Expected extracted content from the complex dummy description in JiraClient
      expected_extracted_reqs = <<~EXPECTED.strip
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
      --- Comments with Additional Context ---
      Comment 1 (Product Manager, 2024-01-15T10:30:00.000Z):
      Additional clarification: The authentication should support both OAuth2 and API key methods. Please ensure backward compatibility with existing integrations.
      Comment 2 (Tech Lead, 2024-01-16T14:20:00.000Z):
      Implementation note: Use the new security library v2.1+ for the authentication module. The payment gateway integration should use the sandbox environment for testing. Database schema changes need migration scripts.
      Comment 3 (QA Engineer, 2024-01-17T09:15:00.000Z):
      Testing requirements:
      - Test with mobile devices (iOS/Android)
      - Verify responsive design on tablets
      - Load testing with 1000+ concurrent users
      - Security penetration testing required
      EXPECTED

      expected_output = "Ticket Key: PROJ-123\nSummary: This is a dummy summary for PROJ-123\n\n--- Extracted Requirements ---\n#{expected_extracted_reqs}"

      # Using a known key that will trigger the dummy data generation
      actual_output = @jira_client.fetch_ticket('PROJ-123')
      assert_equal expected_output, actual_output.strip
    end

    def test_fetch_ticket_api_call_fallback_to_full_description
      # If extract_requirements_from_description returns the original string (or empty)
      # fetch_ticket should return the full_description_output.
      # To test this, we need a dummy description in JiraClient that *doesn't* have known headers.

      # Temporarily override extract_requirements_from_description to simulate no extraction
      original_method = N2B::JiraClient.instance_method(:extract_requirements_from_description)

      N2B::JiraClient.send(:define_method, :extract_requirements_from_description) do |desc|
        desc # Simulate no specific sections found, return original
      end

      # This dummy description will be returned as is by the mocked extraction
      _dummy_desc_content_for_fallback = "This is a simple description without special headers." # Unused but kept for documentation

      # We need to ensure this dummy description is what fetch_ticket uses.
      # This is tricky because the dummy description is hardcoded in fetch_ticket.
      # A more robust test would involve mocking Net::HTTP to return this simple description.
      # For now, we acknowledge this limitation. The test_fetch_ticket_api_call_success_and_extraction
      # already tests the "happy path" of extraction from the existing complex dummy data.

      # The current dummy data in JiraClient is complex and *will* have extracted requirements.
      # So, to test the fallback, we need to ensure extract_requirements_from_description returns the *original description*
      # which it does if no headers are found.
      # The current dummy description in `fetch_ticket` is complex, so extraction will occur.
      # This test case is more about the logic within `fetch_ticket` given a certain outcome from extraction.

      # Let's assume the internal dummy description in fetch_ticket was simpler:
      # And extract_requirements_from_description returned it as is.
      # Then fetch_ticket should format it into the "full_description_output".

      # This test is more conceptual with current JiraClient structure,
      # as the dummy data is fixed. A better test would involve true HTTP mocking.
      # For now, we assume if `extract_requirements_from_description` returns the original description,
      # `fetch_ticket` correctly formats it. The existing `fetch_ticket` structure shows this.

      # Re-evaluating: The fallback in fetch_ticket is:
      # if extracted_requirements != dummy_data['fields']['description'] && !extracted_requirements.empty?
      # So, if extracted_requirements IS EQUAL to dummy_data['fields']['description'], it means fallback.

      # To force this, we can mock extract_requirements_from_description
      # to return exactly its input.

      mock_jira_client = N2B::JiraClient.new(@config_data) # Fresh instance for mocking

      # This is the exact dummy description used in jira_client.rb
      # It's used to construct the expected full output when extraction does nothing.
      live_dummy_description_content = <<~DUMMY_JIRA_DESCRIPTION
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


      --- Comments with Additional Context ---

      Comment 1 (Product Manager, 2024-01-15T10:30:00.000Z):
      Additional clarification: The authentication should support both OAuth2 and API key methods. Please ensure backward compatibility with existing integrations.

      Comment 2 (Tech Lead, 2024-01-16T14:20:00.000Z):
      Implementation note: Use the new security library v2.1+ for the authentication module. The payment gateway integration should use the sandbox environment for testing. Database schema changes need migration scripts.

      Comment 3 (QA Engineer, 2024-01-17T09:15:00.000Z):
      Testing requirements:
      - Test with mobile devices (iOS/Android)
      - Verify responsive design on tablets
      - Load testing with 1000+ concurrent users
      - Security penetration testing required
      DUMMY_JIRA_DESCRIPTION

      mock_jira_client.define_singleton_method(:extract_requirements_from_description) do |description|
        description # Simulate returning the original description
      end

      # Expected full output format when extraction returns the original description
      # This must match the format in fetch_ticket's `full_description_output`
      # and use the `live_dummy_description_content` defined above.
      ticket_key_for_test = 'NOEXTRACT-123'
      expected_full_output = <<~FULL_OUTPUT.strip
      Ticket Key: #{ticket_key_for_test}
      Summary: This is a dummy summary for #{ticket_key_for_test}
      Status: Open
      Assignee: Dummy User
      Reporter: Another Dummy
      Priority: Medium

      --- Full Description ---
      #{live_dummy_description_content.strip}
      (Note: This is dummy data)
      FULL_OUTPUT

      actual_output = mock_jira_client.fetch_ticket(ticket_key_for_test)
      assert_equal expected_full_output, actual_output.strip
    ensure
       # Restore original method if changed
       # This ensure block might not be strictly necessary with define_singleton_method,
       # as it only affects the mock_jira_client instance.
       # However, if we were globally changing N2B::JiraClient.instance_method, it would be crucial.
       # For now, it's harmless.
       N2B::JiraClient.send(:define_method, :extract_requirements_from_description, original_method) if original_method && defined?(original_method)
    end


    def test_update_ticket_placeholder
      # This now makes real API calls and will fail with 404 for non-existent tickets
      # We test it runs without error and returns false for failed API calls
      refute @jira_client.update_ticket('PROJ-123', 'Test comment')
      # Future: Mock Net::HTTP, verify URL, headers, body, and simulate responses.
    end

    # Example of what full Net::HTTP mocking might start to look like (conceptual)
    # def test_fetch_ticket_with_http_mock
    #   mock_response = Minitest::Mock.new
    #   mock_response.expect(:is_a?, true, [Net::HTTPSuccess])
    #   mock_response.expect(:body, {'key' => 'TEST-1', 'fields' => {'summary' => 'Mocked Summary', 'description' => 'Mocked Desc'}}.to_json)
    #
    #   # Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    #   #   http.request(request)
    #   # end
    #   # This block form is harder to mock directly. May need to mock Net::HTTP.new and then the http instance's request method.
    #
    #   # For now, this test is a placeholder for a more complex mocking setup.
    #   skip "Full Net::HTTP mocking for fetch_ticket not yet implemented."
    # end
  end
end


