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
      api_key = ENV['CLAUDE_API_KEY'] || config['access_key']
      model = config['model'] || 'sonnet35'
  
      if api_key.nil? || api_key == '' ||  reconfigure
        print "choose a language model to use (1:claude, 2:openai, 3:gemini) #{ config['llm'] }: "
        llm = $stdin.gets.chomp
        llm = config['llm'] if llm.empty?
        unless ['claude', 'openai', 'gemini', '1', '2', '3'].include?(llm)
          puts "Invalid language model. Choose from: claude, openai, gemini"
          exit 1
        end
        llm = 'claude' if llm == '1'
        llm = 'openai' if llm == '2'
        llm = 'gemini' if llm == '3'
        llm_class = case llm
                   when 'openai'
                     N2M::Llm::OpenAi
                   when 'gemini'
                     N2M::Llm::Gemini
                   else
                     N2M::Llm::Claude
                   end

        print "Enter your #{llm} API key: #{ api_key.nil? || api_key.empty? ? '' : '(leave blank to keep the current key '+api_key[0..10]+'...)' }"
        api_key = $stdin.gets.chomp 
        api_key = config['access_key'] if api_key.empty?
        print "Choose a model (#{ llm_class::MODELS.keys }, #{ llm_class::MODELS.keys.first } default): "
        model = $stdin.gets.chomp 
        model = llm_class::MODELS.keys.first if model.empty?
        config['llm'] = llm
        config['access_key'] = api_key
        config['model'] = model
        unless llm_class::MODELS.keys.include?(model)
          puts "Invalid model. Choose from: #{llm_class::MODELS.keys.join(', ')}"
          exit 1
        end
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