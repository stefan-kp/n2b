require_relative 'model_config'

module N2B
  class Base

    def self.config_file
      # Bulletproof test environment detection
      if test_environment?
        File.expand_path('~/.n2b_test/config.yml')
      else
        ENV['N2B_CONFIG_FILE'] || File.expand_path('~/.n2b/config.yml')
      end
    end

    def self.history_file
      if test_environment?
        File.expand_path('~/.n2b_test/history')
      else
        ENV['N2B_HISTORY_FILE'] || File.expand_path('~/.n2b/history')
      end
    end

    def self.test_environment?
      # Multiple ways to detect test environment for maximum safety
      ENV['RAILS_ENV'] == 'test' ||
      ENV['RACK_ENV'] == 'test' ||
      ENV['N2B_TEST_MODE'] == 'true' ||
      $PROGRAM_NAME.include?('rake') ||
      $PROGRAM_NAME.include?('test') ||
      caller.any? { |line| line.include?('test/') || line.include?('minitest') || line.include?('rake') }
    end

    def load_config
      if File.exist?(self.class.config_file)
        YAML.load_file(self.class.config_file)
      else
        { }
      end
    end
    
    def get_config(reconfigure: false, advanced_flow: false)
      config = load_config
      api_key = ENV['CLAUDE_API_KEY'] || config['access_key'] # This will be used as default or for existing configs
      _model = config['model'] # Unused but kept for potential future use # Model will be handled per LLM

      # Determine if it's effectively a first-time setup for core LLM details
      is_first_time_core_setup = config['llm'].nil?

      if api_key.nil? || api_key == '' || config['llm'].nil? || reconfigure
        puts "--- N2B Core LLM Configuration ---"
        print "Choose a language model to use (1:claude, 2:openai, 3:gemini, 4:openrouter, 5:ollama) [current: #{config['llm']}]: "
        llm_choice = $stdin.gets.chomp
        llm_choice = config['llm'] if llm_choice.empty? && !config['llm'].nil? # Keep current if input is empty

        unless ['claude', 'openai', 'gemini', 'openrouter', 'ollama', '1', '2', '3', '4', '5'].include?(llm_choice)
          puts "Invalid language model selection. Defaulting to 'claude' or previous if available."
          llm_choice = config['llm'] || 'claude' # Fallback
        end

        selected_llm = case llm_choice
                       when '1', 'claude' then 'claude'
                       when '2', 'openai' then 'openai'
                       when '3', 'gemini' then 'gemini'
                       when '4', 'openrouter' then 'openrouter'
                       when '5', 'ollama' then 'ollama'
                       else config['llm'] || 'claude' # Should not happen due to validation
                       end
        config['llm'] = selected_llm

        if selected_llm == 'ollama'
          puts "\n--- Ollama Specific Configuration ---"
          puts "Ollama typically runs locally and doesn't require an API key."

          # Use new model configuration system
          current_model = config['model']
          model_choice = N2B::ModelConfig.get_model_choice(selected_llm, current_model)
          config['model'] = model_choice

          current_ollama_api_url = config['ollama_api_url'] || N2M::Llm::Ollama::DEFAULT_OLLAMA_API_URI
          print "Enter Ollama API base URL [current: #{current_ollama_api_url}]: "
          ollama_api_url_input = $stdin.gets.chomp
          config['ollama_api_url'] = ollama_api_url_input.empty? ? current_ollama_api_url : ollama_api_url_input

          config.delete('access_key') # Remove access_key if switching to ollama
          config.delete('gemini_credential_file') # Also remove gemini specific if switching to ollama

        elsif selected_llm == 'gemini'
          puts "\n--- Gemini (Vertex AI) Specific Configuration ---"
          # Prompt for credential file path
          current_gemini_credential_file = config['gemini_credential_file']
          print "Enter your Google Cloud credential file path for Gemini/Vertex AI #{current_gemini_credential_file ? '[leave blank to keep current]' : ''}: "
          gemini_credential_file_input = $stdin.gets.chomp
          if !gemini_credential_file_input.empty?
            config['gemini_credential_file'] = gemini_credential_file_input
          elsif current_gemini_credential_file
            config['gemini_credential_file'] = current_gemini_credential_file
          else
            config['gemini_credential_file'] = nil # Explicitly set to nil if no input and no current
          end
          config.delete('access_key') # Remove access_key if switching to gemini
          config.delete('ollama_api_url') # Remove ollama specific if switching to gemini

          # Model configuration for Gemini (similar to other providers)
          current_model = config['model']
          model_choice = N2B::ModelConfig.get_model_choice(selected_llm, current_model)
          config['model'] = model_choice
        else
          # Configuration for other API key based LLMs (OpenAI, Claude, OpenRouter)
          puts "\n--- #{selected_llm.capitalize} Specific Configuration ---"
          current_api_key = config['access_key']
          print "Enter your #{selected_llm} API key #{ current_api_key.nil? || current_api_key.empty? ? '' : '[leave blank to keep current]' }: "
          api_key_input = $stdin.gets.chomp
          config['access_key'] = api_key_input if !api_key_input.empty?
          config['access_key'] = current_api_key if api_key_input.empty? && !current_api_key.nil? && !current_api_key.empty?

          if config['access_key'].nil? || config['access_key'].empty?
            puts "API key is required for #{selected_llm}."
            exit 1
          end

          # Ensure other provider-specific keys are removed
          config.delete('gemini_credential_file')
          config.delete('ollama_api_url')

          current_model = config['model']
          model_choice = N2B::ModelConfig.get_model_choice(selected_llm, current_model)
          config['model'] = model_choice

          if selected_llm == 'openrouter'
            current_site_url = config['openrouter_site_url'] || ""
            print "Enter your OpenRouter Site URL (optional, for HTTP-Referer) [current: #{current_site_url}]: "
            openrouter_site_url_input = $stdin.gets.chomp
            config['openrouter_site_url'] = openrouter_site_url_input.empty? ? current_site_url : openrouter_site_url_input

            current_site_name = config['openrouter_site_name'] || ""
            print "Enter your OpenRouter Site Name (optional, for X-Title) [current: #{current_site_name}]: "
            openrouter_site_name_input = $stdin.gets.chomp
            config['openrouter_site_name'] = openrouter_site_name_input.empty? ? current_site_name : openrouter_site_name_input
          end
        end

        # --- Advanced Configuration Flow ---
        # Prompt for advanced settings if advanced_flow is true or if it's the first time setting up core LLM.
        prompt_for_advanced = advanced_flow || is_first_time_core_setup

        if prompt_for_advanced
          puts "\n--- Advanced Settings ---"
          print "Would you like to configure advanced settings (e.g., Jira or GitHub integration, privacy)? (y/n) [default: n]: "
          choice = $stdin.gets.chomp.downcase

          if choice == 'y'
            current_tracker = config['issue_tracker'] || 'none'
            print "\nSelect issue tracker to integrate (none, jira, github) [current: #{current_tracker}]: "
            tracker_choice = $stdin.gets.chomp.downcase
            tracker_choice = current_tracker if tracker_choice.empty?
            config['issue_tracker'] = tracker_choice

            case tracker_choice
            when 'jira'
              puts "\n--- Jira Integration ---"
              puts "You can generate a Jira API token here: https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/"
              config['jira'] ||= {}
              print "Jira Domain (e.g., your-company.atlassian.net) [current: #{config['jira']['domain']}]: "
              config['jira']['domain'] = $stdin.gets.chomp.then { |val| val.empty? ? config['jira']['domain'] : val }

              print "Jira Email Address [current: #{config['jira']['email']}]: "
              config['jira']['email'] = $stdin.gets.chomp.then { |val| val.empty? ? config['jira']['email'] : val }

              print "Jira API Token #{config['jira']['api_key'] ? '[leave blank to keep current]' : ''}: "
              api_token_input = $stdin.gets.chomp
              config['jira']['api_key'] = api_token_input if !api_token_input.empty?

              print "Default Jira Project Key (optional, e.g., MYPROJ) [current: #{config['jira']['default_project']}]: "
              config['jira']['default_project'] = $stdin.gets.chomp.then { |val| val.empty? ? config['jira']['default_project'] : val }
            when 'github'
              puts "\n--- GitHub Integration ---"
              config['github'] ||= {}
              print "GitHub Repository (owner/repo) [current: #{config['github']['repo']}]: "
              config['github']['repo'] = $stdin.gets.chomp.then { |val| val.empty? ? config['github']['repo'] : val }

              print "GitHub Access Token #{config['github']['access_token'] ? '[leave blank to keep current]' : ''}: "
              token_input = $stdin.gets.chomp
              config['github']['access_token'] = token_input if !token_input.empty?
            else
              config['jira'] ||= {}
              config['github'] ||= {}
            end

            # Privacy Settings
            puts "\n--- Privacy Settings ---"
            config['privacy'] ||= {}
            puts "Allow sending shell command history to the LLM? (true/false) [current: #{config['privacy']['send_shell_history']}]"
            config['privacy']['send_shell_history'] = $stdin.gets.chomp.then { |val| val.empty? ? config['privacy']['send_shell_history'] : (val.downcase == 'true') }

            puts "Allow sending LLM interaction history (your prompts and LLM responses) to the LLM? (true/false) [current: #{config['privacy']['send_llm_history']}]"
            config['privacy']['send_llm_history'] = $stdin.gets.chomp.then { |val| val.empty? ? config['privacy']['send_llm_history'] : (val.downcase == 'true') }

            puts "Allow sending current directory to the LLM? (true/false) [current: #{config['privacy']['send_current_directory']}]"
            config['privacy']['send_current_directory'] = $stdin.gets.chomp.then { |val| val.empty? ? config['privacy']['send_current_directory'] : (val.downcase == 'true') }

            puts "Append n2b generated commands to your shell history file? (true/false) [current: #{config['append_to_shell_history']}]"
            # Note: append_to_shell_history was previously outside 'privacy' hash. Standardizing it inside.
            config['append_to_shell_history'] = $stdin.gets.chomp.then { |val| val.empty? ? config['append_to_shell_history'] : (val.downcase == 'true') }
            config['privacy']['append_to_shell_history'] = config['append_to_shell_history'] # Also place under privacy for consistency

            # Editor Configuration
            prompt_for_editor_config(config)

          else # User chose 'n' for advanced settings
            config['jira'] ||= {}
            config['github'] ||= {}
            config['issue_tracker'] ||= 'none'
            # If they opt out, we don't clear existing, just don't prompt.
            # If it's a fresh setup and they opt out, these will remain empty/nil.

            # Ensure privacy settings are initialized to defaults if not already set by advanced flow
            config['privacy'] ||= {}
            config['privacy']['send_shell_history'] = config['privacy']['send_shell_history'] || false
            config['privacy']['send_llm_history'] = config['privacy']['send_llm_history'] || true # Default true
            config['privacy']['send_current_directory'] = config['privacy']['send_current_directory'] || true # Default true
            config['append_to_shell_history'] = config['append_to_shell_history'] || false
            config['privacy']['append_to_shell_history'] = config['append_to_shell_history']
          end
        else # Not prompting for advanced (neither advanced_flow nor first_time_core_setup)
          # Ensure defaults for privacy if they don't exist from a previous config
          config['jira'] ||= {}
          config['github'] ||= {}
          config['issue_tracker'] ||= 'none'
          config['privacy'] ||= {}
          config['privacy']['send_shell_history'] = config['privacy']['send_shell_history'] || false
          config['privacy']['send_llm_history'] = config['privacy']['send_llm_history'] || true
          config['privacy']['send_current_directory'] = config['privacy']['send_current_directory'] || true
          config['append_to_shell_history'] = config['append_to_shell_history'] || false
          config['privacy']['append_to_shell_history'] = config['append_to_shell_history']
        end

        # Editor Configuration
        config['editor'] ||= {}
        config['editor']['command'] ||= nil # or 'nano', 'vi'
        config['editor']['type'] ||= nil # 'text_editor' or 'diff_tool'
        config['editor']['configured'] ||= false

        # Validate configuration before saving
        validation_errors = validate_config(config)
        if validation_errors.any?
          puts "\n⚠️  Configuration validation warnings:"
          validation_errors.each { |error| puts "  - #{error}" }
          puts "Configuration saved with warnings."
        end

        puts "\nConfiguration saved to #{self.class.config_file}"
        FileUtils.mkdir_p(File.dirname(self.class.config_file)) unless File.exist?(File.dirname(self.class.config_file))
        File.write(self.class.config_file, config.to_yaml)
      else
        # If not reconfiguring, still ensure privacy and jira keys exist with defaults if missing
        # This handles configs from before these settings were introduced
        config['jira'] ||= {}
        config['github'] ||= {}
        config['issue_tracker'] ||= 'none'
        config['privacy'] ||= {}
        config['privacy']['send_shell_history'] = config['privacy']['send_shell_history'] || false
        config['privacy']['send_llm_history'] = config['privacy']['send_llm_history'] || true
        config['privacy']['send_current_directory'] = config['privacy']['send_current_directory'] || true
        # append_to_shell_history was outside 'privacy' before, ensure it's correctly defaulted
        # and also placed under 'privacy' for future consistency.
        current_append_setting = config.key?('append_to_shell_history') ? config['append_to_shell_history'] : false
        config['append_to_shell_history'] = current_append_setting
        config['privacy']['append_to_shell_history'] = config['privacy']['append_to_shell_history'] || current_append_setting

        # Ensure editor config is initialized if missing (for older configs)
        config['editor'] ||= {}
        config['editor']['command'] ||= nil
        config['editor']['type'] ||= nil
        config['editor']['configured'] ||= false
      end
      config
    end

    private

    def command_exists?(command)
      # Check for Windows or Unix-like systems for the correct command
      null_device = RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/ ? 'NUL' : '/dev/null'
      system("which #{command} > #{null_device} 2>&1") || system("where #{command} > #{null_device} 2>&1")
    end

    def prompt_for_editor_config(config)
      puts "\n--- Editor Configuration ---"
      current_editor_command = config.dig('editor', 'command')
      current_editor_type = config.dig('editor', 'type')
      current_status = if current_editor_command
                         "Current: #{current_editor_command} (#{current_editor_type || 'not set'})"
                       else
                         "Current: Not configured"
                       end
      puts current_status

      known_editors = [
        { name: 'nano', command: 'nano', description: 'Simple terminal editor', type: 'text_editor' },
        { name: 'vim', command: 'vim', description: 'Powerful terminal editor', type: 'text_editor' },
        { name: 'vi', command: 'vi', description: 'Standard Unix terminal editor', type: 'text_editor' },
        { name: 'code', command: 'code', description: 'Visual Studio Code (requires "code" in PATH)', type: 'text_editor' },
        { name: 'subl', command: 'subl', description: 'Sublime Text (requires "subl" in PATH)', type: 'text_editor' },
        { name: 'meld', command: 'meld', description: 'Visual diff and merge tool', type: 'diff_tool' },
        { name: 'kdiff3', command: 'kdiff3', description: 'Visual diff and merge tool (KDE)', type: 'diff_tool' },
        { name: 'opendiff', command: 'opendiff', description: 'File comparison tool (macOS)', type: 'diff_tool' },
        { name: 'vimdiff', command: 'vimdiff', description: 'Diff tool using Vim', type: 'diff_tool' }
      ]

      available_editors = known_editors.select { |editor| command_exists?(editor[:command]) }

      if available_editors.empty?
        puts "No standard editors detected automatically."
      else
        puts "Choose your preferred editor/diff tool:"
        available_editors.each_with_index do |editor, index|
          puts "#{index + 1}. #{editor[:name]} (#{editor[:description]})"
        end
        puts "#{available_editors.length + 1}. Custom (enter your own command)"
        print "Enter choice (1-#{available_editors.length + 1}) or leave blank to skip: "
      end

      choice_input = $stdin.gets.chomp
      return if choice_input.empty? && current_editor_command # Skip if already configured and user wants to skip

      choice = choice_input.to_i

      selected_editor = nil
      custom_command = nil

      if choice > 0 && choice <= available_editors.length
        selected_editor = available_editors[choice - 1]
        config['editor']['command'] = selected_editor[:command]
        config['editor']['type'] = selected_editor[:type]
        config['editor']['configured'] = true
        puts "✓ Using #{selected_editor[:name]} as your editor/diff tool."
      elsif choice == available_editors.length + 1 || (available_editors.empty? && !choice_input.empty?)
        print "Enter custom editor command: "
        custom_command = $stdin.gets.chomp
        if custom_command.empty?
          puts "No command entered. Editor configuration skipped."
          return
        end

        print "Is this a 'text_editor' or a 'diff_tool'? (text_editor/diff_tool): "
        custom_type = $stdin.gets.chomp.downcase
        unless ['text_editor', 'diff_tool'].include?(custom_type)
          puts "Invalid type. Defaulting to 'text_editor'."
          custom_type = 'text_editor'
        end
        config['editor']['command'] = custom_command
        config['editor']['type'] = custom_type
        config['editor']['configured'] = true
        puts "✓ Using custom command '#{custom_command}' (#{custom_type}) as your editor/diff tool."
      else
        puts "Invalid choice. Editor configuration skipped."
        # Keep existing config if invalid choice, or clear if they wanted to change but failed?
        # For now, just skipping and keeping whatever was there.
        return
      end
    end

    def validate_config(config)
      errors = []

      # Validate LLM configuration
      if config['llm'].nil? || config['llm'].empty?
        errors << "LLM provider not specified"
      end

      # Validate model name
      if config['model'].nil? || config['model'].empty?
        errors << "Model not specified"
      elsif config['model'].length < 3
        errors << "Model name '#{config['model']}' seems too short - might be invalid"
      elsif %w[y n yes no true false].include?(config['model'].downcase)
        errors << "Model name '#{config['model']}' appears to be a boolean response rather than a model name"
      end

      # Validate API key for non-Ollama providers
      if config['llm'] != 'ollama' && config['llm'] != 'gemini' && (config['access_key'].nil? || config['access_key'].empty?)
        errors << "API key missing for #{config['llm']} provider"
      end

      # ADD GEMINI SPECIFIC VALIDATION HERE
      if config['llm'] == 'gemini'
        if config['gemini_credential_file'].nil? || config['gemini_credential_file'].empty?
          errors << "Credential file path for Gemini not provided"
        else
          unless File.exist?(config['gemini_credential_file'])
            errors << "Credential file missing or invalid at #{config['gemini_credential_file']}"
          end
        end
        if config['access_key'] && !config['access_key'].empty?
          errors << "API key (access_key) should not be present when Gemini provider is selected"
        end
      end

      # Validate editor configuration (optional, so more like warnings or info)
      # Example: Check if command is set if configured is true
      # if config['editor'] && config['editor']['configured'] && (config['editor']['command'].nil? || config['editor']['command'].empty?)
      #   errors << "Editor is marked as configured, but no command is set."
      # end

      tracker = config['issue_tracker'] || 'none'
      case tracker
      when 'jira'
        if config['jira'] && !config['jira'].empty?
          jira_config = config['jira']
          if jira_config['domain'] && !jira_config['domain'].empty?
            if jira_config['email'].nil? || jira_config['email'].empty?
              errors << "Jira email missing when domain is configured"
            end
            if jira_config['api_key'].nil? || jira_config['api_key'].empty?
              errors << "Jira API key missing when domain is configured"
            end
          else
            errors << "Jira domain missing when issue_tracker is set to 'jira'"
          end
        else
          errors << "Jira configuration missing when issue_tracker is set to 'jira'"
        end
      when 'github'
        if config['github'] && !config['github'].empty?
          gh = config['github']
          errors << "GitHub repository missing when issue_tracker is set to 'github'" if gh['repo'].nil? || gh['repo'].empty?
          errors << "GitHub access token missing when issue_tracker is set to 'github'" if gh['access_token'].nil? || gh['access_token'].empty?
        else
          errors << "GitHub configuration missing when issue_tracker is set to 'github'"
        end
      when 'none'
        # No validation needed for 'none' tracker
      else
        errors << "Invalid issue_tracker '#{tracker}' - must be 'jira', 'github', or 'none'"
      end

      errors
    end
  end
end