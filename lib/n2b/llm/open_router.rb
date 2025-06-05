require 'net/http'
require 'json'
require 'uri'
require_relative '../model_config'

module N2M
  module Llm
    class OpenRouter
      API_URI = URI.parse('https://openrouter.ai/api/v1/chat/completions')

      def initialize(config)
        @config = config
        @api_key = @config['access_key']
        @site_url = @config['openrouter_site_url'] || '' # Optional: Read from config
        @site_name = @config['openrouter_site_name'] || ''   # Optional: Read from config
      end

      def get_model_name
        # Resolve model name using the centralized configuration
        model_name = N2B::ModelConfig.resolve_model('openrouter', @config['model'])
        if model_name.nil? || model_name.empty?
          # Fallback to default if no model specified
          model_name = N2B::ModelConfig.resolve_model('openrouter', N2B::ModelConfig.default_model('openrouter'))
        end
        model_name
      end

      def make_request(prompt_content)
        request = Net::HTTP::Post.new(API_URI)
        request.content_type = 'application/json'
        request['Authorization'] = "Bearer #{@api_key}"

        # Add OpenRouter specific headers
        request['HTTP-Referer'] = @site_url unless @site_url.empty?
        request['X-Title'] = @site_name unless @site_name.empty?

        request.body = JSON.dump({
          "model" => get_model_name,
          "messages" => [
            {
              "role" => "user",
              "content" => prompt_content
            }
          ]
          # TODO: Consider adding max_tokens, temperature, etc. from @config if needed
        })

        response = Net::HTTP.start(API_URI.hostname, API_URI.port, use_ssl: true) do |http|
          http.request(request)
        end

        if response.code != '200'
          raise N2B::LlmApiError.new("LLM API Error: #{response.code} #{response.message} - #{response.body}")
        end

        # Assuming OpenRouter returns a similar structure to OpenAI for chat completions
        answer_content = JSON.parse(response.body)['choices'].first['message']['content']

        begin
          # Attempt to parse the answer as JSON, as expected by the calling CLI's process_natural_language_command
          parsed_answer = JSON.parse(answer_content)
          # Ensure it has the 'commands' and 'explanation' structure if it's for n2b's command generation
          # This might need adjustment based on how `make_request` is used.
          # If it's just for generic requests, this parsing might be too specific.
          # For now, mirroring the OpenAI class's attempt to parse JSON from the content.
          if parsed_answer.is_a?(Hash) && parsed_answer.key?('commands')
            parsed_answer
          else
            # If the content itself isn't the JSON structure n2b expects,
            # but is valid JSON, return it. Otherwise, wrap it.
            # This part needs to be robust based on actual OpenRouter responses.
            { 'commands' => [answer_content], 'explanation' => 'Response from LLM.' } # Fallback
          end
        rescue JSON::ParserError
          # If the content isn't JSON, wrap it in the expected structure for n2b
          { 'commands' => [answer_content], 'explanation' => answer_content }
        end
      end

      def analyze_code_diff(prompt_content)
        request = Net::HTTP::Post.new(API_URI) # Chat completions endpoint
        request.content_type = 'application/json'
        request['Authorization'] = "Bearer #{@api_key}"

        # Add OpenRouter specific headers
        request['HTTP-Referer'] = @site_url unless @site_url.empty?
        request['X-Title'] = @site_name unless @site_name.empty?

        # The prompt_content for diff analysis should already instruct the LLM to return JSON.
        request.body = JSON.dump({
          "model" => get_model_name,
          # "response_format" => { "type" => "json_object" }, # Some models on OpenRouter might support this
          "messages" => [
            {
              "role" => "user",
              "content" => prompt_content # This prompt should ask for JSON output
            }
          ],
          "max_tokens" => @config['max_tokens'] || 2048 # Ensure enough tokens for JSON
        })

        response = Net::HTTP.start(API_URI.hostname, API_URI.port, use_ssl: true) do |http|
          http.request(request)
        end

        if response.code != '200'
          raise N2B::LlmApiError.new("LLM API Error: #{response.code} #{response.message} - #{response.body}")
        end

        # Return the raw JSON string from the LLM's response content.
        # The calling method (call_llm_for_diff_analysis in cli.rb) will parse this.
        JSON.parse(response.body)['choices'].first['message']['content']
      end
    end
  end
end
