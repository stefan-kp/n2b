require 'minitest/autorun'
require 'minitest/mock'
require 'mocha/minitest'

# Add lib directory to load path
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Require the main library file
require 'n2b'

# Require error classes
require 'n2b/errors'

# Require LLM classes
require 'n2b/llm/open_ai'
require 'n2b/llm/claude'
require 'n2b/llm/gemini'
require 'n2b/llm/open_router'
require 'n2b/llm/ollama'

# Require CLI
require 'n2b/cli'
