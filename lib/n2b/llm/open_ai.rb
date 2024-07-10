require 'net/http'
require 'json'
require 'uri'

module N2M
  module Llm
    class OpenAi
      API_URI = URI.parse('https://api.openai.com/v1/chat/completions')
      MODELS = { 'gpt-4o' =>  'gpt-4o', 'gpt-35' => 'gpt-3.5-turbo-1106' }

      def initialize(config)
        @config = config
      end

      def make_request(content)
        request = Net::HTTP::Post.new(API_URI)
        request.content_type = 'application/json'
        request['Authorization'] = "Bearer #{@config['access_key']}"

        request.body = JSON.dump({
          "model" => MODELS[@config['model']],
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
          puts "Error: #{response.code} #{response.message}"
          puts response.body
          exit 1
        end
        puts JSON.parse(response.body)
        answer = JSON.parse(response.body)['choices'].first['message']['content']
        begin
          # remove everything before the first { and after the last }
          answer = answer.sub(/.*\{(.*)\}.*/m, '{\1}')
          answer = JSON.parse(answer)
        rescue JSON::ParserError
          answer = { 'commands' => answer.split("\n"), explanation: answer }
        end
        answer
      end
    end
  end
end
