# N2B - Natural Language to Bash & Ruby

[![Gem Version](https://badge.fury.io/rb/n2b.svg)](https://badge.fury.io/rb/n2b)

N2B (Natural Language to Bash & Ruby) is a Ruby gem that leverages AI to convert natural language instructions into bash commands and Ruby code.

## Features

- Convert natural language to bash commands
- Generate Ruby code from natural language instructions
- Analyze Errbit errors and generate detailed reports
- Create formatted Scrum tickets from errors

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

Create a config file at `~/.n2b/config.yml` with your API keys. You can also use a custom config file by setting the `N2B_CONFIG_FILE` environment variable:

```bash
export N2B_CONFIG_FILE=/path/to/your/config.yml
```

Example config file:
```yaml
llm: claude  # or openai, gemini
claude:
  key: your-anthropic-api-key
  model: claude-3-opus-20240229 # or opus, haiku, sonnet
openai:
  key: your-openai-api-key
  model: gpt-4 # or gpt-3.5-turbo
gemini:
  key: your-google-api-key
  model: gemini-flash # uses gemini-2.0-flash model
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

## Configuration

Before using n2b, you need to configure it with your Claude API key and preferences. Run:
n2b -c

This will prompt you to enter:
- Your Claude API or OpenAI key
- Preferred  model (e.g. haiku, sonnet, or sonnet35)
- Privacy settings (whether to send shell history, past requests, current directory)
- Whether to append generated commands to your shell history

Configuration is stored in `~/.n2b/config.yml`.

## Usage

Basic usage:

n2b [options] your natural language instruction

Options:
- `-x` or `--execute`: Execute the generated commands after confirmation
- `-c` or `--config`: Reconfigure the tool
- `-h` or `--help`: Display help information

Examples:

1. Generate commands without executing:

```n2b list all PDF files in the current directory ```

2. Generate and execute commands:

```n2b -x create a new directory named 'project' and initialize a git repository in it ```

3. Reconfigure the tool:

```n2b -c  ```


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
- Reference to the original Errbit URL