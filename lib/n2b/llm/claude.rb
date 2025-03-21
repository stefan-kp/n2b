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
          puts "Error: #{response.code} #{response.message}"
          puts response.body
          exit 1
        end
        answer = JSON.parse(response.body)['content'].first['text'] 
        begin 
          File.open('llm_response.json', 'w') do |f|
            f.write(answer)
          end
          # remove everything before the first { and after the last }
          
          answer = answer.sub(/.*?\{(.*)\}.*/m, '{\1}') unless answer.start_with?('{')
          # gsub all \n with \\n that are inside "
          # 
          answer.gsub!(/"([^"]*)"/) { |match| match.gsub(/\n/, "\\n") }
          File.open('llm_response.json', 'w') do |f|
            f.write(answer)
          end
          answer = JSON.parse(answer)
        rescue JSON::ParserError
          puts "Error parsing JSON: #{answer}"
          answer = { 'explanation' => answer}
        end
        answer
      end
    end 
  end
end
