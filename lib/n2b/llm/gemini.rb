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

      def analyze_code_diff(prompt_content)
        # This method assumes prompt_content is the full, ready-to-send prompt
        # including all instructions for the LLM (system message, diff, user additions, JSON format).
        model = MODELS[@config['model']] || 'gemini-flash' # Or a specific model for analysis if different
        uri = URI.parse("#{API_URI}/#{model}:generateContent?key=#{@config['access_key']}")

        request = Net::HTTP::Post.new(uri)
        request.content_type = 'application/json'

        request.body = JSON.dump({
          "contents" => [{
            "parts" => [{
              "text" => prompt_content # The entire prompt is passed as text
            }]
          }],
          # Gemini specific: Ensure JSON output if possible via generationConfig
          # However, the primary method is instructing it within the prompt itself.
          # "generationConfig": {
          #   "responseMimeType": "application/json", # This might be too restrictive or not always work as expected
          # }
        })

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        if response.code != '200'
          raise N2B::LlmApiError.new("LLM API Error: #{response.code} #{response.message} - #{response.body}")
        end

        parsed_response = JSON.parse(response.body)
        # Return the raw JSON string. CLI's call_llm_for_diff_analysis will handle parsing.
        # The Gemini API returns the analysis in parsed_response['candidates'].first['content']['parts'].first['text']
        # which should itself be a JSON string as per our prompt's instructions.
        parsed_response['candidates'].first['content']['parts'].first['text']
      end
    end
  end
end 