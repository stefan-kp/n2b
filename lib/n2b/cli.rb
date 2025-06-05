module N2B 
  class CLI < Base
    def self.run(args)
      new(args).execute
    end

    def initialize(args)
      @args = args
      @options = parse_options
    end

    def execute
      config = get_config(reconfigure: @options[:config])
      command = @args.shift # Get the command, e.g., 'diff'
      user_input = @args.join(' ') # Remaining args form user input/prompt addition

      if command == 'diff'
        vcs_type = get_vcs_type
        if vcs_type == :none
          puts "Error: Not a git or hg repository."
          exit 1
        end

        # Parse --requirements option from @args (which are args after 'diff')
        requirements_filepath = nil
        remaining_args_for_prompt = []
        i = 0
        while i < @args.length
          arg = @args[i]
          if arg.start_with?('--requirements=')
            requirements_filepath = arg.split('=', 2)[1]
            i += 1
          elsif arg == '--requirements' && @args[i+1]
            requirements_filepath = @args[i+1]
            i += 2 # Consumed both --requirements and its value
          else
            remaining_args_for_prompt << arg
            i += 1
          end
        end

        user_prompt_addition = remaining_args_for_prompt.join(' ')

        requirements_content = nil
        if requirements_filepath
          unless File.exist?(requirements_filepath)
            puts "Error: Requirements file not found: #{requirements_filepath}"
            exit 1
          end
          requirements_content = File.read(requirements_filepath)
          # For this subtask, requirements_content is read but not yet passed further.
          # This will be done in a subsequent step.
        end

        diff_output = execute_vcs_diff(vcs_type)
        analyze_diff(diff_output, config, user_prompt_addition, requirements_content)
      elsif command.nil? && user_input.empty? # No command and no input text after options
        puts "Enter your natural language command:"
        input_text = $stdin.gets.chomp
        process_natural_language_command(input_text, config)
      else # Natural language command (either `command` itself if not 'diff', or `user_input` if `command` was nil but there was text)
        input_text = command ? "#{command} #{user_input}".strip : user_input
        process_natural_language_command(input_text, config)
      else
        process_natural_language_command(input_text, config)
      end
    end

    protected

    def get_vcs_type
      if Dir.exist?(File.join(Dir.pwd, '.git'))
        :git
      elsif Dir.exist?(File.join(Dir.pwd, '.hg'))
        :hg
      else
        :none
      end
    end

    def execute_vcs_diff(vcs_type)
      case vcs_type
      when :git
        `git diff HEAD`
      when :hg
        `hg diff`
      else
        "" # Should not happen if get_vcs_type logic is correct and checked before calling
      end
    end

    private

    def process_natural_language_command(input_text, config)
      bash_commands = call_llm(input_text, config)

      puts "\nTranslated #{get_user_shell} Commands:"
      puts "------------------------"
      puts bash_commands['commands']
      puts "------------------------"
      if bash_commands['explanation']
        puts "Explanation:"
        puts bash_commands['explanation']
        puts "------------------------"
      end

      if @options[:execute]
        puts "Press Enter to execute these commands, or Ctrl+C to cancel."
        $stdin.gets
        system(bash_commands['commands'].join("\n"))
      else
        add_to_shell_history(bash_commands['commands'].join("\n")) if config['append_to_shell_history']
      end
    end

    def build_diff_analysis_prompt(diff_output, user_prompt_addition = "", requirements_content = nil)
      default_system_prompt = <<-SYSTEM_PROMPT.strip
You are a senior software developer reviewing a code diff.
Your task is to provide a constructive and detailed analysis of the changes.
Focus on identifying potential bugs, suggesting improvements in code quality, style, performance, and security.
Also, provide a concise summary of the changes.
The user may provide additional instructions or specific requirements below.
SYSTEM_PROMPT

      user_instructions_section = ""
      unless user_prompt_addition.to_s.strip.empty?
        user_instructions_section = "User Instructions:\n#{user_prompt_addition.strip}\n\n"
      end

      requirements_section = ""
      if requirements_content && !requirements_content.to_s.strip.empty?
        requirements_section = <<-REQUIREMENTS_BLOCK
Please pay close attention to the following requirements. You must verify if the code changes align with, implement, or contradict these requirements. Explicitly state how the diff addresses each requirement.
--- BEGIN REQUIREMENTS ---
#{requirements_content.strip}
--- END REQUIREMENTS ---

REQUIREMENTS_BLOCK
      end

      analysis_intro = "Analyze the following diff based on the general instructions above and these specific requirements (if any):"

      json_instruction = <<-JSON_INSTRUCTION.strip
Return your analysis as a JSON object with the keys "summary", "errors" (as a list of strings), and "improvements" (as a list of strings).
JSON_INSTRUCTION

      full_prompt = [
        default_system_prompt,
        user_instructions_section,
        requirements_section,
        analysis_intro,
        "Diff:\n```\n#{diff_output}\n```",
        json_instruction
      ].select { |s| s && !s.empty? }.join("\n\n") # Join non-empty sections with double newlines

      full_prompt
    end

    def analyze_diff(diff_output, config, user_prompt_addition = "", requirements_content = nil)
      prompt = build_diff_analysis_prompt(diff_output, user_prompt_addition, requirements_content)
      analysis_json_str = call_llm_for_diff_analysis(prompt, config)

      begin
        analysis_result = JSON.parse(analysis_json_str)

        puts "\nCode Diff Analysis:"
        puts "-------------------"
        puts "Summary:"
        puts analysis_result['summary'] || "No summary provided."
        puts "\nPotential Errors:"
        errors_list = analysis_result['errors']
        errors_list = [errors_list] if errors_list.is_a?(String) && !errors_list.empty?
        errors_list = [] if errors_list.nil? || (errors_list.is_a?(String) && errors_list.empty?)
        puts errors_list.any? ? errors_list.map{|err| "- #{err}"}.join("\n") : "No errors identified."

        puts "\nSuggested Improvements:"
        improvements_list = analysis_result['improvements']
        improvements_list = [improvements_list] if improvements_list.is_a?(String) && !improvements_list.empty?
        improvements_list = [] if improvements_list.nil? || (improvements_list.is_a?(String) && improvements_list.empty?)
        puts improvements_list.any? ? improvements_list.map{|imp| "- #{imp}"}.join("\n") : "No improvements suggested."
        puts "-------------------"
      rescue JSON::ParserError => e # Handles cases where the JSON string (even fallback) is malformed
        puts "Critical Error: Failed to parse JSON response for diff analysis: #{e.message}"
        puts "Raw response was: #{analysis_json_str}"
      end
    end

    def call_llm_for_diff_analysis(prompt, config)
      begin
        llm_service_name = config['llm']
        llm = case llm_service_name
              when 'openai'
                N2M::Llm::OpenAi.new(config)
              when 'claude'
                N2M::Llm::Claude.new(config)
              when 'gemini'
                N2M::Llm::Gemini.new(config)
              when 'openrouter'
                N2M::Llm::OpenRouter.new(config)
              when 'ollama'
                N2M::Llm::Ollama.new(config)
              else
                # Should not happen if config is validated, but as a safeguard:
                raise N2B::Error, "Unsupported LLM service: #{llm_service_name}"
              end

        response_json_str = llm.analyze_code_diff(prompt) # Call the new dedicated method
        response_json_str
      rescue N2B::LlmApiError => e # This catches errors from analyze_code_diff
        puts "Error communicating with the LLM: #{e.message}"
        return '{"summary": "Error: Could not analyze diff due to LLM API error.", "errors": [], "improvements": []}'
      end
    end
    
    def append_to_llm_history_file(commands)
      File.open(HISTORY_FILE, 'a') do |file|
        file.puts(commands)
      end
    end
    
    def read_llm_history_file
      history = File.read(HISTORY_FILE) if File.exist?(HISTORY_FILE)
      history ||= ''
      # limit to 20 most recent commands
      history.split("\n").last(20).join("\n")
    end
    
    def call_llm(prompt, config)
      begin # Added begin for LlmApiError rescue
        llm_service_name = config['llm']
        llm = case llm_service_name
              when 'openai'
                N2M::Llm::OpenAi.new(config)
              when 'claude'
                N2M::Llm::Claude.new(config)
              when 'gemini'
                N2M::Llm::Gemini.new(config)
              when 'openrouter'
                N2M::Llm::OpenRouter.new(config)
              when 'ollama'
                N2M::Llm::Ollama.new(config)
              else
                # Fallback or error, though config validation should prevent this
                puts "Warning: Unsupported LLM service '#{llm_service_name}' configured. Falling back to Claude."
                N2M::Llm::Claude.new(config)
              end

        # This content is specific to bash command generation
      content = <<-EOF
              Translate the following natural language command to bash commands: #{prompt}\n\nProvide only the #{get_user_shell} commands for #{ get_user_os }. the commands should be separated by newlines. 
              #{' the user is in directory'+Dir.pwd if config['privacy']['send_current_directory']}. 
              #{' the user sent past requests to you and got these answers '+read_llm_history_file if config['privacy']['send_llm_history'] }
              #{ "The user has this history for his shell. "+read_shell_history if config['privacy']['send_shell_history'] }
              he is using #{File.basename(get_user_shell)} shell."
              answer only with a valid json object with the key 'commands' and the value as a list of bash commands plus any additional information you want to provide in explanation.
              { "commands": [ "echo 'Hello, World!'" ], "explanation": "This command prints 'Hello, World!' to the terminal."}
              EOF
    
           
      response_json_str = llm.make_request(content)

      append_to_llm_history_file("#{prompt}\n#{response_json_str}") # Storing the raw JSON string
      # The original call_llm was expected to return a hash after JSON.parse,
      # but it was actually returning the string. Let's assume it should return a parsed Hash.
      # However, the calling method `process_natural_language_command` accesses it like `bash_commands['commands']`
      # which implies it expects a Hash. Let's ensure call_llm returns a Hash.
      # This internal JSON parsing is for the *content* of a successful LLM response.
      # The LlmApiError for network/auth issues should be caught before this.
      begin
        parsed_response = JSON.parse(response_json_str)
        parsed_response
      rescue JSON::ParserError => e
        puts "Error parsing LLM response JSON for command generation: #{e.message}"
        # This is a fallback for when the LLM response *content* is not valid JSON.
        { "commands" => ["echo 'Error: LLM returned invalid JSON content.'"], "explanation" => "The response from the language model was not valid JSON." }
      end
    rescue N2B::LlmApiError => e
      puts "Error communicating with the LLM: #{e.message}"
      # This is the fallback for LlmApiError (network, auth, etc.)
      { "commands" => ["echo 'LLM API error occurred. Please check your configuration and network.'"], "explanation" => "Failed to connect to the LLM." }
    end
    
    def get_user_shell
      ENV['SHELL'] || `getent passwd #{ENV['USER']}`.split(':')[6]
    end

    def get_user_os
      case RbConfig::CONFIG['host_os']
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
      :windows
      when /darwin|mac os/
      :macos
      when /linux/
      :linux
      when /solaris|bsd/
      :unix
      else
      :unknown
      end
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
        opts.banner = "Usage: n2b [options] [natural language command]"

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
      end.parse!(@args)

      options
    end
  end
end