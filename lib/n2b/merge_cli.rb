require 'shellwords'
require 'rbconfig'
require 'optparse'
require 'fileutils'
require 'stringio'
require 'cgi'
require_relative 'base'
require_relative 'merge_conflict_parser'
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
            puts "#{COLOR_YELLOW}⚠️  GitHub configuration is missing or incomplete in N2B settings.#{COLOR_RESET}"
            puts ""
            puts "To set up GitHub integration, run:"
            puts "  #{COLOR_BLUE}n2b --advanced-config#{COLOR_RESET}"
            puts ""
            puts "You'll need:"
            puts "  • GitHub repository (owner/repo format)"
            puts "  • GitHub access token (generate at: https://github.com/settings/tokens)"
            puts ""
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
            puts "#{COLOR_YELLOW}⚠️  Jira configuration is missing or incomplete in N2B settings.#{COLOR_RESET}"
            puts ""
            puts "To set up Jira integration, run:"
            puts "  #{COLOR_BLUE}n2b --advanced-config#{COLOR_RESET}"
            puts ""
            puts "You'll need:"
            puts "  • Jira domain (e.g., your-company.atlassian.net)"
            puts "  • Your email address"
            puts "  • Jira API token (generate at: https://id.atlassian.com/manage-profile/security/api-tokens)"
            puts ""
            puts "Required permissions for the API token:"
            puts "  • read:project:jira"
            puts "  • read:issue:jira"
            puts "  • read:comment:jira"
            puts "  • write:comment:jira"
            puts ""
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

        # First check if the service is actually configured before asking
        service_configured = case tracker_service_name
                            when 'jira'
                              config['jira'] && config['jira']['domain'] && config['jira']['email'] && config['jira']['api_key']
                            when 'github'
                              config['github'] && config['github']['repo'] && config['github']['access_token']
                            else
                              false
                            end

        if !service_configured
          puts "\n#{COLOR_YELLOW}Note: #{tracker_service_name.capitalize} is not configured, so ticket update is not available.#{COLOR_RESET}"
          if tracker_service_name == 'jira'
            puts "Run 'n2b --advanced-config' to set up Jira integration."
          elsif tracker_service_name == 'github'
            puts "Run 'n2b --advanced-config' to set up GitHub integration."
          end
        elsif ticket_update_flag == true # --update
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
              puts "#{COLOR_RED}❌ GitHub configuration is missing. Cannot update GitHub issue.#{COLOR_RESET}"
              puts "Run 'n2b --advanced-config' to set up GitHub integration."
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
              puts "#{COLOR_RED}❌ Jira configuration is missing. Cannot update Jira ticket.#{COLOR_RESET}"
              puts "Run 'n2b --advanced-config' to set up Jira integration."
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

      vcs_type = get_vcs_type_for_file_operations

      # Convert conflict labels to actual VCS revision identifiers
      base_revision = convert_label_to_revision(block.base_label, vcs_type, :base)
      incoming_revision = convert_label_to_revision(block.incoming_label, vcs_type, :incoming)

      base_content_full = get_file_content_from_vcs(base_revision, @file_path, vcs_type) || difficulté_to_load_content_placeholder("base content from #{block.base_label}")
      incoming_content_full = get_file_content_from_vcs(incoming_revision, @file_path, vcs_type) || difficulté_to_load_content_placeholder("incoming content from #{block.incoming_label}")

      generated_html_path = nil

      begin
        loop do
          current_resolution_content_full = apply_hunk_to_full_content(full_file_content, block, suggestion['merged_code'])

          # Don't delete the HTML file immediately - keep it available for user preview

          generated_html_path = generate_conflict_preview_html(
            block,
            base_content_full,
            incoming_content_full,
            current_resolution_content_full,
            block.base_label,
            block.incoming_label,
            @file_path,
            suggestion
          )

          preview_link_message = ""
          if generated_html_path && File.exist?(generated_html_path)
            preview_link_message = "🌐 #{COLOR_BLUE}Preview: file://#{generated_html_path}#{COLOR_RESET}"
          else
            preview_link_message = "#{COLOR_YELLOW}⚠️  Could not generate HTML preview.#{COLOR_RESET}"
          end
          puts preview_link_message

          print_conflict(block)
          print_suggestion(suggestion)

          prompt_message = <<~PROMPT
            #{COLOR_YELLOW}Actions: [y] Accept, [n] Skip, [c] Comment, [e] Edit, [p] Preview, [s] Refresh, [a] Abort#{COLOR_RESET}
            #{COLOR_GRAY}(Preview link above can be cmd/ctrl+clicked if your terminal supports it){COLOR_RESET}
            #{COLOR_YELLOW}Your choice: #{COLOR_RESET}
          PROMPT
          print prompt_message
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
            current_file_on_disk = File.exist?(@file_path) ? File.read(@file_path) : full_file_content
            full_file_content = current_file_on_disk
            suggestion = request_merge_with_spinner(block, config, comment, full_file_content)
            puts "#{COLOR_GREEN}✅ New suggestion ready!#{COLOR_RESET}\n"
            # Loop continues, will regenerate preview
          when 'e'
            edit_result = handle_editor_workflow(block, config, full_file_content)
            if edit_result[:resolved]
              return {accepted: true, merged_code: edit_result[:merged_code], reason: edit_result[:reason], comment: comment}
            elsif edit_result[:updated_content]
              full_file_content = edit_result[:updated_content]
              puts "#{COLOR_YELLOW}🤖 Content changed by editor. Re-analyzing for new suggestion...#{COLOR_RESET}"
              suggestion = request_merge_with_spinner(block, config, comment, full_file_content)
            end
            # Loop continues, will regenerate preview
          when 'p' # Open Preview in Browser
            if generated_html_path && File.exist?(generated_html_path)
              puts "#{COLOR_BLUE}🌐 Opening preview in browser...#{COLOR_RESET}"
              open_html_in_browser(generated_html_path)
            else
              puts "#{COLOR_YELLOW}⚠️  No preview available to open.#{COLOR_RESET}"
            end
            # Loop continues, no changes to suggestion
          when 's' # Refresh Preview
            puts "#{COLOR_BLUE}🔄 Refreshing suggestion and preview...#{COLOR_RESET}"
            suggestion = request_merge_with_spinner(block, config, comment, full_file_content)
            # Loop continues, preview will be regenerated
          when 'a'
            return {abort: true, merged_code: suggestion['merged_code'], reason: suggestion['reason'], comment: comment}
          when '', nil
            puts "#{COLOR_RED}Please enter a valid choice.#{COLOR_RESET}"
          else
            puts "#{COLOR_RED}Invalid option. Please choose from the available actions.#{COLOR_RESET}"
          end
        end
      ensure
        FileUtils.rm_f(generated_html_path) if generated_html_path && File.exist?(generated_html_path)
      end
    end

    def difficulté_to_load_content_placeholder(description)
      # Helper to return a placeholder if VCS content fails, aiding debug in preview
      "N2B: Could not load #{description}. Displaying this placeholder."
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
              .gsub('{start_line}', block.start_line.to_s)
              .gsub('{end_line}', block.end_line.to_s)
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
      editor_command = config.dig('editor', 'command')
      editor_type = config.dig('editor', 'type')
      editor_configured = config.dig('editor', 'configured')

      lines = File.readlines(@file_path, chomp: true)
      current_block_content_with_markers = lines[(block.start_line - 1)...block.end_line].join("\n")

      if editor_configured && editor_command && editor_type == 'diff_tool'
        require 'tmpdir'
        Dir.mktmpdir("n2b_diff_") do |tmpdir|
          base_file_path = File.join(tmpdir, "base_#{File.basename(@file_path)}")
          remote_file_path = File.join(tmpdir, "remote_#{File.basename(@file_path)}")
          merged_file_path = File.join(tmpdir, "merged_#{File.basename(@file_path)}")

          File.write(base_file_path, block.base_content)
          File.write(remote_file_path, block.incoming_content)

          # Initial content for the merged file: LLM suggestion or current block with markers
          initial_merged_content = block.suggestion&.dig('merged_code')
          if initial_merged_content.nil? || initial_merged_content.strip.empty?
            initial_merged_content = current_block_content_with_markers
          end
          File.write(merged_file_path, initial_merged_content)

          # Common pattern: tool base merged remote. Some tools might vary.
          # Example: meld uses local remote base --output output_file
          # For now, using a common sequence. Needs documentation for custom tools.
          # We assume the tool edits the `merged_file_path` (second argument) in place or uses it as output.
          full_diff_command = "#{editor_command} #{Shellwords.escape(base_file_path)} #{Shellwords.escape(merged_file_path)} #{Shellwords.escape(remote_file_path)}"
          puts "#{COLOR_BLUE}🔧 Launching diff tool: #{editor_command}...#{COLOR_RESET}"
          puts "#{COLOR_GRAY}   Base:   #{base_file_path}#{COLOR_RESET}"
          puts "#{COLOR_GRAY}   Remote: #{remote_file_path}#{COLOR_RESET}"
          puts "#{COLOR_GRAY}   Merged: #{merged_file_path} (edit this one)#{COLOR_RESET}"

          system(full_diff_command)

          puts "#{COLOR_BLUE}📁 Diff tool closed.#{COLOR_RESET}"
          merged_code_from_editor = File.read(merged_file_path)

          # Check if the merged content is different from the initial content with markers
          # to avoid considering unchanged initial conflict markers as a resolution.
          if merged_code_from_editor.strip == current_block_content_with_markers.strip && merged_code_from_editor.include?('<<<<<<<')
             puts "#{COLOR_YELLOW}⚠️  It seems the conflict markers are still present. Did you resolve the conflict?#{COLOR_RESET}"
          end

          print "#{COLOR_YELLOW}Did you resolve this conflict using the diff tool? [y/n]: #{COLOR_RESET}"
          response = $stdin.gets&.strip&.downcase
          if response == 'y'
            puts "#{COLOR_GREEN}✅ Conflict marked as resolved by user via diff tool#{COLOR_RESET}"
            return {
              resolved: true,
              merged_code: merged_code_from_editor,
              reason: "User resolved conflict with diff tool: #{editor_command}"
            }
          else
            puts "#{COLOR_BLUE}🔄 Conflict not marked as resolved. Continuing with AI assistance...#{COLOR_RESET}"
            # If user says 'n', we don't use the content from the diff tool as a resolution.
            # We might need to re-fetch LLM suggestion or just go back to menu.
            # For now, return resolved: false. The updated_content is not from the main file.
            return { resolved: false, updated_content: full_file_content } # original full_file_content
          end
        end # Tempdir is automatically removed
      else
        # Fallback to text editor or if editor is 'text_editor'
        editor_to_use = editor_command || detect_system_editor # Use configured or system editor

        original_file_content_for_block_check = File.read(@file_path) # Before text editor opens it

        puts "#{COLOR_BLUE}🔧 Opening #{@file_path} in editor (#{editor_to_use})...#{COLOR_RESET}"
        open_file_in_editor(@file_path, editor_to_use) # Pass specific editor
        puts "#{COLOR_BLUE}📁 Editor closed. Checking for changes...#{COLOR_RESET}"

        current_file_content_after_edit = File.read(@file_path)

        if file_changed?(original_file_content_for_block_check, current_file_content_after_edit)
          puts "#{COLOR_YELLOW}📝 File has been modified.#{COLOR_RESET}"
          print "#{COLOR_YELLOW}Did you resolve this conflict yourself in the editor? [y/n]: #{COLOR_RESET}"
          response = $stdin.gets&.strip&.downcase

          if response == 'y'
            puts "#{COLOR_GREEN}✅ Conflict marked as resolved by user in text editor#{COLOR_RESET}"
            # Extract the changed block content
            # Re-read lines as they might have changed in number
            edited_lines = File.readlines(@file_path, chomp: true)
            # Heuristic: if lines were added/removed, block boundaries might shift.
            # For simplicity, we'll use original block's line numbers to extract,
            # but this might be inaccurate if user adds/removes many lines *outside* the conflict block.
            # A more robust way would be to re-parse or use markers if they exist.
            # For now, assume user edits primarily *within* the original start/end lines.
            # The number of lines in the resolved code could be different.
            # We need to ask the user to ensure the markers are gone.

            # Let's get the content of the lines that corresponded to the original block.
            # This isn't perfect if the user adds/deletes lines *within* the block,
            # changing its length. The LLM's suggestion is for a block of a certain size.
            # For user resolution, they define the new block.
            # We need to get the content from start_line to (potentially new) end_line.
            # This is tricky. The simplest is to take the whole file, but that's not what merge tools do.
            # The contract is that the user removed the conflict markers.

            # We will return the content of the file from the original start line
            # to an end line that reflects the number of lines in the manually merged code.
            # This is still tricky. Let's assume the user edited the block and the surrounding lines are stable.
            # The `resolve_block` method replaces `lines[(block.start_line-1)...block.end_line]`
            # So, the returned `merged_code` should be what replaces that segment.

            # Simplest approach: user confirms resolution, we assume the relevant part of the file is the resolution.
            # We need to extract the content of the resolved block from current_file_content_after_edit
            # based on block.start_line and the *new* end_line of the resolved conflict.
            # This is hard without re-parsing.
            # A practical approach: The user resolved it. The file is now correct *at those lines*.
            # The `resolve_block` method will write the *entire* `lines` array back to the file.
            # If the user resolved it, the `lines` array (after their edit) IS the resolution for that part.
            # So, we need to give `resolve_block` the lines from the file that correspond to the original block markers.
            # This means the `merged_code` should be the content of the file from `block.start_line`
            # up to where the `block.end_line` *would* be after their edits.

            # Let's refine: the user has edited the file. The section of the file
            # that previously contained the conflict markers (block.start_line to block.end_line)
            # now contains their resolution. We need to extract this segment.
            # The number of lines might have changed.
            # The `resolve_block` function will replace `lines[original_start_idx..original_end_idx]` with the new content.
            # So we must provide the exact lines that should go into that slice.

            # We need to ask the user to confirm the new end line if it changed, or trust they know.
            # The simplest is to return the segment from the file from original start_line to original end_line,
            # assuming the user's changes fit there. This is too naive.

            # If the user says 'y', the file is considered resolved in that region.
            # The `resolve_block` will then write the `lines` array (which is `current_file_content_after_edit.split("\n")`)
            # back to the file. The key is that `resolve_block` *already has* the full `lines` from the modified file
            # when it reconstructs the file if result[:accepted] is true.
            # So, the `merged_code` we return here is more for logging/consistency.
            # The critical part is that `lines` in `resolve_block` needs to be updated if the file was changed by the editor.

            # The `resolve_block` method reads `lines = File.readlines(@file_path, chomp: true)` at the beginning.
            # If we edit the file here, `lines` in `resolve_block` becomes stale.
            # This means `handle_editor_workflow` must return the *new* full file content if it changed.
            # And the `merged_code` for the log should be the segment of the new file.

            # Let's re-read the file and extract the relevant segment for the log.
            # The actual application of changes happens because `resolve_block` will use the modified `lines` array.
            # We need to estimate the new end_line. This is complex.
            # For now, let's just say "user resolved". The actual diff applied will be based on the whole file change.
            # The `merged_code` for logging can be a placeholder or the new content of the block.
            # Let's assume the user ensures the markers are gone.
            # The content of lines from block.start_line to block.end_line in the *new file* is their resolution.
            # The number of lines in this resolution can be different from the original block.
            # This is fine, as the `replacement` in `resolve_block` handles this.

            # Simplification: if user says 'y', the code that will be used is the content
            # of the file from block.start_line to some new end_line.
            # The crucial part is that `resolve_block` needs to operate on the *modified* file content.
            # So, we should pass `current_file_content_after_edit` back up.
            # And for logging, extract the lines from `block.start_line` to `block.end_line` from this new content.
            # This assumes the user's resolution fits within the original line numbers, which is not always true.

            # The most robust is to re-parse the file for conflict markers. If none are found in this region, it's resolved.
            # The "merged_code" would be the lines from the edited file that replaced the original conflict.

            # Let's assume the user has resolved the conflict markers from `block.start_line` to `block.end_line`.
            # The content of these lines in `current_file_content_after_edit` is the resolution.
            # The number of lines of this resolution might be different.
            # The `resolve_block` needs to replace `lines[(block.start_line-1)...block.end_line]`
            # The `merged_code` should be this new segment.

            # For now, let `merged_code` be a conceptual value. The `resolve_block` loop needs to use the new file content.
            # The key is `updated_content` for the main loop, and `merged_code` for logging.

            # The `resolve_block` method needs to use the content of the file *after* the edit.
            # The current structure of `resolve_block` re-reads `lines` only if `request_merge_with_spinner` is called again.
            # This needs adjustment.

            # For now, if user says 'y':
            # 1. The `merged_code` will be what's in the file from `block.start_line` to `block.end_line` (original numbering).
            #    This is imperfect for logging if lines were added/removed.
            # 2. The `resolve_block` loop must use `current_file_content_after_edit` for its `lines` variable.
            #    This is the most important part for correctness.

            # Let's return the segment from the modified file for `merged_code`.
            # This is still tricky because `block.end_line` is from the original parse.
            # If user deleted lines, `block.end_line` might be out of bounds for `edited_lines`.
            # If user added lines, we wouldn't capture all of it.

            # Simplest for now: the user resolved it. The merged_code for logging can be a placeholder.
            # The main thing is that `resolve_block` now operates on `current_file_content_after_edit`.
            # The subtask asks for `merged_code` to be `<content_from_editor_or_file>`.
            # This means the content of the resolved block.

            # Let's try to extract the content from the edited file using original line numbers as a guide.
            # This is a known limitation. A better way would be for user to indicate new block end.
            resolved_segment = edited_lines[(block.start_line - 1)..[block.end_line - 1]].join("\n") rescue "User resolved - content not easily extracted due to line changes"
            if edited_lines.slice((block.start_line-1)...(block.end_line)).join("\n").include?("<<<<<<<")
                puts "#{COLOR_YELLOW}⚠️  Conflict markers seem to still be present in the edited file. Please ensure they are removed for proper resolution.#{COLOR_RESET}"
            end


            return {
              resolved: true,
              merged_code: resolved_segment, # Content from the file for the resolved block
              reason: "User resolved conflict in text editor: #{editor_to_use}",
              updated_content: current_file_content_after_edit # Pass back the full content
            }
          else
            puts "#{COLOR_BLUE}🔄 Conflict not marked as resolved. Continuing with AI assistance...#{COLOR_RESET}"
            return {
              resolved: false,
              updated_content: current_file_content_after_edit # Pass back the full content
            }
          end
        else
          puts "#{COLOR_GRAY}📋 No changes detected in the file. Continuing...#{COLOR_RESET}"
          return { resolved: false, updated_content: nil } # No changes, so original full_file_content is still valid
        end
      end
    end

    def detect_system_editor
      # This is the ultimate fallback if no configuration is set.
      # The ENV['EDITOR'] || ENV['VISUAL'] check should be done by the caller if preferred before this.
      case RbConfig::CONFIG['host_os']
      when /darwin|mac os/
        'open' # Typically non-blocking, might need different handling or user awareness.
      when /linux/
        # Prefer common user-friendly editors if available, then vi as fallback.
        # This simple version just picks one. `command_exists?` could be used here.
        ENV['EDITOR'] || ENV['VISUAL'] || 'nano' # or 'vi'
      when /mswin|mingw/
        ENV['EDITOR'] || ENV['VISUAL'] || 'notepad'
      else
        ENV['EDITOR'] || ENV['VISUAL'] || 'vi' # vi is a common default on Unix-like systems
      end
    end

    def open_file_in_editor(file_path, editor_command = nil)
      # If no specific editor_command is passed, try configured editor, then system fallbacks.
      # This method is now simplified as the decision of *which* editor (configured vs fallback)
      # is made in handle_editor_workflow. This method just executes it.
      # However, the original call from resolve_block (before this change) did not pass editor_command.
      # So, if editor_command is nil, we should still try to get it from config or fallback.

      effective_editor = editor_command # Use passed command if available

      if effective_editor.nil?
        config = get_config(reconfigure: false, advanced_flow: false) # Ensure config is loaded
        effective_editor = config.dig('editor', 'command') if config.dig('editor', 'configured')
        effective_editor ||= detect_system_editor # Ultimate fallback
      end

      puts "#{COLOR_GRAY}Attempting to open with: #{effective_editor} #{Shellwords.escape(file_path)}#{COLOR_RESET}"
      begin
        if RbConfig::CONFIG['host_os'] =~ /darwin|mac os/ && effective_editor == 'open'
          # 'open' is non-blocking. This is fine.
          result = system("open #{Shellwords.escape(file_path)}")
          unless result
            # `system` returns true if command found and exited with 0, false otherwise for `open`.
            # It returns nil if command execution fails.
            puts "#{COLOR_YELLOW}⚠️  'open' command might have failed or file opened in background. Please check manually.#{COLOR_RESET}"
          end
          # For 'open', we don't wait. User needs to manually come back.
          # Consider adding a prompt "Press Enter after closing the editor..." for non-blocking editors.
          # For now, keeping it simple.
        else
          # For most terminal editors, system() will block until the editor is closed.
          system("#{effective_editor} #{Shellwords.escape(file_path)}")
        end
      rescue StandardError => e
        puts "#{COLOR_RED}❌ Failed to open editor '#{effective_editor}': #{e.message}#{COLOR_RESET}"
        puts "#{COLOR_YELLOW}💡 Please ensure your configured editor is correct or set your EDITOR environment variable.#{COLOR_RESET}"
        puts "#{COLOR_BLUE}You may need to open #{file_path} manually in your preferred editor to make changes.#{COLOR_RESET}"
        print "#{COLOR_YELLOW}Press Enter to continue after manually editing (if you choose to do so)...#{COLOR_RESET}"
        $stdin.gets # Pause to allow manual editing
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

    private # Ensure all subsequent methods are private unless specified

    def get_vcs_type_for_file_operations
      # Leverages existing get_vcs_type but more for file content retrieval context
      get_vcs_type
    end

    def convert_label_to_revision(label, vcs_type, side)
      # Convert conflict marker labels to actual VCS revision identifiers
      case vcs_type
      when :git
        case label.downcase
        when /head|working.*copy|current/
          'HEAD'
        when /merge.*rev|incoming|branch/
          'MERGE_HEAD'
        else
          # If it's already a valid Git revision, use it as-is
          label
        end
      when :hg
        case label.downcase
        when /working.*copy|current/
          '.'  # Current working directory parent
        when /merge.*rev|incoming|branch/
          'p2()'  # Second parent (incoming branch)
        else
          # If it's already a valid Mercurial revision, use it as-is
          label
        end
      else
        label
      end
    end

    def get_file_content_from_vcs(label, file_path, vcs_type)
      # Note: file_path is the path in the working directory.
      # VCS commands often need path relative to repo root if not run from root.
      # Assuming execution from repo root or that file_path is appropriately relative.
      # Pathname can help make it relative if needed:
      # relative_file_path = Pathname.new(File.absolute_path(file_path)).relative_path_from(Pathname.new(Dir.pwd)).to_s

      # A simpler approach for `git show` is that it usually works with paths from repo root.
      # If @file_path is already relative to repo root or absolute, it might just work.
      # For robustness, ensuring it's relative to repo root is better.
      # However, current `execute_vcs_diff` uses `Dir.pwd`, implying commands are run from current dir.
      # Let's assume file_path as given is suitable for now.

      command = case vcs_type
                when :git
                  # For git show <commit-ish>:<path>, path is usually from repo root.
                  # If @file_path is not from repo root, this might need adjustment.
                  # Let's assume @file_path is correctly specified for this context.
                  "git show #{Shellwords.escape(label)}:#{Shellwords.escape(file_path)}"
                when :hg
                  "hg cat -r #{Shellwords.escape(label)} #{Shellwords.escape(file_path)}"
                else
                  nil
                end

      return nil unless command

      begin
        # Timeout might be needed for very large files or slow VCS.
        content = `#{command}` # Using backticks captures stdout
        # Check $? for command success.
        # `git show` returns 0 on success, non-zero otherwise (e.g. 128 if path not found).
        # `hg cat` also returns 0 on success.
        return content if $?.success?

        # If command failed, log a warning but don't necessarily halt everything.
        # The preview will just show empty for that panel.
        puts "#{COLOR_YELLOW}Warning: VCS command '#{command}' failed or returned no content. Exit status: #{$?.exitstatus}.#{COLOR_RESET}"
        nil
      rescue StandardError => e
        puts "#{COLOR_YELLOW}Warning: Could not fetch content for '#{file_path}' from VCS label '#{label}': #{e.message}#{COLOR_RESET}"
        nil
      end
    end

    def apply_hunk_to_full_content(original_full_content_with_markers, conflict_block_details, resolved_hunk_text)
      return original_full_content_with_markers if resolved_hunk_text.nil?

      lines = original_full_content_with_markers.lines.map(&:chomp)
      # Convert 1-based line numbers from block_details to 0-based array indices
      start_idx = conflict_block_details.start_line - 1
      end_idx = conflict_block_details.end_line - 1

      # Basic validation of indices
      if start_idx < 0 || start_idx >= lines.length || end_idx < start_idx || end_idx >= lines.length
        # This case should ideally not happen if block_details are correct
        # Return original content or handle error appropriately
        # For preview, it's safer to show the original content with markers if hunk application is problematic
        return original_full_content_with_markers
      end

      hunk_lines = resolved_hunk_text.lines.map(&:chomp)

      new_content_lines = []
      new_content_lines.concat(lines[0...start_idx]) if start_idx > 0 # Lines before the conflict block
      new_content_lines.concat(hunk_lines) # The resolved hunk
      new_content_lines.concat(lines[(end_idx + 1)..-1]) if (end_idx + 1) < lines.length # Lines after the conflict block

      new_content_lines.join("\n")
    end

    # --- HTML Preview Generation ---

    # private (already established)

    def get_language_class(file_path)
      ext = File.extname(file_path).downcase
      case ext
      when '.rb' then 'ruby'
      when '.js' then 'javascript'
      when '.py' then 'python'
      when '.java' then 'java'
      when '.c', '.h', '.cpp', '.hpp' then 'cpp'
      when '.cs' then 'csharp'
      when '.go' then 'go'
      when '.php' then 'php'
      when '.ts' then 'typescript'
      when '.swift' then 'swift'
      when '.kt', '.kts' then 'kotlin'
      when '.rs' then 'rust'
      when '.scala' then 'scala'
      when '.pl' then 'perl'
      when '.pm' then 'perl'
      when '.sh' then 'bash'
      when '.html', '.htm', '.xhtml', '.xml' then 'xml' # Highlight.js uses 'xml' for HTML
      when '.css' then 'css'
      when '.json' then 'json'
      when '.yml', '.yaml' then 'yaml'
      when '.md', '.markdown' then 'markdown'
      else
        '' # Let Highlight.js auto-detect or default to plain text
      end
    end

    def find_sub_content_lines(full_content, sub_content)
      return nil if sub_content.nil? || sub_content.empty?
      full_lines = full_content.lines.map(&:chomp)
      sub_lines = sub_content.lines.map(&:chomp)

      return nil if sub_lines.empty?

      full_lines.each_with_index do |_, index|
        match = true
        sub_lines.each_with_index do |sub_line_content, sub_index|
          unless full_lines[index + sub_index] == sub_line_content
            match = false
            break
          end
        end
        return { start: index + 1, end: index + sub_lines.length } if match # 1-based line numbers
      end
      nil
    end

    def generate_conflict_preview_html(block_details, base_content_full, incoming_content_full, current_resolution_content_full, base_branch_name, incoming_branch_name, file_path, llm_suggestion = nil)
      require 'cgi' # For CGI.escapeHTML
      require 'fileutils' # For FileUtils.mkdir_p
      require 'shellwords' # For Shellwords.escape, already used elsewhere but good to have contextually
      require 'rbconfig' # For RbConfig::CONFIG

      lang_class = get_language_class(file_path)

      # Find line numbers for highlighting
      # These are line numbers within their respective full_content strings (1-based)
      base_highlight_lines = find_sub_content_lines(base_content_full, block_details.base_content)
      incoming_highlight_lines = find_sub_content_lines(incoming_content_full, block_details.incoming_content)

      # For resolution, highlight the conflict area within the full resolution content
      # The current_resolution_content_full already contains the resolved content
      # We'll highlight the same line range as the original conflict
      resolution_highlight_lines = { start: block_details.start_line, end: block_details.end_line }

      html_content = StringIO.new
      html_content << "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
      html_content << "  <meta charset=\"UTF-8\">\n"
      html_content << "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
      html_content << "  <title>Conflict Preview: #{CGI.escapeHTML(File.basename(file_path))}</title>\n"
      html_content << "  <link rel=\"stylesheet\" href=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/default.min.css\">\n"
      html_content << "  <script src=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js\"></script>\n"
      # Optional: specific languages if needed, e.g.,
      # html_content << "  <script src=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/#{lang_class}.min.js\"></script>\n" if lang_class && !lang_class.empty?

      html_content << "  <style>\n"
      html_content << "    body { font-family: sans-serif; margin: 0; display: flex; flex-direction: column; height: 100vh; }\n"
      html_content << "    .header { padding: 10px; background-color: #f0f0f0; border-bottom: 1px solid #ccc; text-align: center; }\n"
      html_content << "    .header h2 { margin: 0; }\n"
      html_content << "    .llm-message { padding: 10px; background-color: #e8f4fd; border-bottom: 1px solid #ccc; margin: 0; }\n"
      html_content << "    .llm-message h3 { margin: 0 0 5px 0; color: #1976d2; font-size: 0.9em; }\n"
      html_content << "    .llm-message p { margin: 0; color: #424242; font-size: 0.85em; line-height: 1.3; }\n"
      html_content << "    .columns-container { display: flex; flex: 1; overflow: hidden; }\n"
      html_content << "    .column { flex: 1; padding: 0; border-left: 1px solid #ccc; overflow-y: auto; display: flex; flex-direction: column; }\n"
      html_content << "    .column:first-child { border-left: none; }\n"
      html_content << "    .column h3 { background-color: #e0e0e0; padding: 8px 10px; margin: 0; border-bottom: 1px solid #ccc; text-align: center; font-size: 1em; }\n"
      html_content << "    .code-container { flex: 1; overflow-y: auto; position: relative; }\n"
      html_content << "    pre { margin: 0; padding: 0; height: 100%; }\n"
      html_content << "    code { display: block; padding: 10px 10px 10px 60px; font-family: 'SF Mono', Monaco, Inconsolata, 'Fira Code', monospace; font-size: 0.85em; line-height: 1.4em; }\n"
      html_content << "    .line { display: block; position: relative; }\n"
      html_content << "    .line-number { position: absolute; left: 0; width: 50px; padding-right: 10px; text-align: right; color: #999; user-select: none; font-size: 0.8em; background-color: #f8f8f8; border-right: 1px solid #e0e0e0; }\n"
      html_content << "    .conflict-lines-base { background-color: #ffebee; border-left: 3px solid #f44336; }\n"
      html_content << "    .conflict-lines-incoming { background-color: #e3f2fd; border-left: 3px solid #2196f3; }\n"
      html_content << "    .conflict-lines-resolution { background-color: #e8f5e9; border-left: 3px solid #4caf50; }\n"
      html_content << "    @media (max-width: 768px) { .columns-container { flex-direction: column; } .column { border-left: none; border-top: 1px solid #ccc;} }\n"
      html_content << "  </style>\n</head>\n<body>\n"

      html_content << "  <div class=\"header\"><h2>Conflict Preview: #{CGI.escapeHTML(file_path)}</h2></div>\n"

      # Add LLM message section if available
      if llm_suggestion && llm_suggestion['reason']
        html_content << "  <div class=\"llm-message\">\n"
        html_content << "    <h3>🤖 AI Analysis & Suggestion</h3>\n"
        html_content << "    <p>#{CGI.escapeHTML(llm_suggestion['reason'])}</p>\n"
        html_content << "  </div>\n"
      end

      html_content << "  <div class=\"columns-container\">\n"

      # Helper to generate HTML for one column
      generate_column_html = lambda do |title, full_code, highlight_info, highlight_class_suffix|
        html_content << "    <div class=\"column\">\n"
        html_content << "      <h3>#{CGI.escapeHTML(title)}</h3>\n"
        html_content << "      <div class=\"code-container\">\n" # Wrapper for scrolling
        html_content << "        <pre><code class=\"#{lang_class}\">\n"

        full_code.lines.each_with_index do |line_text, index|
          line_number = index + 1
          line_class = "line"
          if highlight_info && line_number >= highlight_info[:start] && line_number <= highlight_info[:end]
            line_class += " conflict-lines conflict-lines-#{highlight_class_suffix}"
          end
          html_content << "<span class=\"#{line_class}\"><span class=\"line-number\">#{line_number}</span>#{CGI.escapeHTML(line_text.chomp)}</span>\n"
        end

        html_content << "        </code></pre>\n"
        html_content << "      </div>\n" # end .code-container
        html_content << "    </div>\n" # end .column
      end

      generate_column_html.call("Base (#{base_branch_name})", base_content_full, base_highlight_lines, "base")
      generate_column_html.call("Incoming (#{incoming_branch_name})", incoming_content_full, incoming_highlight_lines, "incoming")
      generate_column_html.call("Current Resolution", current_resolution_content_full, resolution_highlight_lines, "resolution")

      html_content << "  </div>\n" # end .columns-container
      html_content << "  <script>hljs.highlightAll();</script>\n"
      html_content << "</body>\n</html>"

      # Save to file with unique but persistent naming
      log_dir = '.n2b_merge_log'
      FileUtils.mkdir_p(log_dir)

      # Create a more stable filename based on file path and conflict location
      file_basename = File.basename(file_path, '.*')
      conflict_id = "#{block_details.start_line}_#{block_details.end_line}"
      preview_filename = "conflict_#{file_basename}_lines_#{conflict_id}.html"
      full_preview_path = File.join(log_dir, preview_filename)

      File.write(full_preview_path, html_content.string)

      return File.absolute_path(full_preview_path)
    end

    def open_html_in_browser(html_file_path)
      absolute_path = File.absolute_path(html_file_path)
      # Ensure correct file URL format for different OSes, especially Windows
      file_url = if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
                   "file:///#{absolute_path.gsub("\\", "/")}" # Windows needs forward slashes
                 else
                   "file://#{absolute_path}"
                 end

      command = nil
      os = RbConfig::CONFIG['host_os']

      case os
      when /darwin|mac os/
        command = "open #{Shellwords.escape(file_url)}"
      when /linux/
        # Check for WSL environment, as xdg-open might not work as expected directly
        # or might open browser inside WSL, not on Windows host.
        # Powershell.exe can be used to open it on Windows host from WSL.
        if ENV['WSL_DISTRO_NAME'] || (ENV['IS_WSL'] == 'true') || File.exist?('/proc/sys/fs/binfmt_misc/WSLInterop')
          # Using powershell.exe to open the URL on the Windows host
          # Ensure the file_url is accessible from Windows (e.g. via /mnt/c/...)
          # This assumes the path is already a Windows-accessible path if running in WSL context
          # or that the user has set up their environment for this.
          # For file URLs, it's often better to translate to Windows path format.
          windows_path = absolute_path.gsub(%r{^/mnt/([a-z])}, '\1:') # Basic /mnt/c -> C:
          command = "powershell.exe -c \"Start-Process '#{windows_path}'\""
          puts "#{COLOR_YELLOW}Detected WSL, attempting to open in Windows browser: #{command}#{COLOR_RESET}"
        else
          command = "xdg-open #{Shellwords.escape(file_url)}"
        end
      when /mswin|mingw|cygwin/ # Windows
        # `start` command with an empty title "" for paths with spaces
        command = "start \"\" \"#{file_url.gsub("file:///", "")}\"" # `start` takes path directly
      else
        puts "#{COLOR_YELLOW}Unsupported OS: #{os}. Cannot open browser automatically.#{COLOR_RESET}"
        return false
      end

      if command
        puts "#{COLOR_BLUE}Attempting to open preview in browser: #{command}#{COLOR_RESET}"
        begin
          success = system(command)
          unless success
            # system() returns false if command executes with non-zero status, nil if command fails to execute
            puts "#{COLOR_RED}Failed to execute command to open browser. Exit status: #{$?.exitstatus if $?}.#{COLOR_RESET}"
            raise "Command execution failed" # Will be caught by rescue
          end
          puts "#{COLOR_GREEN}Preview should now be open in your browser.#{COLOR_RESET}"
          return true
        rescue => e
          puts "#{COLOR_RED}Failed to automatically open the HTML preview: #{e.message}#{COLOR_RESET}"
        end
      end

      puts "#{COLOR_YELLOW}Please open it manually: #{file_url}#{COLOR_RESET}"
      false
    end

  end
end
