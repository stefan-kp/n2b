#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'json'
require 'optparse'
require 'yaml'
require 'fileutils'

CONFIG_FILE = File.expand_path('~/.n2b/config.yml')
HISTORY_FILE = File.expand_path('~/.n2b/history')
def load_config
  if File.exist?(CONFIG_FILE)
    YAML.load_file(CONFIG_FILE)
  else
    { }
  end
end

MODELS = { 'haiku' =>  'claude-3-haiku-20240307', 'sonnet' => 'claude-3-sonnet-20240229', 'sonnet35' => 'claude-3-5-sonnet-20240620' }
def get_config( reconfigure: false)
  config = load_config
  api_key = ENV['CLAUDE_API_KEY'] || config['access_key']
  model = config['model'] || 'sonnet35'
  if api_key.nil? || api_key == '' ||  reconfigure
    print "Enter your Claude API key: #{ api_key.empty? ? '' : '(leave blank to keep the current key '+api_key[0..10]+'...)' }"
    api_key = $stdin.gets.chomp 
    api_key = config['access_key'] if api_key.empty?
    print "Choose a model (haiku, sonnet, sonnet35 (default)): "
    model = $stdin.gets.chomp 
    model = 'sonnet35' if model.empty?
    config['llm'] ||= 'anthropic'
    config['access_key'] = api_key
    config['model'] = model
    unless MODELS.keys.include?(model)
      puts "Invalid model. Choose from: #{MODELS.keys.join(', ')}"
      exit 1
    end
    
    config['privacy'] ||= {} 
    print "Do you want to send your shell history to Claude? (y/n): "
    config['privacy']['send_shell_history'] = $stdin.gets.chomp == 'y'
    print "Do you want to send your past requests and answers to Claude? (y/n): "
    config['privacy']['send_llm_history'] = $stdin.gets.chomp == 'y'
    print "Do you want to send your current directory to Claude? (y/n): "
    config['privacy']['send_current_directory'] = $stdin.gets.chomp == 'y'
    print "Do you want to append the commands to your shell history? (y/n): "
    config['append_to_shell_history'] = $stdin.gets.chomp == 'y'

    FileUtils.mkdir_p(File.dirname(CONFIG_FILE)) unless File.exist?(File.dirname(CONFIG_FILE))
    File.open(CONFIG_FILE, 'w+') do |f|
      f.write(config.to_yaml   )
    end
  end
  
  config
end

def append_to_llm_history_file(commands)
  File.open(HISTORY_FILE, 'a') do |file|
    file.puts(commands)
  end
end

def read_llm_history_file
  history = File.read(HISTORY_FILE) if File.exist?(HISTORY_FILE)
  history || ''
  # limit to 20 most recent commands
  history.split("\n").last(20).join("\n")
end

def call_llm(prompt, config)
  uri = URI.parse('https://api.anthropic.com/v1/messages')
  request = Net::HTTP::Post.new(uri)
  request.content_type = 'application/json'
  request['X-API-Key'] = config['access_key']
  request['anthropic-version'] = '2023-06-01'
  content = <<-EOF 
          Translate the following natural language command to bash commands: #{prompt}\n\nProvide only the #{get_user_shell} commands, no explanations. the commands should be separated by newlines. 
          #{' the user is in directory'+Dir.pwd if config['privacy']['send_current_directory']}. 
          #{' the user sends past requests and answers '+read_llm_history_file if config['privacy']['send_llm_history'] }
          #{ "The user has this history for his shell. "+read_shell_history if config['privacy']['send_shell_history'] }
          he is using #{File.basename(get_user_shell)} shell."
          answer only with a valid json object with the key 'commands' and the value as a list of bash commands plus any additional information you want to provide in explanation.
          { "commands": [ "echo 'Hello, World!'" ], "explanation": "This command prints 'Hello, World!' to the terminal."}
          EOF

  request.body = JSON.dump({
    "model" => MODELS[config['model']],
    "max_tokens" => 1024,
    "messages" => [
      {
        "role" => "user",
        "content" => content 
      }
    ]
  })

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end
  # check for errors
  if response.code != '200'
    puts "Error: #{response.code} #{response.message}"
    puts response.body
    exit 1
  end
  answer = JSON.parse(response.body)['content'].first['text'] 
  begin 
    # removee everything before the first { and after the last }
    answer = answer.sub(/.*\{(.*)\}.*/m, '{\1}')
    answer = JSON.parse(answer)
  rescue JSON::ParserError
    answer = { 'commands' => answer.split("\n"), explanation: answer}
  end
  append_to_llm_history_file("#{prompt}\n#{answer}")
  answer
end

def get_user_shell
  ENV['SHELL'] || `getent passwd #{ENV['USER']}`.split(':')[6]
end

def find_history_file(shell)
  case shell
  when 'zsh'
    [
      ENV['HISTFILE'],
      File.expand_path('~/.zsh_history'),
      File.expand_path('~/.zhistory')
    ].find { |f| f && File.exist?(f) }
  when 'bash'
    [
      ENV['HISTFILE'],
      File.expand_path('~/.bash_history')
    ].find { |f| f && File.exist?(f) }
  else
    nil
  end
end

def read_shell_history()
  shell = File.basename(get_user_shell)
  history_file = find_history_file(shell)
  return '' unless history_file

  File.read(history_file)
end

def add_to_shell_history(commands)
  shell = File.basename(get_user_shell)
  history_file = find_history_file(shell)

  unless history_file
    puts "Could not find history file for #{shell}. Cannot add commands to history."
    return
  end

  case shell
  when 'zsh'
    add_to_zsh_history(commands, history_file)
  when 'bash'
    add_to_bash_history(commands, history_file)
  else
    puts "Unsupported shell: #{shell}. Cannot add commands to history."
    return
  end

  puts "Commands have been added to your #{shell} history file: #{history_file}"
  puts "You may need to start a new shell session or reload your history to see the changes. #{ shell == 'zsh' ? 'For example, run `fc -R` in your zsh session.' : 'history -r for bash' }"
  puts "Then you can access them using the up arrow key or Ctrl+R for reverse search."
end

def add_to_zsh_history(commands, history_file)
  File.open(history_file, 'a') do |file|
    commands.each_line do |cmd|
      timestamp = Time.now.to_i
      file.puts(": #{timestamp}:0;#{cmd.strip}")
    end
  end
end

def add_to_bash_history(commands, history_file)
  File.open(history_file, 'a') do |file|
    commands.each_line do |cmd|
      file.puts(cmd.strip)
    end
  end
  system("history -r") # Attempt to reload history in current session
end

def parse_options
  options = { execute: false, config: nil }

  OptionParser.new do |opts|
    opts.banner = "Usage: script.rb [options]"

    opts.on('-x', '--execute', 'Execute the commands after confirmation') do
      options[:execute] = true
    end

    opts.on('-h', '--help', 'Print this help') do
      puts opts
      exit
    end

    opts.on('-c', '--config', 'Configure the API key and model') do
      options[:config] = true
    end
  end.parse!

  options
end



execute = false
options = parse_options
config = get_config( reconfigure: options[:config])
input_text = ARGV.join(' ')
if input_text.empty?
  puts "Enter your natural language command:"
  input_text = $stdin.gets.chomp
end
history_file = File.expand_path('~/.n2b_history')

bash_commands = call_llm(input_text,  config)

puts "\nTranslated #{get_user_shell} Commands:"
puts "------------------------"
puts bash_commands['commands']
puts "------------------------"
if bash_commands['explanation']
  puts "Explanation:" 
  puts bash_commands['explanation']
  puts "------------------------"
end 

if options[:execute]
  puts "Press Enter to execute these commands, or Ctrl+C to cancel."
  $stdin.gets
  system(bash_commands['commands'].join("\n"))
else
  add_to_shell_history(bash_commands['commands'].join("\n")) if config['append_to_shell_history']
end