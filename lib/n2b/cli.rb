module N2B 
  class CLI < Base
    def self.run(args)
      new(args).execute
    end

    def initialize(args)
      @args = args
      @options = parse_options
    end

    def execute
      config = get_config(reconfigure: @options[:config])
      user_input = @args.join(' ') # All remaining args form user input/prompt addition

      if @options[:diff]
        handle_diff_analysis(config)
      elsif user_input.empty? # No input text after options
        puts "Enter your natural language command:"
        input_text = $stdin.gets.chomp
        process_natural_language_command(input_text, config)
      else # Natural language command
        process_natural_language_command(user_input, config)
      end
    end

    protected

    def handle_diff_analysis(config)
      vcs_type = get_vcs_type
      if vcs_type == :none
        puts "Error: Not a git or hg repository."
        exit 1
      end

      # Get requirements file from parsed options
      requirements_filepath = @options[:requirements]
      user_prompt_addition = @args.join(' ') # All remaining args are user prompt addition

      requirements_content = nil
      if requirements_filepath
        unless File.exist?(requirements_filepath)
          puts "Error: Requirements file not found: #{requirements_filepath}"
          exit 1
        end
        requirements_content = File.read(requirements_filepath)
      end

      diff_output = execute_vcs_diff(vcs_type, @options[:branch])
      analyze_diff(diff_output, config, user_prompt_addition, requirements_content)
    end

    def get_vcs_type
      if Dir.exist?(File.join(Dir.pwd, '.git'))
        :git
      elsif Dir.exist?(File.join(Dir.pwd, '.hg'))
        :hg
      else
        :none
      end
    end

    def execute_vcs_diff(vcs_type, branch_option = nil)
      case vcs_type
      when :git
        if branch_option
          target_branch = branch_option == 'auto' ? detect_git_default_branch : branch_option
          if target_branch
            # Validate that the target branch exists
            unless validate_git_branch_exists(target_branch)
              puts "Error: Branch '#{target_branch}' does not exist."
              puts "Available branches:"
              puts `git branch -a`.lines.map(&:strip).reject(&:empty?)
              exit 1
            end

            puts "Comparing current branch against '#{target_branch}'..."
            `git diff #{target_branch}...HEAD`
          else
            puts "Could not detect default branch, falling back to HEAD diff..."
            `git diff HEAD`
          end
        else
          `git diff HEAD`
        end
      when :hg
        if branch_option
          target_branch = branch_option == 'auto' ? detect_hg_default_branch : branch_option
          if target_branch
            # Validate that the target branch exists
            unless validate_hg_branch_exists(target_branch)
              puts "Error: Branch '#{target_branch}' does not exist."
              puts "Available branches:"
              puts `hg branches`.lines.map(&:strip).reject(&:empty?)
              exit 1
            end

            puts "Comparing current branch against '#{target_branch}'..."
            `hg diff -r #{target_branch}`
          else
            puts "Could not detect default branch, falling back to standard diff..."
            `hg diff`
          end
        else
          `hg diff`
        end
      else
        "" # Should not happen if get_vcs_type logic is correct and checked before calling
      end
    end

    def detect_git_default_branch
      # Try multiple methods to detect the default branch

      # Method 1: Check origin/HEAD symbolic ref
      result = `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null`.strip
      if $?.success? && !result.empty?
        return result.split('/').last
      end

      # Method 2: Check remote show origin
      result = `git remote show origin 2>/dev/null | grep "HEAD branch"`.strip
      if $?.success? && !result.empty?
        match = result.match(/HEAD branch:\s*(\w+)/)
        return match[1] if match
      end

      # Method 3: Check if common default branches exist
      ['main', 'master'].each do |branch|
        result = `git rev-parse --verify origin/#{branch} 2>/dev/null`
        if $?.success?
          return branch
        end
      end

      # Method 4: Fallback - check local branches
      ['main', 'master'].each do |branch|
        result = `git rev-parse --verify #{branch} 2>/dev/null`
        if $?.success?
          return branch
        end
      end

      # If all else fails, return nil
      nil
    end

    def detect_hg_default_branch
      # Method 1: Check current branch (if it's 'default', that's the main branch)
      result = `hg branch 2>/dev/null`.strip
      if $?.success? && result == 'default'
        return 'default'
      end

      # Method 2: Look for 'default' branch in branch list
      result = `hg branches 2>/dev/null`
      if $?.success? && result.include?('default')
        return 'default'
      end

      # Method 3: Check if there are any branches at all
      result = `hg branches 2>/dev/null`.strip
      if $?.success? && !result.empty?
        # Get the first branch (usually the main one)
        first_branch = result.lines.first&.split&.first
        return first_branch if first_branch
      end

      # Fallback to 'default' (standard hg main branch name)
      'default'
    end

    def validate_git_branch_exists(branch)
      # Check if branch exists locally
      result = `git rev-parse --verify #{branch} 2>/dev/null`
      return true if $?.success?

      # Check if branch exists on remote
      result = `git rev-parse --verify origin/#{branch} 2>/dev/null`
      return true if $?.success?

      false
    end

    def validate_hg_branch_exists(branch)
      # Check if branch exists in hg branches
      result = `hg branches 2>/dev/null`
      if $?.success?
        return result.lines.any? { |line| line.strip.start_with?(branch) }
      end

      # If we can't list branches, assume it exists (hg is more permissive)
      true
    end

    private

    def process_natural_language_command(input_text, config)
      bash_commands = call_llm(input_text, config)

      puts "\nTranslated #{get_user_shell} Commands:"
      puts "------------------------"
      puts bash_commands['commands']
      puts "------------------------"
      if bash_commands['explanation']
        puts "Explanation:"
        puts bash_commands['explanation']
        puts "------------------------"
      end

      if @options[:execute]
        puts "Press Enter to execute these commands, or Ctrl+C to cancel."
        $stdin.gets
        system(bash_commands['commands'].join("\n"))
      else
        add_to_shell_history(bash_commands['commands'].join("\n")) if config['append_to_shell_history']
      end
    end

    def build_diff_analysis_prompt(diff_output, user_prompt_addition = "", requirements_content = nil)
      default_system_prompt = <<-SYSTEM_PROMPT.strip
You are a senior software developer reviewing a code diff.
Your task is to provide a constructive and detailed analysis of the changes.
Focus on identifying potential bugs, suggesting improvements in code quality, style, performance, and security.
Also, provide a concise summary of the changes.

IMPORTANT: When referring to specific issues or improvements, always include:
- The exact file path (e.g., "lib/n2b/cli.rb")
- The specific line numbers or line ranges (e.g., "line 42" or "lines 15-20")
- The exact code snippet you're referring to when possible

This helps users quickly locate and understand the issues you identify.

SPECIAL FOCUS ON TEST COVERAGE:
Pay special attention to whether the developer has provided adequate test coverage for the changes:
- Look for new test files or modifications to existing test files
- Check if new functionality has corresponding tests
- Evaluate if edge cases and error conditions are tested
- Assess if the tests are meaningful and comprehensive
- Note any missing test coverage that should be added

NOTE: In addition to the diff, you will also receive the current code context around the changed areas.
This provides better understanding of the surrounding code and helps with more accurate analysis.
The user may provide additional instructions or specific requirements below.
SYSTEM_PROMPT

      user_instructions_section = ""
      unless user_prompt_addition.to_s.strip.empty?
        user_instructions_section = "User Instructions:\n#{user_prompt_addition.strip}\n\n"
      end

      requirements_section = ""
      if requirements_content && !requirements_content.to_s.strip.empty?
        requirements_section = <<-REQUIREMENTS_BLOCK
CRITICAL REQUIREMENTS EVALUATION:
You must carefully evaluate whether the code changes meet the following requirements from the ticket/task.
For each requirement, explicitly state whether it is:
- ✅ IMPLEMENTED: The requirement is fully satisfied by the changes
- ⚠️ PARTIALLY IMPLEMENTED: The requirement is partially addressed but needs more work
- ❌ NOT IMPLEMENTED: The requirement is not addressed by these changes
- 🔍 UNCLEAR: Cannot determine from the diff whether the requirement is met

--- BEGIN REQUIREMENTS ---
#{requirements_content.strip}
--- END REQUIREMENTS ---

REQUIREMENTS_BLOCK
      end

      analysis_intro = "Analyze the following diff based on the general instructions above and these specific requirements (if any):"

      # Extract context around changed lines
      context_sections = extract_code_context_from_diff(diff_output)
      context_info = ""
      unless context_sections.empty?
        context_info = "\n\nCurrent Code Context (for better analysis):\n"
        context_sections.each do |file_path, sections|
          context_info += "\n--- #{file_path} ---\n"
          sections.each do |section|
            context_info += "Lines #{section[:start_line]}-#{section[:end_line]}:\n"
            context_info += "```\n#{section[:content]}\n```\n\n"
          end
        end
      end

      json_instruction = <<-JSON_INSTRUCTION.strip
CRITICAL: Return ONLY a valid JSON object with the keys "summary", "errors" (as a list of strings), "improvements" (as a list of strings), "test_coverage" (as a string), and "requirements_evaluation" (as a string, only if requirements were provided).
Do not include any explanatory text before or after the JSON.
Each error and improvement should include specific file paths and line numbers.

Example format:
{
  "summary": "Brief description of the changes",
  "errors": [
    "lib/example.rb line 42: Potential null pointer exception when accessing user.name without checking if user is nil",
    "src/main.js lines 15-20: Missing error handling for async operation"
  ],
  "improvements": [
    "lib/example.rb line 30: Consider using a constant for the magic number 42",
    "src/utils.py lines 5-10: This method could be simplified using list comprehension"
  ],
  "test_coverage": "Good: New functionality in lib/example.rb has corresponding tests in test/example_test.rb. Missing: No tests for error handling edge cases in the new validation method.",
  "requirements_evaluation": "✅ IMPLEMENTED: User authentication feature is fully implemented in auth.rb. ⚠️ PARTIALLY IMPLEMENTED: Error handling is present but lacks specific error codes. ❌ NOT IMPLEMENTED: Email notifications are not addressed in this diff."
}
JSON_INSTRUCTION

      full_prompt = [
        default_system_prompt,
        user_instructions_section,
        requirements_section,
        analysis_intro,
        "Diff:\n```\n#{diff_output}\n```",
        context_info,
        json_instruction
      ].select { |s| s && !s.empty? }.join("\n\n") # Join non-empty sections with double newlines

      full_prompt
    end

    def analyze_diff(diff_output, config, user_prompt_addition = "", requirements_content = nil)
      prompt = build_diff_analysis_prompt(diff_output, user_prompt_addition, requirements_content)
      analysis_json_str = call_llm_for_diff_analysis(prompt, config)

      begin
        # Try to extract JSON from response that might have text before it
        json_content = extract_json_from_response(analysis_json_str)
        analysis_result = JSON.parse(json_content)

        puts "\nCode Diff Analysis:"
        puts "-------------------"
        puts "Summary:"
        puts analysis_result['summary'] || "No summary provided."
        puts "\nPotential Errors:"
        errors_list = analysis_result['errors']
        errors_list = [errors_list] if errors_list.is_a?(String) && !errors_list.empty?
        errors_list = [] if errors_list.nil? || (errors_list.is_a?(String) && errors_list.empty?)
        puts errors_list.any? ? errors_list.map{|err| "- #{err}"}.join("\n") : "No errors identified."

        puts "\nSuggested Improvements:"
        improvements_list = analysis_result['improvements']
        improvements_list = [improvements_list] if improvements_list.is_a?(String) && !improvements_list.empty?
        improvements_list = [] if improvements_list.nil? || (improvements_list.is_a?(String) && improvements_list.empty?)
        puts improvements_list.any? ? improvements_list.map{|imp| "- #{imp}"}.join("\n") : "No improvements suggested."

        puts "\nTest Coverage Assessment:"
        test_coverage = analysis_result['test_coverage']
        puts test_coverage && !test_coverage.to_s.strip.empty? ? test_coverage : "No test coverage assessment provided."

        # Show requirements evaluation if requirements were provided
        requirements_eval = analysis_result['requirements_evaluation']
        if requirements_eval && !requirements_eval.to_s.strip.empty?
          puts "\nRequirements Evaluation:"
          puts requirements_eval
        end
        puts "-------------------"
      rescue JSON::ParserError => e # Handles cases where the JSON string (even fallback) is malformed
        puts "Critical Error: Failed to parse JSON response for diff analysis: #{e.message}"
        puts "Raw response was: #{analysis_json_str}"
      end
    end

    def extract_json_from_response(response)
      # First try to parse the response as-is
      begin
        JSON.parse(response)
        return response
      rescue JSON::ParserError
        # If that fails, try to find JSON within the response
      end

      # Look for JSON object starting with { and ending with }
      json_start = response.index('{')
      return response unless json_start

      # Find the matching closing brace
      brace_count = 0
      json_end = nil
      (json_start...response.length).each do |i|
        case response[i]
        when '{'
          brace_count += 1
        when '}'
          brace_count -= 1
          if brace_count == 0
            json_end = i
            break
          end
        end
      end

      return response unless json_end

      response[json_start..json_end]
    end

    def extract_code_context_from_diff(diff_output)
      context_sections = {}
      current_file = nil

      diff_output.each_line do |line|
        line = line.chomp

        # Parse file headers (e.g., "diff --git a/lib/n2b/cli.rb b/lib/n2b/cli.rb")
        if line.start_with?('diff --git')
          # Extract file path from "diff --git a/path b/path"
          match = line.match(/diff --git a\/(.+) b\/(.+)/)
          current_file = match[2] if match # Use the "b/" path (new file)
        elsif line.start_with?('+++')
          # Alternative way to get file path from "+++ b/path"
          match = line.match(/\+\+\+ b\/(.+)/)
          current_file = match[1] if match
        elsif line.start_with?('@@') && current_file
          # Parse hunk header (e.g., "@@ -10,7 +10,8 @@")
          match = line.match(/@@ -(\d+),?\d* \+(\d+),?\d* @@/)
          if match
            old_start = match[1].to_i
            new_start = match[2].to_i

            # Use the new file line numbers for context
            context_start = [new_start - 5, 1].max  # 5 lines before, but not less than 1
            context_end = new_start + 10  # 10 lines after the start

            # Read the actual file content
            if File.exist?(current_file)
              file_lines = File.readlines(current_file)
              # Adjust end to not exceed file length
              context_end = [context_end, file_lines.length].min

              if context_start <= file_lines.length
                context_content = file_lines[(context_start-1)...context_end].map.with_index do |content, idx|
                  line_num = context_start + idx
                  "#{line_num.to_s.rjust(4)}: #{content.rstrip}"
                end.join("\n")

                context_sections[current_file] ||= []
                context_sections[current_file] << {
                  start_line: context_start,
                  end_line: context_end,
                  content: context_content
                }
              end
            end
          end
        end
      end

      context_sections
    end

    def call_llm_for_diff_analysis(prompt, config)
      begin
        llm_service_name = config['llm']
        llm = case llm_service_name
              when 'openai'
                N2M::Llm::OpenAi.new(config)
              when 'claude'
                N2M::Llm::Claude.new(config)
              when 'gemini'
                N2M::Llm::Gemini.new(config)
              else
                # Should not happen if config is validated, but as a safeguard:
                raise N2B::Error, "Unsupported LLM service: #{llm_service_name}"
              end

        response_json_str = llm.analyze_code_diff(prompt) # Call the new dedicated method
        response_json_str
      rescue N2B::LlmApiError => e # This catches errors from analyze_code_diff
        puts "Error communicating with the LLM: #{e.message}"
        return '{"summary": "Error: Could not analyze diff due to LLM API error.", "errors": [], "improvements": []}'
      end
    end
    
    def append_to_llm_history_file(commands)
      File.open(HISTORY_FILE, 'a') do |file|
        file.puts(commands)
      end
    end
    
    def read_llm_history_file
      history = File.read(HISTORY_FILE) if File.exist?(HISTORY_FILE)
      history ||= ''
      # limit to 20 most recent commands
      history.split("\n").last(20).join("\n")
    end
    
    def call_llm(prompt, config)
      begin # Added begin for LlmApiError rescue
        llm = config['llm'] == 'openai' ?   N2M::Llm::OpenAi.new(config) : N2M::Llm::Claude.new(config)

        # This content is specific to bash command generation
      content = <<-EOF
              Translate the following natural language command to bash commands: #{prompt}\n\nProvide only the #{get_user_shell} commands for #{ get_user_os }. the commands should be separated by newlines. 
              #{' the user is in directory'+Dir.pwd if config['privacy']['send_current_directory']}. 
              #{' the user sent past requests to you and got these answers '+read_llm_history_file if config['privacy']['send_llm_history'] }
              #{ "The user has this history for his shell. "+read_shell_history if config['privacy']['send_shell_history'] }
              he is using #{File.basename(get_user_shell)} shell."
              answer only with a valid json object with the key 'commands' and the value as a list of bash commands plus any additional information you want to provide in explanation.
              { "commands": [ "echo 'Hello, World!'" ], "explanation": "This command prints 'Hello, World!' to the terminal."}
              EOF
    
           
      response_json_str = llm.make_request(content)

      append_to_llm_history_file("#{prompt}\n#{response_json_str}") # Storing the raw JSON string
      # The original call_llm was expected to return a hash after JSON.parse,
      # but it was actually returning the string. Let's assume it should return a parsed Hash.
      # However, the calling method `process_natural_language_command` accesses it like `bash_commands['commands']`
      # which implies it expects a Hash. Let's ensure call_llm returns a Hash.
      # This internal JSON parsing is for the *content* of a successful LLM response.
      # The LlmApiError for network/auth issues should be caught before this.
      begin
        # Check if response_json_str is already a Hash (parsed JSON)
        if response_json_str.is_a?(Hash)
          response_json_str
        else
          parsed_response = JSON.parse(response_json_str)
          parsed_response
        end
      rescue JSON::ParserError => e
        puts "Error parsing LLM response JSON for command generation: #{e.message}"
        # This is a fallback for when the LLM response *content* is not valid JSON.
        { "commands" => ["echo 'Error: LLM returned invalid JSON content.'"], "explanation" => "The response from the language model was not valid JSON." }
      end
    rescue N2B::LlmApiError => e
      puts "Error communicating with the LLM: #{e.message}"
      # This is the fallback for LlmApiError (network, auth, etc.)
      { "commands" => ["echo 'LLM API error occurred. Please check your configuration and network.'"], "explanation" => "Failed to connect to the LLM." }
    end
    end
    
    def get_user_shell
      ENV['SHELL'] || `getent passwd #{ENV['USER']}`.split(':')[6]
    end

    def get_user_os
      case RbConfig::CONFIG['host_os']
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
      :windows
      when /darwin|mac os/
      :macos
      when /linux/
      :linux
      when /solaris|bsd/
      :unix
      else
      :unknown
      end
    end
    
    def find_history_file(shell)
      case shell
      when 'zsh'
        [
          ENV['HISTFILE'],
          File.expand_path('~/.zsh_history'),
          File.expand_path('~/.zhistory')
        ].find { |f| f && File.exist?(f) }
      when 'bash'
        [
          ENV['HISTFILE'],
          File.expand_path('~/.bash_history')
        ].find { |f| f && File.exist?(f) }
      else
        nil
      end
    end
    
    def read_shell_history()
      shell = File.basename(get_user_shell)
      history_file = find_history_file(shell)
      return '' unless history_file
    
      File.read(history_file)
    end
    
    def add_to_shell_history(commands)
      shell = File.basename(get_user_shell)
      history_file = find_history_file(shell)
    
      unless history_file
        puts "Could not find history file for #{shell}. Cannot add commands to history."
        return
      end
    
      case shell
      when 'zsh'
        add_to_zsh_history(commands, history_file)
      when 'bash'
        add_to_bash_history(commands, history_file)
      else
        puts "Unsupported shell: #{shell}. Cannot add commands to history."
        return
      end
    
      puts "Commands have been added to your #{shell} history file: #{history_file}"
      puts "You may need to start a new shell session or reload your history to see the changes. #{ shell == 'zsh' ? 'For example, run `fc -R` in your zsh session.' : 'history -r for bash' }"
      puts "Then you can access them using the up arrow key or Ctrl+R for reverse search."
    end
    
    def add_to_zsh_history(commands, history_file)
      File.open(history_file, 'a') do |file|
        commands.each_line do |cmd|
          timestamp = Time.now.to_i
          file.puts(": #{timestamp}:0;#{cmd.strip}")
        end
      end
    end
    
    def add_to_bash_history(commands, history_file)
      File.open(history_file, 'a') do |file|
        commands.each_line do |cmd|
          file.puts(cmd.strip)
        end
      end
      system("history -r") # Attempt to reload history in current session
    end
    

    def parse_options
      options = { execute: false, config: nil, diff: false, requirements: nil, branch: nil }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: n2b [options] [natural language command]"

        opts.on('-x', '--execute', 'Execute the commands after confirmation') do
          options[:execute] = true
        end

        opts.on('-d', '--diff', 'Analyze git/hg diff with AI') do
          options[:diff] = true
        end

        opts.on('-b', '--branch [BRANCH]', 'Compare against branch (default: auto-detect main/master)') do |branch|
          options[:branch] = branch || 'auto'
        end

        opts.on('-r', '--requirements FILE', 'Requirements file for diff analysis') do |file|
          options[:requirements] = file
        end

        opts.on('-h', '--help', 'Print this help') do
          puts opts
          exit
        end

        opts.on('-c', '--config', 'Configure the API key and model') do
          options[:config] = true
        end
      end

      begin
        parser.parse!(@args)
      rescue OptionParser::InvalidOption => e
        puts "Error: #{e.message}"
        puts ""
        puts parser.help
        exit 1
      end

      # Validate option combinations
      if options[:branch] && !options[:diff]
        puts "Error: --branch option can only be used with --diff"
        puts ""
        puts parser.help
        exit 1
      end

      options
    end
  end
end