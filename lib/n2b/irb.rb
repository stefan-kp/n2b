module N2B
  class IRB
    MAX_SOURCE_FILES = 4
    DEFAULT_CONTEXT_LINES = 20

    def self.n2r(input_string='', files: [], exception: nil, log: false)
      new.n2r(input_string, files: files, exception: exception, log: log)
    end

    def self.n2rrbit(url:, cookie:, source_dir: nil, context_lines: DEFAULT_CONTEXT_LINES, log: false)
      new.n2rrbit(url: url, cookie: cookie, source_dir: source_dir, context_lines: context_lines, log: log)
    end

    def self.n2rscrum(input_string='', files: [], exception: nil, url: nil, cookie: nil, source_dir: nil, context_lines: DEFAULT_CONTEXT_LINES, log: false)
      new.n2rscrum(input_string: input_string, files: files, exception: exception, url: url, cookie: cookie, source_dir: source_dir, context_lines: context_lines, log: log)
    end

    def n2r(input_string='', files: [], exception: nil, log: false)
      config = N2B::Base.new.get_config
      llm = config['llm'] == 'openai' ? N2M::Llm::OpenAi.new(config) : N2M::Llm::Claude.new(config)
      # detect if inside rails console
      console = case 
      when defined?(Rails) && Rails.respond_to?(:application)
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
        input_string << ' ' << exception.message << "\m" << exception.backtrace.join(' ')
      end
      source_files = source_files.sort_by do |file|
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
      if log
        log_file_path = File.expand_path('~/.n2b/n2r.log')
        File.open(log_file_path, 'a') do |file|
          file.puts(content)
        end
      end
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

    def n2rrbit(url:, cookie:, source_dir: nil, context_lines: DEFAULT_CONTEXT_LINES, log: false)
      require 'net/http'
      require 'uri'
      require 'nokogiri'
      
      # Download the Errbit page
      errbit_html = fetch_errbit(url, cookie)
      
      if errbit_html.nil?
        puts "Failed to download Errbit error from #{url}"
        return nil
      end
      
      # Parse the error information
      error_info = parse_errbit(errbit_html)
      
      if error_info.nil?
        puts "Failed to parse Errbit error information"
        return nil
      end
      
      # Find related files in the current project using source_dir if provided
      related_files = find_related_files(error_info[:backtrace], source_dir: source_dir, context_lines: context_lines)
      
      # Analyze the error
      analysis = analyze_error(error_info, related_files)
      
      # Log if requested
      if log
        log_file_path = File.expand_path('~/.n2b/n2rrbit.log')
        File.open(log_file_path, 'a') do |file|
          file.puts("===== N2RRBIT REQUEST LOG =====")
          file.puts("URL: #{url}")
          file.puts("Error: #{error_info[:error_class]} - #{error_info[:error_message]}")
          file.puts("Backtrace: #{error_info[:backtrace].join("\n")}")
          file.puts("Source directory: #{source_dir || Dir.pwd}")
          file.puts("\nFound Related Files:")
          
          # Log detailed information about each file that was found
          related_files.each do |file_path, content|
            file.puts("\n--- File: #{file_path}")
            if content.is_a?(Hash) && content[:full_path]
              file.puts("Full path: #{content[:full_path]}")
              file.puts("Error occurred at line: #{content[:line_number]}")
              file.puts("Context lines: #{content[:start_line]}-#{content[:end_line]}")
              file.puts("\nContext code:")
              file.puts("```ruby")
              file.puts(content[:context])
              file.puts("```")
            else
              file.puts("Full content (no specific line context)")
              file.puts("```ruby")
              file.puts(content)
              file.puts("```")
            end
          end
          
          # Log the actual prompt sent to the LLM
          file_content_section = related_files.map do |file_path, content|
            if content.is_a?(Hash) && content[:context]
              "#{file_path} (around line #{content[:line_number]}, showing lines #{content[:start_line]}-#{content[:end_line]}):\n```ruby\n#{content[:context]}\n```"
            else
              "#{file_path}:\n```ruby\n#{content.is_a?(Hash) ? content[:full_content] : content}\n```"
            end
          end.join("\n\n")
          
          llm_prompt = <<~HEREDOC
            You are an expert Ruby programmer analyzing application errors.
            
            Error Type: #{error_info[:error_class]}
            Error Message: #{error_info[:error_message]}
            Application: #{error_info[:app_name]}
            Environment: #{error_info[:environment]}
            
            Backtrace:
            #{error_info[:backtrace].join("\n")}
            
            Related Files with Context:
            #{file_content_section}
            
            Please analyze this error and provide:
            1. A clear explanation of what caused the error
            2. Specific code that might be causing the issue
            3. Suggested fixes for the problem
            4. If the error seems related to specific parameters, explain which parameter values might be triggering it
            
            Your analysis should be detailed but concise.
          HEREDOC
          
          file.puts("\n=== PROMPT SENT TO LLM ===")
          file.puts(llm_prompt)
          file.puts("\n=== LLM RESPONSE ===")
          file.puts(analysis)
          file.puts("\n===== END OF LOG =====\n\n")
        end
      end
      
      # Display the error analysis
      puts "Error Type: #{error_info[:error_class]}"
      puts "Message: #{error_info[:error_message]}"
      
      if error_info[:parameters] && !error_info[:parameters].empty?
        puts "\nRequest Parameters:"
        error_info[:parameters].each do |key, value|
          # Truncate long values for display
          display_value = value.to_s.length > 100 ? "#{value.to_s[0..100]}..." : value
          puts "  #{key} => #{display_value}"
        end
      end
      
      if error_info[:session] && !error_info[:session].empty?
        puts "\nSession Data:"
        puts "  (Available but not displayed - see log for details)"
      end
      
      puts "\nBacktrace Highlights:"
      error_info[:backtrace].first(5).each do |line|
        puts "  #{line}"
      end
      
      puts "\nSource Directory: #{source_dir || Dir.pwd}"
      puts "\nRelated Files:"
      related_files.each do |file, content|
        if content.is_a?(Hash) && content[:context]
          puts "  #{file} (with context around line #{content[:line_number]})"
        else
          puts "  #{file}"
        end
      end
      
      puts "\nAnalysis:"
      puts analysis
      
      nil
    end
    
    def n2rscrum(input_string: '', files: [], exception: nil, url: nil, cookie: nil, source_dir: nil, context_lines: DEFAULT_CONTEXT_LINES, log: false)
      # Determine which mode we're running in
      if url && cookie
        # Errbit URL mode
        require 'net/http'
        require 'uri'
        require 'nokogiri'
        
        # Download the Errbit page
        errbit_html = fetch_errbit(url, cookie)
        
        if errbit_html.nil?
          puts "Failed to download Errbit error from #{url}"
          return nil
        end
        
        # Parse the error information
        error_info = parse_errbit(errbit_html)
        
        if error_info.nil?
          puts "Failed to parse Errbit error information"
          return nil
        end
        
        # Find related files with context for better analysis
        related_files = find_related_files(error_info[:backtrace], source_dir: source_dir, context_lines: context_lines)
        
        # Generate a Scrum ticket from error info, passing the URL
        ticket = generate_error_ticket(error_info, related_files, url)
      else
        # If we have an exception, convert it to error_info format and use generate_error_ticket
        if exception
          files += exception.backtrace.map do |line|
            line.split(':').first
          end
          
          # Create error_info hash from exception with better Rails detection
          app_name = if defined?(Rails) && Rails.respond_to?(:application) && 
                        Rails.application.respond_to?(:class) &&
                        Rails.application.class.respond_to?(:module_parent_name)
                          Rails.application.class.module_parent_name 
                        else 
                          'Ruby Application'
                        end
          
          environment = if defined?(Rails) && Rails.respond_to?(:env)
                          Rails.env
                        else
                          'development'
                        end
          
          error_info = {
            error_class: exception.class.name,
            error_message: exception.message,
            backtrace: exception.backtrace,
            app_name: app_name,
            environment: environment
          }
          
          # Find related files with context
          related_files = find_related_files(error_info[:backtrace], source_dir: source_dir, context_lines: context_lines)
          
          # Use the same ticket generator for consistency
          ticket = generate_error_ticket(error_info, related_files)
        else
          # Standard mode (input string/files)
          config = N2B::Base.new.get_config
          llm = config['llm'] == 'openai' ? N2M::Llm::OpenAi.new(config) : N2M::Llm::Claude.new(config)
          
          # detect if inside rails console
          console = case 
          when defined?(Rails) && Rails.respond_to?(:application)
            "You are in a Rails console"
          when defined?(IRB)
            "You are in an IRB console"
          else
            "You are in a standard Ruby console"
          end
          
          # Read file contents
          file_content = files.inject({}) do |h, file|
            h[file] = File.read(file) if File.exist?(file)
            h
          end
          
          # Generate ticket content using LLM
          content = <<~HEREDOC
            you are a professional ruby programmer and scrum master
            #{console}
            your task is to create a scrum ticket for the following issue/question:
            answer in a valid json object with the key 'code' with only the ruby code to be executed and a key 'explanation' with a markdown string containing a well-formatted scrum ticket with:
            
            1. A clear and concise title
            2. Description of the issue with technical details
            3. Acceptance criteria
            4. Estimate of complexity (story points)
            5. Priority level suggestion
            
            #{input_string}
            #{"the user provided the following files: #{file_content.collect{|k,v| "#{k}:#{v}" }.join("\n") }" if file_content.any?}
          HEREDOC
          
          response = safe_llm_request(llm, content)
          ticket = response['explanation'] || response['code'] || "Failed to generate Scrum ticket."
        end
      end
      
      # Log if requested
      if log
        log_file_path = File.expand_path('~/.n2b/n2rscrum.log')
        File.open(log_file_path, 'a') do |file|
          file.puts("===== N2RSCRUM REQUEST LOG =====")
          file.puts("Timestamp: #{Time.now}")
          
          if url
            file.puts("Mode: Errbit URL")
            file.puts("URL: #{url}")
          elsif exception
            file.puts("Mode: Exception")
            file.puts("Exception: #{exception.class.name} - #{exception.message}")
          else
            file.puts("Mode: Input String")
            file.puts("Input: #{input_string}")
          end
          
          file.puts("Files: #{files.join(', ')}") if files.any?
          file.puts("Source directory: #{source_dir || Dir.pwd}")
          
          # If we have related files (from Errbit or exception mode)
          if defined?(related_files) && related_files.any?
            file.puts("\nFound Related Files:")
            
            related_files.each do |file_path, content|
              file.puts("\n--- File: #{file_path}")
              if content.is_a?(Hash) && content[:full_path]
                file.puts("Full path: #{content[:full_path]}")
                file.puts("Error occurred at line: #{content[:line_number]}")
                file.puts("Context lines: #{content[:start_line]}-#{content[:end_line]}")
                file.puts("\nContext code:")
                file.puts("```ruby")
                file.puts(content[:context])
                file.puts("```")
              else
                file.puts("Full content (no specific line context)")
                file.puts("```ruby")
                file.puts(content)
                file.puts("```")
              end
            end
            
            # Log the actual prompt sent to the LLM
            file_content_section = related_files.map do |file_path, content|
              if content.is_a?(Hash) && content[:context]
                "#{file_path} (around line #{content[:line_number]}, showing lines #{content[:start_line]}-#{content[:end_line]}):\n```ruby\n#{content[:context]}\n```"
              else
                "#{file_path}:\n```ruby\n#{content.is_a?(Hash) ? content[:full_content] : content}\n```"
              end
            end.join("\n\n")
            
            if defined?(error_info) && error_info
              llm_prompt = <<~HEREDOC
                You are a software developer creating a Scrum task for a bug fix.
                
                Error details:
                Type: #{error_info[:error_class]}
                Message: #{error_info[:error_message]}
                Application: #{error_info[:app_name] || 'Local Application'}
                Environment: #{error_info[:environment] || 'Development'}
                
                Backtrace highlights:
                #{error_info[:backtrace]&.first(5)&.join("\n") || 'No backtrace available'}
                
                Related Files with Context:
                #{file_content_section}
                
                Please generate a well-formatted Scrum ticket that includes:
                1. A clear and concise title
                2. Description of the issue with technical details
                3. Details about the parameter values that were present when the error occurred
                4. Likely root causes and assumptions about what's causing the problem (be specific)
                5. Detailed suggested fixes with code examples where possible
                6. Acceptance criteria
                7. Estimate of complexity (story points)
                8. Priority level suggestion
                
                IMPORTANT: Your response must be a valid JSON object with ONLY two keys:
                - 'explanation': containing the formatted Scrum ticket as a markdown string
                - 'code': set to null or omitted
                
                For example: {"explanation": "# Ticket Title\\n## Description\\n...", "code": null}
                
                Ensure all code examples are properly formatted with markdown code blocks using triple backticks.
              HEREDOC
              
              file.puts("\n=== PROMPT SENT TO LLM ===")
              file.puts(llm_prompt)
            elsif !input_string.empty?
              # Log the prompt for input string mode
              file.puts("\n=== PROMPT SENT TO LLM ===")
              file.puts("Input string mode prompt with input: #{input_string}")
              if file_content.any?
                file.puts("With files content included")
              end
            end
          end
          
          file.puts("\n=== LLM RESPONSE (RAW) ===")
          file.puts(ticket.inspect)
          file.puts("\n=== FORMATTED TICKET ===")
          file.puts(ticket)
          file.puts("\n===== END OF LOG =====\n\n")
        end
      end
      
      # Safely handle the ticket
      begin
        # Display the ticket
        puts "Generated Scrum Ticket:"
        puts ticket
      rescue => e
        puts "Error displaying ticket: #{e.message}"
        puts "Raw ticket data: #{ticket.inspect}"
      end
      
      nil
    end
    
    private
    
    def fetch_errbit(url, cookie)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      
      request = Net::HTTP::Get.new(uri.request_uri)
      request['Cookie'] = cookie
      
      response = http.request(request)
      
      if response.code == '200'
        response.body
      else
        puts "HTTP Error: #{response.code} - #{response.message}"
        nil
      end
    end
    
    def parse_errbit(html)
      doc = Nokogiri::HTML(html)
      
      error_class = doc.css('h1').text.strip
      error_message = doc.css('h4').text.strip
      
      backtrace = []
      doc.css('#backtrace .line.in-app').each do |line|
        file_path = line.css('.path').text.strip + line.css('.file').text.strip
        line_number = line.css('.number').text.strip.tr(':', '')
        method_name = line.css('.method').text.strip
        backtrace << "#{file_path}:#{line_number} in `#{method_name}`"
      end
      
      app_name = doc.css('#content-title .meta a').text.strip
      environment = doc.css('#content-title .meta strong:contains("Environment:")').first&.next&.text&.strip
      
      # Extract parameters
      parameters = {}
      
      # Find the parameters section
      params_div = doc.css('#params')
      if params_div && !params_div.empty?
        # Try to find a hash structure in the params section
        hash_content = params_div.css('.raw_data pre.hash').text
        
        if hash_content && !hash_content.empty?
          # Simple parsing of the hash structure
          # This is a basic approach - you might need to enhance this for complex structures
          parameters = parse_hash_content(hash_content)
        end
      end
      
      # Extract session data too, if available
      session_data = {}
      session_div = doc.css('#session')
      if session_div && !session_div.empty?
        hash_content = session_div.css('.raw_data pre.hash').text
        
        if hash_content && !hash_content.empty?
          session_data = parse_hash_content(hash_content)
        end
      end
      
      {
        error_class: error_class,
        error_message: error_message,
        backtrace: backtrace,
        app_name: app_name,
        environment: environment,
        parameters: parameters,
        session: session_data
      }
    end
    
    def parse_hash_content(content)
      # Very basic parsing - this could be improved for more complex structures
      result = {}
      
      # Remove the outer braces
      content = content.strip.sub(/^\{/, '').sub(/\}$/, '')
      
      # Split by top-level keys
      current_key = nil
      current_value = ""
      level = 0
      
      content.each_line do |line|
        line = line.strip
        
        # Skip empty lines
        next if line.empty?
        
        # Check for key-value pattern at top level
        if level == 0 && line =~ /^"([^"]+)"\s*=>\s*(.+)$/
          # Save previous key-value if any
          if current_key
            result[current_key] = current_value.strip
          end
          
          # Start new key-value
          current_key = $1
          current_value = $2
          
          # Adjust brace/bracket level
          level += line.count('{') + line.count('[') - line.count('}') - line.count(']')
        else
          # Continue previous value
          current_value += "\n" + line
          
          # Adjust brace/bracket level
          level += line.count('{') + line.count('[') - line.count('}') - line.count(']')
        end
      end
      
      # Save the last key-value
      if current_key
        result[current_key] = current_value.strip
      end
      
      result
    end
    
    def analyze_error(error_info, related_files)
      config = N2B::Base.new.get_config
      llm = config['llm'] == 'openai' ? N2M::Llm::OpenAi.new(config) : N2M::Llm::Claude.new(config)
      
      # Build file content section, showing context if available
      file_content_section = related_files.map do |file_path, content|
        if content.is_a?(Hash) && content[:context]
          # Show context around the error line
          "#{file_path} (around line #{content[:line_number]}, showing lines #{content[:start_line]}-#{content[:end_line]}):\n```ruby\n#{content[:context]}\n```"
        else
          # Show the whole file content
          "#{file_path}:\n```ruby\n#{content.is_a?(Hash) ? content[:full_content] : content}\n```"
        end
      end.join("\n\n")
      
      # Format parameters for better readability
      params_section = ""
      if error_info[:parameters] && !error_info[:parameters].empty?
        params_section = "Request Parameters:\n```\n"
        error_info[:parameters].each do |key, value|
          params_section += "#{key} => #{value}\n"
        end
        params_section += "```\n\n"
      end
      
      # Format session data
      session_section = ""
      if error_info[:session] && !error_info[:session].empty?
        session_section = "Session Data:\n```\n"
        error_info[:session].each do |key, value|
          session_section += "#{key} => #{value}\n"
        end
        session_section += "```\n\n"
      end
      
      content = <<~HEREDOC
        You are an expert Ruby programmer analyzing application errors.
        
        Error Type: #{error_info[:error_class]}
        Error Message: #{error_info[:error_message]}
        Application: #{error_info[:app_name]}
        Environment: #{error_info[:environment]}
        
        Backtrace:
        #{error_info[:backtrace].join("\n")}
        
        #{params_section}
        #{session_section}
        
        Related Files with Context:
        #{file_content_section}
        
        Please analyze this error and provide:
        1. A clear explanation of what caused the error
        2. Specific code that might be causing the issue
        3. Suggested fixes for the problem
        4. If the error seems related to specific parameters, explain which parameter values might be triggering it
        
        Your analysis should be detailed but concise.
      HEREDOC
      
      response = llm.make_request(content)
      response['explanation'] || response['code'] || "Failed to analyze the error."
    end
    
    def generate_error_ticket(error_info, related_files = {}, url = nil)
      config = N2B::Base.new.get_config
      llm = config['llm'] == 'openai' ? N2M::Llm::OpenAi.new(config) : N2M::Llm::Claude.new(config)
      
      # Build file content section, showing context if available
      file_content_section = related_files.map do |file_path, content|
        if content.is_a?(Hash) && content[:context]
          # Show context around the error line
          "#{file_path} (around line #{content[:line_number]}, showing lines #{content[:start_line]}-#{content[:end_line]}):\n```ruby\n#{content[:context]}\n```"
        else
          # Show the whole file content
          "#{file_path}:\n```ruby\n#{content.is_a?(Hash) ? content[:full_content] : content}\n```"
        end
      end.join("\n\n")
      
      # Format parameters for better readability
      params_section = ""
      if error_info[:parameters] && !error_info[:parameters].empty?
        params_section = "Request Parameters:\n```\n"
        error_info[:parameters].each do |key, value|
          params_section += "#{key} => #{value}\n"
        end
        params_section += "```\n\n"
      end
      
      # Format session data
      session_section = ""
      if error_info[:session] && !error_info[:session].empty?
        session_section = "Session Data:\n```\n"
        error_info[:session].each do |key, value|
          session_section += "#{key} => #{value}\n"
        end
        session_section += "```\n\n"
      end
      
      content = <<~HEREDOC
        You are a software developer creating a Scrum task for a bug fix.
        
        Error details:
        Type: #{error_info[:error_class]}
        Message: #{error_info[:error_message]}
        Application: #{error_info[:app_name] || 'Local Application'}
        Environment: #{error_info[:environment] || 'Development'}
        
        Backtrace highlights:
        #{error_info[:backtrace]&.first(5)&.join("\n") || 'No backtrace available'}
        
        #{params_section}
        #{session_section}
        
        Related Files with Context:
        #{file_content_section}
        
        Please generate a well-formatted Scrum ticket that includes:
        1. A clear and concise title
        2. Description of the issue with technical details
        3. Details about the parameter values that were present when the error occurred
        4. Likely root causes and assumptions about what's causing the problem (be specific)
        5. Detailed suggested fixes with code examples where possible
        6. Acceptance criteria
        7. Estimate of complexity (story points)
        8. Priority level suggestion
        
        IMPORTANT: Your response must be a valid JSON object with ONLY two keys:
        - 'explanation': containing the formatted Scrum ticket as a markdown string
        - 'code': set to null or omitted
        
        For example: {"explanation": "# Ticket Title\\n## Description\\n...", "code": null}
        
        Ensure all code examples are properly formatted with markdown code blocks using triple backticks.
      HEREDOC
      
      # Safe response handling
      begin
        response = llm.make_request(content)
        
        # Check if response is a Hash with the expected keys
        ticket = nil
        if response.is_a?(Hash) && (response['explanation'] || response['code'])
          ticket = response['explanation'] || response['code']
        elsif response.is_a?(Hash)
          # Try to convert the response to the expected format
          ticket = fix_malformed_response(llm, response)
        else
          # If response is not a hash, convert to string safely
          ticket = "Failed to generate properly formatted ticket. Raw response: #{response.inspect}"
        end
        
        # Append the Errbit URL if it's provided and not already included in the ticket
        if url && !ticket.include?(url)
          ticket += "\n\n## Reference\nErrbit URL: #{url}"
        end
        
        return ticket
      rescue => e
        # Handle any errors during LLM request or parsing
        result = "Error generating ticket: #{e.message}\n\nPlease try again or check your source directory path."
        
        # Still append the URL even to error messages
        if url
          result += "\n\nErrbit URL: #{url}"
        end
        
        return result
      end
    end

    def find_related_files(backtrace, source_dir: nil, context_lines: DEFAULT_CONTEXT_LINES)
      related_files = {}
      source_root = source_dir || Dir.pwd
      
      backtrace.each do |trace_line|
        # Extract file path and line number from backtrace line
        parts = trace_line.split(':')
        file_path = parts[0]
        line_number = parts[1].to_i if parts.size > 1
        
        # Skip gem files, only look for app files
        next if file_path.include?('/gems/')
        
        # Try multiple search paths
        search_paths = []
        
        # If file starts with app/, try direct match from source_root
        if file_path.start_with?('app/')
          search_paths << File.join(source_root, file_path)
        end
        
        # Also try just the basename as it might be in a different structure
        search_paths << File.join(source_root, file_path)
        
        # If none of the above match, try a find operation for the file name only
        basename = File.basename(file_path)
        
        # Try to find the file in any of the search paths
        full_path = nil
        search_paths.each do |path|
          if File.exist?(path)
            full_path = path
            break
          end
        end
        
        # If not found via direct paths, try to search for it
        if full_path.nil? && source_dir
          # Find command to locate the file in the source directory
          # We're limiting depth to avoid searching too deep
          begin
            find_result = `find #{source_root} -name #{basename} -type f -not -path "*/\\.*" -not -path "*/vendor/*" -not -path "*/node_modules/*" 2>/dev/null | head -1`.strip
            full_path = find_result unless find_result.empty?
          rescue => e
            # If find command fails for any reason, just log and continue
            puts "Warning: find command failed: #{e.message}"
          end
        end
        
        # Skip if we couldn't find the file
        next if full_path.nil? || !File.exist?(full_path)
        
        # Skip if we already have this file
        next if related_files.key?(file_path)
        
        begin
          if line_number && context_lines > 0
            # Read file with context
            file_content = File.read(full_path)
            file_lines = file_content.lines
            
            # Calculate start and end line for context
            start_line = [line_number - context_lines, 1].max
            end_line = [line_number + context_lines, file_lines.length].min
            
            # Extract context
            context_lines_array = file_lines[(start_line-1)..(end_line-1)]
            
            # Guard against nil context
            if context_lines_array.nil?
              context = "# Failed to extract context lines"
            else
              context = context_lines_array.join
            end
            
            # Store file content with context information
            related_files[file_path] = {
              full_path: full_path,
              line_number: line_number,
              context: context,
              start_line: start_line,
              end_line: end_line,
              full_content: file_content
            }
          else
            # Just store the whole file content
            related_files[file_path] = File.read(full_path)
          end
        rescue => e
          # If reading the file fails, add a placeholder
          related_files[file_path] = "# Error reading file: #{e.message}"
        end
      end
      
      related_files
    end

    def safe_llm_request(llm, content)
      begin
        response = llm.make_request(content)
        
        # Check if response is a Hash with the expected keys
        if response.is_a?(Hash) && (response.key?('explanation') || response.key?('code'))
          return response
        else
          # Try to convert to a valid format if possible
          return {
            'explanation' => response.is_a?(String) ? response : response.inspect,
            'code' => nil
          }
        end
      rescue => e
        # Return a valid response format even if there's an error
        return {
          'explanation' => "Error in LLM request: #{e.message}",
          'code' => nil
        }
      end
    end

    def fix_malformed_response(llm, original_response)
      # Prepare a prompt asking the LLM to reformat the response
      fix_prompt = <<~HEREDOC
        I received a response from you that's not in the expected format. Please reformat this response 
        into a valid JSON object with ONLY the keys 'explanation' (containing all the content as a markdown string) 
        and 'code' (which should be null).
        
        Original response:
        #{original_response.inspect}
        
        Please provide ONLY a valid JSON object like:
        {"explanation": "# Your title here\\n\\nAll the content here as markdown...", "code": null}
        
        Do not include any other keys or explanatory text outside the JSON.
      HEREDOC
      
      begin
        # Get a fixed response
        fixed_response = llm.make_request(fix_prompt)
        
        # If the fixed response is in the right format, use it
        if fixed_response.is_a?(Hash) && fixed_response['explanation']
          return fixed_response['explanation']
        end
        
        # If still not in right format, try to auto-fix it
        if original_response.is_a?(Hash)
          # Try to convert the original response to a markdown string
          markdown = []
          
          # Try to extract title
          markdown << "# #{original_response['title']}" if original_response['title']
          
          # Try to extract description
          if original_response['description']
            markdown << "\n## Description"
            markdown << original_response['description']
          end
          
          # Try to extract technical details
          if original_response['technicalDetails']
            markdown << "\n## Technical Details"
            markdown << "```"
            markdown << original_response['technicalDetails']
            markdown << "```"
          end
          
          # Try to extract root causes
          if original_response['rootCauses'] && original_response['rootCauses'].is_a?(Array)
            markdown << "\n## Root Causes & Assumptions"
            original_response['rootCauses'].each_with_index do |cause, i|
              markdown << "#{i+1}. #{cause}"
            end
          end
          
          # Try to extract suggested fixes
          if original_response['suggestedFixes'] && original_response['suggestedFixes'].is_a?(Array)
            markdown << "\n## Suggested Fixes"
            original_response['suggestedFixes'].each do |fix|
              markdown << fix
            end
          end
          
          # Try to extract acceptance criteria
          if original_response['acceptanceCriteria'] && original_response['acceptanceCriteria'].is_a?(Array)
            markdown << "\n## Acceptance Criteria"
            original_response['acceptanceCriteria'].each do |criteria|
              markdown << "- #{criteria}"
            end
          end
          
          # Try to extract story points
          if original_response['storyPoints']
            markdown << "\n## Story Points"
            markdown << original_response['storyPoints'].to_s
          end
          
          # Try to extract priority
          if original_response['priority']
            markdown << "\n## Priority"
            markdown << original_response['priority']
          end
          
          # Try to extract additional notes
          if original_response['additionalNotes']
            markdown << "\n## Additional Notes"
            markdown << original_response['additionalNotes']
          end
          
          return markdown.join("\n")
        end
        
        # If we still can't fix it, return a formatted version of the original
        "# Auto-formatted Ticket\n\n```\n#{original_response.inspect}\n```"
      rescue => e
        # If anything goes wrong in the fixing process, return a readable version of the original
        if original_response.is_a?(Hash)
          # Try to create a readable markdown from the hash
          sections = []
          original_response.each do |key, value|
            sections << "## #{key.to_s.gsub(/([A-Z])/, ' \\1').capitalize}"
            if value.is_a?(Array)
              value.each_with_index do |item, i|
                sections << "#{i+1}. #{item}"
              end
            else
              sections << value.to_s
            end
          end
          return "# Auto-formatted Ticket\n\n#{sections.join("\n\n")}"
        else
          return "Failed to format response: #{original_response.inspect}"
        end
      end
    end
  end
end