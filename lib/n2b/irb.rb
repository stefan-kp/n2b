module N2B
  module IRB
    def n2r(input_string='')
      config = N2B::Base.new.get_config
      llm = config['llm'] == 'openai' ? N2M::Llm::OpenAi.new(config) : N2M::Llm::Claude.new(config)
      # detect if inside rails console
      console = case 
      when defined?(Rails)
         "You are in a Rails console"
      when defined?(IRB)
         "You are in an IRB console"
      else
        "You are in a standard Ruby console"
      end
      get_defined_classes = ObjectSpace.each_object(Class).to_a
      get_gemfile = File.read('Gemfile') if File.exist?('Gemfile') 
      content = <<~HEREDOC
        you are a professional ruby programmer  
        #{ console}
        The following classes are defined in this session:
        #{ get_defined_classes}
        #{ get_gemfile }
        #{ @n2r_answers ? "user have made #{@n2r_answers} before" : "" }
        your task is to give the user guidance on how perform a task he is asking for
        if he pasts an error or backtrace, you can provide a solution to the problem.
        if you need files or directories, you can ask the user to provide them in the json.
        answer in a valid json object with the key 'code' with only the ruby code to be executed and a key 'explanation' with a markdown string with the explanation and the code.
        { "code": "puts 'Hello, World!'", "explanation": "### Explanation \n This command ´´´puts 'Hello, world!'´´´  prints 'Hello, World!' to the terminal.", files: ['file1.rb', 'file2.rb']}
         #{input_string}
      HEREDOC
      @n2r_answers ||= []
      @n2r_answer = llm.make_request(content)
      @n2r_answers << { input: input_string, output: @n2r_answer }
      @n2r_answer['code'].split("\n").each do |line|
        puts line
      end if @n2r_answer['code']
      @n2r_answer['explanation'].split("\n").each do |line|
        puts line
      end
      nil
    end
  end 
end

# Include the module in the main object if in console
include N2B::IRB if defined?(IRB)