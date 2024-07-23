module N2B
  module IRB
    MAX_SOURCE_FILES = 4
    def n2r(input_string='', files: [], exception: nil)
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
      # scan the input for any files that the user has provided
      # look for strings that end with .rb and get the path to the file
      source_files = []
      input_string.scan(/[\w\/.-]+\.rb(?=\s|:|$)/).each do |file|
        full_path = File.expand_path(file) # Resolve the full path
        source_files << full_path if File.exist?(full_path)
      end
      if exception
        source_files += exception.backtrace.map do |line|
          line.split(':').first
        end
        input_string << ' ' << exception.message
      end
      source_files = source_files.reverse.sort_by do |file|
        # Check if the file path starts with the current directory path
        if file.start_with?(Dir.pwd)
          0 # Prioritize files in or below the current directory
        else
          1 # Keep other files in their original order
        end
      end
     
      
      file_content = (files+source_files[0..MAX_SOURCE_FILES-1]).inject({}) do |h,file|
        h[file] = File.read(file) if File.exist?(file)
        h
      end
      content = <<~HEREDOC
        you are a professional ruby programmer  
        #{ console}
        The following classes are defined in this session:
        #{ get_defined_classes}
        #{ get_gemfile }
        #{ @n2r_answers ? "user have made #{@n2r_answers} before" : "" }
        your task is to give the user guidance on how perform a task he is asking for
        if he pasts an error or backtrace, you can provide a solution to the problem.
        if you need files you can ask the user to provide them request.
        he can send them with n2r "his question" files: ['file1.rb', 'file2.rb']
        if he sends files and you mention them in the response, provide the file name of the snippets you are referring to.
        answer in a valid json object with the key 'code' with only the ruby code to be executed and a key 'explanation' with a markdown string with the explanation and the code.
        { "code": "puts 'Hello, World!'", "explanation": "### Explanation \n This command ´´´puts 'Hello, world!'´´´  prints 'Hello, World!' to the terminal.", files: ['file1.rb', 'file2.rb']}
         #{input_string}
        #{ "the user provided the following files: #{ file_content.collect{|k,v| "#{k}:#{v}" }.join("\n") }" if file_content }
        }}
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