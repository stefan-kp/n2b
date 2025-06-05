# N2B - Natural Language to Bash & Ruby

[![Gem Version](https://badge.fury.io/rb/n2b.svg)](https://badge.fury.io/rb/n2b)

N2B (Natural Language to Bash & Ruby) is a Ruby gem that leverages AI to convert natural language instructions into bash commands and Ruby code.

## Features

- **🤖 Natural Language to Commands**: Convert natural language to bash commands
- **💎 Ruby Code Generation**: Generate Ruby code from natural language instructions
- **🔍 AI-Powered Diff Analysis**: Analyze git/hg diffs with comprehensive code review
- **📋 Requirements Compliance**: Check if code changes meet specified requirements
- **🧪 Test Coverage Assessment**: Evaluate test coverage for code changes
- **🌿 Branch Comparison**: Compare changes against any branch (main/master/default)
- **🛠️ VCS Support**: Full support for both Git and Mercurial repositories
- **📊 Errbit Integration**: Analyze Errbit errors and generate detailed reports
- **🎫 Scrum Tickets**: Create formatted Scrum tickets from errors

### 🆕 **New in v0.4.0: Flexible Model Configuration**

- **🎯 Multiple LLM Providers**: Claude, OpenAI, Gemini, OpenRouter, Ollama
- **🔧 Custom Models**: Use any model name - fine-tunes, beta models, custom deployments
- **📋 Suggested Models**: Curated lists of latest models with easy selection
- **🚀 Latest Models**: OpenAI O3/O4 series, Gemini 2.5, updated OpenRouter models
- **🔄 Backward Compatible**: Existing configurations continue working seamlessly
- **⚡ No Restrictions**: Direct API model names accepted without validation

## Installation

```bash
gem install n2b
```

## Usage

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
- `-c` or `--config`: Reconfigure the tool
- `-h` or `--help`: Display help information

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
- Reference to the original Errbit URL# Test change
