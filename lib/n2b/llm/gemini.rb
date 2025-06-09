require 'net/http'
require 'json'
require 'uri'
require 'googleauth' # Added for service account authentication
require_relative '../model_config'

module N2B
  module Llm
    class Gemini
      API_URI = URI.parse('https://generativelanguage.googleapis.com/v1beta/models')

      def initialize(config)
        @config = config # Retain for model name and gemini_credential_file access
      end

      def get_model_name
        # Resolve model name using the centralized configuration
        model_name = N2B::ModelConfig.resolve_model('gemini', @config['model'])
        if model_name.nil? || model_name.empty?
          # Fallback to default if no model specified
          model_name = N2B::ModelConfig.resolve_model('gemini', N2B::ModelConfig.default_model('gemini'))
        end
        model_name
      end

      def make_request(content)
        model = get_model_name
        # Remove API key from URI
        uri = URI.parse("#{API_URI}/#{model}:generateContent")
        
        request = Net::HTTP::Post.new(uri)
        request.content_type = 'application/json'

        # Add Authorization header
        begin
          scope = 'https://www.googleapis.com/auth/cloud-platform'
          authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
            json_key_io: File.open(@config['gemini_credential_file']),
            scope: scope
          )
          access_token = authorizer.fetch_access_token!['access_token']
          request['Authorization'] = "Bearer #{access_token}"
        rescue StandardError => e
          raise N2B::LlmApiError.new("Failed to obtain Google Cloud access token: #{e.message}")
        end

        request.body = JSON.dump({
          "contents" => [{
            "parts" => [{
              "text" => content
            }]
          }],
          "generationConfig" => {
            "responseMimeType" => "application/json"
          }
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
        model = get_model_name
        # Remove API key from URI
        uri = URI.parse("#{API_URI}/#{model}:generateContent")

        request = Net::HTTP::Post.new(uri)
        request.content_type = 'application/json'

        # Add Authorization header
        begin
          scope = 'https://www.googleapis.com/auth/cloud-platform'
          authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
            json_key_io: File.open(@config['gemini_credential_file']),
            scope: scope
          )
          access_token = authorizer.fetch_access_token!['access_token']
          request['Authorization'] = "Bearer #{access_token}"
        rescue StandardError => e
          raise N2B::LlmApiError.new("Failed to obtain Google Cloud access token: #{e.message}")
        end

        request.body = JSON.dump({
          "contents" => [{
            "parts" => [{
              "text" => prompt_content
            }]
          }],
          "generationConfig" => {
            "responseMimeType" => "application/json"
          }
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