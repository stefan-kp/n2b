# N2B Changelog

## 0.5.3 (2025-06-05) - Critical Bug Fix
- Fixed Claude API error: Removed unsupported response_format parameter
- Claude (Anthropic) doesn't support JSON mode like OpenAI does
- Updated tests to reflect correct Claude API behavior

## 0.5.2 (2025-06-05) - JSON Mode Support
- Added JSON mode support for OpenAI (response_format: json_object)
- Added JSON mode support for Gemini (responseMimeType: application/json)
- Enhanced JSON parsing with fallback handling for all providers
- Note: Claude relies on prompt instructions for JSON formatting (no native JSON mode)

## 0.5.1 (2025-06-05) - Bug Fixes
- Fixed typographical error in gemspec description ("q quick helper" → "a quick helper")
- Fixed undefined MODELS constant in Ollama LLM client causing runtime errors
- Removed duplicate extract_requirements_from_description method in test file
- Cleaned up outdated test code and comments

## 0.5.0 (2025-06-05) - Jira Integration & Enhanced Analysis
- Full Jira API integration with real ticket fetching and comment posting
- Structured Jira comments using Atlassian Document Format (ADF) with proper formatting
- Collapsible sections in Jira comments for clean, professional appearance
- Smart requirements extraction from ticket descriptions and comments
- Automatic ticket updates with implementation summaries and detailed analysis
- Built-in Jira connection testing with n2b-test-jira utility script
- Comprehensive permission validation for Jira API tokens
- Enhanced configuration validation with user-friendly warnings
- Improved model name validation to prevent common input errors
- Better error handling for network issues and API failures
- Extensive documentation with setup guides and troubleshooting
- Test coverage improvements with proper config file isolation
- CLI options: --jira, --jira-update, --jira-no-update, --advanced-config
- Required Jira API scopes: read:project:jira, read:issue:jira, read:comment:jira, write:comment:jira

## 0.4.0 (2025-06-05) - Flexible Model Configuration System
- Centralized model configuration in config/models.yml
- Support for custom model names across all LLM providers
- Enhanced model selection UI with numbered options + custom input
- Latest model support: OpenAI O3/O4 series, Gemini 2.5, updated OpenRouter models
- Backward compatibility with existing model configurations
- Removed hardcoded model restrictions (except suggested models)
- Improved error handling for invalid models with reconfiguration suggestions
- Consistent model handling across Claude, OpenAI, Gemini, OpenRouter, and Ollama

## 0.3.1 (2025-06-04) - Bug fixes and Mercurial branch support
- Fixed JSON parsing error in natural language commands
- Added --branch/-b flag for comparing against specific branches
- Full Mercurial (hg) branch comparison support with auto-detection
- Git branch comparison with auto-detection of main/master branches
- Enhanced branch validation and error handling for both git and hg
- Option validation to prevent invalid flag combinations

## 0.3.0 (2025-06-04) - Major diff analysis enhancement
- Added --diff/-d flag for AI-powered git/hg diff analysis
- Added --requirements/-r flag for requirements compliance checking
- Enhanced LLM prompts with code context extraction (±5-10 lines around changes)
- Added test coverage assessment in diff analysis
- Improved error handling with helpful messages for invalid options
- Better JSON parsing to handle mixed LLM responses
- Code organization improvements and method extraction
- Requirements evaluation with clear status indicators (✅ ⚠️ ❌ 🔍)

## 0.2.4 (2025-03-21) - Syntax fixes and improvements

## 0.2.3 (2025-03-21) - Small bug fix

## 0.2.2 (2025-03-20) - Errbit integration
- Added Errbit integration with n2rrbit and n2rscrum commands
- Including request parameters analysis

## 0.2.1 (2025-03-20) - Class conversion
- Converted to class, added logging possibility

## 0.2.0 (2025-03-20) - n2r Ruby helper

## 0.1.5 (2025-03-20) - Claude JSON answer improved

## 0.1.3 (2025-03-20) - OpenAI support

## 0.1.2 (2025-03-20) - Typo fix

## 0.1.1 (2025-03-20) - Ruby GEMs links

## 0.1.0 (2025-03-20) - Initial release
- First implementation that gets the job done
