# n2b.gemspec
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'n2b/version'

Gem::Specification.new do |spec|
  spec.name          = "n2b"
  spec.version       = N2B::VERSION
  spec.authors       = ["Stefan Nothegger"]
  spec.email         = ["stefan@kaproblem.com"]
  spec.summary       = %q{Convert natural language to bash commands or ruby code and help with debugging.}
  spec.description   = %q{A tool to convert natural language instructions to bash commands using Claude API or OpenAI's GPT. also is a quick helper in the console to provide ruby code snippets and explanations or debug exceptions.}
  spec.homepage      = "https://github.com/stefan-kp/n2b"
  spec.metadata      = {
    "source_code_uri" => "https://github.com/stefan-kp/n2b",
    "changelog_uri" => "https://github.com/stefan-kp/n2b/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://github.com/stefan-kp/n2b/blob/main/README.md"
  }
  spec.license       = "MIT"

  spec.files         = Dir.glob("{bin,lib}/**/*") + %w(README.md)
  spec.executables   = ["n2b", "n2b-diff"]
  spec.require_paths = ["lib"]

  spec.add_dependency "json", "~> 2.0"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
