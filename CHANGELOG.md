# N2B Changelog

## [2.0.1] - 2025-01-08

### 🎯 **Major Jira Integration Enhancements**
- **Enhanced Jira Comment Formatting**: Professional, structured comments with collapsible sections
- **Template-Based Approach**: All formatting now properly handled in templates, not hardcoded
- **Clean Requirements Display**: Removed redundant checkbox symbols for cleaner presentation
- **Debug Environment Variable**: Added `N2B_DEBUG=true` for detailed troubleshooting output
- **Improved Footer**: Simplified footer without problematic color syntax

### 🔧 **HTML Merge Log System**
- **4-Column Layout**: Base branch code, incoming branch code, final resolution, and resolution details
- **Beautiful Styling**: Modern HTML design with color-coded sections and responsive layout
- **Rich Metadata**: Conflict statistics, timestamps, resolution methods, and LLM analysis
- **Professional Audit Trail**: Perfect for code reviews, compliance, and team collaboration
- **Method Detection**: Automatic classification of LLM vs Manual vs Skip vs Abort resolutions

### 🎨 **Enhanced User Experience**
- **Better Conflict Display**: Shows 3 lines of context before/after conflicts for better understanding
- **Configurable Context**: `--context N` option now clearly documented for LLM analysis
- **Full File Context**: LLM receives complete file content for superior merge decisions
- **Clean Output**: Debug information only shown when `N2B_DEBUG=true` is set

### 🧪 **Test Suite Improvements**
- **Fixed Mocha Compatibility**: Resolved `reset_instance` method issues with newer Mocha versions
- **Updated Test Expectations**: Fixed tests to match new formatting behavior
- **Comprehensive Coverage**: All core functionality thoroughly tested and passing
- **Namespace Fixes**: Corrected N2M → N2B namespace issues in LLM tests

### 🔧 **Technical Improvements**
- **Structured Data Handling**: Proper handling of analysis results in Jira integration
- **Severity Classification**: Automatic categorization of issues as Critical vs Important
- **Template Engine**: Enhanced support for complex data structures and formatting
- **Error Recovery**: Robust handling of edge cases and malformed data

## [2.0.0] - 2024-07-20

### BREAKING CHANGES
- **Command Restructuring:** The N2B CLI has undergone a major restructuring to simplify `n2b` and consolidate analysis features into `n2b-diff`.
  - The `n2b` command is now exclusively for natural language to shell command translation and basic utilities (config, help, version).
  - All functionalities related to code diff analysis, merge conflict resolution, and issue tracker integration (Jira, GitHub) have been moved to the `n2b-diff` command.
  - Users performing diff analysis should migrate from `n2b --diff ...` to `n2b-diff --analyze ...`.
  - Please see `MIGRATION.MD` for a detailed guide on updating your workflows.

### Added
- **Custom Analysis Messages for `n2b-diff`:** Introduced `-m/--message/--msg` options for `n2b-diff --analyze` to allow users to provide custom instructions or focus points for the AI-powered code analysis.
- **GitHub Issue Integration for `n2b-diff`:** Added `--github <ISSUE_ID_OR_URL>` option to `n2b-diff --analyze` for fetching context from and updating GitHub issues, similar to the existing Jira integration.
- **Dedicated `N2B::MessageUtils` module:** For handling validation, sanitization, and logging of user-provided messages.

### Changed
- `n2b-diff` is now the primary tool for all code analysis tasks, including those previously under `n2b --diff`. Its help text and options have been updated accordingly.
- VCS utilities and issue tracker clients (`JiraClient`, `GitHubClient`) are now utilized by `n2b-diff`.
- `lib/n2b/cli.rb` (for `n2b` command) has been streamlined, removing all diff analysis and direct issue tracker logic. Its help text now reflects its focused role.
- Templates for Jira and GitHub comments (`jira_comment.txt`, `github_comment.txt`) updated to include custom analysis focus messages.

### Removed
- Diff analysis, branch comparison, requirements file processing, and Jira/GitHub integration flags and logic have been removed from the `n2b` command.
- Obsolete tests related to removed `n2b` functionalities were deleted from `test/n2b/cli_test.rb`.

### Fixed
- (If any bugs were fixed as a direct result of this refactoring, they would be listed here. For this task, focusing on the restructure.)

## 0.7.2 (2025-01-27) - GitHub Integration & Enhanced Stability

### 🔗 GitHub Integration
- **Added configurable issue tracker selection**: Choose between Jira or GitHub
- **Implemented GitHub integration**: Full fetch and comment update functionality
- **GitHub template system**: Uses new template engine with `github_comment.txt`
- **New `n2b-test-github` script**: Verify GitHub connectivity and permissions
- **Comprehensive tests**: Full test suite for GitHub client functionality

### 🔧 Critical Bug Fixes
- **Fixed n2b-diff hanging issue**: Implemented robust timeout mechanism for VCS commands
- **Eliminated Ruby warnings**: Resolved method redefinition warnings in test suite
- **Enhanced error handling**: Better timeout management and process termination
- **Improved Jira client**: Fixed TypeError in template data preparation for string inputs

### ⚡ Performance & Reliability Improvements
- **Timeout mechanism**: VCS commands now have configurable timeouts (10s for resolution, 5s for status)
- **Process management**: Clean process termination using `Open3.popen3` with proper signal handling
- **Error recovery**: Graceful fallback with helpful manual command suggestions
- **Test stability**: Eliminated thread exceptions and IOError warnings

### 🧪 Test Suite Enhancements
- **Clean test output**: Removed all Ruby method redefinition warnings
- **Shared test helpers**: Consolidated `MockHTTPResponse` class to prevent conflicts
- **Timeout testing**: Added comprehensive tests for timeout functionality
- **Mocha integration**: Added mocha gem dependency for proper test stubbing

### 📚 Documentation Updates
- **Prominent diff analysis**: AI-powered diff analysis now featured prominently in README
- **Beta feature notice**: Clear beta labeling with feedback request
- **Enhanced positioning**: Diff analysis moved to top of Quick Start section
- **Feedback channels**: Multiple paths for user feedback (issues, discussions, stars)

### 🎯 User Experience
- **No more hanging**: Tool completes reliably without getting stuck
- **Clear error messages**: Specific timeout and error information
- **Manual fallback**: Helpful commands when auto-resolution fails
- **Professional output**: Clean, warning-free execution

## 0.7.1 (2025-01-06) - Comprehensive Test Suite & Updated Gemspec

### 🧪 Comprehensive Test Coverage
- **Template Engine Tests**: 18 test cases covering variables, loops, conditionals, and edge cases
- **Jira Integration Tests**: 17 test cases for error classification, file parsing, and template generation
- **Real-world scenarios**: Complex template structures, multiline content, and nested conditionals
- **Error handling**: Invalid data, missing variables, malformed templates
- **Cross-platform compatibility**: Symbol/string key handling for robust data processing

### 📝 Updated Gemspec & Documentation
- **Modern description**: Reflects current AI-powered development toolkit capabilities
- **Feature highlights**: Merge conflict resolution, Jira integration, multi-LLM support
- **Professional presentation**: Clear value proposition for developers and teams
- **Metadata improvements**: Enhanced discoverability and security settings

### 🔧 Bug Fixes & Improvements
- **Requirements parsing**: Fixed regex patterns for "PARTIALLY IMPLEMENTED" status detection
- **Data handling**: Robust symbol/string key compatibility in template data
- **Error classification**: Improved severity detection and file reference extraction
- **Template validation**: Better handling of missing data and edge cases

## 0.7.0 (2025-01-06) - Jira Template System & Interactive Checklists

### 🎯 Full Template Engine
- **Complete templating system**: Variables, loops, conditionals for maximum flexibility
- **Jira-optimized templates**: Native checkbox support and collapsible sections
- **Smart error classification**: Automatic severity detection (Critical/Important/Low)
- **File reference extraction**: Intelligent parsing of file paths and line numbers
- **Git/Mercurial integration**: Automatic branch and diff stats extraction

### ☐ Interactive Jira Checklists
- **Native Jira checkboxes**: ☐ (unchecked) and ☑ (checked) for team collaboration
- **Collapsible sections**: `{expand:Title}...{expand}` for organized findings
- **Severity-based grouping**: Critical Issues, Important Issues, Improvements
- **Requirements tracking**: Status-based checklist (✅ Implemented, ⚠️ Partial, ❌ Not Done)
- **Test coverage gaps**: Actionable checklist items for missing tests

### 🔧 Template Features
- **Variables**: `{implementation_summary}`, `{timestamp}`, `{branch_name}`
- **Loops**: `{#each critical_errors}...{/each}` for dynamic content
- **Conditionals**: `{#if status == 'IMPLEMENTED'}...{/if}` for smart display
- **File references**: Automatic `*file.rb:42*` formatting with line numbers
- **Git integration**: Auto-extract branch, files changed, lines added/removed

### 📋 Default Template Structure
```
*N2B Code Analysis Report*
{expand:🚨 Critical Issues (Must Fix Before Merge)}
☐ *app/auth.rb:42* - SQL injection vulnerability
{expand}

{expand:⚠️ Important Issues (Should Address)}
☐ *controllers/auth.rb:15* - Missing rate limiting
{expand}

*📋 Requirements Evaluation:*
☑ ✅ *IMPLEMENTED:* User authentication working
☐ ⚠️ *PARTIALLY IMPLEMENTED:* Password validation
☐ ❌ *NOT IMPLEMENTED:* Two-factor authentication
```

### 🎯 Team Collaboration Benefits
- **Trackable progress**: Team members check off resolved items
- **Organized findings**: Collapsible sections prevent overwhelming comments
- **Clear priorities**: Critical vs Important vs Nice-to-have separation
- **Actionable items**: Each finding becomes a trackable task
- **Professional presentation**: Clean, structured Jira comments

## 0.6.1 (2025-06-06) - Editor Integration

### 🔧 Editor Integration
- **[e] Edit option**: Open conflicted file in user's preferred editor
- **Smart change detection**: Automatically detects if file was modified
- **Manual resolution support**: Ask user if they resolved conflicts themselves
- **Fresh content for AI**: Always re-read file before sending to LLM
- **Cross-platform editor support**: Works on macOS, Linux, and Windows

### ⚡ Editor Workflow
1. **[e] Edit** → Opens file in system editor (respects $EDITOR/$VISUAL)
2. **User edits** → View context, make changes, resolve conflicts manually
3. **File change detection** → "Did you resolve this conflict yourself? [y/n]"
4. **Smart continuation** → If yes: mark resolved, if no: continue with AI assistance
5. **Fresh context** → All subsequent AI calls use updated file content

### 🎯 Cross-Platform Support
- **macOS**: Uses `open` command (default app association)
- **Linux**: Uses `nano` as safe default
- **Windows**: Uses `notepad`
- **Custom**: Respects `$EDITOR` and `$VISUAL` environment variables

### 💡 User Experience
- **No confirmations**: User already chose [e] option
- **No file re-parsing**: Continue with current conflict workflow
- **No diff display**: Clean, simple interaction
- **Graceful fallback**: Clear error messages if editor fails

## 0.6.0 (2025-06-06) - Intelligent JSON Auto-Repair

### 🧠 Smart JSON Repair System
- **Automatic malformed JSON fixing**: Sends broken responses back to LLM for repair
- **Seamless error recovery**: Most JSON issues now resolve automatically
- **Universal implementation**: Works for both merge conflicts and command generation
- **Intelligent prompting**: Specific repair instructions for different response types

### ⚡ Auto-Repair Workflow
1. **LLM returns malformed JSON** → Detected automatically
2. **Repair prompt sent** → "Fix this JSON and return only the corrected version"
3. **LLM fixes the JSON** → Usually succeeds on first attempt
4. **Validation & use** → Continues normal workflow
5. **Fallback options** → Manual recovery if repair fails

### 🎯 Technical Implementation
- **Merge conflicts**: Validates `merged_code` and `reason` keys
- **Command generation**: Validates `commands` and `explanation` keys
- **Smart prompting**: Context-specific repair instructions
- **Graceful degradation**: Falls back to manual options if repair fails

### 💡 User Experience
- **Mostly invisible**: Auto-repair happens in background
- **Clear feedback**: Shows when repair is attempted and result
- **No interruption**: Workflow continues smoothly when repair succeeds
- **Professional handling**: Clean error messages when repair fails

## 0.5.9 (2025-06-06) - Robust Error Handling & Recovery

### 🛡️ Enhanced Error Handling
- **Comprehensive LLM error recovery**: Multiple options when AI responses fail
- **Smart retry mechanisms**: Retry with same prompt or add user guidance
- **Manual fallback options**: Choose conflict sides manually when AI fails
- **Debug information**: Automatic saving of problematic responses for troubleshooting

### 🔧 Error Recovery Options
When LLM returns invalid responses, users can:
- **[r] Retry**: Same prompt, fresh attempt
- **[c] Comment**: Add guidance to help AI understand better
- **[m] Manual**: Choose HEAD or incoming version manually
- **[s] Skip**: Skip the problematic conflict
- **[a] Abort**: Exit merge resolution entirely

### 🐛 Improved Diagnostics
- **Detailed error messages**: Clear explanation of what went wrong
- **Response validation**: Checks for required JSON structure
- **Debug file creation**: Saves problematic responses to `.n2b_debug/`
- **Specific guidance**: Tailored advice for auth, model, and network errors

### 💡 User Experience
- **No more cryptic failures**: Clear options when things go wrong
- **Graceful degradation**: Always have a way forward
- **Professional error handling**: Colored, structured error messages
- **Debug support**: Easy troubleshooting with saved error details

## 0.5.8 (2025-06-06) - Smart VCS Resolution Logic

### 🐛 Critical Fix
- **Fixed auto-resolution logic**: Files are only marked as resolved when ALL conflicts are accepted
- **Proper rejection handling**: Skipped conflicts prevent automatic VCS marking
- **Clear feedback**: Users know exactly why files aren't marked as resolved

### 🎯 Smart Resolution Behavior
- **All accepted** → File marked as resolved in VCS (hg/git)
- **Some skipped** → File NOT marked, helpful guidance provided
- **None accepted** → File NOT marked, no VCS changes
- **Aborted** → File NOT marked, no changes made

### ✨ Enhanced User Feedback
- **Resolution status**: Clear indication of VCS marking decisions
- **Helpful guidance**: Instructions for manual resolution when needed
- **Professional workflow**: Respects user decisions about conflict resolution

## 0.5.7 (2025-06-06) - VCS Integration & Editor Support

### 🔧 VCS Integration
- **Auto-mark resolved conflicts**: Automatically runs `hg resolve --mark` or `git add` when conflicts are resolved
- **Smart VCS detection**: Detects Mercurial (.hg) and Git (.git) repositories automatically
- **Resolution summary**: Shows count of accepted/skipped conflicts after processing
- **Unresolved conflict listing**: `n2b-diff` without arguments shows remaining conflicts

### 📍 Editor Integration
- **File and line info**: Shows file path and line numbers for each conflict
- **Editor hints**: "💡 You can check this conflict in your editor at the specified line numbers"
- **Line numbers in conflict display**: `<<<<<<< HEAD (lines 26-33)` format
- **Precise navigation**: Users can jump directly to conflicts in their editor

### ✨ Enhanced User Experience
- **Clear file context**: `📁 File: path/to/file.rb` and `📍 Lines: 26-33 (HEAD ↔ feature)`
- **Resolution tracking**: Visual summary of what was accepted vs skipped
- **VCS status integration**: Shows which files still need resolution
- **Professional workflow**: Seamless integration with Mercurial and Git workflows

### 🎯 Workflow Improvements
- **Batch processing**: Resolve multiple conflicts, auto-mark completed files
- **Status awareness**: Always know which files still need attention
- **Editor coordination**: Easy switching between n2b-diff and your editor
- **VCS compliance**: Follows proper Mercurial/Git resolution protocols

## 0.5.6 (2025-06-06) - Enhanced Context & Universal Spinners

### 🚀 Major Improvements
- **Full file context for n2b-diff**: LLM now receives complete file content for better merge decisions
- **Universal spinner indicators**: Added animated spinners to all LLM interactions
- **Better AI understanding**: Merge conflicts resolved with full code context awareness
- **Consistent UX**: Visual feedback across all n2b tools (diff, merge, commands)

### ✨ Enhanced Features
- **n2b-diff improvements**:
  - Full file content sent to LLM via `{full_file_content}` template variable
  - Spinner shows during initial conflict analysis: "🤖 AI is analyzing the conflict..."
  - Much better merge suggestions due to complete context understanding
- **n2b command improvements**:
  - Spinner during command generation: "🤖 AI is generating commands..."
  - Clear completion message: "✅ Commands generated!"
- **n2b --diff improvements**:
  - Spinner during diff analysis: "🔍 AI is analyzing your code diff..."
  - Progress indication: "✅ Diff analysis complete!"

### 🎯 Technical Details
- Updated merge conflict template to include `{full_file_content}` variable
- Added `make_request_with_spinner()` and `analyze_diff_with_spinner()` methods
- Consistent spinner animation across all LLM interactions
- Better error handling with spinner cleanup

## 0.5.5 (2025-06-06) - Critical UX Fixes for n2b-diff

### 🐛 Critical Bug Fixes
- **Fixed accidental merge acceptance**: Empty input no longer defaults to 'y' (accept)
- **Explicit confirmation required**: Users must type 'y', 'n', 'c', or 'a' explicitly
- **Added loading indicator**: Animated spinner shows when AI is processing comments
- **Improved comment workflow**: Clear instructions and feedback for multiline input
- **Better error messages**: Clearer prompts and validation messages

### ✨ UX Improvements
- **Visual feedback**: Colored status messages and progress indicators
- **Safer defaults**: No accidental actions from pressing Enter repeatedly
- **Comment confirmation**: Shows character count when comment is received
- **Processing visibility**: Users know when AI is working vs waiting for input

## 0.5.4 (2025-06-06) - AI-Powered Merge Conflict Resolver + Critical Fixes

### 🔧 NEW FEATURE: n2b-diff Command
- **AI-powered merge conflict resolution tool** with interactive workflow
- **Colorized conflict display** with configurable context lines (--context N)
- **Interactive options**: Accept/Skip/Comment/Abort for each conflict
- **Smart AI suggestions** with detailed reasoning explanations
- **Comment-driven improvements** - add context to get better suggestions
- **Merge logging** with timestamps and decision tracking in `.n2b_merge_log/`
- **Custom templates** - configurable merge prompts via `merge_conflict_prompt.txt`
- **Git & Mercurial support** - works with both VCS conflict markers
- **Template system** - extract merge prompts to customizable text files

### 🐛 Critical Bug Fixes
- **Fixed TypeError**: no implicit conversion of Hash into String in CLI
- **Improved JSON handling**: properly handles both Hash and String responses from LLM providers
- **Type safety**: JSON mode providers return parsed Hash, non-JSON mode returns String
- **Enhanced error handling**: better response type checking and fallbacks

### ✨ Enhancements
- **Added --version/-v flag** to display current version information
- **Template extraction**: merge prompts now use customizable template files
- **Better documentation**: comprehensive README updates with examples and use cases

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
