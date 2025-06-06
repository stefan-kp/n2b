# N2B - AI-Powered Code Analysis & Jira Integration

[![Gem Version](https://badge.fury.io/rb/n2b.svg)](https://badge.fury.io/rb/n2b)

**Transform your development workflow with intelligent code analysis and seamless Jira integration.** N2B is an AI-powered development tool that revolutionizes code review, requirements compliance, and project management through automated analysis and smart ticket integration.

## 🚀 **Key Features**

### 🎯 **Smart Jira Integration**
- **Automated Ticket Analysis**: Fetch requirements from Jira tickets and analyze code changes against them
- **Intelligent Updates**: Post beautifully formatted analysis results directly to Jira with collapsible sections
- **Requirements Extraction**: Automatically identify acceptance criteria, tasks, and requirements from tickets and comments
- **Real-time Feedback**: Get instant compliance checking and implementation guidance

### 🔍 **AI-Powered Code Analysis**
- **Context-Aware Diff Review**: Intelligent analysis of git/hg changes with comprehensive insights
- **Requirements Compliance**: Automated verification against project requirements and acceptance criteria
- **Test Coverage Assessment**: Evaluate test completeness and suggest improvements
- **Security & Quality Insights**: Identify potential issues, risks, and improvement opportunities

### 🤖 **Flexible AI Support**
- **Multiple LLM Providers**: Claude, OpenAI, Gemini, OpenRouter, Ollama
- **Latest Models**: OpenAI O3/O4 series, Gemini 2.5, Claude Sonnet 4.0
- **Custom Models**: Support for fine-tuned models, beta releases, and custom deployments

### 💻 **Development Workflow**
- **Natural Language Commands**: Convert descriptions to executable bash commands
- **Ruby Code Generation**: Generate Ruby code from natural language instructions
- **VCS Integration**: Full Git and Mercurial support with branch comparison
- **AI Merge Conflict Resolution**: Interactive merge conflict resolver with intelligent suggestions
- **Errbit Integration**: Analyze errors and generate actionable reports

## 🎯 **Jira Integration - Get Started in 2 Minutes**

Transform your development workflow with intelligent Jira integration:

### Quick Setup

```bash
# Install and configure
gem install n2b
n2b --advanced-config  # Set up Jira credentials

# Test your connection
n2b-test-jira

# Analyze code against ticket requirements
n2b --diff --jira PROJ-123 --jira-update
```

### What You Get

1. **📥 Smart Ticket Analysis**: Automatically fetches requirements, acceptance criteria, and comments from Jira
2. **🔍 Intelligent Code Review**: AI analyzes your changes against ticket requirements
3. **📤 Structured Updates**: Posts beautifully formatted analysis back to Jira with collapsible sections
4. **✅ Requirements Compliance**: Clear status on what's implemented, partially done, or missing

### Example Workflow

```bash
# Working on ticket PROJ-123
git add .
n2b --diff --jira PROJ-123 --jira-update
```

**Result**: Your Jira ticket gets updated with a professional analysis comment showing implementation progress, technical insights, and compliance status.

## 🔍 **AI-Powered Code Analysis**

Get comprehensive code review and insights:

```bash
# Analyze uncommitted changes
n2b --diff

# Compare against specific branch with requirements
n2b --diff --branch main --requirements requirements.md

# Full workflow with Jira integration
n2b --diff --jira PROJ-123 --requirements specs.md
```

## 🆕 **What's New in v0.5.4**

- **🔧 NEW: n2b-diff Command**: AI-powered merge conflict resolution tool
- **🎨 Interactive Workflow**: Accept/Skip/Comment/Abort for each conflict with colorized display
- **🤖 Smart Suggestions**: AI analyzes both sides and suggests optimal merges
- **📝 Custom Templates**: Configurable merge prompts for different workflows
- **🎯 Full Jira Integration**: Real API integration with ticket fetching and automated updates
- **📝 Structured Comments**: Beautifully formatted Jira comments with collapsible sections
- **🔍 Smart Requirements Extraction**: AI identifies requirements from tickets and comments
- **🧪 Connection Testing**: Built-in `n2b-test-jira` utility for troubleshooting
- **📋 Permission Validation**: Verifies all required Jira API permissions
- **⚡ Enhanced Analysis**: Improved code review with better context and insights

## Installation

### **Basic Installation**

```bash
gem install n2b
```

### **Global Installation with rbenv**

For users with rbenv (Ruby version manager), install globally to make n2b available across all Ruby versions:

```bash
# Option 1: Install in system Ruby (Recommended)
rbenv global system
gem install n2b
rbenv rehash

# Option 2: Install in a dedicated Ruby version
rbenv install 3.3.0
rbenv global 3.3.0
gem install n2b
rbenv rehash

# Verify installation works across Ruby versions
rbenv shell 3.1.0 && n2b --version
rbenv shell 3.2.0 && n2b --version
```

### **Fix rbenv Shim Issues**

If `n2b-diff` command is not found after installation:

```bash
# Remove corrupted shim and regenerate
rm ~/.rbenv/shims/.rbenv-shim
rm -rf ~/.rbenv/shims/*
rbenv rehash

# Verify both commands are available
which n2b
which n2b-diff
```

### **Configure as Default Merge Tool**

#### **Git Integration**

Add to your `~/.gitconfig`:

```ini
[merge]
    tool = n2b-diff

[mergetool "n2b-diff"]
    cmd = n2b-diff "$MERGED"
    trustExitCode = true
    keepBackup = false
```

Usage:
```bash
git merge feature-branch
# CONFLICT (content): Merge conflict in file.rb
git mergetool  # Uses n2b-diff automatically
```

#### **Mercurial (hg) Integration**

Add to your `~/.hgrc`:

```ini
[ui]
merge = n2b-diff

[merge-tools]
n2b-diff.executable = n2b-diff
n2b-diff.args = $output
n2b-diff.premerge = keep
n2b-diff.priority = 100
```

Usage:
```bash
hg merge
# conflict in file.rb
# n2b-diff launches automatically
```

## Quick Start

### 🎯 **For Jira Users** (Most Popular)

```bash
# Set up Jira integration
n2b --advanced-config

# Analyze code changes against ticket
n2b --diff --jira PROJ-123 --jira-update
```

### 🔍 **For Code Review**

```bash
# AI-powered diff analysis
n2b --diff

# Compare against main branch with requirements
n2b --diff --branch main --requirements specs.md
```

### 💻 **For Command Generation**

```bash
# Generate bash commands
n2b "create a new git repo and push to github"

# Execute commands directly
n2b -x "backup all .rb files to backup folder"
```

## Detailed Usage

### In IRB/Rails Console

First, require and extend the N2B module:

```ruby
require 'n2b'
extend N2B::IRB
```

For automatic loading in every IRB session, add these lines to your `~/.irbrc`:

```ruby
require 'n2b'
extend N2B::IRB
```

After loading, you can use the following commands:

- `n2r` - For general Ruby assistance
- `n2rrbit` - For Errbit error analysis
- `n2rscrum` - For generating Scrum tickets

### Examples

```ruby
# Get help with a Ruby question
n2r "How do I parse JSON in Ruby?"

# Analyze an Errbit error
n2rrbit(url: "your_errbit_url", cookie: "your_cookie")

# Generate a Scrum ticket
n2rscrum "Create a user authentication system"
```

## Configuration

N2B now features a **flexible model configuration system** that supports both suggested models and custom model names across all providers.

### Quick Setup

Run the configuration command to get started:

```bash
n2b -c
```

This will guide you through:
- Selecting your preferred LLM provider (Claude, OpenAI, Gemini, OpenRouter, Ollama)
- Choosing from suggested models or entering custom model names
- Setting up API keys
- Configuring privacy settings

### Supported Models

#### 🤖 **Claude** (Default: sonnet)
- `haiku` → claude-3-haiku-20240307
- `sonnet` → claude-3-sonnet-20240229
- `sonnet35` → claude-3-5-sonnet-20240620
- `sonnet37` → claude-3-7-sonnet-20250219
- `sonnet40` → claude-sonnet-4-20250514
- **Custom models**: Any Claude model name

#### 🧠 **OpenAI** (Default: gpt-4o-mini)
- `gpt-4o` → gpt-4o
- `gpt-4o-mini` → gpt-4o-mini
- `o3` → o3 (Latest reasoning model)
- `o3-mini` → o3-mini
- `o3-mini-high` → o3-mini-high
- `o4` → o4
- `o4-mini` → o4-mini
- `o4-mini-high` → o4-mini-high
- **Custom models**: Any OpenAI model name

#### 🔮 **Gemini** (Default: gemini-2.5-flash)
- `gemini-2.5-flash` → gemini-2.5-flash-preview-05-20
- `gemini-2.5-pro` → gemini-2.5-pro-preview-05-06
- **Custom models**: Any Gemini model name

#### 🌐 **OpenRouter** (Default: deepseek-v3)
- `deepseek-v3` → deepseek-v3-0324
- `deepseek-r1-llama-8b` → deepseek-r1-distill-llama-8b
- `llama-3.3-70b` → llama-3.3-70b-instruct
- `llama-3.3-8b` → llama-3.3-8b-instruct
- `wayfinder-large` → wayfinder-large-70b-llama-3.3
- **Custom models**: Any OpenRouter model name

#### 🦙 **Ollama** (Default: llama3)
- `llama3` → llama3
- `mistral` → mistral
- `codellama` → codellama
- `qwen` → qwen2.5
- **Custom models**: Any locally available Ollama model

### Custom Configuration File

You can use a custom config file by setting the `N2B_CONFIG_FILE` environment variable:

```bash
export N2B_CONFIG_FILE=/path/to/your/config.yml
```

You can also set the history file location using the `N2B_HISTORY_FILE` environment variable:
```bash
export N2B_HISTORY_FILE=/path/to/your/history
```

### Custom Prompt Templates

N2B uses text templates for AI prompts. To override them, specify paths in your configuration:

```yaml
templates:
  diff_system_prompt: /path/to/my_system_prompt.txt
  diff_json_instruction: /path/to/my_json_instruction.txt
  merge_conflict_prompt: /path/to/my_merge_prompt.txt
```

When these paths are not provided, the built-in templates located in `lib/n2b/templates/` are used.

**Available Templates:**
- `diff_system_prompt.txt` - Main diff analysis prompt
- `diff_json_instruction.txt` - JSON formatting instructions for diff analysis
- `merge_conflict_prompt.txt` - Merge conflict resolution prompt

## Quick Example N2B

```
n2b init a new github repo called abc, add local files, transmit
```

results in 
```
Translated /bin/zsh Commands:
------------------------
git init
git remote add origin https://github.com/yourusername/abc.git
git add .
git commit -m 'Initial commit'
git push -u origin main
------------------------
Explanation:
These commands initialize a new Git repository, add a remote GitHub repository named 'abc', stage all local files, create an initial commit, and push the changes to GitHub. Replace 'yourusername' with your actual GitHub username. Note that you'll need to create the repository on GitHub first before running these commands. Also, ensure you have Git installed and configured with your GitHub credentials.
```

## Quick example n2r 

```
irb
require 'n2b'
n2r 4544 # results in exception
n2r "what is the bug",exception:_
```

result
```
input_string.to_s.scan(/[\/\w.-]+\.rb(?=\s|:|$)/)
```
Explanation 
 The error `undefined method 'scan' for 7767:Integer` occurs because the method `scan` is being called on an integer instead of a string. To fix the issue, we need to ensure that `input_string` is a string before calling the `scan` method on it. Here's the corrected part of the code that converts `input_string` to a string before using `scan`:

```ruby
input_string.to_s.scan(/[\/\w.-]+\.rb(?=\s|:|$)/)
```

------------------------
## Installation

Install the gem by running:
gem install n2b

## Enhanced Model Selection

N2B v0.4.0 introduces a **flexible model configuration system**:

### Interactive Model Selection

When you run `n2b -c`, you'll see an enhanced interface:

```
Choose a model for openai:
1. gpt-4o (gpt-4o)
2. gpt-4o-mini (gpt-4o-mini) [default]
3. o3 (o3)
4. o3-mini (o3-mini)
5. o3-mini-high (o3-mini-high)
6. o4 (o4)
7. o4-mini (o4-mini)
8. o4-mini-high (o4-mini-high)
9. custom (enter your own model name)

Enter choice (1-9) or model name [gpt-4o-mini]: 9
Enter custom model name: gpt-5-preview
✓ Using custom model: gpt-5-preview
```

### Key Features

- **🎯 Suggested Models**: Curated list of latest models for each provider
- **🔧 Custom Models**: Enter any model name for fine-tunes, beta models, etc.
- **🔄 Backward Compatible**: Existing configurations continue working
- **🚀 Latest Models**: Access to newest OpenAI O-series, Gemini 2.5, etc.
- **⚡ No Validation**: Direct API model names accepted - let the API handle errors

Configuration is stored in `~/.n2b/config.yml`.

## Usage

Basic usage:

n2b [options] your natural language instruction

Options:
- `-x` or `--execute`: Execute the generated commands after confirmation
- `-d` or `--diff`: Analyze git/hg diff with AI-powered code review
- `-b` or `--branch [BRANCH]`: Compare against specific branch (auto-detects main/master/default)
- `-r` or `--requirements FILE`: Requirements file for compliance checking
- `-j` or `--jira TICKET`: Jira ticket ID or URL for context and updates
- `--jira-update`: Automatically update Jira ticket with analysis (no prompt)
- `--jira-no-update`: Skip Jira ticket update (analyze only)
- `-c` or `--config`: Reconfigure the tool
- `--advanced-config`: Advanced configuration including Jira setup
- `-v` or `--version`: Show version information
- `-h` or `--help`: Display help information

**Additional Commands:**
- `n2b-diff FILE`: AI-powered merge conflict resolution
- `n2b-test-jira`: Test Jira API connection and permissions

Examples:

1. Generate commands without executing:

```n2b list all PDF files in the current directory ```

2. Generate and execute commands:

```n2b -x create a new directory named 'project' and initialize a git repository in it ```

3. Reconfigure the tool:

```n2b -c  ```

## 🔍 AI-Powered Diff Analysis

N2B provides comprehensive AI-powered code review for your git and mercurial repositories.

### Basic Diff Analysis

```bash
# Analyze uncommitted changes
n2b --diff

# Analyze changes against specific branch
n2b --diff --branch main
n2b --diff --branch feature/auth

# Auto-detect default branch (main/master/default)
n2b --diff --branch

# Short form
n2b -d -b main
```

### Requirements Compliance Checking

```bash
# Check if changes meet requirements
n2b --diff --requirements requirements.md
n2b -d -r req.md

# Combine with branch comparison
n2b --diff --branch main --requirements requirements.md
```

### What You Get

The AI analysis provides:

- **📝 Summary**: Clear overview of what changed
- **🚨 Potential Errors**: Bugs, security issues, logic problems with exact file/line references
- **💡 Suggested Improvements**: Code quality, performance, style recommendations
- **🧪 Test Coverage Assessment**: Evaluation of test completeness and quality
- **📋 Requirements Evaluation**: Compliance check with clear status indicators:
  - ✅ **IMPLEMENTED**: Requirement fully satisfied
  - ⚠️ **PARTIALLY IMPLEMENTED**: Needs more work
  - ❌ **NOT IMPLEMENTED**: Not addressed
  - 🔍 **UNCLEAR**: Cannot determine from diff

### Example Output

```
Code Diff Analysis:
-------------------
Summary:
Added user authentication with JWT tokens and password validation.

Potential Errors:
- lib/auth.rb line 42: Password validation allows weak passwords
- controllers/auth_controller.rb lines 15-20: Missing rate limiting for login attempts

Suggested Improvements:
- lib/auth.rb line 30: Consider using bcrypt for password hashing
- spec/auth_spec.rb: Add tests for edge cases and security scenarios

Test Coverage Assessment:
Good: Basic authentication flow is tested. Missing: No tests for password validation edge cases, JWT expiration handling, or security attack scenarios.

Requirements Evaluation:
✅ IMPLEMENTED: User login/logout functionality fully working
⚠️ PARTIALLY IMPLEMENTED: Password strength requirements present but not comprehensive
❌ NOT IMPLEMENTED: Two-factor authentication not addressed in this diff
-------------------
```

### Supported Version Control Systems

- **Git**: Full support with auto-detection of main/master branches
- **Mercurial (hg)**: Full support with auto-detection of default branch

## 🎯 Jira Integration

N2B provides seamless integration with Jira for automated ticket analysis and updates.

### Setup

Configure Jira integration using the advanced configuration:

```bash
n2b --advanced-config
```

You'll need:
- **Jira Domain**: Your Atlassian domain (e.g., `company.atlassian.net`)
- **Email**: Your Jira account email
- **API Token**: Generate from [Atlassian Account Settings](https://id.atlassian.com/manage-profile/security/api-tokens)

### Required Jira API Scopes

Your API token needs these specific scopes:

**Essential Scopes:**
- `read:project:jira` - View projects (access project list)
- `read:issue:jira` - View issues (fetch ticket details)
- `read:comment:jira` - View comments (fetch ticket comments for context)
- `write:comment:jira` - Create and update comments (post analysis results)

**Optional but Recommended:**
- `read:issue-details:jira` - View detailed issue information
- `read:issue.property:jira` - View issue properties (comprehensive ticket data)

**Legacy Permission Names (for older Jira versions):**
- Browse Projects, Browse Issues, View Comments, Add Comments

### Usage

```bash
# Analyze code changes against Jira ticket requirements
n2b --diff --jira PROJ-123

# Use full Jira URL
n2b --diff --jira https://company.atlassian.net/browse/PROJ-123

# Auto-update ticket without prompt
n2b --diff --jira PROJ-123 --jira-update

# Analyze only (no ticket update)
n2b --diff --jira PROJ-123 --jira-no-update
```

### What It Does

1. **Fetches Ticket Details**: Downloads ticket description and comments
2. **Extracts Requirements**: Automatically identifies requirements, acceptance criteria, and tasks
3. **Analyzes Code Changes**: Compares your diff against ticket requirements
4. **Updates Ticket**: Posts structured analysis comment with:
   - Implementation summary (what you accomplished)
   - Technical analysis findings
   - Potential issues and suggestions
   - Test coverage assessment
   - Requirements compliance check

### Example Jira Comment

```
*N2B Code Analysis Report*
=========================

*Implementation Summary:*
Implemented user authentication with JWT tokens, password validation,
and session management as specified in the ticket requirements.

---

*Automated Analysis Findings:*

*Technical Changes:*
Added authentication middleware, JWT token generation, and password
hashing with bcrypt. Updated user model with authentication methods.

*Potential Issues/Risks:*
• No rate limiting on login attempts
• Password validation could be stronger

*Suggested Improvements:*
• Add rate limiting middleware
• Implement password strength requirements
• Add two-factor authentication support

*Test Coverage Assessment:*
Good: Basic authentication flow tested. Missing: Edge cases, security
scenarios, and JWT expiration handling tests.

*Requirements Evaluation:*
✅ IMPLEMENTED: User login/logout functionality
✅ IMPLEMENTED: Password hashing and validation
⚠️ PARTIALLY IMPLEMENTED: Session management (basic implementation)
❌ NOT IMPLEMENTED: Two-factor authentication
```

### Testing Jira Connection

Test your Jira API connection and permissions:

```bash
# Test basic connection
n2b-test-jira

# Test specific ticket access
n2b-test-jira PROJ-123
```

This will verify:
- Network connectivity to Jira
- Authentication with your API token
- Required permissions
- Specific ticket access (if provided)

## 🔧 **AI-Powered Merge Conflict Resolution (n2b-diff)**

Resolve Git and Mercurial merge conflicts with intelligent AI assistance.

### Quick Start

```bash
# Resolve conflicts in a file
n2b-diff conflicted_file.rb

# With more context lines
n2b-diff conflicted_file.rb --context 20

# Get help
n2b-diff --help
```

### How It Works

1. **🔍 Detects Conflicts**: Automatically finds `<<<<<<<`, `=======`, `>>>>>>>` markers
2. **📋 Extracts Context**: Shows surrounding code for better understanding
3. **🤖 AI Analysis**: LLM analyzes both sides and suggests optimal merge
4. **🎨 Interactive Review**: Colorized display with Accept/Skip/Comment/Abort options
5. **✅ Applies Changes**: Updates file with accepted merges

### Interactive Workflow

For each conflict, you can:
- **[y] Accept** - Apply the AI suggestion
- **[n] Skip** - Keep the conflict as-is
- **[c] Comment** - Add context to improve AI suggestions
- **[a] Abort** - Stop processing and keep file unchanged

### Features

#### **🎨 Colorized Display**
- 🔴 **Red**: Base/HEAD content (`<<<<<<< HEAD`)
- 🟢 **Green**: Incoming content (`>>>>>>> feature`)
- 🟡 **Yellow**: Conflict markers (`=======`)
- 🔵 **Blue**: AI suggestions
- ⚪ **Gray**: Reasoning explanations

#### **🤖 Smart AI Analysis**
- **Context Awareness**: Understands surrounding code patterns
- **Quality Decisions**: Chooses enhanced implementations over simple ones
- **Consistency**: Maintains coding patterns and architectural decisions
- **User Feedback**: Incorporates comments to improve suggestions

#### **⚙️ Configurable Options**
- **Context Lines**: `--context N` (default: 10)
- **Merge Logging**: Optional JSON logs in `.n2b_merge_log/`
- **Custom Templates**: Configurable merge prompts

### Example Session

```bash
$ n2b-diff user_service.rb

<<<<<<< HEAD
def create_user(name, email)
  # Basic validation
  raise "Invalid" if name.empty?
  User.create(name: name, email: email)
end
=======
def create_user(name, email, age = nil)
  # Enhanced validation
  validate_name(name)
  validate_email(email)
  User.create(name: name.titleize, email: email.downcase, age: age)
end
>>>>>>> feature/enhanced-validation

--- Suggestion ---
def create_user(name, email, age = nil)
  # Enhanced validation with fallback
  validate_name(name) if respond_to?(:validate_name)
  validate_email(email) if respond_to?(:validate_email)
  User.create(name: name.titleize, email: email.downcase, age: age)
end

Reason: Combined enhanced validation from feature branch with safety checks
for method existence, maintaining backward compatibility while adding new features.

Accept [y], Skip [n], Comment [c], Abort [a]: y
```

### Custom Templates

Customize merge prompts by adding to your config:

```yaml
templates:
  merge_conflict_prompt: /path/to/my_merge_prompt.txt
```

Template variables available:
- `{full_file_content}` - Complete file content for full context understanding
- `{context_before}` - Code before the conflict
- `{context_after}` - Code after the conflict
- `{base_label}` - Base branch label (e.g., "HEAD")
- `{base_content}` - Base branch content
- `{incoming_label}` - Incoming branch label (e.g., "feature/auth")
- `{incoming_content}` - Incoming branch content
- `{user_comment}` - User-provided comment (if any)

### Use Cases

- **Feature Branch Merges**: Resolve conflicts when merging feature branches
- **Code Reviews**: Get AI assistance for complex merge decisions
- **Refactoring**: Handle conflicts during large refactoring efforts
- **Team Collaboration**: Standardize merge conflict resolution approaches
- **Learning Tool**: Understand best practices for conflict resolution

### **Daily Workflow Integration**

#### **Git Workflow**
```bash
# During merge conflicts
git merge feature-branch
# CONFLICT (content): Merge conflict in file.rb

# Use configured merge tool
git mergetool

# Or call directly
n2b-diff file.rb

# Continue merge
git add file.rb
git commit -m "Resolve merge conflicts"
```

#### **Mercurial Workflow**
```bash
# During hg merge conflicts
hg merge
# conflict in file.rb

# Resolve with n2b-diff (auto-launches if configured)
n2b-diff file.rb

# Mark as resolved and commit
hg resolve --mark file.rb
hg commit -m "Resolve merge conflicts"
```

#### **Rebase Conflicts**
```bash
# Git rebase conflicts
git rebase -i main
# CONFLICT: Merge conflict in user_service.rb

n2b-diff user_service.rb
git add user_service.rb
git rebase --continue
```

#### **Batch Conflict Resolution**
```bash
# Find and resolve all conflicts
find . -name "*.rb" -exec grep -l "<<<<<<< HEAD" {} \; | while read file; do
    echo "Resolving conflicts in $file"
    n2b-diff "$file"
done
```

#### **Shell Aliases for Convenience**
Add to your `.zshrc` or `.bashrc`:
```bash
# Quick aliases for n2b tools
alias resolve-conflicts='n2b-diff'
alias test-jira='n2b-test-jira'
alias ai-diff='n2b --diff'

# Function to resolve all conflict files
resolve-all-conflicts() {
    find . -name "*.rb" -exec grep -l "<<<<<<< HEAD" {} \; | while read file; do
        echo "Resolving conflicts in $file"
        n2b-diff "$file"
    done
}
```

n2r in ruby or rails console
n2r "your question", files:['file1.rb', 'file2.rb'], exception: AnError
only question is mandatory

N2B::IRB.n2r if no shortcut defined

## Shortcut in rails console
create an initializer 
```
# config/initializers/n2r.rb
require 'n2b/irb' 
Rails.application.config.after_initialize do

  Object.include(Module.new do
    def n2r(input_string = '', files: [], exception: nil, log: false)
      N2B::IRB.n2r(input_string, files: files, exception: exception, log: log)
    end
  end)

end
```

## How It Works

1. N2B takes your natural language input and sends it to the Claude AI API.
2. The AI generates appropriate shell commands based on your input and configured shell.
3. N2B displays the generated commands and explanations (if any).
4. If the execute option is used, N2B will prompt for confirmation before running the commands.
5. Optionally, commands are added to your shell history for future reference.

## Privacy

N2B allows you to configure what information is sent to the Claude API:
- Shell history / probably not needed, I added the option to give the llm more context
- Past n2b requests and responses / probably not needed, I added the option to give the llm more context
- Current working directory / recommended

You can adjust these settings during configuration.

Always sent to llm
- prompt
- shell type 
- operating system


## Limitations

- The quality of generated commands depends on the Claude AI model's capabilities.
- Complex or ambiguous instructions might not always produce the desired results.
- Always review generated commands before execution, especially when using the `-x` option.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.

## Version History

### 🔧 **v0.5.4 - AI-Powered Merge Conflict Resolver**
- **NEW: n2b-diff command** - Interactive AI-powered merge conflict resolution
- Colorized conflict display with Accept/Skip/Comment/Abort workflow
- Smart AI suggestions with detailed reasoning and user feedback integration
- Custom templates for merge prompts and configurable context lines
- Merge logging and Git/Mercurial support

### 🚀 **v0.5.0 - Jira Integration & Enhanced Analysis**
- Full Jira API integration with real ticket fetching and comment posting
- Structured Jira comments using ADF with collapsible sections
- Smart requirements extraction from ticket descriptions and comments
- Built-in connection testing with `n2b-test-jira` utility
- Enhanced configuration validation and error handling

### 🔧 **v0.4.0 - Flexible Model Configuration**
- Multiple LLM providers: Claude, OpenAI, Gemini, OpenRouter, Ollama
- Custom model support for fine-tunes and beta releases
- Latest models: OpenAI O3/O4 series, Gemini 2.5, Claude Sonnet 4.0
- Backward compatible configuration system

### 🔍 **v0.3.0 - AI-Powered Diff Analysis**
- Git/Mercurial diff analysis with context extraction
- Requirements compliance checking
- Test coverage assessment
- Branch comparison with auto-detection

## Support

If you encounter any issues or have questions, please file an issue on the GitHub repository.

### Generate Scrum Tickets from Errors

Create well-formatted Scrum tickets from Errbit errors:

```ruby
require 'n2b'

# Generate a Scrum ticket from an Errbit error
n2rscrum(
  url: "https://your-errbit-instance/apps/12345/problems/67890",
  cookie: "your_errbit_session_cookie",
  source_dir: "/path/to/your/app"   # Optional: source code directory
)
```

The generated tickets include:
- Clear title and description
- Technical details with error context
- Request parameters analysis
- Root cause analysis
- Suggested fixes with code examples
- Acceptance criteria
- Story point estimate
- Priority level
- Reference to the original Errbit URL
