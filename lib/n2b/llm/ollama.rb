require 'net/http'
require 'json'
require 'uri'
require_relative '../model_config'

module N2M
  module Llm
    class Ollama
      # Default API URI for Ollama. This might need to be configurable later.
      DEFAULT_OLLAMA_API_URI = 'http://localhost:11434/api/chat'

      def initialize(config)
        @config = config
        # Allow overriding the Ollama API URI from config if needed
        @api_uri = URI.parse(@config['ollama_api_url'] || DEFAULT_OLLAMA_API_URI)
      end

      def get_model_name
        # Resolve model name using the centralized configuration
        model_name = N2B::ModelConfig.resolve_model('ollama', @config['model'])
        if model_name.nil? || model_name.empty?
          # Fallback to default if no model specified
          model_name = N2B::ModelConfig.resolve_model('ollama', N2B::ModelConfig.default_model('ollama'))
        end
        model_name
      end

      def make_request(prompt_content)
        request = Net::HTTP::Post.new(@api_uri)
        request.content_type = 'application/json'

        # Ollama expects the model name directly in the request body.
        # It also expects the full message history.
        request.body = JSON.dump({
          "model" => get_model_name,
          "messages" => [
            {
              "role" => "user",
              "content" => prompt_content
            }
          ],
          "stream" => false # Ensure we get the full response, not a stream
          # "format" => "json" # For some Ollama versions/models to enforce JSON output
        })

        begin
          response = Net::HTTP.start(@api_uri.hostname, @api_uri.port, use_ssl: @api_uri.scheme == 'https') do |http|
            # Set timeouts: open_timeout for connection, read_timeout for waiting for response
            http.open_timeout = 5 # seconds
            http.read_timeout = 120 # seconds
            http.request(request)
          end
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise N2B::LlmApiError.new("Ollama API Error: Timeout connecting or reading from Ollama at #{@api_uri}: #{e.message}")
        rescue Errno::ECONNREFUSED => e
          raise N2B::LlmApiError.new("Ollama API Error: Connection refused at #{@api_uri}. Is Ollama running? #{e.message}")
        end


        if response.code != '200'
          raise N2B::LlmApiError.new("Ollama API Error: #{response.code} #{response.message} - #{response.body}")
        end

        # Ollama's chat response structure is slightly different. The message is in `message.content`.
        raw_response_body = JSON.parse(response.body)
        answer_content = raw_response_body['message']['content']

        begin
          # Attempt to parse the answer_content as JSON
          # This is for n2b's expectation of JSON with 'commands' and 'explanation'
          parsed_answer = JSON.parse(answer_content)
          if parsed_answer.is_a?(Hash) && parsed_answer.key?('commands')
            parsed_answer
          else
            # If the content itself is valid JSON but not the expected structure, wrap it.
             { 'commands' => [answer_content], 'explanation' => 'Response from LLM (JSON content).' }
          end
        rescue JSON::ParserError
          # If answer_content is not JSON, wrap it in the n2b expected structure
          { 'commands' => [answer_content], 'explanation' => answer_content }
        end
      end

      def analyze_code_diff(prompt_content)
        request = Net::HTTP::Post.new(@api_uri)
        request.content_type = 'application/json'

        # The prompt_content for diff analysis should instruct the LLM to return JSON.
        # For Ollama, you can also try adding "format": "json" to the request if the model supports it.
        request_body = {
          "model" => get_model_name,
          "messages" => [
            {
              "role" => "user",
              "content" => prompt_content # This prompt must ask for JSON output
            }
          ],
          "stream" => false
        }
        # Some Ollama models/versions might respect a "format": "json" parameter
        # request_body["format"] = "json" # Uncomment if you want to try this

        request.body = JSON.dump(request_body)

        begin
          response = Net::HTTP.start(@api_uri.hostname, @api_uri.port, use_ssl: @api_uri.scheme == 'https') do |http|
            http.open_timeout = 5
            http.read_timeout = 180 # Potentially longer for analysis
            http.request(request)
          end
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise N2B::LlmApiError.new("Ollama API Error (analyze_code_diff): Timeout for #{@api_uri}: #{e.message}")
        rescue Errno::ECONNREFUSED => e
          raise N2B::LlmApiError.new("Ollama API Error (analyze_code_diff): Connection refused at #{@api_uri}. Is Ollama running? #{e.message}")
        end


        if response.code != '200'
          raise N2B::LlmApiError.new("Ollama API Error (analyze_code_diff): #{response.code} #{response.message} - #{response.body}")
        end

        # Return the raw JSON string from the LLM's response content.
        # The calling method (call_llm_for_diff_analysis in cli.rb) will parse this.
        raw_response_body = JSON.parse(response.body)
        raw_response_body['message']['content']
      end
    end
  end
end
