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
      # Pass advanced_config flag to get_config
      config = get_config(reconfigure: @options[:config], advanced_flow: @options[:advanced_config])
      user_input = @args.join(' ') # All remaining args form user input/prompt addition

      # Diff functionality has been removed from N2B::CLI
      # if @options[:diff]
      #   handle_diff_analysis(config)
      # els
      if user_input.empty? # No input text after options
        # If config mode was chosen, it's handled by get_config.
        # If not, and no input, prompt for it.
        unless @options[:config] # Don't prompt if only -c or --advanced-config was used
          puts "Enter your natural language command (or type 'exit' or 'quit'):"
          input_text = $stdin.gets.chomp
          exit if ['exit', 'quit'].include?(input_text.downcase)
          process_natural_language_command(input_text, config)
        end
      else # Natural language command provided as argument
        process_natural_language_command(user_input, config)
      end
    end

    protected

    # All diff-related methods like handle_diff_analysis, get_vcs_type, etc., are removed.

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

    def build_diff_analysis_prompt(diff_output, user_prompt_addition = "", requirements_content = nil, config = {})
      default_system_prompt_path = resolve_template_path('diff_system_prompt', config)
      default_system_prompt = File.read(default_system_prompt_path).strip

      user_instructions_section = ""
      unless user_prompt_addition.to_s.strip.empty?
        user_instructions_section = "User Instructions:\n#{user_prompt_addition.strip}\n\n"
      end

      requirements_section = ""
      if requirements_content && !requirements_content.to_s.strip.empty?
        requirements_section = <<-REQUIREMENTS_BLOCK
CRITICAL REQUIREMENTS EVALUATION:
You must carefully evaluate whether the code changes meet the following requirements from the ticket/task.
For each requirement, explicitly state whether it is:
- ✅ IMPLEMENTED: The requirement is fully satisfied by the changes
- ⚠️ PARTIALLY IMPLEMENTED: The requirement is partially addressed but needs more work
- ❌ NOT IMPLEMENTED: The requirement is not addressed by these changes
- 🔍 UNCLEAR: Cannot determine from the diff whether the requirement is met

--- BEGIN REQUIREMENTS ---
#{requirements_content.strip}
--- END REQUIREMENTS ---

REQUIREMENTS_BLOCK
      end

      analysis_intro = "Analyze the following diff based on the general instructions above and these specific requirements (if any):"

      # Extract context around changed lines
      context_sections = extract_code_context_from_diff(diff_output)
      context_info = ""
      unless context_sections.empty?
        context_info = "\n\nCurrent Code Context (for better analysis):\n"
        context_sections.each do |file_path, sections|
          context_info += "\n--- #{file_path} ---\n"
          sections.each do |section|
            context_info += "Lines #{section[:start_line]}-#{section[:end_line]}:\n"
            context_info += "```\n#{section[:content]}\n```\n\n"
          end
        end
      end

      json_instruction_path = resolve_template_path('diff_json_instruction', config)
      json_instruction = File.read(json_instruction_path).strip

      full_prompt = [
        default_system_prompt,
        user_instructions_section,
        requirements_section,
        analysis_intro,
        "Diff:\n```\n#{diff_output}\n```",
        context_info,
        json_instruction
      ].select { |s| s && !s.empty? }.join("\n\n") # Join non-empty sections with double newlines

      full_prompt
    end

    def analyze_diff(diff_output, config, user_prompt_addition = "", requirements_content = nil)
      prompt = build_diff_analysis_prompt(diff_output, user_prompt_addition, requirements_content, config)
      analysis_json_str = call_llm_for_diff_analysis(prompt, config)

      begin
        # Try to extract JSON from response that might have text before it
        json_content = extract_json_from_response(analysis_json_str)
        analysis_result = JSON.parse(json_content)

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

        puts "\nTest Coverage Assessment:"
        test_coverage = analysis_result['test_coverage']
        puts test_coverage && !test_coverage.to_s.strip.empty? ? test_coverage : "No test coverage assessment provided."

        # Show requirements evaluation if requirements were provided
        requirements_eval = analysis_result['requirements_evaluation']
        if requirements_eval && !requirements_eval.to_s.strip.empty?
          puts "\nRequirements Evaluation:"
          puts requirements_eval
        end

        puts "\nTicket Implementation Summary:"
        impl_summary = analysis_result['ticket_implementation_summary']
        puts impl_summary && !impl_summary.to_s.strip.empty? ? impl_summary : "No implementation summary provided."

        puts "-------------------"
        return analysis_result # Return the parsed hash
      rescue JSON::ParserError => e # Handles cases where the JSON string (even fallback) is malformed
        puts "Critical Error: Failed to parse JSON response for diff analysis: #{e.message}"
        puts "Raw response was: #{analysis_json_str}"
        return {} # Return empty hash on parsing error
      end
    end

    private # Make sure new helper is private

    def format_analysis_for_jira(analysis_result)
      return "No analysis result available." if analysis_result.nil? || analysis_result.empty?

      # Return structured data for ADF formatting
      {
        implementation_summary: analysis_result['ticket_implementation_summary']&.strip,
        technical_summary: analysis_result['summary']&.strip,
        issues: format_issues_for_adf(analysis_result['errors']),
        improvements: format_improvements_for_adf(analysis_result['improvements']),
        test_coverage: analysis_result['test_coverage']&.strip,
        requirements_evaluation: analysis_result['requirements_evaluation']&.strip
      }
    end

    def format_issues_for_adf(errors)
      return [] unless errors.is_a?(Array) && errors.any?
      errors.map(&:strip).reject(&:empty?)
    end

    def format_improvements_for_adf(improvements)
      return [] unless improvements.is_a?(Array) && improvements.any?
      improvements.map(&:strip).reject(&:empty?)
    end

    def format_analysis_for_github(analysis_result)
      return "No analysis result available." if analysis_result.nil? || analysis_result.empty?

      {
        implementation_summary: analysis_result['ticket_implementation_summary']&.strip,
        technical_summary: analysis_result['summary']&.strip,
        issues: format_issues_for_adf(analysis_result['errors']),
        improvements: format_improvements_for_adf(analysis_result['improvements']),
        test_coverage: analysis_result['test_coverage']&.strip,
        requirements_evaluation: analysis_result['requirements_evaluation']&.strip
      }
    end

    def extract_json_from_response(response)
      # First try to parse the response as-is
      begin
        JSON.parse(response)
        return response
      rescue JSON::ParserError
        # If that fails, try to find JSON within the response
      end

      # Look for JSON object starting with { and ending with }
      json_start = response.index('{')
      return response unless json_start

      # Find the matching closing brace
      brace_count = 0
      json_end = nil
      (json_start...response.length).each do |i|
        case response[i]
        when '{'
          brace_count += 1
        when '}'
          brace_count -= 1
          if brace_count == 0
            json_end = i
            break
          end
        end
      end

      return response unless json_end

      response[json_start..json_end]
    end

    def extract_code_context_from_diff(diff_output)
      context_sections = {}
      current_file = nil

      diff_output.each_line do |line|
        line = line.chomp

        # Parse file headers (e.g., "diff --git a/lib/n2b/cli.rb b/lib/n2b/cli.rb")
        if line.start_with?('diff --git')
          # Extract file path from "diff --git a/path b/path"
          match = line.match(/diff --git a\/(.+) b\/(.+)/)
          current_file = match[2] if match # Use the "b/" path (new file)
        elsif line.start_with?('+++')
          # Alternative way to get file path from "+++ b/path"
          match = line.match(/\+\+\+ b\/(.+)/)
          current_file = match[1] if match
        elsif line.start_with?('@@') && current_file
          # Parse hunk header (e.g., "@@ -10,7 +10,8 @@")
          match = line.match(/@@ -(\d+),?\d* \+(\d+),?\d* @@/)
          if match
            _old_start = match[1].to_i
            new_start = match[2].to_i

            # Use the new file line numbers for context
            context_start = [new_start - 5, 1].max  # 5 lines before, but not less than 1
            context_end = new_start + 10  # 10 lines after the start

            # Read the actual file content
            if File.exist?(current_file)
              file_lines = File.readlines(current_file)
              # Adjust end to not exceed file length
              context_end = [context_end, file_lines.length].min

              if context_start <= file_lines.length
                context_content = file_lines[(context_start-1)...context_end].map.with_index do |content, idx|
                  line_num = context_start + idx
                  "#{line_num.to_s.rjust(4)}: #{content.rstrip}"
                end.join("\n")

                context_sections[current_file] ||= []
                context_sections[current_file] << {
                  start_line: context_start,
                  end_line: context_end,
                  content: context_content
                }
              end
            end
          end
        end
      end

      context_sections
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
    
           
      puts "🤖 AI is generating commands..."
      response = make_request_with_spinner(llm, content)

      # Handle both Hash (from JSON mode providers) and String responses
      if response.is_a?(Hash)
        # Already parsed by the LLM provider
        parsed_response = response
        response_str = response.to_json # For history logging
      else
        # String response that needs parsing
        response_str = response
        begin
          parsed_response = JSON.parse(response_str)
        rescue JSON::ParserError => e
          puts "⚠️  Invalid JSON detected, attempting automatic repair..."
          repaired_response = attempt_json_repair_for_commands(response_str, llm)

          if repaired_response
            puts "✅ JSON repair successful!"
            parsed_response = repaired_response
          else
            puts "❌ JSON repair failed"
            puts "Error parsing LLM response JSON for command generation: #{e.message}"
            # This is a fallback for when the LLM response *content* is not valid JSON.
            parsed_response = { "commands" => ["echo 'Error: LLM returned invalid JSON content.'"], "explanation" => "The response from the language model was not valid JSON." }
          end
        end
      end

      append_to_llm_history_file("#{prompt}\n#{response_str}") # Storing the response for history
      parsed_response
      rescue N2B::LlmApiError => e
        puts "Error communicating with the LLM: #{e.message}"

        # Check if it might be a model-related error
        if e.message.include?('model') || e.message.include?('Model') || e.message.include?('invalid') || e.message.include?('not found')
          puts "\nThis might be due to an invalid or unsupported model configuration."
          puts "Run 'n2b -c' to reconfigure your model settings."
        end

        # This is the fallback for LlmApiError (network, auth, etc.)
        { "commands" => ["echo 'LLM API error occurred. Please check your configuration and network.'"], "explanation" => "Failed to connect to the LLM." }
      end
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

    def resolve_template_path(template_key, config)
      user_path = config.dig('templates', template_key) if config.is_a?(Hash)
      return user_path if user_path && File.exist?(user_path)

      File.expand_path(File.join(__dir__, 'templates', "#{template_key}.txt"))
    end

    def make_request_with_spinner(llm, content)
      spinner_chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
      spinner_thread = Thread.new do
        i = 0
        while true
          print "\r⠿ #{spinner_chars[i % spinner_chars.length]} Processing..."
          $stdout.flush
          sleep(0.1)
          i += 1
        end
      end

      begin
        result = llm.make_request(content)
        spinner_thread.kill
        print "\r#{' ' * 25}\r"  # Clear the spinner line
        puts "✅ Commands generated!"
        result
      rescue => e
        spinner_thread.kill
        print "\r#{' ' * 25}\r"  # Clear the spinner line
        raise e
      end
    end

    def attempt_json_repair_for_commands(malformed_response, llm)
      repair_prompt = <<~PROMPT
        The following response was supposed to be valid JSON with keys "commands" (array) and "explanation" (string), but it has formatting issues. Please fix it and return ONLY the corrected JSON:

        Original response:
        #{malformed_response}

        Requirements:
        - Must be valid JSON
        - Must have "commands" key with array of command strings
        - Must have "explanation" key with explanation text
        - Return ONLY the JSON, no other text

        Fixed JSON:
      PROMPT

      begin
        puts "🔧 Asking AI to fix the JSON..."
        repaired_json_str = llm.make_request(repair_prompt)

        # Handle both Hash and String responses
        if repaired_json_str.is_a?(Hash)
          repaired_response = repaired_json_str
        else
          repaired_response = JSON.parse(repaired_json_str)
        end

        # Validate the repaired response structure
        if repaired_response.is_a?(Hash) && repaired_response.key?('commands') && repaired_response.key?('explanation')
          return repaired_response
        else
          return nil
        end
      rescue JSON::ParserError, StandardError
        return nil
      end
    end


    def parse_options
      options = {
        execute: false,
        config: nil,
        # diff: false, # Removed
        # requirements: nil, # Removed
        # branch: nil, # Removed
        # jira_ticket: nil, # Removed
        # jira_update: nil, # Removed
        advanced_config: false
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: n2b [options] [natural language command]"

        opts.on('-x', '--execute', 'Execute the translated commands after confirmation.') do
          options[:execute] = true
        end

        # Removed options: -d, --diff, -b, --branch, -r, --requirements, -j, --jira, --jira-update, --jira-no-update

        opts.on('-c', '--config', 'Configure N2B (API key, model, privacy settings, etc.).') do
          options[:config] = true
        end

        opts.on('--advanced-config', 'Access advanced configuration options.') do
          options[:advanced_config] = true
          options[:config] = true # --advanced-config implies -c
        end

        opts.on_tail('-h', '--help', 'Show this help message.') do
          puts opts
          exit
        end

        opts.on_tail('-v', '--version', 'Show version.') do
          puts "n2b version #{N2B::VERSION}" # Assuming N2B::VERSION is defined
          exit
        end
      end

      begin
        parser.parse!(@args)
      rescue OptionParser::InvalidOption => e
        puts "Error: #{e.message}"
        puts ""
        puts parser.help
        exit 1
      rescue OptionParser::MissingArgument => e
        puts "Error: #{e.message}"
        puts ""
        puts parser.help
        exit 1
      end

      # Removed validation logic for diff/jira related options

      options
    end
  end
end