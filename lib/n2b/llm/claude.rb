module N2M
  module Llm
    class Claude
      API_URI = URI.parse('https://api.anthropic.com/v1/messages')
      MODELS = { 'haiku' =>  'claude-3-haiku-20240307', 'sonnet' => 'claude-3-sonnet-20240229', 'sonnet35' => 'claude-3-5-sonnet-20240620', "sonnet37" => "claude-3-7-sonnet-20250219" }

      def initialize(config)
        @config = config
      end

      def make_request( content)
        uri = URI.parse('https://api.anthropic.com/v1/messages')
        request = Net::HTTP::Post.new(uri)
        request.content_type = 'application/json'
        request['X-API-Key'] = @config['access_key']
        request['anthropic-version'] = '2023-06-01'
      
        request.body = JSON.dump({
          "model" => MODELS[@config['model']],
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
          # The llm_response.json file is likely for debugging and can be kept or removed.
          # For this refactoring, I'll keep it as it doesn't affect the error handling logic.
          File.open('llm_response.json', 'w') do |f|
            f.write(answer)
          end
          # remove everything before the first { and after the last }
          
          answer = answer.sub(/.*?\{(.*)\}.*/m, '{\1}') unless answer.start_with?('{')
          # gsub all \n with \\n that are inside "
          # 
          answer.gsub!(/"([^"]*)"/) { |match| match.gsub(/\n/, "\\n") }
          # The llm_response.json file is likely for debugging and can be kept or removed.
          File.open('llm_response.json', 'w') do |f|
            f.write(answer)
          end
          answer = JSON.parse(answer)
        rescue JSON::ParserError
          # This specific JSON parsing error is about the LLM's *response content*, not an API error.
          # It should probably be handled differently, but the subtask is about LlmApiError.
          # For now, keeping existing behavior for this part.
          puts "Error parsing JSON from LLM response: #{answer}" # Clarified error message
          answer = { 'explanation' => answer} # Default fallback
        end
        answer
      end
    end 
  end
end
