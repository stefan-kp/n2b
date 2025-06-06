require_relative 'test_helper'
require_relative '../../../lib/n2b/llm/gemini'
require_relative '../../../lib/n2b/errors'

module N2M
  module Llm
    class GeminiTest < Minitest::Test
      def setup
        @config = { 'access_key' => 'test_key', 'model' => 'gemini-1.5' }
        @client = Gemini.new(@config)
      end

      def test_make_request_sets_generation_config_and_parses_json
        resp_body = {
          'candidates' => [
            { 'content' => { 'parts' => [ { 'text' => { 'explanation' => 'ok' }.to_json } ] } }
          ]
        }.to_json
        http_resp = MockHTTPResponse.new('200', resp_body)

        mock_post = Minitest::Mock.new
        mock_post.expect(:content_type=, nil, ['application/json'])
        mock_post.expect(:body=, nil) do |body|
          data = JSON.parse(body)
          assert_equal 'application/json', data['generationConfig']['responseMimeType']
        end

        mock_http = Minitest::Mock.new
        mock_http.expect(:request, http_resp, [mock_post])

        Net::HTTP::Post.stub :new, mock_post do
          Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
            result = @client.make_request('ok')
            assert_equal({ 'explanation' => 'ok' }, result)
          end
        end

        mock_post.verify
        mock_http.verify
      end
    end
  end
end
