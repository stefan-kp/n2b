# N2B: Natural Language to Bash Commands Converter

N2B (Natural to Bash) is a Ruby gem that converts natural language instructions into executable shell commands using the Claude AI API. It's designed to help users quickly generate shell commands without needing to remember exact syntax.

## Features

- Convert natural language to shell commands
- Support for multiple Claude AI models (Haiku, Sonnet, Sonnet 3.5)
- Option to execute generated commands directly
- Configurable privacy settings
- Shell history integration
- Command history tracking for improved context

## Installation

Install the gem by running:
gem install n2b

## Configuration

Before using n2b, you need to configure it with your Claude API key and preferences. Run:
n2b -c

This will prompt you to enter:
- Your Claude API key
- Preferred Claude model (haiku, sonnet, or sonnet35)
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

n2b list all PDF files in the current directory

2. Generate and execute commands:

n2b -x create a new directory named 'project' and initialize a git repository in it

3. Reconfigure the tool:

n2b -c 

## How It Works

1. N2B takes your natural language input and sends it to the Claude AI API.
2. The AI generates appropriate shell commands based on your input and configured shell.
3. N2B displays the generated commands and explanations (if any).
4. If the execute option is used, N2B will prompt for confirmation before running the commands.
5. Optionally, commands are added to your shell history for future reference.

## Privacy

N2B allows you to configure what information is sent to the Claude API:
- Shell history
- Past n2b requests and responses
- Current working directory

You can adjust these settings during configuration.

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