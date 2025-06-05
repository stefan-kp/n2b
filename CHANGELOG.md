# N2B Changelog

## 0.5.1 (2025-01-20) - Bug Fixes
- Fixed typographical error in gemspec description ("q quick helper" → "a quick helper")
- Fixed undefined MODELS constant in Ollama LLM client causing runtime errors
- Removed duplicate extract_requirements_from_description method in test file
- Cleaned up outdated test code and comments

## 0.5.0 (2025-01-20) - Jira Integration & Enhanced Analysis
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
- Required Jira permissions: Browse Projects, Browse Issues, View Comments, Add Comments

## 0.4.0 (2024-12-XX) - Flexible Model Configuration System
- Centralized model configuration in config/models.yml
- Support for custom model names across all LLM providers
- Enhanced model selection UI with numbered options + custom input
- Latest model support: OpenAI O3/O4 series, Gemini 2.5, updated OpenRouter models
- Backward compatibility with existing model configurations
- Removed hardcoded model restrictions (except suggested models)
- Improved error handling for invalid models with reconfiguration suggestions
- Consistent model handling across Claude, OpenAI, Gemini, OpenRouter, and Ollama

## 0.3.1 (2024-XX-XX) - Bug fixes and Mercurial branch support
- Fixed JSON parsing error in natural language commands
- Added --branch/-b flag for comparing against specific branches
- Full Mercurial (hg) branch comparison support with auto-detection
- Git branch comparison with auto-detection of main/master branches
- Enhanced branch validation and error handling for both git and hg
- Option validation to prevent invalid flag combinations

## 0.3.0 (2024-XX-XX) - Major diff analysis enhancement
- Added --diff/-d flag for AI-powered git/hg diff analysis
- Added --requirements/-r flag for requirements compliance checking
- Enhanced LLM prompts with code context extraction (±5-10 lines around changes)
- Added test coverage assessment in diff analysis
- Improved error handling with helpful messages for invalid options
- Better JSON parsing to handle mixed LLM responses
- Code organization improvements and method extraction
- Requirements evaluation with clear status indicators (✅ ⚠️ ❌ 🔍)

## 0.2.4 (2024-XX-XX) - Syntax fixes and improvements

## 0.2.3 (2024-XX-XX) - Small bug fix

## 0.2.2 (2024-XX-XX) - Errbit integration
- Added Errbit integration with n2rrbit and n2rscrum commands
- Including request parameters analysis

## 0.2.1 (2024-XX-XX) - Class conversion
- Converted to class, added logging possibility

## 0.2.0 (2024-XX-XX) - n2r Ruby helper

## 0.1.5 (2024-XX-XX) - Claude JSON answer improved

## 0.1.3 (2024-XX-XX) - OpenAI support

## 0.1.2 (2024-XX-XX) - Typo fix

## 0.1.1 (2024-XX-XX) - Ruby GEMs links

## 0.1.0 (2024-XX-XX) - Initial release
- First implementation that gets the job done
