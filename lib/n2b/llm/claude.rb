require_relative '../model_config'

module N2M
  module Llm
    class Claude
      API_URI = URI.parse('https://api.anthropic.com/v1/messages')

      def initialize(config)
        @config = config
      end

      def get_model_name
        # Resolve model name using the centralized configuration
        model_name = N2B::ModelConfig.resolve_model('claude', @config['model'])
        if model_name.nil? || model_name.empty?
          # Fallback to default if no model specified
          model_name = N2B::ModelConfig.resolve_model('claude', N2B::ModelConfig.default_model('claude'))
        end
        model_name
      end

      def make_request( content)
        uri = URI.parse('https://api.anthropic.com/v1/messages')
        request = Net::HTTP::Post.new(uri)
        request.content_type = 'application/json'
        request['X-API-Key'] = @config['access_key']
        request['anthropic-version'] = '2023-06-01'
      
        request.body = JSON.dump({
          "model" => get_model_name,
          "max_tokens" => 1024,
          "messages" => [
            {
              "role" => "user",
              "content" => content
            }
          ]
        })

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end
        # check for errors
        if response.code != '200'
          raise N2B::LlmApiError.new("LLM API Error: #{response.code} #{response.message} - #{response.body}")
        end
        answer = JSON.parse(response.body)['content'].first['text']
        begin
          answer = answer.sub(/.*?\{(.*)\}.*/m, '{\1}') unless answer.start_with?('{')
          answer.gsub!(/"([^"]*)"/) { |match| match.gsub(/\n/, "\\n") }
          answer = JSON.parse(answer)
        rescue JSON::ParserError
          # This specific JSON parsing error is about the LLM's *response content*, not an API error.
          # It should probably be handled differently, but the subtask is about LlmApiError.
          # For now, keeping existing behavior for this part.
          puts "Error parsing JSON from LLM response: #{answer}"
          answer = { 'explanation' => answer} # Default fallback
        end
        answer
      end

      def analyze_code_diff(prompt_content)
        # This method assumes prompt_content is the full, ready-to-send prompt
        # including all instructions for the LLM (system message, diff, user additions, JSON format).
        uri = URI.parse('https://api.anthropic.com/v1/messages')
        request = Net::HTTP::Post.new(uri)
        request.content_type = 'application/json'
        request['X-API-Key'] = @config['access_key']
        request['anthropic-version'] = '2023-06-01'

        request.body = JSON.dump({
          "model" => get_model_name,
          "max_tokens" => @config['max_tokens'] || 1024,
          "messages" => [
            {
              "role" => "user",
              "content" => prompt_content
            }
          ]
        })

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        if response.code != '200'
          raise N2B::LlmApiError.new("LLM API Error: #{response.code} #{response.message} - #{response.body}")
        end

        # Return the raw JSON string. CLI's call_llm_for_diff_analysis will handle parsing.
        # The Claude API for messages returns the analysis in response.body['content'].first['text']
        # which should itself be a JSON string as per our prompt's instructions.
        JSON.parse(response.body)['content'].first['text']
      end
    end 
  end
end
