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

# Alias library namespace for tests
module N2M
  module Llm
    Claude = N2B::Llm::Claude if defined?(N2B::Llm::Claude)
    OpenAi = N2B::Llm::OpenAi if defined?(N2B::Llm::OpenAi)
    Gemini = N2B::Llm::Gemini if defined?(N2B::Llm::Gemini)
    OpenRouter = N2B::Llm::OpenRouter if defined?(N2B::Llm::OpenRouter)
    # Ollama already defined under N2M
  end
end
