module N2B
  class MergeCLI < Base
    COLOR_RED   = "\e[31m"
    COLOR_GREEN = "\e[32m"
    COLOR_YELLOW= "\e[33m"
    COLOR_BLUE  = "\e[34m"
    COLOR_GRAY  = "\e[90m"
    COLOR_RESET = "\e[0m"

    def self.run(args)
      new(args).execute
    end

    def initialize(args)
      @args = args
      @options = parse_options
      @file_path = @args.shift
    end

    def execute
      if @file_path.nil?
        puts "Usage: n2b-diff FILE [--context N]"
        exit 1
      end

      unless File.exist?(@file_path)
        puts "File not found: #{@file_path}"
        exit 1
      end

      config = get_config(reconfigure: false, advanced_flow: false)

      parser = MergeConflictParser.new(context_lines: @options[:context_lines])
      blocks = parser.parse(@file_path)
      if blocks.empty?
        puts "No merge conflicts found."
        return
      end

      lines = File.readlines(@file_path, chomp: true)
      log_entries = []
      aborted = false

      blocks.reverse_each do |block|
        result = resolve_block(block, config)
        log_entries << result.merge({
          base_content: block.base_content,
          incoming_content: block.incoming_content,
          base_label: block.base_label,
          incoming_label: block.incoming_label
        })
        if result[:abort]
          aborted = true
          break
        elsif result[:accepted]
          replacement = result[:merged_code].to_s.split("\n")
          lines[(block.start_line-1)...block.end_line] = replacement
        end
      end

      unless aborted
        File.write(@file_path, lines.join("\n") + "\n")
      end

      if config['merge_log_enabled'] && log_entries.any?
        dir = '.n2b_merge_log'
        FileUtils.mkdir_p(dir)
        timestamp = Time.now.strftime('%Y-%m-%d-%H%M%S')
        log_path = File.join(dir, "#{timestamp}.json")
        File.write(log_path, JSON.pretty_generate({file: @file_path, timestamp: Time.now, entries: log_entries}))
      end
    end

    private

    def parse_options
      options = { context_lines: MergeConflictParser::DEFAULT_CONTEXT_LINES }
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: n2b-diff FILE [options]'
        opts.on('--context N', Integer, 'Context lines (default: 10)') { |v| options[:context_lines] = v }
        opts.on('-h', '--help', 'Show this help') { puts opts; exit }
      end
      parser.parse!(@args)
      options
    end

    def resolve_block(block, config)
      comment = nil
      suggestion = request_merge(block, config, comment)

      loop do
        print_conflict(block)
        print_suggestion(suggestion)
        print "#{COLOR_YELLOW}Accept [y], Skip [n], Comment [c], Abort [a] (explicit choice required): #{COLOR_RESET}"
        choice = $stdin.gets&.strip&.downcase

        case choice
        when 'y'
          return {accepted: true, merged_code: suggestion['merged_code'], reason: suggestion['reason'], comment: comment}
        when 'n'
          return {accepted: false, merged_code: suggestion['merged_code'], reason: suggestion['reason'], comment: comment}
        when 'c'
          puts 'Enter comment (end with blank line):'
          comment = read_multiline_input
          puts "#{COLOR_YELLOW}🤖 AI is analyzing your comment and generating new suggestion...#{COLOR_RESET}"
          suggestion = request_merge_with_spinner(block, config, comment)
          puts "#{COLOR_GREEN}✅ New suggestion ready!#{COLOR_RESET}\n"
        when 'a'
          return {abort: true, merged_code: suggestion['merged_code'], reason: suggestion['reason'], comment: comment}
        when '', nil
          puts "#{COLOR_RED}Please enter a valid choice: y/n/c/a#{COLOR_RESET}"
        else
          puts "#{COLOR_RED}Invalid option. Please enter: y (accept), n (skip), c (comment), or a (abort)#{COLOR_RESET}"
        end
      end
    end

    def request_merge(block, config, comment)
      prompt = build_merge_prompt(block, comment)
      json_str = call_llm_for_merge(prompt, config)
      begin
        parsed = JSON.parse(extract_json(json_str))
        parsed
      rescue JSON::ParserError
        { 'merged_code' => '', 'reason' => 'Invalid LLM response' }
      end
    end

    def request_merge_with_spinner(block, config, comment)
      spinner_chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
      spinner_thread = Thread.new do
        i = 0
        while true
          print "\r#{COLOR_BLUE}#{spinner_chars[i % spinner_chars.length]} Processing...#{COLOR_RESET}"
          $stdout.flush
          sleep(0.1)
          i += 1
        end
      end

      begin
        result = request_merge(block, config, comment)
        spinner_thread.kill
        print "\r#{' ' * 20}\r"  # Clear the spinner line
        result
      rescue => e
        spinner_thread.kill
        print "\r#{' ' * 20}\r"  # Clear the spinner line
        { 'merged_code' => '', 'reason' => "Error: #{e.message}" }
      end
    end

    def build_merge_prompt(block, comment)
      config = get_config(reconfigure: false, advanced_flow: false)
      template_path = resolve_template_path('merge_conflict_prompt', config)
      template = File.read(template_path)

      user_comment_text = comment && !comment.empty? ? "User comment: #{comment}" : ""

      template.gsub('{context_before}', block.context_before.to_s)
              .gsub('{base_label}', block.base_label.to_s)
              .gsub('{base_content}', block.base_content.to_s)
              .gsub('{incoming_content}', block.incoming_content.to_s)
              .gsub('{incoming_label}', block.incoming_label.to_s)
              .gsub('{context_after}', block.context_after.to_s)
              .gsub('{user_comment}', user_comment_text)
    end

    def call_llm_for_merge(prompt, config)
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
              raise N2B::Error, "Unsupported LLM service: #{llm_service_name}"
            end
      llm.analyze_code_diff(prompt)
    rescue N2B::LlmApiError => e
      puts "Error communicating with the LLM: #{e.message}"
      '{"merged_code":"","reason":"LLM API error"}'
    end

    def extract_json(response)
      JSON.parse(response)
      response
    rescue JSON::ParserError
      start = response.index('{')
      stop = response.rindex('}')
      return response unless start && stop
      response[start..stop]
    end

    def read_multiline_input
      lines = []
      puts "#{COLOR_GRAY}(Type your comment, then press Enter on an empty line to finish)#{COLOR_RESET}"
      while (line = $stdin.gets)
        line = line.chomp
        break if line.empty?
        lines << line
      end
      comment = lines.join("\n")
      if comment.empty?
        puts "#{COLOR_YELLOW}No comment entered.#{COLOR_RESET}"
      else
        puts "#{COLOR_GREEN}Comment received: #{comment.length} characters#{COLOR_RESET}"
      end
      comment
    end

    def print_conflict(block)
      puts "#{COLOR_RED}<<<<<<< #{block.base_label}#{COLOR_RESET}"
      puts "#{COLOR_RED}#{block.base_content}#{COLOR_RESET}"
      puts "#{COLOR_YELLOW}=======#{COLOR_RESET}"
      puts "#{COLOR_GREEN}#{block.incoming_content}#{COLOR_RESET}"
      puts "#{COLOR_YELLOW}>>>>>>> #{block.incoming_label}#{COLOR_RESET}"
    end

    def print_suggestion(sug)
      puts "#{COLOR_BLUE}--- Suggestion ---#{COLOR_RESET}"
      puts "#{COLOR_BLUE}#{sug['merged_code']}#{COLOR_RESET}"
      puts "#{COLOR_GRAY}Reason: #{sug['reason']}#{COLOR_RESET}"
    end

    def resolve_template_path(template_key, config)
      user_path = config.dig('templates', template_key) if config.is_a?(Hash)
      return user_path if user_path && File.exist?(user_path)

      File.expand_path(File.join(__dir__, 'templates', "#{template_key}.txt"))
    end
  end
end
