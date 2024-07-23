# lib/n2b.rb
require 'net/http'
require 'uri'
require 'json'
require 'optparse'
require 'yaml'
require 'fileutils'
require 'n2b/version'
require 'n2b/llm/claude'
require 'n2b/llm/open_ai'
require 'n2b/base'
require 'n2b/cli'

require 'n2b/irb'

module N2B
  class Error < StandardError; end

end