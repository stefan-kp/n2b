require_relative 'jira_client' # For N2B::JiraClient

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

      if @options[:diff]
        handle_diff_analysis(config)
      elsif user_input.empty? # No input text after options
        puts "Enter your natural language command:"
        input_text = $stdin.gets.chomp
        process_natural_language_command(input_text, config)
      else # Natural language command
        process_natural_language_command(user_input, config)
      end
    end

    protected

    def handle_diff_analysis(config)
      vcs_type = get_vcs_type
      if vcs_type == :none
        puts "Error: Not a git or hg repository."
        exit 1
      end

      # Get requirements file from parsed options
      requirements_filepath = @options[:requirements]
      user_prompt_addition = @args.join(' ') # All remaining args are user prompt addition

      # Jira Ticket Information
      jira_ticket = @options[:jira_ticket]
      jira_update_flag = @options[:jira_update] # true, false, or nil

      requirements_content = nil # Initialize requirements_content

      if jira_ticket
        puts "Jira ticket specified: #{jira_ticket}"
        if config['jira'] && config['jira']['domain'] && config['jira']['email'] && config['jira']['api_key']
          begin
            jira_client = N2B::JiraClient.new(config) # Pass the whole config
            puts "Fetching Jira ticket details..."
            # If a requirements file is also provided, the Jira ticket will take precedence.
            # Or, we could append/prepend. For now, Jira overwrites.
            requirements_content = jira_client.fetch_ticket(jira_ticket)
            puts "Successfully fetched Jira ticket details."
            # The fetched content is now in requirements_content and will be passed to analyze_diff
          rescue N2B::JiraClient::JiraApiError => e
            puts "Error fetching Jira ticket: #{e.message}"
            puts "Proceeding with diff analysis without Jira ticket details."
          rescue ArgumentError => e # Catches missing Jira config in JiraClient.new
            puts "Jira configuration error: #{e.message}"
            puts "Please ensure Jira is configured correctly using 'n2b -c'."
            puts "Proceeding with diff analysis without Jira ticket details."
          rescue StandardError => e
            puts "An unexpected error occurred while fetching Jira ticket: #{e.message}"
            puts "Proceeding with diff analysis without Jira ticket details."
          end
        else
          puts "Jira configuration is missing or incomplete in N2B settings."
          puts "Please configure Jira using 'n2b -c' to fetch ticket details."
          puts "Proceeding with diff analysis without Jira ticket details."
        end
        # Handling of jira_update_flag can be done elsewhere, e.g., after analysis
        if jira_update_flag == true
          puts "Note: Jira ticket update (--jira-update) is flagged."
          # Actual update logic will be separate
        elsif jira_update_flag == false
          puts "Note: Jira ticket will not be updated (--jira-no-update)."
        end
      end

      # Load requirements from file if no Jira ticket was fetched or if specifically desired even with Jira.
      # Current logic: Jira fetch, if successful, populates requirements_content.
      # If Jira not specified, or fetch failed, try to load from file.
      if requirements_content.nil? && requirements_filepath
        if File.exist?(requirements_filepath)
          puts "Loading requirements from file: #{requirements_filepath}"
          requirements_content = File.read(requirements_filepath)
        else
          puts "Error: Requirements file not found: #{requirements_filepath}"
          # Decide if to exit or proceed. For now, proceed.
          puts "Proceeding with diff analysis without file-based requirements."
        end
      elsif requirements_content && requirements_filepath
        puts "Note: Both Jira ticket and requirements file were provided. Using Jira ticket content for analysis."
      end

      diff_output = execute_vcs_diff(vcs_type, @options[:branch])
      analysis_result = analyze_diff(diff_output, config, user_prompt_addition, requirements_content) # Store the result

      # --- Jira Update Logic ---
      if jira_ticket && analysis_result && !analysis_result.empty?
        # Check if Jira config is valid for updating
        if config['jira'] && config['jira']['domain'] && config['jira']['email'] && config['jira']['api_key']
          jira_comment_data = format_analysis_for_jira(analysis_result)
          proceed_with_update = false

          if jira_update_flag == true # --jira-update used
            proceed_with_update = true
          elsif jira_update_flag.nil? # Neither --jira-update nor --jira-no-update used
            puts "\nWould you like to update Jira ticket #{jira_ticket} with this analysis? (y/n)"
            user_choice = $stdin.gets.chomp.downcase
            proceed_with_update = user_choice == 'y'
          end # If jira_update_flag is false, proceed_with_update remains false

          if proceed_with_update
            begin
              # Re-instantiate JiraClient or use an existing one if available and in scope
              # For safety and simplicity here, re-instantiate with current config.
              update_jira_client = N2B::JiraClient.new(config)
              puts "Updating Jira ticket #{jira_ticket}..."
              if update_jira_client.update_ticket(jira_ticket, jira_comment_data)
                puts "Jira ticket #{jira_ticket} updated successfully."
              else
                # update_ticket currently returns true/false, but might raise error for http issues
                puts "Failed to update Jira ticket #{jira_ticket}. The client did not report an error, but the update may not have completed."
              end
            rescue N2B::JiraClient::JiraApiError => e
              puts "Error updating Jira ticket: #{e.message}"
            rescue ArgumentError => e # From JiraClient.new if config is suddenly invalid
              puts "Jira configuration error before update: #{e.message}"
            rescue StandardError => e
              puts "An unexpected error occurred while updating Jira ticket: #{e.message}"
            end
          else
            puts "Jira ticket update skipped."
          end
        else
          puts "Jira configuration is missing or incomplete. Cannot proceed with Jira update."
        end
      elsif jira_ticket && (analysis_result.nil? || analysis_result.empty?)
        puts "Skipping Jira update as analysis result was empty or not generated."
      end
      # --- End of Jira Update Logic ---

      analysis_result # Return analysis_result from handle_diff_analysis
    end

    def get_vcs_type
      if Dir.exist?(File.join(Dir.pwd, '.git'))
        :git
      elsif Dir.exist?(File.join(Dir.pwd, '.hg'))
        :hg
      else
        :none
      end
    end

    def execute_vcs_diff(vcs_type, branch_option = nil)
      case vcs_type
      when :git
        if branch_option
          target_branch = branch_option == 'auto' ? detect_git_default_branch : branch_option
          if target_branch
            # Validate that the target branch exists
            unless validate_git_branch_exists(target_branch)
              puts "Error: Branch '#{target_branch}' does not exist."
              puts "Available branches:"
              puts `git branch -a`.lines.map(&:strip).reject(&:empty?)
              exit 1
            end

            puts "Comparing current branch against '#{target_branch}'..."
            `git diff #{target_branch}...HEAD`
          else
            puts "Could not detect default branch, falling back to HEAD diff..."
            `git diff HEAD`
          end
        else
          `git diff HEAD`
        end
      when :hg
        if branch_option
          target_branch = branch_option == 'auto' ? detect_hg_default_branch : branch_option
          if target_branch
            # Validate that the target branch exists
            unless validate_hg_branch_exists(target_branch)
              puts "Error: Branch '#{target_branch}' does not exist."
              puts "Available branches:"
              puts `hg branches`.lines.map(&:strip).reject(&:empty?)
              exit 1
            end

            puts "Comparing current branch against '#{target_branch}'..."
            `hg diff -r #{target_branch}`
          else
            puts "Could not detect default branch, falling back to standard diff..."
            `hg diff`
          end
        else
          `hg diff`
        end
      else
        "" # Should not happen if get_vcs_type logic is correct and checked before calling
      end
    end

    def detect_git_default_branch
      # Try multiple methods to detect the default branch

      # Method 1: Check origin/HEAD symbolic ref
      result = `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null`.strip
      if $?.success? && !result.empty?
        return result.split('/').last
      end

      # Method 2: Check remote show origin
      result = `git remote show origin 2>/dev/null | grep "HEAD branch"`.strip
      if $?.success? && !result.empty?
        match = result.match(/HEAD branch:\s*(\w+)/)
        return match[1] if match
      end

      # Method 3: Check if common default branches exist
      ['main', 'master'].each do |branch|
        result = `git rev-parse --verify origin/#{branch} 2>/dev/null`
        if $?.success?
          return branch
        end
      end

      # Method 4: Fallback - check local branches
      ['main', 'master'].each do |branch|
        result = `git rev-parse --verify #{branch} 2>/dev/null`
        if $?.success?
          return branch
        end
      end

      # If all else fails, return nil
      nil
    end

    def detect_hg_default_branch
      # Method 1: Check current branch (if it's 'default', that's the main branch)
      result = `hg branch 2>/dev/null`.strip
      if $?.success? && result == 'default'
        return 'default'
      end

      # Method 2: Look for 'default' branch in branch list
      result = `hg branches 2>/dev/null`
      if $?.success? && result.include?('default')
        return 'default'
      end

      # Method 3: Check if there are any branches at all
      result = `hg branches 2>/dev/null`.strip
      if $?.success? && !result.empty?
        # Get the first branch (usually the main one)
        first_branch = result.lines.first&.split&.first
        return first_branch if first_branch
      end

      # Fallback to 'default' (standard hg main branch name)
      'default'
    end

    def validate_git_branch_exists(branch)
      # Check if branch exists locally
      _result = `git rev-parse --verify #{branch} 2>/dev/null`
      return true if $?.success?

      # Check if branch exists on remote
      _result = `git rev-parse --verify origin/#{branch} 2>/dev/null`
      return true if $?.success?

      false
    end

    def validate_hg_branch_exists(branch)
      # Check if branch exists in hg branches
      result = `hg branches 2>/dev/null`
      if $?.success?
        return result.lines.any? { |line| line.strip.start_with?(branch) }
      end

      # If we can't list branches, assume it exists (hg is more permissive)
      true
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

        # Check if it might be a model-related error
        if e.message.include?('model') || e.message.include?('Model') || e.message.include?('invalid') || e.message.include?('not found')
          puts "\nThis might be due to an invalid or unsupported model configuration."
          puts "Run 'n2b -c' to reconfigure your model settings."
        end

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
    
           
      response = llm.make_request(content)

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
          puts "Error parsing LLM response JSON for command generation: #{e.message}"
          # This is a fallback for when the LLM response *content* is not valid JSON.
          parsed_response = { "commands" => ["echo 'Error: LLM returned invalid JSON content.'"], "explanation" => "The response from the language model was not valid JSON." }
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
    

    def parse_options
      options = {
        execute: false,
        config: nil,
        diff: false,
        requirements: nil,
        branch: nil,
        jira_ticket: nil,
        jira_update: nil, # Using nil as default, true for --jira-update, false for --jira-no-update
        advanced_config: false # New option for advanced configuration flow
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: n2b [options] [natural language command]"

        opts.on('-x', '--execute', 'Execute the commands after confirmation') do
          options[:execute] = true
        end

        opts.on('-d', '--diff', 'Analyze git/hg diff with AI') do
          options[:diff] = true
        end

        opts.on('-b', '--branch [BRANCH]', 'Compare against branch (default: auto-detect main/master)') do |branch|
          options[:branch] = branch || 'auto'
        end

        opts.on('-r', '--requirements FILE', 'Requirements file for diff analysis') do |file|
          options[:requirements] = file
        end

        opts.on('-j', '--jira JIRA_ID_OR_URL', 'Jira ticket ID or URL for context or update') do |jira|
          options[:jira_ticket] = jira
        end

        opts.on('--jira-update', 'Update the linked Jira ticket (requires -j)') do
          options[:jira_update] = true
        end

        opts.on('--jira-no-update', 'Do not update the linked Jira ticket (requires -j)') do
          options[:jira_update] = false
        end

        opts.on('-h', '--help', 'Print this help') do
          puts opts
          exit
        end

        opts.on('-v', '--version', 'Show version') do
          puts "n2b version #{N2B::VERSION}"
          exit
        end

        opts.on('-c', '--config', 'Configure the API key and model') do
          options[:config] = true
        end

        opts.on('--advanced-config', 'Access advanced configuration options including Jira and privacy settings') do
          options[:advanced_config] = true
          options[:config] = true # Forcing config mode if advanced is chosen
        end
      end

      begin
        parser.parse!(@args)
      rescue OptionParser::InvalidOption => e
        puts "Error: #{e.message}"
        puts ""
        puts parser.help
        exit 1
      end

      # Validate option combinations
      if options[:branch] && !options[:diff]
        puts "Error: --branch option can only be used with --diff"
        puts ""
        puts parser.help
        exit 1
      end

      if options[:jira_update] == true && options[:jira_ticket].nil?
        puts "Error: --jira-update option requires a Jira ticket to be specified with -j or --jira."
        puts ""
        puts parser.help
        exit 1
      end

      if options[:jira_update] == false && options[:jira_ticket].nil?
        puts "Error: --jira-no-update option requires a Jira ticket to be specified with -j or --jira."
        puts ""
        puts parser.help
        exit 1
      end

      if options[:jira_update] == true && options[:jira_update] == false
        puts "Error: --jira-update and --jira-no-update are mutually exclusive."
        puts ""
        puts parser.help
        exit 1
      end

      options
    end
  end
end