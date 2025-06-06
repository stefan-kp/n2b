# Shared test helper for LLM tests
require 'minitest/autorun'
require 'net/http'
require 'json'

# Shared mock HTTP response class for all LLM tests
class MockHTTPResponse
  attr_accessor :code, :body, :message

  def initialize(code, body, message = 'OK')
    @code = code
    @body = body
    @message = message
  end

  def ==(other)
    other.is_a?(MockHTTPResponse) && other.code == @code && other.body == @body && other.message == @message
  end
end
