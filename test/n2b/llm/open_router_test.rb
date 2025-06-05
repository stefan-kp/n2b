require 'minitest/autorun'
require 'net/http'
require 'json'
require_relative '../../../lib/n2b/llm/open_router' # Adjust path if necessary
require_relative '../../../lib/n2b/errors' # For N2B::LlmApiError

# Mock Net::HTTP and its response
class MockHTTPResponse
  attr_accessor :code, :body, :message

  def initialize(code, body, message = 'OK')
    @code = code
    @body = body
    @message = message
  end

  def ==(other)
    other.is_a?(MockHTTPResponse) && other.code == @code && other.body == @body && other.message == @message
  end
end

module N2M
  module Llm
    class OpenRouterTest < Minitest::Test
      def setup
        @config_with_headers = {
          'access_key' => 'test_api_key',
          'model' => 'openai/gpt-4o',
          'openrouter_site_url' => 'https://example.com',
          'openrouter_site_name' => 'TestSite'
        }
        @config_without_headers = {
          'access_key' => 'test_api_key',
          'model' => 'google/gemini-flash-1.5'
          # No optional headers
        }
        @open_router_client_with_headers = N2M::Llm::OpenRouter.new(@config_with_headers)
        @open_router_client_without_headers = N2M::Llm::OpenRouter.new(@config_without_headers)
        @prompt_content = "What is the meaning of life?"
      end

      def test_make_request_success_with_headers
        mock_response_body = {
          "choices" => [{ "message" => { "content" => { "commands" => ["echo '42'"], "explanation" => "It is 42." }.to_json } }]
        }.to_json
        mock_http_response = MockHTTPResponse.new('200', mock_response_body)

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          response = @open_router_client_with_headers.make_request(@prompt_content)
          assert_equal({ "commands" => ["echo '42'"], "explanation" => "It is 42." }, response)
        end

        mock_http.verify
      end

      def test_make_request_success_without_headers
        # Test that it works fine even if optional headers are not in config
        mock_response_body = {
          "choices" => [{ "message" => { "content" => { "commands" => ["ls"], "explanation" => "List files." }.to_json } }]
        }.to_json
        mock_http_response = MockHTTPResponse.new('200', mock_response_body)

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          response = @open_router_client_without_headers.make_request("list files")
          assert_equal({ "commands" => ["ls"], "explanation" => "List files." }, response)
        end

        mock_http.verify
      end

      def test_make_request_success_non_json_content
        # Test when LLM returns plain text instead of JSON string for commands/explanation
        mock_response_body = {
          "choices" => [{ "message" => { "content" => "This is plain text." } }]
        }.to_json
        mock_http_response = MockHTTPResponse.new('200', mock_response_body)

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          response = @open_router_client_with_headers.make_request(@prompt_content)
          assert_equal({ "commands" => ["This is plain text."], "explanation" => "This is plain text." }, response)
        end

        mock_http.verify
      end

      def test_make_request_api_error
        mock_http_response = MockHTTPResponse.new('500', 'Internal Server Error', 'Internal Server Error')

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          assert_raises(N2B::LlmApiError) do
            @open_router_client_with_headers.make_request(@prompt_content)
          end
        end

        mock_http.verify
      end

      def test_analyze_code_diff_success
        expected_json_output = {
          "summary" => "LGTM",
          "errors" => [],
          "improvements" => ["Add more tests"]
        }.to_json # The method should return the raw JSON string from the LLM

        mock_response_body = {
          "choices" => [{ "message" => { "content" => expected_json_output } }]
        }.to_json
        mock_http_response = MockHTTPResponse.new('200', mock_response_body)

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          response = @open_router_client_with_headers.analyze_code_diff("diff content")
          assert_equal expected_json_output, response
        end

        mock_http.verify
      end

      def test_analyze_code_diff_api_error
        mock_http_response = MockHTTPResponse.new('401', 'Unauthorized', 'Unauthorized')

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          assert_raises(N2B::LlmApiError) do
            @open_router_client_with_headers.analyze_code_diff("diff content")
          end
        end

        mock_http.verify
      end

      # Test for header inclusion
      def test_headers_are_set_correctly
        # Define a mock that will be returned by Net::HTTP::Post.new
        mock_post_request_instance = Minitest::Mock.new
        mock_post_request_instance.expect(:content_type=, nil, ['application/json'])
        mock_post_request_instance.expect(:[]=, nil, ['Authorization', "Bearer test_api_key"])
        mock_post_request_instance.expect(:[]=, nil, ['HTTP-Referer', @config_with_headers['openrouter_site_url']])
        mock_post_request_instance.expect(:[]=, nil, ['X-Title', @config_with_headers['openrouter_site_name']])
        mock_post_request_instance.expect(:body=, nil, [String])

        # Stub Net::HTTP::Post.new to return our mock instance
        Net::HTTP::Post.stub :new, mock_post_request_instance do
          mock_response_body = { "choices" => [{ "message" => { "content" => { "commands" => [], "explanation" => "" }.to_json } }] }.to_json
          mock_http_response = MockHTTPResponse.new('200', mock_response_body)

          # Create a mock HTTP object
          mock_http = Minitest::Mock.new
          mock_http.expect(:request, mock_http_response, [mock_post_request_instance])

          # Stub Net::HTTP.start to yield the mock HTTP object and return the response
          Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
            @open_router_client_with_headers.make_request("test")
          end

          mock_http.verify
        end
        mock_post_request_instance.verify
      end

      def test_headers_not_set_when_absent_in_config
        mock_post_request_instance = Minitest::Mock.new
        mock_post_request_instance.expect(:content_type=, nil, ['application/json'])
        mock_post_request_instance.expect(:[]=, nil, ['Authorization', "Bearer test_api_key"])
        # HTTP-Referer and X-Title should NOT be called on mock_post_request_instance if not in config
        mock_post_request_instance.expect(:body=, nil, [String])

        Net::HTTP::Post.stub :new, mock_post_request_instance do
          mock_response_body = { "choices" => [{ "message" => { "content" => { "commands" => [], "explanation" => "" }.to_json } }] }.to_json
          mock_http_response = MockHTTPResponse.new('200', mock_response_body)

          # Create a mock HTTP object
          mock_http = Minitest::Mock.new
          mock_http.expect(:request, mock_http_response, [mock_post_request_instance])

          # Stub Net::HTTP.start to yield the mock HTTP object and return the response
          Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
            @open_router_client_without_headers.make_request("test")
          end

          mock_http.verify
        end
        mock_post_request_instance.verify
      end
    end
  end
end

# Ensure the test file can be run directly:
# ruby test/n2b/llm/open_router_test.rb
