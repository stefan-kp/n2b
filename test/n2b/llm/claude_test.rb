require 'minitest/autorun'
require 'net/http'
require 'json'
require_relative '../../../lib/n2b/llm/claude'
require_relative '../../../lib/n2b/errors'

class MockHTTPResponse
  attr_accessor :code, :body, :message
  def initialize(code, body, message = 'OK')
    @code = code
    @body = body
    @message = message
  end
end

module N2M
  module Llm
    class ClaudeTest < Minitest::Test
      def setup
        @config = { 'access_key' => 'test_key', 'model' => 'claude-3-opus' }
        @client = Claude.new(@config)
      end

      def test_make_request_includes_response_format_and_parses_json
        resp_body = { 'content' => [ { 'text' => { 'commands' => ['echo hi'], 'explanation' => 'hi' }.to_json } ] }.to_json
        http_resp = MockHTTPResponse.new('200', resp_body)

        mock_post = Minitest::Mock.new
        mock_post.expect(:content_type=, nil, ['application/json'])
        mock_post.expect(:[]=, nil, ['X-API-Key', 'test_key'])
        mock_post.expect(:[]=, nil, ['anthropic-version', '2023-06-01'])
        mock_post.expect(:body=, nil) do |body|
          data = JSON.parse(body)
          assert_equal({ 'type' => 'json_object' }, data['response_format'])
        end

        mock_http = Minitest::Mock.new
        mock_http.expect(:request, http_resp, [mock_post])

        Net::HTTP::Post.stub :new, mock_post do
          Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
            result = @client.make_request('hi')
            assert_equal({ 'commands' => ['echo hi'], 'explanation' => 'hi' }, result)
          end
        end

        mock_post.verify
        mock_http.verify
      end
    end
  end
end
