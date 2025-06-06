# n2b.gemspec
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'n2b/version'

Gem::Specification.new do |spec|
  spec.name          = "n2b"
  spec.version       = N2B::VERSION
  spec.authors       = ["Stefan Nothegger"]
  spec.email         = ["stefan@kaproblem.com"]
  spec.summary       = %q{AI-powered development toolkit with merge conflict resolution and Jira integration}
  spec.description   = %q{N2B is a comprehensive AI-powered development toolkit that enhances your daily workflow with smart merge conflict resolution, interactive Jira ticket analysis, and intelligent code diff analysis. Features include: AI-assisted merge conflicts with editor integration, interactive Jira templates with checklists, automatic VCS resolution marking, JSON auto-repair, and multi-LLM support (OpenAI, Claude, Gemini, OpenRouter, Ollama).}
  spec.homepage      = "https://github.com/stefan-kp/n2b"
  spec.metadata      = {
    "source_code_uri" => "https://github.com/stefan-kp/n2b",
    "changelog_uri" => "https://github.com/stefan-kp/n2b/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://github.com/stefan-kp/n2b/blob/main/README.md",
    "rubygems_mfa_required" => "true"
  }
  spec.license       = "MIT"

  spec.files         = Dir.glob("{bin,lib}/**/*") + %w(README.md)
  spec.executables   = ["n2b", "n2b-diff"]
  spec.require_paths = ["lib"]

  spec.add_dependency "json", "~> 2.0"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
