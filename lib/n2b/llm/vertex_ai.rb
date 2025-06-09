require 'net/http'
require 'json'
require 'uri'
require 'googleauth' # For service account authentication
require_relative '../model_config'
require_relative '../errors'

module N2B
  module Llm
    class VertexAi
      # Using the same Gemini API endpoint, but will be authenticated via Service Account
      API_URI = URI.parse('https://generativelanguage.googleapis.com/v1beta/models')

      def initialize(config)
        @config = config # Contains 'vertex_credential_file' and 'model'
      end

      def get_model_name
        # Resolve model name using the centralized configuration for 'vertexai'
        model_name = N2B::ModelConfig.resolve_model('vertexai', @config['model'])
        if model_name.nil? || model_name.empty?
          # Fallback to default if no model specified for vertexai
          model_name = N2B::ModelConfig.resolve_model('vertexai', N2B::ModelConfig.default_model('vertexai'))
        end
        # If still no model, a generic default could be used, or an error raised.
        # For now, assume ModelConfig handles returning a usable default or nil.
        # If ModelConfig.resolve_model can return nil and that's an issue, add handling here.
        # For example, if model_name is still nil, raise an error or use a hardcoded default.
        # Let's assume ModelConfig provides a valid model or a sensible default from models.yml.
        model_name
      end

      def make_request(content)
        model = get_model_name
        raise N2B::LlmApiError.new("No model configured for Vertex AI.") if model.nil? || model.empty?

        uri = URI.parse("#{API_URI}/#{model}:generateContent") # No API key in URI

        request = Net::HTTP::Post.new(uri)
        request.content_type = 'application/json'

        begin
          scope = 'https://www.googleapis.com/auth/cloud-platform'
          authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
            json_key_io: File.open(@config['vertex_credential_file']),
            scope: scope
          )
          access_token = authorizer.fetch_access_token!['access_token']
          request['Authorization'] = "Bearer #{access_token}"
        rescue StandardError => e
          raise N2B::LlmApiError.new("Vertex AI - Failed to obtain Google Cloud access token: #{e.message}")
        end

        request.body = JSON.dump({
          "contents" => [{
            "parts" => [{
              "text" => content
            }]
          }],
          "generationConfig" => {
            "responseMimeType" => "application/json" # Requesting JSON output from the LLM
          }
        })

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        if response.code != '200'
          raise N2B::LlmApiError.new("Vertex AI LLM API Error: #{response.code} #{response.message} - #{response.body}")
        end

        parsed_response = JSON.parse(response.body)
        # Assuming the Gemini API structure for response when auth is via SA
        answer = parsed_response['candidates'].first['content']['parts'].first['text']

        begin
          if answer.strip.start_with?('{') && answer.strip.end_with?('}')
            answer = JSON.parse(answer) # LLM returned JSON as a string
          else
            # If not JSON, wrap it as per existing Gemini class (for CLI compatibility)
            answer = { 'explanation' => answer, 'code' => nil }
          end
        rescue JSON::ParserError
          answer = { 'explanation' => answer, 'code' => nil }
        end
        answer
      end

      def analyze_code_diff(prompt_content)
        model = get_model_name
        raise N2B::LlmApiError.new("No model configured for Vertex AI.") if model.nil? || model.empty?

        uri = URI.parse("#{API_URI}/#{model}:generateContent") # No API key

        request = Net::HTTP::Post.new(uri)
        request.content_type = 'application/json'

        begin
          scope = 'https://www.googleapis.com/auth/cloud-platform'
          authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
            json_key_io: File.open(@config['vertex_credential_file']),
            scope: scope
          )
          access_token = authorizer.fetch_access_token!['access_token']
          request['Authorization'] = "Bearer #{access_token}"
        rescue StandardError => e
          raise N2B::LlmApiError.new("Vertex AI - Failed to obtain Google Cloud access token for diff analysis: #{e.message}")
        end

        request.body = JSON.dump({
          "contents" => [{
            "parts" => [{
              "text" => prompt_content
            }]
          }],
          "generationConfig" => {
            "responseMimeType" => "application/json" # Expecting JSON response from LLM
          }
        })

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        if response.code != '200'
          raise N2B::LlmApiError.new("Vertex AI LLM API Error for diff analysis: #{response.code} #{response.message} - #{response.body}")
        end

        parsed_response = JSON.parse(response.body)
        # Return the raw JSON string from the 'text' field, CLI will parse it.
        parsed_response['candidates'].first['content']['parts'].first['text']
      end
    end
  end
end
