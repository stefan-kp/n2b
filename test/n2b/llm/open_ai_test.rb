require 'minitest/autorun'
require 'net/http'
require 'json'
require_relative '../../../lib/n2b/llm/open_ai'
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
    class OpenAiTest < Minitest::Test
      def setup
        @config = { 'access_key' => 'test_key', 'model' => 'gpt-4o' }
        @client = OpenAi.new(@config)
      end

      def test_make_request_json_mode
        resp_body = { 'choices' => [ { 'message' => { 'content' => { 'commands' => ['ls'], 'explanation' => 'list' }.to_json } } ] }.to_json
        http_resp = MockHTTPResponse.new('200', resp_body)

        mock_post = Minitest::Mock.new
        mock_post.expect(:content_type=, nil, ['application/json'])
        mock_post.expect(:[]=, nil, ['Authorization', 'Bearer test_key'])
        mock_post.expect(:body=, nil) do |body|
          data = JSON.parse(body)
          assert_equal({ 'type' => 'json_object' }, data['response_format'])
        end

        mock_http = Minitest::Mock.new
        mock_http.expect(:request, http_resp, [mock_post])

        Net::HTTP::Post.stub :new, mock_post do
          Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
            result = @client.make_request('ls', expect_json: true)
            assert_equal({ 'commands' => ['ls'], 'explanation' => 'list' }, result)
          end
        end

        mock_post.verify
        mock_http.verify
      end

      def test_make_request_plain_text_no_json_mode
        resp_body = { 'choices' => [ { 'message' => { 'content' => 'Plain text' } } ] }.to_json
        http_resp = MockHTTPResponse.new('200', resp_body)

        mock_post = Minitest::Mock.new
        mock_post.expect(:content_type=, nil, ['application/json'])
        mock_post.expect(:[]=, nil, ['Authorization', 'Bearer test_key'])
        mock_post.expect(:body=, nil) do |body|
          data = JSON.parse(body)
          refute data.key?('response_format')
        end

        mock_http = Minitest::Mock.new
        mock_http.expect(:request, http_resp, [mock_post])

        Net::HTTP::Post.stub :new, mock_post do
          Net::HTTP.stub :start, proc { |*args, &block| block.call(mock_http) } do
            result = @client.make_request('ls', expect_json: false)
            assert_equal 'Plain text', result
          end
        end

        mock_post.verify
        mock_http.verify
      end
    end
  end
end
