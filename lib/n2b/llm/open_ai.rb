require 'net/http'
require 'json'
require 'uri'
require_relative '../model_config'

module N2M
  module Llm
    class OpenAi
      API_URI = URI.parse('https://api.openai.com/v1/chat/completions')

      def initialize(config)
        @config = config
      end

      def get_model_name
        # Resolve model name using the centralized configuration
        model_name = N2B::ModelConfig.resolve_model('openai', @config['model'])
        if model_name.nil? || model_name.empty?
          # Fallback to default if no model specified
          model_name = N2B::ModelConfig.resolve_model('openai', N2B::ModelConfig.default_model('openai'))
        end
        model_name
      end

      def make_request(content)
        request = Net::HTTP::Post.new(API_URI)
        request.content_type = 'application/json'
        request['Authorization'] = "Bearer #{@config['access_key']}"

        request.body = JSON.dump({
          "model" => get_model_name,
          response_format: { type: 'json_object' },
          "messages" => [
            {
              "role" => "user",
              "content" => content
            }]
        })

        response = Net::HTTP.start(API_URI.hostname, API_URI.port, use_ssl: true) do |http|
          http.request(request)
        end

        # check for errors
        if response.code != '200'
          raise N2B::LlmApiError.new("LLM API Error: #{response.code} #{response.message} - #{response.body}")
        end
        answer = JSON.parse(response.body)['choices'].first['message']['content']
        begin
          # remove everything before the first { and after the last }
          answer = answer.sub(/.*\{(.*)\}.*/m, '{\1}') unless answer.start_with?('{')
          answer = JSON.parse(answer)
        rescue JSON::ParserError
          answer = { 'commands' => answer.split("\n"), explanation: answer }
        end
        answer
      end

      def analyze_code_diff(prompt_content)
        # This method assumes prompt_content is the full, ready-to-send prompt
        # including all instructions for the LLM (system message, diff, user additions, JSON format).
        request = Net::HTTP::Post.new(API_URI)
        request.content_type = 'application/json'
        request['Authorization'] = "Bearer #{@config['access_key']}"

        request.body = JSON.dump({
          "model" => get_model_name,
          "response_format" => { "type" => "json_object" }, # Crucial for OpenAI to return JSON
          "messages" => [
            {
              "role" => "user", # The entire prompt is passed as a single user message
              "content" => prompt_content
            }
          ],
          "max_tokens" => @config['max_tokens'] || 1500 # Allow overriding, ensure it's enough for JSON
        })

        response = Net::HTTP.start(API_URI.hostname, API_URI.port, use_ssl: true) do |http|
          http.request(request)
        end

        if response.code != '200'
          raise N2B::LlmApiError.new("LLM API Error: #{response.code} #{response.message} - #{response.body}")
        end

        # Return the raw JSON string. CLI's call_llm_for_diff_analysis will handle parsing.
        # OpenAI with json_object mode should return the JSON directly in 'choices'.first.message.content
        JSON.parse(response.body)['choices'].first['message']['content']
      end
    end
  end
end
