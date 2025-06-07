require 'shellwords'
require 'rbconfig'

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
        show_usage_and_unresolved
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
        result = resolve_block(block, config, lines.join("\n"))
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

        # Show summary
        accepted_count = log_entries.count { |entry| entry[:accepted] }
        skipped_count = log_entries.count { |entry| !entry[:accepted] && !entry[:abort] }

        puts "\n#{COLOR_BLUE}📊 Resolution Summary:#{COLOR_RESET}"
        puts "#{COLOR_GREEN}✅ Accepted: #{accepted_count}#{COLOR_RESET}"
        puts "#{COLOR_YELLOW}⏭️  Skipped: #{skipped_count}#{COLOR_RESET}" if skipped_count > 0

        # Only auto-mark as resolved if ALL conflicts were accepted (none skipped)
        if accepted_count > 0 && skipped_count == 0
          mark_file_as_resolved(@file_path)
          puts "#{COLOR_GREEN}🎉 All conflicts resolved! File marked as resolved in VCS.#{COLOR_RESET}"
        elsif accepted_count > 0 && skipped_count > 0
          puts "#{COLOR_YELLOW}⚠️  Some conflicts were skipped - file NOT marked as resolved#{COLOR_RESET}"
          puts "#{COLOR_GRAY}💡 Resolve remaining conflicts or manually mark: hg resolve --mark #{@file_path}#{COLOR_RESET}"
        else
          puts "#{COLOR_YELLOW}⚠️  No conflicts were accepted - file NOT marked as resolved#{COLOR_RESET}"
        end
      else
        puts "\n#{COLOR_YELLOW}⚠️  Resolution aborted - no changes made#{COLOR_RESET}"
      end

      if config['merge_log_enabled'] && log_entries.any?
        dir = '.n2b_merge_log'
        FileUtils.mkdir_p(dir)
        timestamp = Time.now.strftime('%Y-%m-%d-%H%M%S')
        log_path = File.join(dir, "#{timestamp}.json")
        File.write(log_path, JSON.pretty_generate({file: @file_path, timestamp: Time.now, entries: log_entries}))
        puts "#{COLOR_GRAY}📝 Merge log saved to #{log_path}#{COLOR_RESET}"
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

    def resolve_block(block, config, full_file_content)
      comment = nil

      # Display file and line information
      puts "\n#{COLOR_BLUE}📁 File: #{@file_path}#{COLOR_RESET}"
      puts "#{COLOR_BLUE}📍 Lines: #{block.start_line}-#{block.end_line} (#{block.base_label} ↔ #{block.incoming_label})#{COLOR_RESET}"
      puts "#{COLOR_GRAY}💡 You can check this conflict in your editor at the specified line numbers#{COLOR_RESET}\n"

      puts "#{COLOR_YELLOW}🤖 AI is analyzing the conflict...#{COLOR_RESET}"
      suggestion = request_merge_with_spinner(block, config, comment, full_file_content)
      puts "#{COLOR_GREEN}✅ Initial suggestion ready!#{COLOR_RESET}\n"

      loop do
        print_conflict(block)
        print_suggestion(suggestion)
        print "#{COLOR_YELLOW}Accept [y], Skip [n], Comment [c], Edit [e], Abort [a] (explicit choice required): #{COLOR_RESET}"
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
          # Re-read file content in case it was edited previously
          fresh_file_content = File.read(@file_path)
          suggestion = request_merge_with_spinner(block, config, comment, fresh_file_content)
          puts "#{COLOR_GREEN}✅ New suggestion ready!#{COLOR_RESET}\n"
        when 'e'
          edit_result = handle_editor_workflow(block, config, full_file_content)
          if edit_result[:resolved]
            return {accepted: true, merged_code: edit_result[:merged_code], reason: edit_result[:reason], comment: comment}
          elsif edit_result[:updated_content]
            # File was changed but conflict not resolved, update content for future LLM calls
            full_file_content = edit_result[:updated_content]
          end
          # Continue the loop with potentially updated content
        when 'a'
          return {abort: true, merged_code: suggestion['merged_code'], reason: suggestion['reason'], comment: comment}
        when '', nil
          puts "#{COLOR_RED}Please enter a valid choice: y/n/c/e/a#{COLOR_RESET}"
        else
          puts "#{COLOR_RED}Invalid option. Please enter: y (accept), n (skip), c (comment), e (edit), or a (abort)#{COLOR_RESET}"
        end
      end
    end

    def request_merge(block, config, comment, full_file_content)
      prompt = build_merge_prompt(block, comment, full_file_content)
      json_str = call_llm_for_merge(prompt, config)

      begin
        parsed = JSON.parse(extract_json(json_str))

        # Validate the response structure
        unless parsed.is_a?(Hash) && parsed.key?('merged_code') && parsed.key?('reason')
          raise JSON::ParserError, "Response missing required keys 'merged_code' and 'reason'"
        end

        parsed
      rescue JSON::ParserError => e
        # First try automatic JSON repair
        puts "#{COLOR_YELLOW}⚠️  Invalid JSON detected, attempting automatic repair...#{COLOR_RESET}"
        repaired_response = attempt_json_repair(json_str, config)

        if repaired_response
          puts "#{COLOR_GREEN}✅ JSON repair successful!#{COLOR_RESET}"
          return repaired_response
        else
          puts "#{COLOR_RED}❌ JSON repair failed#{COLOR_RESET}"
          handle_invalid_llm_response(json_str, e, block)
        end
      end
    end

    def request_merge_with_spinner(block, config, comment, full_file_content)
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
        result = request_merge(block, config, comment, full_file_content)
        spinner_thread.kill
        print "\r#{' ' * 20}\r"  # Clear the spinner line
        result
      rescue => e
        spinner_thread.kill
        print "\r#{' ' * 20}\r"  # Clear the spinner line
        { 'merged_code' => '', 'reason' => "Error: #{e.message}" }
      end
    end

    def build_merge_prompt(block, comment, full_file_content)
      config = get_config(reconfigure: false, advanced_flow: false)
      template_path = resolve_template_path('merge_conflict_prompt', config)
      template = File.read(template_path)

      user_comment_text = comment && !comment.empty? ? "User comment: #{comment}" : ""

      template.gsub('{full_file_content}', full_file_content.to_s)
              .gsub('{context_before}', block.context_before.to_s)
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
      puts "\n#{COLOR_RED}❌ LLM API Error#{COLOR_RESET}"
      puts "#{COLOR_YELLOW}Failed to communicate with the AI service.#{COLOR_RESET}"
      puts "#{COLOR_GRAY}Error: #{e.message}#{COLOR_RESET}"

      # Check for common error types and provide specific guidance
      if e.message.include?('model') || e.message.include?('Model') || e.message.include?('invalid') || e.message.include?('not found')
        puts "\n#{COLOR_BLUE}💡 This looks like a model configuration issue.#{COLOR_RESET}"
        puts "#{COLOR_YELLOW}Run 'n2b -c' to reconfigure your model settings.#{COLOR_RESET}"
      elsif e.message.include?('auth') || e.message.include?('unauthorized') || e.message.include?('401')
        puts "\n#{COLOR_BLUE}💡 This looks like an authentication issue.#{COLOR_RESET}"
        puts "#{COLOR_YELLOW}Check your API key configuration with 'n2b -c'.#{COLOR_RESET}"
      elsif e.message.include?('timeout') || e.message.include?('network')
        puts "\n#{COLOR_BLUE}💡 This looks like a network issue.#{COLOR_RESET}"
        puts "#{COLOR_YELLOW}Check your internet connection and try again.#{COLOR_RESET}"
      end

      '{"merged_code":"","reason":"LLM API error: ' + e.message.gsub('"', '\\"') + '"}'
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

    def handle_invalid_llm_response(raw_response, error, block)
      puts "\n#{COLOR_RED}❌ Invalid LLM Response Error#{COLOR_RESET}"
      puts "#{COLOR_YELLOW}The AI returned an invalid response that couldn't be parsed.#{COLOR_RESET}"
      puts "#{COLOR_YELLOW}Automatic JSON repair was attempted but failed.#{COLOR_RESET}"
      puts "#{COLOR_GRAY}Error: #{error.message}#{COLOR_RESET}"

      # Save problematic response for debugging
      save_debug_response(raw_response, error)

      # Show truncated raw response for debugging
      truncated_response = raw_response.length > 200 ? "#{raw_response[0..200]}..." : raw_response
      puts "\n#{COLOR_GRAY}Raw response (truncated):#{COLOR_RESET}"
      puts "#{COLOR_GRAY}#{truncated_response}#{COLOR_RESET}"

      puts "\n#{COLOR_BLUE}What would you like to do?#{COLOR_RESET}"
      puts "#{COLOR_GREEN}[r]#{COLOR_RESET} Retry with the same prompt"
      puts "#{COLOR_YELLOW}[c]#{COLOR_RESET} Add a comment to guide the AI better"
      puts "#{COLOR_BLUE}[m]#{COLOR_RESET} Manually choose one side of the conflict"
      puts "#{COLOR_RED}[s]#{COLOR_RESET} Skip this conflict"
      puts "#{COLOR_RED}[a]#{COLOR_RESET} Abort entirely"

      loop do
        print "#{COLOR_YELLOW}Choose action [r/c/m/s/a]: #{COLOR_RESET}"
        choice = $stdin.gets&.strip&.downcase

        case choice
        when 'r'
          puts "#{COLOR_YELLOW}🔄 Retrying with same prompt...#{COLOR_RESET}"
          return retry_llm_request(block)
        when 'c'
          puts "#{COLOR_YELLOW}💬 Please provide guidance for the AI:#{COLOR_RESET}"
          comment = read_multiline_input
          return retry_llm_request_with_comment(block, comment)
        when 'm'
          return handle_manual_choice(block)
        when 's'
          puts "#{COLOR_YELLOW}⏭️  Skipping this conflict#{COLOR_RESET}"
          return { 'merged_code' => '', 'reason' => 'Skipped due to invalid LLM response' }
        when 'a'
          puts "#{COLOR_RED}🛑 Aborting merge resolution#{COLOR_RESET}"
          return { 'merged_code' => '', 'reason' => 'Aborted due to invalid LLM response', 'abort' => true }
        when '', nil
          puts "#{COLOR_RED}Please enter a valid choice: r/c/m/s/a#{COLOR_RESET}"
        else
          puts "#{COLOR_RED}Invalid option. Please enter: r (retry), c (comment), m (manual), s (skip), or a (abort)#{COLOR_RESET}"
        end
      end
    end

    def retry_llm_request(block)
      config = get_config(reconfigure: false, advanced_flow: false)
      # Always re-read file content in case it was edited
      full_file_content = File.read(@file_path)

      puts "#{COLOR_YELLOW}🤖 Retrying AI analysis...#{COLOR_RESET}"
      suggestion = request_merge_with_spinner(block, config, nil, full_file_content)
      puts "#{COLOR_GREEN}✅ Retry successful!#{COLOR_RESET}"
      suggestion
    rescue => e
      puts "#{COLOR_RED}❌ Retry failed: #{e.message}#{COLOR_RESET}"
      { 'merged_code' => '', 'reason' => 'Retry failed due to persistent LLM error' }
    end

    def retry_llm_request_with_comment(block, comment)
      config = get_config(reconfigure: false, advanced_flow: false)
      # Always re-read file content in case it was edited
      full_file_content = File.read(@file_path)

      puts "#{COLOR_YELLOW}🤖 Retrying with your guidance...#{COLOR_RESET}"
      suggestion = request_merge_with_spinner(block, config, comment, full_file_content)
      puts "#{COLOR_GREEN}✅ Retry with comment successful!#{COLOR_RESET}"
      suggestion
    rescue => e
      puts "#{COLOR_RED}❌ Retry with comment failed: #{e.message}#{COLOR_RESET}"
      { 'merged_code' => '', 'reason' => 'Retry with comment failed due to persistent LLM error' }
    end

    def handle_manual_choice(block)
      puts "\n#{COLOR_BLUE}Manual conflict resolution:#{COLOR_RESET}"
      puts "#{COLOR_RED}[1] Choose HEAD version (#{block.base_label})#{COLOR_RESET}"
      puts "#{COLOR_RED}#{block.base_content}#{COLOR_RESET}"
      puts ""
      puts "#{COLOR_GREEN}[2] Choose incoming version (#{block.incoming_label})#{COLOR_RESET}"
      puts "#{COLOR_GREEN}#{block.incoming_content}#{COLOR_RESET}"
      puts ""
      puts "#{COLOR_YELLOW}[3] Skip this conflict#{COLOR_RESET}"

      loop do
        print "#{COLOR_YELLOW}Choose version [1/2/3]: #{COLOR_RESET}"
        choice = $stdin.gets&.strip

        case choice
        when '1'
          puts "#{COLOR_GREEN}✅ Selected HEAD version#{COLOR_RESET}"
          return {
            'merged_code' => block.base_content,
            'reason' => "Manually selected HEAD version (#{block.base_label}) due to LLM error"
          }
        when '2'
          puts "#{COLOR_GREEN}✅ Selected incoming version#{COLOR_RESET}"
          return {
            'merged_code' => block.incoming_content,
            'reason' => "Manually selected incoming version (#{block.incoming_label}) due to LLM error"
          }
        when '3'
          puts "#{COLOR_YELLOW}⏭️  Skipping conflict#{COLOR_RESET}"
          return { 'merged_code' => '', 'reason' => 'Manually skipped due to LLM error' }
        when '', nil
          puts "#{COLOR_RED}Please enter 1, 2, or 3#{COLOR_RESET}"
        else
          puts "#{COLOR_RED}Invalid choice. Please enter 1 (HEAD), 2 (incoming), or 3 (skip)#{COLOR_RESET}"
        end
      end
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
      puts "#{COLOR_RED}<<<<<<< #{block.base_label} (lines #{block.start_line}-#{block.end_line})#{COLOR_RESET}"
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

    def mark_file_as_resolved(file_path)
      # Detect VCS and mark file as resolved
      if File.exist?('.hg')
        result = execute_vcs_command_with_timeout("hg resolve --mark #{Shellwords.escape(file_path)}", 10)
        if result[:success]
          puts "#{COLOR_GREEN}✅ Marked #{file_path} as resolved in Mercurial#{COLOR_RESET}"
        else
          puts "#{COLOR_YELLOW}⚠️  Could not mark #{file_path} as resolved in Mercurial#{COLOR_RESET}"
          puts "#{COLOR_GRAY}Error: #{result[:error]}#{COLOR_RESET}" if result[:error]
          puts "#{COLOR_GRAY}💡 You can manually mark it with: hg resolve --mark #{file_path}#{COLOR_RESET}"
        end
      elsif File.exist?('.git')
        result = execute_vcs_command_with_timeout("git add #{Shellwords.escape(file_path)}", 10)
        if result[:success]
          puts "#{COLOR_GREEN}✅ Added #{file_path} to Git staging area#{COLOR_RESET}"
        else
          puts "#{COLOR_YELLOW}⚠️  Could not add #{file_path} to Git staging area#{COLOR_RESET}"
          puts "#{COLOR_GRAY}Error: #{result[:error]}#{COLOR_RESET}" if result[:error]
          puts "#{COLOR_GRAY}💡 You can manually add it with: git add #{file_path}#{COLOR_RESET}"
        end
      else
        puts "#{COLOR_BLUE}ℹ️  No VCS detected - file saved but not marked as resolved#{COLOR_RESET}"
      end
    end

<<<<<<< HEAD
=======
    def execute_vcs_command_with_timeout(command, timeout_seconds)
      require 'open3'

      begin
        # Use Open3.popen3 with manual timeout handling to avoid thread issues
        stdin, stdout, stderr, wait_thr = Open3.popen3(command)
        stdin.close

        # Wait for the process with timeout
        if wait_thr.join(timeout_seconds)
          # Process completed within timeout
          stdout_content = stdout.read
          stderr_content = stderr.read
          status = wait_thr.value

          stdout.close
          stderr.close

          if status.success?
            { success: true, stdout: stdout_content, stderr: stderr_content }
          else
            { success: false, error: "Command failed: #{stderr_content.strip}", stdout: stdout_content, stderr: stderr_content }
          end
        else
          # Process timed out, kill it
          Process.kill('TERM', wait_thr.pid) rescue nil
          sleep(0.1)
          Process.kill('KILL', wait_thr.pid) rescue nil

          stdout.close rescue nil
          stderr.close rescue nil
          wait_thr.join rescue nil

          { success: false, error: "Command timed out after #{timeout_seconds} seconds" }
        end
      rescue => e
        { success: false, error: "Unexpected error: #{e.message}" }
      end
    end
    def show_usage_and_unresolved
      puts "Usage: n2b-diff FILE [--context N]"
      puts ""

      # Show unresolved conflicts if in a VCS repository
      if File.exist?('.hg')
        puts "#{COLOR_BLUE}📋 Unresolved conflicts in Mercurial:#{COLOR_RESET}"
        result = execute_vcs_command_with_timeout("hg resolve --list", 5)

        if result[:success]
          unresolved_files = result[:stdout].lines.select { |line| line.start_with?('U ') }

          if unresolved_files.any?
            unresolved_files.each do |line|
              file = line.strip.sub(/^U /, '')
              puts "  #{COLOR_RED}❌ #{file}#{COLOR_RESET}"
            end
            puts ""
            puts "#{COLOR_YELLOW}💡 Use: n2b-diff <filename> to resolve conflicts#{COLOR_RESET}"
          else
            puts "  #{COLOR_GREEN}✅ No unresolved conflicts#{COLOR_RESET}"
          end
        else
          puts "  #{COLOR_YELLOW}⚠️  Could not check Mercurial status: #{result[:error]}#{COLOR_RESET}"
        end
      elsif File.exist?('.git')
        puts "#{COLOR_BLUE}📋 Unresolved conflicts in Git:#{COLOR_RESET}"
        result = execute_vcs_command_with_timeout("git diff --name-only --diff-filter=U", 5)

        if result[:success]
          unresolved_files = result[:stdout].lines

          if unresolved_files.any?
            unresolved_files.each do |file|
              puts "  #{COLOR_RED}❌ #{file.strip}#{COLOR_RESET}"
            end
            puts ""
            puts "#{COLOR_YELLOW}💡 Use: n2b-diff <filename> to resolve conflicts#{COLOR_RESET}"
          else
            puts "  #{COLOR_GREEN}✅ No unresolved conflicts#{COLOR_RESET}"
          end
        else
          puts "  #{COLOR_YELLOW}⚠️  Could not check Git status: #{result[:error]}#{COLOR_RESET}"
        end
      end
    end

    def attempt_json_repair(malformed_response, config)
      repair_prompt = build_json_repair_prompt(malformed_response)

      begin
        puts "#{COLOR_BLUE}🔧 Asking AI to fix the JSON...#{COLOR_RESET}"
        repaired_json_str = call_llm_for_merge(repair_prompt, config)

        # Try to parse the repaired response
        parsed = JSON.parse(extract_json(repaired_json_str))

        # Validate the repaired response structure
        if parsed.is_a?(Hash) && parsed.key?('merged_code') && parsed.key?('reason')
          return parsed
        else
          puts "#{COLOR_YELLOW}⚠️  Repaired JSON missing required keys#{COLOR_RESET}"
          return nil
        end
      rescue JSON::ParserError => e
        puts "#{COLOR_YELLOW}⚠️  JSON repair attempt also returned invalid JSON#{COLOR_RESET}"
        return nil
      rescue => e
        puts "#{COLOR_YELLOW}⚠️  JSON repair failed: #{e.message}#{COLOR_RESET}"
        return nil
      end
    end

    def build_json_repair_prompt(malformed_response)
      <<~PROMPT
        The following response was supposed to be valid JSON with keys "merged_code" and "reason", but it has formatting issues. Please fix it and return ONLY the corrected JSON:

        Original response:
        #{malformed_response}

        Requirements:
        - Must be valid JSON
        - Must have "merged_code" key with the code content
        - Must have "reason" key with explanation
        - Return ONLY the JSON, no other text

        Fixed JSON:
      PROMPT
    end

    def handle_editor_workflow(block, config, full_file_content)
      original_content = File.read(@file_path)

      puts "#{COLOR_BLUE}🔧 Opening #{@file_path} in editor...#{COLOR_RESET}"
      open_file_in_editor(@file_path)
      puts "#{COLOR_BLUE}📁 Editor closed. Checking for changes...#{COLOR_RESET}"

      current_content = File.read(@file_path)

      if file_changed?(original_content, current_content)
        puts "#{COLOR_YELLOW}📝 File has been modified.#{COLOR_RESET}"
        print "#{COLOR_YELLOW}Did you resolve this conflict yourself? [y/n]: #{COLOR_RESET}"
        response = $stdin.gets&.strip&.downcase

        if response == 'y'
          puts "#{COLOR_GREEN}✅ Conflict marked as resolved by user#{COLOR_RESET}"
          return {
            resolved: true,
            merged_code: "user_resolved",
            reason: "User resolved conflict manually in editor"
          }
        else
          puts "#{COLOR_BLUE}🔄 Continuing with AI assistance...#{COLOR_RESET}"
          return {
            resolved: false,
            updated_content: current_content
          }
        end
      else
        puts "#{COLOR_GRAY}📋 No changes detected. Continuing...#{COLOR_RESET}"
        return {resolved: false, updated_content: nil}
      end
    end

    def detect_editor
      ENV['EDITOR'] || ENV['VISUAL'] || detect_system_editor
    end

    def detect_system_editor
      case RbConfig::CONFIG['host_os']
      when /darwin|mac os/
        'open'
      when /linux/
        'nano'
      when /mswin|mingw/
        'notepad'
      else
        'vi'
      end
    end

    def open_file_in_editor(file_path)
      editor = detect_editor

      begin
        case editor
        when 'open'
          # macOS: open with default application (non-blocking)
          result = execute_vcs_command_with_timeout("open #{Shellwords.escape(file_path)}", 5)
          unless result[:success]
            puts "#{COLOR_YELLOW}⚠️  Could not open with 'open' command: #{result[:error]}#{COLOR_RESET}"
            puts "#{COLOR_BLUE}💡 Please open #{file_path} manually in your editor#{COLOR_RESET}"
          end
        else
          # Other editors: open directly (blocking)
          puts "#{COLOR_BLUE}🔧 Opening with #{editor}...#{COLOR_RESET}"
          system("#{editor} #{Shellwords.escape(file_path)}")
        end
      rescue => e
        puts "#{COLOR_RED}❌ Failed to open editor: #{e.message}#{COLOR_RESET}"
        puts "#{COLOR_YELLOW}💡 Try setting EDITOR environment variable to your preferred editor#{COLOR_RESET}"
      end
    end

    def file_changed?(original_content, current_content)
      original_content != current_content
    end

    def save_debug_response(raw_response, error)
      begin
        debug_dir = '.n2b_debug'
        FileUtils.mkdir_p(debug_dir)
        timestamp = Time.now.strftime('%Y-%m-%d-%H%M%S')
        debug_file = File.join(debug_dir, "invalid_response_#{timestamp}.txt")

        debug_content = <<~DEBUG
          N2B Debug: Invalid LLM Response
          ===============================
          Timestamp: #{Time.now}
          File: #{@file_path}
          Error: #{error.message}
          Error Class: #{error.class}

          Raw LLM Response:
          -----------------
          #{raw_response}

          End of Response
          ===============
        DEBUG

        File.write(debug_file, debug_content)
        puts "#{COLOR_GRAY}🐛 Debug info saved to #{debug_file}#{COLOR_RESET}"
      rescue => e
        puts "#{COLOR_GRAY}⚠️  Could not save debug info: #{e.message}#{COLOR_RESET}"
      end
    end
  end
end
