require 'yaml'

module N2B
  class ModelConfig
    CONFIG_PATH = File.expand_path('config/models.yml', __dir__)
    
    def self.load_models
      @models ||= YAML.load_file(CONFIG_PATH)
    rescue => e
      puts "Warning: Could not load models configuration: #{e.message}"
      puts "Using fallback model configuration."
      fallback_models
    end
    
    def self.fallback_models
      {
        'claude' => { 'suggested' => { 'sonnet' => 'claude-3-sonnet-20240229' }, 'default' => 'sonnet' },
        'openai' => { 'suggested' => { 'gpt-4o-mini' => 'gpt-4o-mini' }, 'default' => 'gpt-4o-mini' },
        'gemini' => { 'suggested' => { 'gemini-flash' => 'gemini-2.0-flash' }, 'default' => 'gemini-flash' },
        'openrouter' => { 'suggested' => { 'gpt-4o' => 'openai/gpt-4o' }, 'default' => 'gpt-4o' },
        'ollama' => { 'suggested' => { 'llama3' => 'llama3' }, 'default' => 'llama3' }
      }
    end
    
    def self.suggested_models(provider)
      load_models.dig(provider, 'suggested') || {}
    end
    
    def self.default_model(provider)
      load_models.dig(provider, 'default')
    end
    
    def self.resolve_model(provider, user_input)
      return nil if user_input.nil? || user_input.empty?
      
      suggested = suggested_models(provider)
      
      # If user input matches a suggested model key, return the API name
      if suggested.key?(user_input)
        suggested[user_input]
      else
        # Otherwise, treat as custom model (return as-is)
        user_input
      end
    end
    
    def self.display_model_options(provider)
      suggested = suggested_models(provider)
      default = default_model(provider)
      
      options = []
      suggested.each_with_index do |(key, api_name), index|
        default_marker = key == default ? " [default]" : ""
        options << "#{index + 1}. #{key} (#{api_name})#{default_marker}"
      end
      options << "#{suggested.size + 1}. custom (enter your own model name)"
      
      options
    end
    
    def self.get_model_choice(provider, current_model = nil)
      options = display_model_options(provider)
      suggested = suggested_models(provider)
      default = default_model(provider)
      
      puts "\nChoose a model for #{provider}:"
      options.each { |option| puts "  #{option}" }
      
      current_display = current_model || default
      print "\nEnter choice (1-#{options.size}) or model name [#{current_display}]: "
      
      input = $stdin.gets.chomp
      
      # If empty input, use current or default
      if input.empty?
        return current_model || resolve_model(provider, default)
      end
      
      # If numeric input, handle menu selection
      if input.match?(/^\d+$/)
        choice_num = input.to_i
        if choice_num >= 1 && choice_num <= suggested.size
          # Selected a suggested model
          selected_key = suggested.keys[choice_num - 1]
          return resolve_model(provider, selected_key)
        elsif choice_num == suggested.size + 1
          # Selected custom option
          print "Enter custom model name: "
          custom_model = $stdin.gets.chomp
          if custom_model.empty?
            puts "Custom model name cannot be empty. Using default."
            return resolve_model(provider, default)
          end
          puts "✓ Using custom model: #{custom_model}"
          return custom_model
        else
          puts "Invalid choice. Using default."
          return resolve_model(provider, default)
        end
      else
        # Direct model name input
        resolved = resolve_model(provider, input)
        if suggested.key?(input)
          puts "✓ Using suggested model: #{input} (#{resolved})"
        else
          puts "✓ Using custom model: #{resolved}"
        end
        return resolved
      end
    end
  end
end
