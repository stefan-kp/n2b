# N2B: Natural Language to Bash Commands Converter

N2B (Natural to Bash) is a Ruby gem that converts natural language instructions into executable shell commands using the Claude AI or OpenAI API. It's designed to help users quickly generate shell commands without needing to remember exact syntax.
Also it has the n2r method which can help you with any Ruby or Rails related issues

## Features

### N2B

- Convert natural language to shell commands
- Support for multiple Claude AI models (Haiku, Sonnet, Sonnet 3.5)
- Support for OpenAI models
- Option to execute generated commands directly
- Configurable privacy settings
- Shell history integration
- Command history tracking for improved context

### N2R
- Convert natural language to ruby code or explain it 
- analyze an exception and find the cause
- analyze existing ruby files
 

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