require 'net/http'
require 'json'
require 'uri'

module N2M
  module Llm
    class Gemini
      API_URI = URI.parse('https://generativelanguage.googleapis.com/v1beta/models')
      MODELS = { 
        'gemini-flash' => 'gemini-2.0-flash'
      }

      def initialize(config)
        @config = config
      end

      def make_request(content)
        model = MODELS[@config['model']] || 'gemini-flash'
        uri = URI.parse("#{API_URI}/#{model}:generateContent?key=#{@config['access_key']}")
        
        request = Net::HTTP::Post.new(uri)
        request.content_type = 'application/json'

        request.body = JSON.dump({
          "contents" => [{
            "parts" => [{
              "text" => content
            }]
          }]
        })

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        # check for errors
        if response.code != '200'
          raise N2B::LlmApiError.new("LLM API Error: #{response.code} #{response.message} - #{response.body}")
        end

        parsed_response = JSON.parse(response.body)
        answer = parsed_response['candidates'].first['content']['parts'].first['text']
        
        begin
          # Try to parse as JSON if it looks like JSON
          if answer.strip.start_with?('{') && answer.strip.end_with?('}')
            answer = JSON.parse(answer)
          else
            # If not JSON, wrap it in our expected format
            answer = {
              'explanation' => answer,
              'code' => nil
            }
          end
        rescue JSON::ParserError
          # If JSON parsing fails, wrap the text in our expected format
          answer = {
            'explanation' => answer,
            'code' => nil
          }
        end
        answer
      end
    end
  end
end 