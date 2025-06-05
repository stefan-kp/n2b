require_relative 'model_config'

module N2B
  class Base

    CONFIG_FILE = ENV['N2B_CONFIG_FILE'] || File.expand_path('~/.n2b/config.yml')
    HISTORY_FILE = ENV['N2B_HISTORY_FILE'] || File.expand_path('~/.n2b/history')

    def load_config
      if File.exist?(CONFIG_FILE)
        YAML.load_file(CONFIG_FILE)
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
          model_choice = N2B::ModelConfig.get_model_choice(selected_llm, current_model) # Renamed to model_choice to avoid conflict
          config['model'] = model_choice

          current_ollama_api_url = config['ollama_api_url'] || N2M::Llm::Ollama::DEFAULT_OLLAMA_API_URI
          print "Enter Ollama API base URL [current: #{current_ollama_api_url}]: "
          ollama_api_url_input = $stdin.gets.chomp
          config['ollama_api_url'] = ollama_api_url_input.empty? ? current_ollama_api_url : ollama_api_url_input
          config.delete('access_key') # Remove access_key if switching to ollama
        else
          # Configuration for API key based LLMs
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

          current_model = config['model']
          model_choice = N2B::ModelConfig.get_model_choice(selected_llm, current_model) # Renamed
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
          print "Would you like to configure advanced settings (e.g., Jira integration, privacy)? (y/n) [default: n]: "
          choice = $stdin.gets.chomp.downcase

          if choice == 'y'
            # Jira Configuration
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

          else # User chose 'n' for advanced settings
            # Ensure Jira config is empty or defaults are cleared if user opts out of advanced
            config['jira'] ||= {} # Ensure it exists
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
          config['jira'] ||= {} # Ensure Jira key exists
          config['privacy'] ||= {}
          config['privacy']['send_shell_history'] = config['privacy']['send_shell_history'] || false
          config['privacy']['send_llm_history'] = config['privacy']['send_llm_history'] || true
          config['privacy']['send_current_directory'] = config['privacy']['send_current_directory'] || true
          config['append_to_shell_history'] = config['append_to_shell_history'] || false
          config['privacy']['append_to_shell_history'] = config['append_to_shell_history']
        end

        # Validate configuration before saving
        validation_errors = validate_config(config)
        if validation_errors.any?
          puts "\n⚠️  Configuration validation warnings:"
          validation_errors.each { |error| puts "  - #{error}" }
          puts "Configuration saved with warnings."
        end

        puts "\nConfiguration saved to #{CONFIG_FILE}"
        FileUtils.mkdir_p(File.dirname(CONFIG_FILE)) unless File.exist?(File.dirname(CONFIG_FILE))
        File.write(CONFIG_FILE, config.to_yaml)
      else
        # If not reconfiguring, still ensure privacy and jira keys exist with defaults if missing
        # This handles configs from before these settings were introduced
        config['jira'] ||= {}
        config['privacy'] ||= {}
        config['privacy']['send_shell_history'] = config['privacy']['send_shell_history'] || false
        config['privacy']['send_llm_history'] = config['privacy']['send_llm_history'] || true
        config['privacy']['send_current_directory'] = config['privacy']['send_current_directory'] || true
        # append_to_shell_history was outside 'privacy' before, ensure it's correctly defaulted
        # and also placed under 'privacy' for future consistency.
        current_append_setting = config.key?('append_to_shell_history') ? config['append_to_shell_history'] : false
        config['append_to_shell_history'] = current_append_setting
        config['privacy']['append_to_shell_history'] = config['privacy']['append_to_shell_history'] || current_append_setting
      end
      config
    end

    private

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
      if config['llm'] != 'ollama' && (config['access_key'].nil? || config['access_key'].empty?)
        errors << "API key missing for #{config['llm']} provider"
      end

      # Validate Jira configuration if present
      if config['jira'] && !config['jira'].empty?
        jira_config = config['jira']
        if jira_config['domain'] && !jira_config['domain'].empty?
          # If domain is set, email and api_key should also be set
          if jira_config['email'].nil? || jira_config['email'].empty?
            errors << "Jira email missing when domain is configured"
          end
          if jira_config['api_key'].nil? || jira_config['api_key'].empty?
            errors << "Jira API key missing when domain is configured"
          end
        end
      end

      errors
    end
  end
end