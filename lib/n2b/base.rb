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
    
    def get_config( reconfigure: false)
      config = load_config
      api_key = ENV['CLAUDE_API_KEY'] || config['access_key'] # This will be used as default or for existing configs
      model = config['model'] # Model will be handled per LLM
  
      if api_key.nil? || api_key == '' || config['llm'].nil? || reconfigure # Added config['llm'].nil? to force config if llm type isn't set
        print "choose a language model to use (1:claude, 2:openai, 3:gemini, 4:openrouter, 5:ollama) #{ config['llm'] }: "
        llm = $stdin.gets.chomp
        llm = config['llm'] if llm.empty? && !config['llm'].nil? # Keep current if input is empty and current exists

        unless ['claude', 'openai', 'gemini', 'openrouter', 'ollama', '1', '2', '3', '4', '5'].include?(llm)
          puts "Invalid language model. Choose from: claude, openai, gemini, openrouter, ollama, or 1-5"
          exit 1
        end
        llm = 'claude' if llm == '1'
        llm = 'openai' if llm == '2'
        llm = 'gemini' if llm == '3'
        llm = 'openrouter' if llm == '4'
        llm = 'ollama' if llm == '5'

        # Set default LLM if needed
        if llm.nil? || llm.empty?
          llm = 'claude'
        end

        config['llm'] = llm

        if llm == 'ollama'
          # Ollama specific configuration
          puts "Ollama typically runs locally and doesn't require an API key."

          # Use new model configuration system
          current_model = config['model']
          model = N2B::ModelConfig.get_model_choice(llm, current_model)

          # Configure Ollama API URL
          current_ollama_api_url = config['ollama_api_url'] || N2M::Llm::Ollama::DEFAULT_OLLAMA_API_URI
          print "Enter Ollama API base URL (default: #{current_ollama_api_url}): "
          ollama_api_url_input = $stdin.gets.chomp
          config['ollama_api_url'] = ollama_api_url_input.empty? ? current_ollama_api_url : ollama_api_url_input
          config.delete('access_key') # Remove access_key if switching to ollama
        else
          # Configuration for API key based LLMs (Claude, OpenAI, Gemini, OpenRouter)
          current_api_key = config['access_key'] # Use existing key from config as default
          print "Enter your #{llm} API key: #{ current_api_key.nil? || current_api_key.empty? ? '' : '(leave blank to keep the current key)' }"
          api_key_input = $stdin.gets.chomp
          config['access_key'] = api_key_input if !api_key_input.empty?
          config['access_key'] = current_api_key if api_key_input.empty? && !current_api_key.nil? && !current_api_key.empty?

          # Ensure API key is present if not Ollama
          if config['access_key'].nil? || config['access_key'].empty?
            puts "API key is required for #{llm}."
            exit 1
          end

          # Use new model configuration system
          current_model = config['model']
          model = N2B::ModelConfig.get_model_choice(llm, current_model)

          if llm == 'openrouter'
            current_site_url = config['openrouter_site_url'] || ""
            print "Enter your OpenRouter Site URL (optional, for HTTP-Referer header, current: #{current_site_url}): "
            openrouter_site_url_input = $stdin.gets.chomp
            config['openrouter_site_url'] = openrouter_site_url_input.empty? ? current_site_url : openrouter_site_url_input

            current_site_name = config['openrouter_site_name'] || ""
            print "Enter your OpenRouter Site Name (optional, for X-Title header, current: #{current_site_name}): "
            openrouter_site_name_input = $stdin.gets.chomp
            config['openrouter_site_name'] = openrouter_site_name_input.empty? ? current_site_name : openrouter_site_name_input
          end
        end

        config['model'] = model # Store selected model for all types

        # Ensure privacy settings are initialized if not present
        config['privacy'] ||= {}
        # Set defaults for any privacy settings that are nil
        config['privacy']['send_shell_history'] = false if config['privacy']['send_shell_history'].nil?
        config['privacy']['send_llm_history'] = true if config['privacy']['send_llm_history'].nil?
        config['privacy']['send_current_directory'] = true if config['privacy']['send_current_directory'].nil?
        config['append_to_shell_history'] = false if config['append_to_shell_history'].nil?

        puts "configure privacy settings directly in the config file #{CONFIG_FILE}"
        config['privacy'] ||= {} 
        config['privacy']['send_shell_history'] = false
        config['privacy']['send_llm_history'] = true
        config['privacy']['send_current_directory'] =true
        config['append_to_shell_history'] = false 
        puts "Current configuration: #{config['privacy']}"
        FileUtils.mkdir_p(File.dirname(CONFIG_FILE)) unless File.exist?(File.dirname(CONFIG_FILE))
        File.write(CONFIG_FILE, config.to_yaml)
      end
      config
    end
  end
end