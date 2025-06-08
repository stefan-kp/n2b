require 'shellwords'
require 'rbconfig'
require_relative 'jira_client'
require_relative 'github_client'
require_relative 'message_utils'

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
      # @file_path = @args.shift # Moved to execute based on mode
    end

    def execute
      config = get_config(reconfigure: false, advanced_flow: false)

      if @options[:analyze]
        # In analyze mode, @args might be used for custom prompt additions later,
        # similar to how original cli.rb handled it.
        # For now, custom_message option is the primary way.
        handle_diff_analysis(config)
      else
        @file_path = @args.shift
        if @file_path.nil?
          show_help_and_status # Renamed from show_usage_and_unresolved
          exit 1
        end

        unless File.exist?(@file_path)
          puts "File not found: #{@file_path}"
          exit 1
        end

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
          incoming_label: block.incoming_label,
          start_line: block.start_line,
          end_line: block.end_line,
          resolved_content: result[:merged_code],
          llm_suggestion: result[:reason],
          resolution_method: determine_resolution_method(result),
          action: determine_action(result),
          timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S UTC')
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
        log_path = File.join(dir, "#{timestamp}.html")
        html_content = generate_merge_log_html(log_entries, timestamp)
        File.write(log_path, html_content)
        puts "#{COLOR_GRAY}📝 Merge log saved to #{log_path}#{COLOR_RESET}"
      end
      end
    end

    private

    def parse_options
      options = {
        context_lines: MergeConflictParser::DEFAULT_CONTEXT_LINES,
        analyze: false,
        branch: nil,
        jira_ticket: nil,
        github_issue: nil,
        requirements_file: nil,
        update_issue: nil, # nil means ask, true means update, false means no update
        custom_message: nil
      }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: n2b-diff FILE [options] OR n2b-diff --analyze [options]"
        opts.separator ""
        opts.separator "Merge Conflict Options:"
        opts.on('--context N', Integer, 'Context lines for merge conflict analysis (default: 10, affects LLM context)') { |v| options[:context_lines] = v }

        opts.separator ""
        opts.separator "Diff Analysis Options:"
        opts.on('-a', '--analyze', 'Analyze git/hg diff with AI') { options[:analyze] = true }
        opts.on('--branch [BRANCH]', 'Branch to compare against for analysis (default: auto-detect main/master)') do |branch|
          options[:branch] = branch || 'auto' # 'auto' will trigger detection logic
        end
        opts.on('-j', '--jira JIRA_ID_OR_URL', 'Jira ticket ID or URL for context or update') do |jira|
          options[:jira_ticket] = jira
        end
        opts.on('--github GITHUB_ISSUE_ID_OR_URL', 'GitHub issue ID or URL for context or update (e.g., owner/repo/issues/123)') do |gh|
          options[:github_issue] = gh
        end
        opts.on('-r', '--requirements FILEPATH', 'Requirements file for diff analysis context') do |file|
          options[:requirements_file] = file
        end
        opts.on('--update', 'Attempt to update the linked Jira/GitHub issue with the analysis result (will ask for confirmation by default)') do
          options[:update_issue] = true # Explicitly true
        end
        opts.on('--no-update', 'Do not attempt to update the linked Jira/GitHub issue') do
          options[:update_issue] = false # Explicitly false
        end
        opts.on('-m', '--message MESSAGE', '--msg MESSAGE', String, 'Custom instructions for AI analysis (max 500 chars)') do |raw_msg|
          validated_msg = N2B::MessageUtils.validate_message(raw_msg)
          # Sanitization happens after validation (e.g. truncation)
          # No need to log here, will log after all options parsed if message exists
          options[:custom_message] = validated_msg # Store potentially truncated message
        end

        opts.separator ""
        opts.separator "Common Options:"
        opts.on_tail('-h', '--help', 'Show this help message') { puts opts; exit }
        opts.on_tail('-v', '--version', 'Show version') { puts N2B::VERSION; exit } # Assuming VERSION is defined

        opts.separator ""
        opts.separator "Examples:"
        opts.separator "  n2b-diff path/to/your/file_with_conflicts.rb"
        opts.separator "  n2b-diff --analyze"
        opts.separator "  n2b-diff --analyze --branch main"
        opts.separator "  n2b-diff --analyze --jira PROJ-123 -m \"Focus on data validation.\""
        opts.separator "  n2b-diff --analyze --github org/repo/issues/42 --update"
      end

      begin
        parser.parse!(@args)
      rescue OptionParser::InvalidOption => e
        puts "#{COLOR_RED}Error: #{e.message}#{COLOR_RESET}"
        puts parser.help
        exit 1
      end

      # --- Option Validations ---
      if options[:analyze]
        # Options that only make sense with analyze
      else
        # Options that don't make sense without analyze (if any)
        if options[:branch] || options[:jira_ticket] || options[:github_issue] || options[:requirements_file] || options[:custom_message] || !options[:update_issue].nil?
          puts "#{COLOR_RED}Error: Options like --branch, --jira, --github, --requirements, --message, --update/--no-update are only for --analyze mode.#{COLOR_RESET}"
          puts parser.help
          exit 1
        end
      end

      if options[:update_issue] == true && options[:jira_ticket].nil? && options[:github_issue].nil?
        puts "#{COLOR_RED}Error: --update option requires --jira or --github to be specified for context.#{COLOR_RESET}"
        puts parser.help
        exit 1
      end

      # If --no-update is used without specifying a ticket, it's not an error, just has no effect.
      # It's fine for --jira or --github to be specified without --update or --no-update (implies ask user)

      # Perform sanitization and logging for custom_message after all options are parsed.
      if options[:custom_message]
        # Sanitize the already validated (potentially truncated) message
        sanitized_message = N2B::MessageUtils.sanitize_message(options[:custom_message])
        options[:custom_message] = sanitized_message # Store the sanitized version

        # Log the final message that will be used
        N2B::MessageUtils.log_message("Using custom analysis message: \"#{options[:custom_message]}\"", :info) unless options[:custom_message].strip.empty?
      end

      options
    end

    # --- Methods moved and adapted from original N2B::CLI for diff analysis ---
    def handle_diff_analysis(config)
      vcs_type = get_vcs_type
      if vcs_type == :none
        puts "Error: Not a git or hg repository. Diff analysis requires a VCS."
        exit 1
      end

      requirements_filepath = @options[:requirements_file] # Adapted option name
      # user_prompt_addition now directly uses the processed @options[:custom_message]
      user_prompt_addition = @options[:custom_message] || ""

      # Logging of custom_message is now handled in parse_options by MessageUtils.log_message
      # So, the specific puts here can be removed or changed to debug level if needed.
      # For now, removing:
      # if @options[:custom_message] && !@options[:custom_message].strip.empty?
      #   puts "DEBUG: Custom message for analysis: #{@options[:custom_message]}" # Or use MessageUtils.log_message if preferred for debug
      # end

      # Ticket / Issue Information - Standardize to use jira_ticket and github_issue
      # The original cli.rb used @options[:jira_ticket] for both. Here we differentiate.
      ticket_input = @options[:jira_ticket] || @options[:github_issue]
      ticket_type = @options[:jira_ticket] ? 'jira' : (@options[:github_issue] ? 'github' : nil)
      # ticket_update_flag from @options[:update_issue] (true, false, or nil)
      # nil means ask, true means update, false means no update.
      ticket_update_flag = @options[:update_issue]


      requirements_content = nil

      if ticket_input && ticket_type
        # Determine which issue tracker based on which option was provided
        # Default to 'jira' if somehow ticket_type is nil but ticket_input exists (should not happen)
        tracker_service_name = ticket_type || (config['issue_tracker'] || 'jira')

        case tracker_service_name
        when 'github'
          puts "GitHub issue specified: #{ticket_input}"
          if config['github'] && config['github']['repo'] && config['github']['access_token']
            begin
              github_client = N2B::GitHubClient.new(config) # Ensure N2B::GitHubClient is available
              puts "Fetching GitHub issue details..."
              requirements_content = github_client.fetch_issue(ticket_input) # ticket_input here is ID/URL
              puts "Successfully fetched GitHub issue details."
            rescue StandardError => e
              puts "Error fetching GitHub issue: #{e.message}"
              puts "Proceeding with diff analysis without GitHub issue details."
            end
          else
            puts "GitHub configuration is missing or incomplete in N2B settings."
            puts "Please configure GitHub using 'n2b -c' (or main n2b config) to fetch issue details."
            puts "Proceeding with diff analysis without GitHub issue details."
          end
        when 'jira'
          puts "Jira ticket specified: #{ticket_input}"
          if config['jira'] && config['jira']['domain'] && config['jira']['email'] && config['jira']['api_key']
            begin
              jira_client = N2B::JiraClient.new(config) # Ensure N2B::JiraClient is available
              puts "Fetching Jira ticket details..."
              requirements_content = jira_client.fetch_ticket(ticket_input)
              puts "Successfully fetched Jira ticket details."
            rescue N2B::JiraClient::JiraApiError => e
              puts "Error fetching Jira ticket: #{e.message}"
              puts "Proceeding with diff analysis without Jira ticket details."
            rescue ArgumentError => e # Catches config errors from JiraClient init
              puts "Jira configuration error: #{e.message}"
              puts "Please ensure Jira is configured correctly."
              puts "Proceeding with diff analysis without Jira ticket details."
            rescue StandardError => e
              puts "An unexpected error occurred while fetching Jira ticket: #{e.message}"
              puts "Proceeding with diff analysis without Jira ticket details."
            end
          else
            puts "Jira configuration is missing or incomplete in N2B settings."
            puts "Please configure Jira using 'n2b -c' (or main n2b config) to fetch ticket details."
            puts "Proceeding with diff analysis without Jira ticket details."
          end
        end
        # Common message for ticket update status based on new flag
        if ticket_update_flag == true
            puts "Note: Issue update is flagged (--update)."
        elsif ticket_update_flag == false
            puts "Note: Issue will not be updated (--no-update)."
        else # nil case
            puts "Note: You will be prompted whether to update the issue after analysis."
        end
      end


      if requirements_content.nil? && requirements_filepath
        if File.exist?(requirements_filepath)
          puts "Loading requirements from file: #{requirements_filepath}"
          requirements_content = File.read(requirements_filepath)
        else
          puts "Error: Requirements file not found: #{requirements_filepath}"
          puts "Proceeding with diff analysis without file-based requirements."
        end
      elsif requirements_content && requirements_filepath
        puts "Note: Both issue details and a requirements file were provided. Using issue details for analysis context."
      end

      diff_output = execute_vcs_diff(vcs_type, @options[:branch])
      if diff_output.nil? || diff_output.strip.empty?
        puts "No differences found to analyze."
        exit 0
      end

      # Pass user_prompt_addition (custom_message) to analyze_diff
      analysis_result = analyze_diff(diff_output, config, user_prompt_addition, requirements_content)

      # --- Ticket Update Logic (adapted) ---
      if ticket_input && ticket_type && analysis_result && !analysis_result.empty?
        tracker_service_name = ticket_type

        # Determine if we should proceed with update based on ticket_update_flag
        proceed_with_update_action = false
        if ticket_update_flag == true # --update
          proceed_with_update_action = true
        elsif ticket_update_flag.nil? # Ask user
          puts "\nWould you like to update #{tracker_service_name.capitalize} issue #{ticket_input} with this analysis? (y/n)"
          user_choice = $stdin.gets.chomp.downcase
          proceed_with_update_action = user_choice == 'y'
        end # If ticket_update_flag is false, proceed_with_update_action remains false

        if proceed_with_update_action
          case tracker_service_name
          when 'github'
            if config['github'] && config['github']['repo'] && config['github']['access_token']
              # Pass custom_message to formatting function
              comment_data = format_analysis_for_github(analysis_result, @options[:custom_message])
              begin
                update_client = N2B::GitHubClient.new(config)
                puts "Updating GitHub issue #{ticket_input}..."
                if update_client.update_issue(ticket_input, comment_data) # ticket_input is ID/URL
                  puts "GitHub issue #{ticket_input} updated successfully."
                else
                  puts "Failed to update GitHub issue #{ticket_input}."
                end
              rescue StandardError => e
                puts "Error updating GitHub issue: #{e.message}"
              end
            else
              puts "GitHub configuration is missing. Cannot update GitHub issue."
            end
          when 'jira'
            if config['jira'] && config['jira']['domain'] && config['jira']['email'] && config['jira']['api_key']
              # Pass custom_message to formatting function
              jira_comment_data = format_analysis_for_jira(analysis_result, @options[:custom_message])
              begin
                update_jira_client = N2B::JiraClient.new(config)
                puts "Updating Jira ticket #{ticket_input}..."
                if update_jira_client.update_ticket(ticket_input, jira_comment_data)
                  puts "Jira ticket #{ticket_input} updated successfully."
                else
                  puts "Failed to update Jira ticket #{ticket_input}."
                end
              rescue N2B::JiraClient::JiraApiError => e
                puts "Error updating Jira ticket: #{e.message}"
              rescue ArgumentError => e
                puts "Jira configuration error for update: #{e.message}"
              rescue StandardError => e
                puts "An unexpected error occurred while updating Jira ticket: #{e.message}"
              end
            else
              puts "Jira configuration is missing. Cannot update Jira ticket."
            end
          end
        else
          puts "Issue/Ticket update skipped."
        end
      elsif ticket_input && (analysis_result.nil? || analysis_result.empty?)
        puts "Skipping ticket update as analysis result was empty or not generated."
      end
      # --- End of Ticket Update Logic ---
      analysis_result # Return for potential further use or testing
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
      # Ensure shell commands are properly escaped if branch_option comes from user input
      # Though OptionParser should handle this for fixed options.
      # For this method, branch_option is generally safe as it's from parsed options.

      case vcs_type
      when :git
        target_branch_name = branch_option == 'auto' ? detect_git_default_branch : branch_option
        if target_branch_name
          unless validate_git_branch_exists(target_branch_name)
            puts "Error: Git branch '#{target_branch_name}' does not exist or is not accessible."
            # Suggest available branches if possible (might be noisy, consider a debug flag)
            # puts "Available local branches:\n`git branch`"
            # puts "Available remote branches for 'origin':\n`git branch -r`"
            exit 1
          end
          puts "Comparing current HEAD against git branch '#{target_branch_name}'..."
          # Use three dots for "changes on your branch since target_branch_name diverged from it"
          # Or two dots for "changes between target_branch_name and your current HEAD"
          # Three dots is common for PR-like diffs.
          `git diff #{Shellwords.escape(target_branch_name)}...HEAD`
        else
          puts "Could not automatically detect default git branch and no branch specified. Falling back to 'git diff HEAD' (staged changes)..."
          `git diff HEAD` # This shows staged changes. `git diff` shows unstaged.
        end
      when :hg
        target_branch_name = branch_option == 'auto' ? detect_hg_default_branch : branch_option
        if target_branch_name
          unless validate_hg_branch_exists(target_branch_name)
            puts "Error: Mercurial branch '#{target_branch_name}' does not exist."
            exit 1
          end
          puts "Comparing current working directory against hg branch '#{target_branch_name}'..."
          # For hg, diff against the revision of the branch tip
          `hg diff -r #{Shellwords.escape(target_branch_name)}`
        else
          puts "Could not automatically detect default hg branch and no branch specified. Falling back to 'hg diff' (uncommitted changes)..."
          `hg diff` # Shows uncommitted changes.
        end
      else
        puts "Error: Unsupported VCS type." # Should be caught by get_vcs_type check earlier
        ""
      end
    end

    def detect_git_default_branch
      # Method 1: Check origin/HEAD symbolic ref (most reliable for remotes)
      result = `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null`.strip
      return result.split('/').last if $?.success? && !result.empty?

      # Method 2: Check local 'main' or 'master' if they track a remote branch
      ['main', 'master'].each do |branch|
        local_tracking = `git rev-parse --abbrev-ref #{branch}@{upstream} 2>/dev/null`.strip
        return branch if $?.success? && !local_tracking.empty?
      end

      # Method 3: Check remote show origin for HEAD branch (less direct but good fallback)
      result = `git remote show origin 2>/dev/null | grep "HEAD branch"`.strip
      if $?.success? && !result.empty?
        match = result.match(/HEAD branch:\s*(\S+)/)
        return match[1] if match && match[1] != '(unknown)'
      end

      # Method 4: Last resort, check for local main/master even if not tracking
      ['main', 'master'].each do |branch|
        return branch if system("git show-ref --verify --quiet refs/heads/#{branch}")
      end
      nil # No default branch found
    end

    def detect_hg_default_branch
      # Mercurial typically uses 'default' as the main branch.
      # `hg branch` shows the current branch. If it's 'default', that's a strong candidate.
      current_branch = `hg branch 2>/dev/null`.strip
      return current_branch if $?.success? && current_branch == 'default'

      # Check if 'default' branch exists in the list of branches
      branches_output = `hg branches 2>/dev/null`
      if $?.success? && branches_output.lines.any? { |line| line.strip.start_with?('default ') }
        return 'default'
      end

      # Fallback if 'default' isn't found but there's only one branch (common in simple repos)
      if $?.success?
          active_branches = branches_output.lines.reject { |line| line.include?('(inactive)') }
          if active_branches.size == 1
              return active_branches.first.split.first
          end
      end

      # If current branch is not 'default' but exists, it might be the one being used as main.
      return current_branch if $?.success? && !current_branch.empty?

      'default' # Default assumption for Mercurial
    end

    def validate_git_branch_exists(branch)
      # Check local branches
      return true if system("git show-ref --verify --quiet refs/heads/#{Shellwords.escape(branch)}")
      # Check remote branches (assuming 'origin' remote)
      return true if system("git show-ref --verify --quiet refs/remotes/origin/#{Shellwords.escape(branch)}")
      false
    end

    def validate_hg_branch_exists(branch)
      # `hg branches` lists all branches. Check if the branch is in the list.
      # `hg id -r branchname` would fail if branch doesn't exist.
      system("hg id -r #{Shellwords.escape(branch)} > /dev/null 2>&1")
    end

    def build_diff_analysis_prompt(diff_output, user_prompt_addition = "", requirements_content = nil, config = {})
      default_system_prompt_path = resolve_template_path('diff_system_prompt', config) # Ensure this template exists
      default_system_prompt = File.read(default_system_prompt_path).strip rescue "Analyze this diff." # Fallback

      # user_prompt_addition is @options[:custom_message], already validated and sanitized.
      user_instructions_section = ""
      if user_prompt_addition && !user_prompt_addition.to_s.strip.empty?
        # No need to call .strip here again as sanitize_message in parse_options already does it.
        user_instructions_section = "User's Custom Instructions:\n#{user_prompt_addition}\n\n---\n\n"
      end

      requirements_section = ""
      if requirements_content && !requirements_content.to_s.strip.empty?
        requirements_section = <<-REQUIREMENTS_BLOCK
CRITICAL REQUIREMENTS EVALUATION:
Based on the provided context, evaluate if the code changes meet these requirements.
For each requirement, explicitly state whether it is:
- ✅ IMPLEMENTED
- ⚠️ PARTIALLY IMPLEMENTED
- ❌ NOT IMPLEMENTED
- 🔍 UNCLEAR

--- BEGIN REQUIREMENTS ---
#{requirements_content.strip}
--- END REQUIREMENTS ---

REQUIREMENTS_BLOCK
      end

      analysis_intro = "Analyze the following code diff. Focus on identifying potential bugs, suggesting improvements, and assessing test coverage. If requirements are provided, evaluate against them."

      # Context extraction (can be intensive, consider making optional or smarter)
      # context_sections = extract_code_context_from_diff(diff_output) # This can be slow
      # context_info = context_sections.empty? ? "" : "\n\nRelevant Code Context:\n#{format_context_for_prompt(context_sections)}"
      # For now, let's keep context extraction simpler or rely on LLM's ability with just the diff.
      # If extract_code_context_from_diff is too complex or slow, it might be omitted or simplified.
      # For this integration, assuming extract_code_context_from_diff is efficient enough.
      context_sections = extract_code_context_from_diff(diff_output)
      context_info = ""
      unless context_sections.empty?
        context_info = "\n\nCurrent Code Context (for better analysis):\n"
        context_sections.each do |file_path, sections|
          context_info += "\n--- Context from: #{file_path} ---\n"
          sections.each do |section|
            context_info += "Lines approx #{section[:start_line]}-#{section[:end_line]}:\n" # Approximate lines
            context_info += "```\n#{section[:content]}\n```\n\n"
          end
        end
      end


      json_instruction_path = resolve_template_path('diff_json_instruction', config) # Ensure this template exists
      json_instruction = File.read(json_instruction_path).strip rescue 'Respond in JSON format with keys: "summary", "errors", "improvements", "test_coverage", "requirements_evaluation", "ticket_implementation_summary".' # Fallback

      full_prompt = [
        user_instructions_section, # Custom instructions first
        default_system_prompt,
        requirements_section,
        analysis_intro,
        "Diff:\n```diff\n#{diff_output}\n```", # Ensure diff is marked as diff language
        context_info,
        json_instruction
      ].select { |s| s && !s.strip.empty? }.join("\n\n")

      full_prompt
    end

    def analyze_diff(diff_output, config, user_prompt_addition = "", requirements_content = nil)
      # user_prompt_addition here IS the custom_message from options
      prompt = build_diff_analysis_prompt(diff_output, user_prompt_addition, requirements_content, config)

      # Use analyze_diff_with_spinner for this call
      analysis_json_str = analyze_diff_with_spinner(config) do |llm| # Pass config to spinner wrapper
        llm.analyze_code_diff(prompt) # This is the actual call the spinner will make
      end
      # Fallback if spinner itself has an issue or if LLM call within spinner fails before LlmApiError
      analysis_json_str ||= '{"summary": "Error: Failed to get analysis from LLM.", "errors": [], "improvements": []}'


      begin
        json_content = extract_json_from_response(analysis_json_str)
        analysis_result = JSON.parse(json_content)

        # Output formatting (consider making this a separate method or class)
        puts "\n#{COLOR_BLUE}📊 Code Diff Analysis:#{COLOR_RESET}"
        puts "-------------------"
        puts "#{COLOR_GREEN}Summary:#{COLOR_RESET}"
        puts analysis_result['summary'] || "No summary provided."

        puts "\n#{COLOR_RED}Potential Issues/Errors:#{COLOR_RESET}"
        errors_list = [analysis_result['errors']].flatten.compact.reject(&:empty?)
        puts errors_list.any? ? errors_list.map { |err| "- #{err}" }.join("\n") : "  No specific errors identified."

        puts "\n#{COLOR_YELLOW}Suggested Improvements:#{COLOR_RESET}"
        improvements_list = [analysis_result['improvements']].flatten.compact.reject(&:empty?)
        puts improvements_list.any? ? improvements_list.map { |imp| "- #{imp}" }.join("\n") : "  No specific improvements suggested."

        puts "\n#{COLOR_BLUE}Test Coverage Assessment:#{COLOR_RESET}"
        test_coverage = analysis_result['test_coverage']
        puts test_coverage && !test_coverage.to_s.strip.empty? ? test_coverage : "  No test coverage assessment provided."

        if requirements_content && !requirements_content.to_s.strip.empty?
          puts "\n#{COLOR_GREEN}Requirements Evaluation:#{COLOR_RESET}"
          eval_text = analysis_result['requirements_evaluation']
          puts eval_text && !eval_text.to_s.strip.empty? ? eval_text : "  No requirements evaluation provided."
        end

        # This field is often more specific for tickets
        ticket_summary = analysis_result['ticket_implementation_summary']
        if ticket_summary && !ticket_summary.to_s.strip.empty?
            puts "\n#{COLOR_GREEN}Ticket Implementation Summary:#{COLOR_RESET}"
            puts ticket_summary
        end

        puts "-------------------"
        return analysis_result
      rescue JSON::ParserError => e
        puts "#{COLOR_RED}Critical Error: Failed to parse JSON response for diff analysis: #{e.message}#{COLOR_RESET}"
        puts "Raw response was: #{analysis_json_str}"
        # Fallback if parsing fails
        return {"summary" => "Failed to parse analysis.", "errors" => ["JSON parsing error."], "improvements" => [], "test_coverage" => "Unknown", "requirements_evaluation" => "Unknown", "ticket_implementation_summary" => "Unknown"}
      end
    end

    # Extracted from original N2B::CLI, might need slight path adjustments if templates are structured differently
    # def resolve_template_path(template_key, config)
    #   user_path = config.dig('templates', template_key) if config.is_a?(Hash)
    #   return user_path if user_path && File.exist?(user_path)
    #   # Assuming templates are in a subdir relative to THIS file (merge_cli.rb)
    #   File.expand_path(File.join(__dir__, 'templates', "#{template_key}.txt"))
    # end


    def format_analysis_for_jira(analysis_result, custom_message = nil)
      # Basic check, ensure analysis_result is a hash
      return { body: "Error: Analysis result is not in the expected format." } unless analysis_result.is_a?(Hash)

      summary = analysis_result['ticket_implementation_summary']&.strip || analysis_result['summary']&.strip || "No summary."

      details_parts = []
      details_parts << "*Custom Analysis Focus:*\n#{custom_message}\n" if custom_message && !custom_message.empty?
      details_parts << "*Technical Summary:*\n#{analysis_result['summary']&.strip}\n" if analysis_result['summary']

      issues = format_issues_for_adf(analysis_result['errors'])
      improvements = format_improvements_for_adf(analysis_result['improvements'])

      details_parts << "*Potential Issues:*\n" + (issues.empty? ? "None identified.\n" : issues.map { |i| "- #{i}\n" }.join)
      details_parts << "*Suggested Improvements:*\n" + (improvements.empty? ? "None identified.\n" : improvements.map { |i| "- #{i}\n" }.join)
      details_parts << "*Test Coverage Assessment:*\n#{analysis_result['test_coverage']&.strip || "Not assessed."}\n"

      req_eval = analysis_result['requirements_evaluation']&.strip
      details_parts << "*Requirements Evaluation:*\n#{req_eval}\n" if req_eval && !req_eval.empty?

      # ADF structure for Jira
      # This is a simplified version. Real ADF is more complex.
      # N2B::JiraClient would need to construct the actual ADF document.
      # Here, we are returning a hash that the client can use.
      {
        implementation_summary: summary, # Often used as a primary comment or field
        technical_summary: analysis_result['summary']&.strip,
        issues: issues, # Array of strings
        improvements: improvements, # Array of strings
        test_coverage: analysis_result['test_coverage']&.strip,
        requirements_evaluation: req_eval,
        custom_analysis_focus: custom_message # Added new key
      }
    end

    def format_issues_for_adf(errors) # Helper for Jira/GitHub formatting
      return [] unless errors.is_a?(Array) && errors.any?
      errors.map(&:strip).reject(&:empty?)
    end

    def format_improvements_for_adf(improvements) # Helper for Jira/GitHub formatting
      return [] unless improvements.is_a?(Array) && improvements.any?
      improvements.map(&:strip).reject(&:empty?)
    end

    def format_analysis_for_github(analysis_result, custom_message = nil)
      # Basic check
      return "Error: Analysis result is not in the expected format." unless analysis_result.is_a?(Hash)

      title = "### Code Diff Analysis Summary 🤖\n"
      summary_section = "**Implementation/Overall Summary:**\n#{analysis_result['ticket_implementation_summary']&.strip || analysis_result['summary']&.strip || "No summary provided."}\n\n"

      details_parts = []
      details_parts << "**Custom Analysis Focus:**\n#{custom_message}\n" if custom_message && !custom_message.empty?
      details_parts << "**Technical Detail Summary:**\n#{analysis_result['summary']&.strip}\n" if analysis_result['summary'] && analysis_result['summary'] != analysis_result['ticket_implementation_summary']


      errors_list = [analysis_result['errors']].flatten.compact.reject(&:empty?)
      details_parts << "**Potential Issues/Errors:**\n" + (errors_list.empty? ? "_None identified._\n" : errors_list.map { |err| "- [ ] #{err}\n" }.join) # Added checkbox

      improvements_list = [analysis_result['improvements']].flatten.compact.reject(&:empty?)
      details_parts << "**Suggested Improvements:**\n" + (improvements_list.empty? ? "_None identified._\n" : improvements_list.map { |imp| "- [ ] #{imp}\n" }.join) # Added checkbox

      details_parts << "**Test Coverage Assessment:**\n#{analysis_result['test_coverage']&.strip || "_Not assessed._"}\n"

      req_eval = analysis_result['requirements_evaluation']&.strip
      details_parts << "**Requirements Evaluation:**\n#{req_eval.empty? ? "_Not applicable or not assessed._" : req_eval}\n" if req_eval

      # For GitHub, typically a Markdown string is returned for the comment body.
      # The N2B::GitHubClient would take this string.
      # Returning a hash that the client can use to build the comment.
      {
        title: "Code Diff Analysis Summary 🤖",
        implementation_summary: analysis_result['ticket_implementation_summary']&.strip || analysis_result['summary']&.strip,
        technical_summary: analysis_result['summary']&.strip,
        issues: errors_list, # Array of strings
        improvements: improvements_list, # Array of strings
        test_coverage: analysis_result['test_coverage']&.strip,
        requirements_evaluation: req_eval,
        custom_analysis_focus: custom_message, # Added new key
        # Construct a body for convenience, client can override
        body: title + summary_section + details_parts.join("\n")
      }
    end

    def extract_json_from_response(response)
      # This is a robust way to extract JSON that might be embedded in other text.
      # First, try to parse as-is, in case the LLM behaves perfectly.
      begin
        JSON.parse(response)
        return response # It's already valid JSON
      rescue JSON::ParserError
        # If not, search for the first '{' and last '}'
      end

      json_start = response.index('{')
      json_end = response.rindex('}') # Use rindex for the last occurrence

      if json_start && json_end && json_end > json_start
        potential_json = response[json_start..json_end]
        begin
          JSON.parse(potential_json) # Check if this substring is valid JSON
          return potential_json
        rescue JSON::ParserError
          # Fallback: if the strict extraction fails, return the original response
          # and let the caller deal with a more comprehensive repair or error.
          # This can happen if there are '{' or '}' in string literals within the JSON.
          # A more sophisticated parser would be needed for those cases.
          # For now, this is a common heuristic.
          return response # Or perhaps an error string/nil
        end
      else
        # No clear JSON structure found, return original response for error handling
        return response
      end
    end

    def extract_code_context_from_diff(diff_output, lines_of_context: 5)
      # Simplified context extraction focusing on lines around changes.
      # This is a placeholder for potentially more sophisticated context extraction.
      # A full AST parse or more complex diff parsing could be used for richer context.
      context_sections = {}
      current_file = nil
      file_lines_buffer = {} # Cache for file lines

      # First pass: identify files and changed line numbers from hunk headers
      # @@ -old_start,old_lines +new_start,new_lines
      hunks_by_file = {}
      diff_output.each_line do |line|
        line.chomp!
        if line.start_with?('diff --git')
          # Extracts 'b_file_path' from "diff --git a/a_file_path b/b_file_path"
          match = line.match(/diff --git a\/(.+?) b\/(.+)/)
          current_file = match[2] if match && match[2] != '/dev/null'
        elsif line.start_with?('+++ b/')
          # Extracts file path from "+++ b/file_path"
          current_file = line[6..].strip unless line.include?('/dev/null')
        elsif line.start_with?('@@') && current_file
          match = line.match(/@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/)
          next unless match
          start_line = match[1].to_i
          # hunk_lines = match[2]&.to_i || 1 # Number of lines in the hunk in the new file
          # For context, we care more about the range of lines around the start_line of the change.
          hunks_by_file[current_file] ||= []
          hunks_by_file[current_file] << { new_start: start_line }
        end
      end

      # Second pass: extract context for each hunk
      hunks_by_file.each do |file_path, hunks|
        next unless File.exist?(file_path) # Ensure file exists to read context from

        file_lines_buffer[file_path] ||= File.readlines(file_path, chomp: true)
        all_lines = file_lines_buffer[file_path]

        hunks.each do |hunk|
          context_start_line = [1, hunk[:new_start] - lines_of_context].max
          # Estimate end of change based on typical hunk sizes or simplify
          # For simplicity, take fixed lines after start, or up to next hunk.
          # This is a very rough heuristic.
          context_end_line = [all_lines.length, hunk[:new_start] + lines_of_context + 5].min # +5 for some change content

          actual_start_index = context_start_line - 1
          actual_end_index = context_end_line - 1

          if actual_start_index < all_lines.length && actual_start_index <= actual_end_index
            section_content = all_lines[actual_start_index..actual_end_index].join("\n")
            context_sections[file_path] ||= []
            # Avoid duplicate sections if hunks are very close
            unless context_sections[file_path].any? { |s| s[:content] == section_content }
              context_sections[file_path] << {
                # Store actual line numbers for reference, not just indices
                start_line: context_start_line,
                end_line: context_end_line,
                content: section_content
              }
            end
          end
        end
      end
      context_sections
    end

    # Spinner method specifically for diff analysis
    def analyze_diff_with_spinner(config) # Takes config to initialize LLM
      llm_service_name = config['llm']
      llm = case llm_service_name # Initialize LLM based on config
            when 'openai' then N2B::Llm::OpenAi.new(config)
            when 'claude' then N2B::Llm::Claude.new(config)
            when 'gemini' then N2B::Llm::Gemini.new(config)
            when 'openrouter' then N2B::Llm::OpenRouter.new(config)
            when 'ollama' then N2B::Llm::Ollama.new(config)
            else raise N2B::Error, "Unsupported LLM service for analysis: #{llm_service_name}"
            end

      spinner_chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
      spinner_thread = Thread.new do
        i = 0
        loop do
          print "\r#{COLOR_BLUE}🔍 #{spinner_chars[i % spinner_chars.length]} Analyzing diff...#{COLOR_RESET}"
          $stdout.flush
          sleep(0.1)
          i += 1
        end
      end

      begin
        # The block passed to this method contains the actual LLM call
        result = yield(llm) if block_given?
        spinner_thread.kill
        spinner_thread.join # Ensure thread is fully cleaned up
        print "\r#{' ' * 35}\r" # Clear spinner line
        puts "#{COLOR_GREEN}✅ Diff analysis complete!#{COLOR_RESET}"
        result
      rescue N2B::LlmApiError => e
        spinner_thread.kill
        spinner_thread.join
        print "\r#{' ' * 35}\r"
        puts "#{COLOR_RED}LLM API Error during diff analysis: #{e.message}#{COLOR_RESET}"
        # Provide specific model error guidance
        if e.message.match?(/model|invalid|not found/i)
          puts "#{COLOR_YELLOW}This might be due to an invalid or unsupported model in your config. Run 'n2b -c' to reconfigure.#{COLOR_RESET}"
        end
        # Return a structured error JSON
        '{"summary": "Error: Could not analyze diff due to LLM API error.", "errors": ["#{e.message}"], "improvements": []}'
      rescue StandardError => e # Catch other unexpected errors during the yield or LLM call
        spinner_thread.kill
        spinner_thread.join
        print "\r#{' ' * 35}\r"
        puts "#{COLOR_RED}Unexpected error during diff analysis: #{e.message}#{COLOR_RESET}"
        '{"summary": "Error: Unexpected failure during diff analysis.", "errors": ["#{e.message}"], "improvements": []}'
      end
    end
    # --- End of moved methods ---


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
              N2B::Llm::OpenAi.new(config)
            when 'claude'
              N2B::Llm::Claude.new(config)
            when 'gemini'
              N2B::Llm::Gemini.new(config)
            when 'openrouter'
              N2B::Llm::OpenRouter.new(config)
            when 'ollama'
              N2B::Llm::Ollama.new(config)
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
      # Show context before conflict for better understanding
      if block.context_before && !block.context_before.empty?
        puts "#{COLOR_GRAY}... context before ...#{COLOR_RESET}"
        context_lines = block.context_before.split("\n").last(3) # Show last 3 lines of context
        context_lines.each { |line| puts "#{COLOR_GRAY}#{line}#{COLOR_RESET}" }
      end

      puts "#{COLOR_RED}<<<<<<< #{block.base_label} (lines #{block.start_line}-#{block.end_line})#{COLOR_RESET}"
      puts "#{COLOR_RED}#{block.base_content}#{COLOR_RESET}"
      puts "#{COLOR_YELLOW}=======#{COLOR_RESET}"
      puts "#{COLOR_GREEN}#{block.incoming_content}#{COLOR_RESET}"
      puts "#{COLOR_YELLOW}>>>>>>> #{block.incoming_label}#{COLOR_RESET}"

      # Show context after conflict for better understanding
      if block.context_after && !block.context_after.empty?
        context_lines = block.context_after.split("\n").first(3) # Show first 3 lines of context
        context_lines.each { |line| puts "#{COLOR_GRAY}#{line}#{COLOR_RESET}" }
        puts "#{COLOR_GRAY}... context after ...#{COLOR_RESET}"
      end
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

    def show_help_and_status
      # This method will be invoked by OptionParser for -h/--help,
      # or when n2b-diff is run without arguments in non-analyze mode.
      # The OptionParser instance itself will print most of the help text.
      # We just add any extra status info here.

      puts "" # Extra newline for spacing after OptionParser's output if it called this.
      # If running not due to -h, but due to missing file_path in merge mode:
      if !@options[:analyze] && @file_path.nil? && !@args.include?('-h') && !@args.include?('--help')
         puts "#{COLOR_RED}Error: No file path provided for merge conflict resolution."
         puts "Run with -h or --help for detailed usage."
         puts ""
      end


      # Show unresolved conflicts if in a VCS repository and not in analyze mode
      # (or if specifically requested, but for now, tied to non-analyze mode)
      if !@options[:analyze] && (File.exist?('.hg') || File.exist?('.git'))
        puts "#{COLOR_BLUE}📋 Unresolved Conflicts Status:#{COLOR_RESET}"
        if File.exist?('.hg')
          puts "#{COLOR_GRAY}Checking Mercurial...#{COLOR_RESET}"
          result = execute_vcs_command_with_timeout("hg resolve --list", 5)
          if result[:success]
            unresolved_files = result[:stdout].lines.select { |line| line.start_with?('U ') }
            if unresolved_files.any?
              unresolved_files.each { |line| puts "  #{COLOR_RED}❌ #{line.strip.sub(/^U /, '')} (Mercurial)#{COLOR_RESET}" }
              puts "\n#{COLOR_YELLOW}💡 Use: n2b-diff <filename> to resolve listed conflicts.#{COLOR_RESET}"
            else
              puts "  #{COLOR_GREEN}✅ No unresolved Mercurial conflicts.#{COLOR_RESET}"
            end
          else
            puts "  #{COLOR_YELLOW}⚠️  Could not check Mercurial status: #{result[:error]}#{COLOR_RESET}"
          end
        end

        if File.exist?('.git')
          puts "#{COLOR_GRAY}Checking Git...#{COLOR_RESET}"
          # For Git, `git status --porcelain` is better as `git diff --name-only --diff-filter=U` only shows unmerged paths.
          # We want to show files with conflict markers.
          # `git status --porcelain=v1` shows "UU" for unmerged files.
          result = execute_vcs_command_with_timeout("git status --porcelain=v1", 5)
          if result[:success]
            unresolved_files = result[:stdout].lines.select{|line| line.start_with?('UU ')}.map{|line| line.sub(/^UU /, '').strip}
            if unresolved_files.any?
              unresolved_files.each { |file| puts "  #{COLOR_RED}❌ #{file} (Git)#{COLOR_RESET}" }
              puts "\n#{COLOR_YELLOW}💡 Use: n2b-diff <filename> to resolve listed conflicts.#{COLOR_RESET}"
            else
              puts "  #{COLOR_GREEN}✅ No unresolved Git conflicts.#{COLOR_RESET}"
            end
          else
            puts "  #{COLOR_YELLOW}⚠️  Could not check Git status: #{result[:error]}#{COLOR_RESET}"
          end
        end
      elsif @options[:analyze]
        # This part might not be reached if -h is used, as OptionParser exits.
        # But if called for other reasons in analyze mode:
        puts "#{COLOR_BLUE}ℹ️  Running in analysis mode. VCS conflict status check is skipped.#{COLOR_RESET}"
      end
      # Ensure exit if we got here due to an operational error (like no file in merge mode)
      # but not if it was just -h (OptionParser handles exit for -h)
      if !@options[:analyze] && @file_path.nil? && !@args.include?('-h') && !@args.include?('--help')
        exit 1
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

    def generate_merge_log_html(log_entries, timestamp)
      git_info = extract_git_info

      html = <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>N2B Merge Log - #{@file_path} - #{timestamp}</title>
          <style>
            body {
              font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Fira Code', monospace;
              margin: 0;
              padding: 20px;
              background-color: #f8f9fa;
              color: #333;
              line-height: 1.6;
            }
            .header {
              background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
              color: white;
              padding: 20px;
              border-radius: 8px;
              margin-bottom: 20px;
              box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            }
            .header h1 {
              margin: 0 0 10px 0;
              font-size: 24px;
            }
            .header .meta {
              opacity: 0.9;
              font-size: 14px;
            }
            .conflict-container {
              background: white;
              border-radius: 8px;
              margin-bottom: 20px;
              box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
              overflow: hidden;
            }
            .conflict-header {
              background-color: #e9ecef;
              padding: 15px;
              border-bottom: 1px solid #dee2e6;
              font-weight: bold;
              color: #495057;
            }
            .conflict-table {
              width: 100%;
              border-collapse: collapse;
            }
            .conflict-table th {
              background-color: #f8f9fa;
              padding: 12px;
              text-align: left;
              font-weight: 600;
              border-bottom: 2px solid #dee2e6;
              color: #495057;
            }
            .conflict-table td {
              padding: 12px;
              border-bottom: 1px solid #e9ecef;
              vertical-align: top;
            }
            .code-block {
              background-color: #f8f9fa;
              border: 1px solid #e9ecef;
              border-radius: 4px;
              padding: 10px;
              font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Fira Code', monospace;
              font-size: 13px;
              white-space: pre-wrap;
              overflow-x: auto;
              max-height: 300px;
              overflow-y: auto;
            }
            .base-code { border-left: 4px solid #dc3545; }
            .incoming-code { border-left: 4px solid #007bff; }
            .resolution-code { border-left: 4px solid #28a745; }
            .method-badge {
              display: inline-block;
              padding: 4px 8px;
              border-radius: 12px;
              font-size: 12px;
              font-weight: 500;
              text-transform: uppercase;
            }
            .method-llm { background-color: #e3f2fd; color: #1976d2; }
            .method-manual { background-color: #fff3e0; color: #f57c00; }
            .method-skip { background-color: #fce4ec; color: #c2185b; }
            .method-abort { background-color: #ffebee; color: #d32f2f; }
            .footer {
              text-align: center;
              margin-top: 30px;
              padding: 20px;
              color: #6c757d;
              font-size: 14px;
            }
            .stats {
              display: flex;
              gap: 20px;
              margin-top: 10px;
            }
            .stat-item {
              background: rgba(255, 255, 255, 0.2);
              padding: 8px 12px;
              border-radius: 4px;
            }
          </style>
        </head>
        <body>
          <div class="header">
            <h1>🔀 N2B Merge Resolution Log</h1>
            <div class="meta">
              <strong>File:</strong> #{@file_path}<br>
              <strong>Timestamp:</strong> #{Time.now.strftime('%Y-%m-%d %H:%M:%S UTC')}<br>
              <strong>Branch:</strong> #{git_info[:branch]}<br>
              <strong>Total Conflicts:</strong> #{log_entries.length}
            </div>
            <div class="stats">
              <div class="stat-item">
                <strong>Resolved:</strong> #{log_entries.count { |e| e[:action] == 'accepted' }}
              </div>
              <div class="stat-item">
                <strong>Skipped:</strong> #{log_entries.count { |e| e[:action] == 'skipped' }}
              </div>
              <div class="stat-item">
                <strong>Aborted:</strong> #{log_entries.count { |e| e[:action] == 'aborted' }}
              </div>
            </div>
          </div>
      HTML

      log_entries.each_with_index do |entry, index|
        conflict_number = index + 1
        method_class = case entry[:resolution_method]
                      when /llm|ai|suggested/i then 'method-llm'
                      when /manual|user|edit/i then 'method-manual'
                      when /skip/i then 'method-skip'
                      when /abort/i then 'method-abort'
                      else 'method-llm'
                      end

        html += <<~CONFLICT_HTML
          <div class="conflict-container">
            <div class="conflict-header">
              Conflict ##{conflict_number} - Lines #{entry[:start_line]}-#{entry[:end_line]}
              <span class="method-badge #{method_class}">#{entry[:resolution_method]}</span>
            </div>
            <table class="conflict-table">
              <thead>
                <tr>
                  <th style="width: 25%">Base Branch Code</th>
                  <th style="width: 25%">Incoming Branch Code</th>
                  <th style="width: 25%">Final Resolution</th>
                  <th style="width: 25%">Resolution Details</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>
                    <div class="code-block base-code">#{escape_html(entry[:base_content] || 'N/A')}</div>
                  </td>
                  <td>
                    <div class="code-block incoming-code">#{escape_html(entry[:incoming_content] || 'N/A')}</div>
                  </td>
                  <td>
                    <div class="code-block resolution-code">#{escape_html(entry[:resolved_content] || 'N/A')}</div>
                  </td>
                  <td>
                    <div class="code-block">
                      <strong>Method:</strong> #{escape_html(entry[:resolution_method])}<br>
                      <strong>Action:</strong> #{escape_html(entry[:action])}<br>
                      <strong>Time:</strong> #{entry[:timestamp]}<br><br>
                      #{entry[:llm_suggestion] ? "<strong>LLM Analysis:</strong><br>#{escape_html(entry[:llm_suggestion])}" : ''}
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        CONFLICT_HTML
      end

      html += <<~FOOTER_HTML
          <div class="footer">
            Generated by N2B v#{N2B::VERSION} - AI-Powered Merge Conflict Resolution<br>
            <small>This log contains the complete history of merge conflict resolutions for audit and review purposes.</small>
          </div>
        </body>
        </html>
      FOOTER_HTML

      html
    end

    def escape_html(text)
      return '' if text.nil?
      text.to_s
          .gsub('&', '&amp;')
          .gsub('<', '&lt;')
          .gsub('>', '&gt;')
          .gsub('"', '&quot;')
          .gsub("'", '&#39;')
    end

    def extract_git_info
      branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip rescue 'unknown'
      {
        branch: branch.empty? ? 'unknown' : branch
      }
    end

    def determine_resolution_method(result)
      return 'Aborted' if result[:abort]
      return 'Manual Edit' if result[:reason]&.include?('manually resolved')
      return 'Manual Choice' if result[:reason]&.include?('Manually selected')
      return 'Skipped' if !result[:accepted] && !result[:abort]
      return 'LLM Suggestion' if result[:accepted] && result[:reason]
      'Unknown'
    end

    def determine_action(result)
      return 'aborted' if result[:abort]
      return 'accepted' if result[:accepted]
      return 'skipped'
    end
  end
end
