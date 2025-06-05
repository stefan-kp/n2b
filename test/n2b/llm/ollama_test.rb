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

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:open_timeout=, nil, [Integer])
        mock_http.expect(:read_timeout=, nil, [Integer])
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          response = @ollama_client_default_url.make_request(@prompt_content)
          assert_equal({ "commands" => ["echo 'Hello'"], "explanation" => "Says hello" }, response)
        end

        mock_http.verify
      end

      def test_make_request_success_plain_text_response
        llm_plain_text_content = "This is a plain text answer."
        mock_response_body = { "model" => "llama3", "created_at" => "...", "message" => { "role" => "assistant", "content" => llm_plain_text_content } }.to_json
        mock_http_response = MockHTTPResponse.new('200', mock_response_body)

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:open_timeout=, nil, [Integer])
        mock_http.expect(:read_timeout=, nil, [Integer])
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          response = @ollama_client_default_url.make_request(@prompt_content)
          assert_equal({ "commands" => [llm_plain_text_content], "explanation" => llm_plain_text_content }, response)
        end

        mock_http.verify
      end

      def test_make_request_custom_url
        llm_plain_text_content = "Response from custom URL."
        mock_response_body = { "model" => "mistral", "message" => { "content" => llm_plain_text_content } }.to_json
        mock_http_response = MockHTTPResponse.new('200', mock_response_body)

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:open_timeout=, nil, [Integer])
        mock_http.expect(:read_timeout=, nil, [Integer])
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          response = @ollama_client_custom_url.make_request(@prompt_content)
          assert_equal({ "commands" => [llm_plain_text_content], "explanation" => llm_plain_text_content }, response)
        end

        mock_http.verify
      end


      def test_make_request_api_error
        mock_http_response = MockHTTPResponse.new('500', 'Internal Server Error', 'Internal Server Error')

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:open_timeout=, nil, [Integer])
        mock_http.expect(:read_timeout=, nil, [Integer])
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          assert_raises(N2B::LlmApiError) do
            @ollama_client_default_url.make_request(@prompt_content)
          end
        end

        mock_http.verify
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

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:open_timeout=, nil, [Integer])
        mock_http.expect(:read_timeout=, nil, [Integer])
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          response = @ollama_client_default_url.analyze_code_diff("diff --git a/file b/file")
          assert_equal expected_json_output, response
        end

        mock_http.verify
      end

      def test_analyze_code_diff_api_error
        mock_http_response = MockHTTPResponse.new('400', 'Bad Request', 'Bad Request')

        # Create a mock HTTP object
        mock_http = Minitest::Mock.new
        mock_http.expect(:open_timeout=, nil, [Integer])
        mock_http.expect(:read_timeout=, nil, [Integer])
        mock_http.expect(:request, mock_http_response, [Object])

        # Stub Net::HTTP.start to yield the mock HTTP object and return the response
        Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
          assert_raises(N2B::LlmApiError) do
            @ollama_client_default_url.analyze_code_diff("diff --git a/file b/file")
          end
        end

        mock_http.verify
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
