require 'minitest/autorun'
require 'net/http'
require 'json'
require_relative '../../../lib/n2b/llm/ollama' # Adjust path if necessary
require_relative '../../../lib/n2b/errors'   # For N2B::LlmApiError

# Mock Net::HTTP and its response (can be shared if a test_helper is used)
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
    class OllamaTest < Minitest::Test
      def setup
        @config_default_url = {
          'model' => 'llama3'
        }
        @config_custom_url = {
          'model' => 'mistral',
          'ollama_api_url' => 'http://customhost:12345/api/chat'
        }
        @ollama_client_default_url = N2M::Llm::Ollama.new(@config_default_url)
        @ollama_client_custom_url = N2M::Llm::Ollama.new(@config_custom_url)
        @prompt_content = "Explain quantum computing."
      end

      def test_make_request_success_json_response
        # Ollama response structure is different: { "message": { "content": "..." } }
        # And our make_request tries to parse the content if it's JSON.
        llm_json_content = { "commands" => ["echo 'Hello'"], "explanation" => "Says hello" }.to_json
        mock_response_body = { "model" => "llama3", "created_at" => "...", "message" => { "role" => "assistant", "content" => llm_json_content } }.to_json
        mock_http_response = MockHTTPResponse.new('200', mock_response_body)

        Net::HTTP.stub :start, mock_http_response do
          response = @ollama_client_default_url.make_request(@prompt_content)
          assert_equal({ "commands" => ["echo 'Hello'"], "explanation" => "Says hello" }, response)
        end
      end

      def test_make_request_success_plain_text_response
        llm_plain_text_content = "This is a plain text answer."
        mock_response_body = { "model" => "llama3", "created_at" => "...", "message" => { "role" => "assistant", "content" => llm_plain_text_content } }.to_json
        mock_http_response = MockHTTPResponse.new('200', mock_response_body)

        Net::HTTP.stub :start, mock_http_response do
          response = @ollama_client_default_url.make_request(@prompt_content)
          assert_equal({ "commands" => [llm_plain_text_content], "explanation" => llm_plain_text_content }, response)
        end
      end

      def test_make_request_custom_url
        llm_plain_text_content = "Response from custom URL."
        mock_response_body = { "model" => "mistral", "message" => { "content" => llm_plain_text_content } }.to_json
        mock_http_response = MockHTTPResponse.new('200', mock_response_body)

        custom_uri = URI.parse('http://customhost:12345/api/chat')

        # This will capture the http object Net::HTTP.start would yield
        http_mock = Minitest::Mock.new
        http_mock.expect(:request, mock_http_response, [Net::HTTP::Post]) # Allow any Net::HTTP::Post object

        Net::HTTP.stub :start, http_mock, [custom_uri.hostname, custom_uri.port, use_ssl: false] do |host, port, options, &block|
          # Check if the yielded object (http_mock) is called as expected by the Ollama class
          # The actual Net::HTTP.start yields an http object to the block.
          # Our stub replaces this yielded object with http_mock.
          # The Ollama class will then call `request` on this http_mock.
          # This setup is a bit more involved to verify the yielded object is used.
          # A simpler stub for just checking the URI in `start` might be preferred if this is too complex.
          # For this test, we'll assume the Ollama class calls http.request(request) inside the block.
          # The crucial part is that Net::HTTP.start was called with the correct host and port.
          # The provided stub in the prompt was a good way to check the URI directly. Let's try to use that pattern.

          # Reverting to a simpler stubbing pattern for clarity on URI check
          # The goal is to ensure Net::HTTP.start is *called* with the correct URI parameters.
        end

        # More direct way to test URI used by Net::HTTP.start:
        # We expect Net::HTTP.start to be called with specific arguments.
        # Minitest's simple stub doesn't easily allow asserting call arguments on the stubbed method itself
        # without more complex mock objects for Net::HTTP itself.
        # The original prompt's way of stubbing Net::HTTP.start with a block that asserts the uri is good.

        # Let's use the pattern from the prompt for clarity on URI check
        # Store the URI that Net::HTTP.start is called with
        called_uri = nil
        Net::HTTP.stub :start, ->(uri, _port, *_rest, &block) { called_uri = uri; block.call(http_mock) } do # http_mock will handle the request call
            # The request will be made inside this block by the Ollama client
            # We need http_mock to return our desired response when `request` is called on it.
             @ollama_client_custom_url.make_request(@prompt_content)
        end
        assert_equal custom_uri, called_uri

        # To ensure the response is also processed correctly with the custom URL:
         Net::HTTP.stub :start, mock_http_response do # General stub for the response processing part
           response = @ollama_client_custom_url.make_request(@prompt_content)
           assert_equal({ "commands" => [llm_plain_text_content], "explanation" => llm_plain_text_content }, response)
        end
      end


      def test_make_request_api_error
        mock_http_response = MockHTTPResponse.new('500', 'Internal Server Error', 'Internal Server Error')
        Net::HTTP.stub :start, mock_http_response do
          assert_raises(N2B::LlmApiError) do
            @ollama_client_default_url.make_request(@prompt_content)
          end
        end
      end

      def test_make_request_connection_refused
        Net::HTTP.stub :start, ->(_host, _port, *_options) { raise Errno::ECONNREFUSED.new("Connection refused") } do
          assert_raises(N2B::LlmApiError) do
            @ollama_client_default_url.make_request(@prompt_content)
          end
        end
      end

      def test_make_request_timeout_error
        Net::HTTP.stub :start, ->(_host, _port, *_options) { raise Net::OpenTimeout.new("Timeout") } do
          assert_raises(N2B::LlmApiError) do
            @ollama_client_default_url.make_request(@prompt_content)
          end
        end
      end

      def test_analyze_code_diff_success
        expected_json_output = { "summary" => "Looks good.", "errors" => [], "improvements" => [] }.to_json
        mock_response_body = { "model" => "llama3", "message" => { "content" => expected_json_output } }.to_json
        mock_http_response = MockHTTPResponse.new('200', mock_response_body)

        Net::HTTP.stub :start, mock_http_response do
          response = @ollama_client_default_url.analyze_code_diff("diff --git a/file b/file")
          assert_equal expected_json_output, response
        end
      end

      def test_analyze_code_diff_api_error
        mock_http_response = MockHTTPResponse.new('400', 'Bad Request', 'Bad Request')
        Net::HTTP.stub :start, mock_http_response do
          assert_raises(N2B::LlmApiError) do
            @ollama_client_default_url.analyze_code_diff("diff --git a/file b/file")
          end
        end
      end

      def test_analyze_code_diff_connection_refused
        Net::HTTP.stub :start, ->(_host, _port, *_options) { raise Errno::ECONNREFUSED.new("Connection refused") } do
          assert_raises(N2B::LlmApiError) do
            @ollama_client_default_url.analyze_code_diff("diff")
          end
        end
      end
    end
  end
end

# For running directly:
# ruby test/n2b/llm/ollama_test.rb
