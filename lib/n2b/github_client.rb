require 'net/http'
require 'uri'
require 'json'
require_relative 'template_engine'

module N2B
  class GitHubClient
    class GitHubApiError < StandardError; end

    def initialize(config)
      @config = config
      @github_config = @config['github'] || {}
      unless @github_config['repo'] && @github_config['access_token']
        raise ArgumentError, "GitHub repo and access token must be configured in N2B settings."
      end
      @api_base = @github_config['api_base'] || 'https://api.github.com'
    end

    def fetch_issue(issue_input)
      repo, number = parse_issue_input(issue_input)
      begin
        issue_data = make_api_request('GET', "/repos/#{repo}/issues/#{number}")
        comments = make_api_request('GET', "/repos/#{repo}/issues/#{number}/comments")
        format_issue_for_requirements(repo, issue_data, comments)
      rescue GitHubApiError => e
        puts "⚠️  Failed to fetch from GitHub API: #{e.message}"
        fetch_dummy_issue_data(repo, number)
      end
    end

    def update_issue(issue_input, comment_data)
      repo, number = parse_issue_input(issue_input)
      body_text = comment_data.is_a?(String) ? comment_data : generate_templated_comment(comment_data)
      body = { 'body' => body_text }
      make_api_request('POST', "/repos/#{repo}/issues/#{number}/comments", body)
      puts "✅ Successfully added comment to GitHub issue #{repo}##{number}"
      true
    rescue GitHubApiError => e
      puts "❌ Failed to update GitHub issue #{repo}##{number}: #{e.message}"
      false
    end

    def generate_templated_comment(comment_data)
      template_data = prepare_template_data(comment_data)
      template_path = resolve_template_path('github_comment', @config)
      template_content = File.read(template_path)
      engine = N2B::TemplateEngine.new(template_content, template_data)
      engine.render
    end

    def prepare_template_data(comment_data)
      errors = comment_data[:issues] || comment_data['issues'] || []
      critical_errors = []
      important_errors = []

      errors.each do |error|
        severity = classify_error_severity(error)
        file_ref = extract_file_reference(error)
        item = {
          'file_reference' => file_ref,
          'description' => clean_error_description(error)
        }
        case severity
        when 'CRITICAL'
          critical_errors << item
        else
          important_errors << item
        end
      end

      improvements = (comment_data[:improvements] || comment_data['improvements'] || []).map do |imp|
        {
          'file_reference' => extract_file_reference(imp),
          'description' => clean_error_description(imp)
        }
      end

      missing_tests = extract_missing_tests(comment_data[:test_coverage] || comment_data['test_coverage'] || '')
      requirements = extract_requirements_status(comment_data[:requirements_evaluation] || comment_data['requirements_evaluation'] || '')

      git_info = extract_git_info

      {
        'implementation_summary' => comment_data[:implementation_summary] || comment_data['implementation_summary'] || 'Code analysis completed',
        'critical_errors' => critical_errors,
        'important_errors' => important_errors,
        'improvements' => improvements,
        'missing_tests' => missing_tests,
        'requirements' => requirements,
        'timestamp' => Time.now.strftime('%Y-%m-%d %H:%M UTC'),
        'branch_name' => git_info[:branch],
        'files_changed' => git_info[:files_changed],
        'lines_added' => git_info[:lines_added],
        'lines_removed' => git_info[:lines_removed],
        'critical_errors_empty' => critical_errors.empty?,
        'important_errors_empty' => important_errors.empty?,
        'improvements_empty' => improvements.empty?,
        'missing_tests_empty' => missing_tests.empty?
      }
    end

    def classify_error_severity(error_text)
      text = error_text.downcase
      case text
      when /security|sql injection|xss|csrf|vulnerability|exploit|attack/
        'CRITICAL'
      when /performance|n\+1|timeout|memory leak|slow query|bottleneck/
        'IMPORTANT'
      when /error|exception|bug|fail|crash|break/
        'IMPORTANT'
      when /style|convention|naming|format|indent|space/
        'LOW'
      else
        'IMPORTANT'
      end
    end

    def extract_file_reference(text)
      if match = text.match(/(\S+\.(?:rb|js|py|java|cpp|c|h|ts|jsx|tsx|php|go|rs|swift|kt))(?:\s+(?:line|lines?)\s+(\d+(?:-\d+)?)|:(\d+(?:-\d+)?)|\s*\(line\s+(\d+)\))?/i)
        file = match[1]
        line = match[2] || match[3] || match[4]
        line ? "#{file}:#{line}" : file
      else
        'General'
      end
    end

    def clean_error_description(text)
      text.gsub(/\S+\.(?:rb|js|py|java|cpp|c|h|ts|jsx|tsx|php|go|rs|swift|kt)(?:\s+(?:line|lines?)\s+\d+(?:-\d+)?|:\d+(?:-\d+)?|\s*\(line\s+\d+\))?:?\s*/i, '').strip
    end

    def extract_missing_tests(test_coverage_text)
      missing_tests = []
      test_coverage_text.scan(/(?:missing|need|add|require).*?test.*?(?:\.|$)/i) do |match|
        missing_tests << { 'description' => match.strip }
      end
      if missing_tests.empty? && test_coverage_text.include?('%')
        if coverage_match = test_coverage_text.match(/(\d+)%/)
          coverage = coverage_match[1].to_i
          if coverage < 80
            missing_tests << { 'description' => "Increase test coverage from #{coverage}% to target 80%+" }
          end
        end
      end
      missing_tests
    end

    def extract_requirements_status(requirements_text)
      requirements = []
      requirements_text.split("\n").each do |line|
        line = line.strip
        next if line.empty?
        if match = line.match(/(✅|⚠️|❌|🔍)?\s*(PARTIALLY\s+IMPLEMENTED|NOT\s+IMPLEMENTED|IMPLEMENTED|UNCLEAR)?:?\s*(.+)/i)
          status_emoji, status_text, description = match.captures
          status = case
                   when status_text&.include?('PARTIALLY')
                     'PARTIALLY_IMPLEMENTED'
                   when status_text&.include?('NOT')
                     'NOT_IMPLEMENTED'
                   when status_emoji == '✅' || (status_text&.include?('IMPLEMENTED') && !status_text&.include?('NOT') && !status_text&.include?('PARTIALLY'))
                     'IMPLEMENTED'
                   when status_emoji == '⚠️'
                     'PARTIALLY_IMPLEMENTED'
                   when status_emoji == '❌'
                     'NOT_IMPLEMENTED'
                   else
                     'UNCLEAR'
                   end
          requirements << {
            'status' => status,
            'description' => description.strip
          }
        end
      end
      requirements
    end

    def extract_git_info
      begin
        if File.exist?('.git')
          branch = execute_vcs_command_with_timeout('git branch --show-current', 5)
          branch = branch[:success] ? branch[:stdout].strip : 'unknown'
          branch = 'unknown' if branch.empty?

          diff_result = execute_vcs_command_with_timeout('git diff --stat HEAD~1', 5)
          if diff_result[:success]
            diff_stats = diff_result[:stdout].strip
            files_changed = diff_stats.scan(/(\d+) files? changed/).flatten.first || '0'
            lines_added = diff_stats.scan(/(\d+) insertions?/).flatten.first || '0'
            lines_removed = diff_stats.scan(/(\d+) deletions?/).flatten.first || '0'
          else
            files_changed = '0'
            lines_added = '0'
            lines_removed = '0'
          end
        elsif File.exist?('.hg')
          branch_result = execute_vcs_command_with_timeout('hg branch', 5)
          branch = branch_result[:success] ? branch_result[:stdout].strip : 'default'
          branch = 'default' if branch.empty?

          diff_result = execute_vcs_command_with_timeout('hg diff --stat', 5)
          if diff_result[:success]
            files_changed = diff_result[:stdout].lines.count.to_s
          else
            files_changed = '0'
          end
          lines_added = '0'
          lines_removed = '0'
        else
          branch = 'unknown'
          files_changed = '0'
          lines_added = '0'
          lines_removed = '0'
        end
      rescue
        branch = 'unknown'
        files_changed = '0'
        lines_added = '0'
        lines_removed = '0'
      end
      { branch: branch, files_changed: files_changed, lines_added: lines_added, lines_removed: lines_removed }
    end

    def execute_vcs_command_with_timeout(command, timeout_seconds)
      require 'open3'

      begin
        # Use Open3.popen3 with manual timeout handling to avoid thread issues
        stdin, stdout, stderr, wait_thr = Open3.popen3(command)
        stdin.close

        # Manual timeout implementation
        start_time = Time.now
        while wait_thr.alive?
          if Time.now - start_time > timeout_seconds
            # Kill the process
            begin
              Process.kill('TERM', wait_thr.pid)
              sleep(0.5)
              Process.kill('KILL', wait_thr.pid) if wait_thr.alive?
            rescue Errno::ESRCH
              # Process already dead
            end
            stdout.close
            stderr.close
            return { success: false, error: "Command timed out after #{timeout_seconds} seconds" }
          end
          sleep(0.1)
        end

        # Process completed within timeout
        stdout_content = stdout.read
        stderr_content = stderr.read
        stdout.close
        stderr.close

        exit_status = wait_thr.value
        if exit_status.success?
          { success: true, stdout: stdout_content, stderr: stderr_content }
        else
          { success: false, error: stderr_content.empty? ? "Command failed with exit code #{exit_status.exitstatus}" : stderr_content }
        end
      rescue => e
        { success: false, error: "Unexpected error: #{e.message}" }
      end
    end

    def resolve_template_path(template_key, config)
      user_path = config.dig('templates', template_key) if config.is_a?(Hash)
      return user_path if user_path && File.exist?(user_path)
      File.expand_path(File.join(__dir__, 'templates', "#{template_key}.txt"))
    end

    def get_config(reconfigure: false, advanced_flow: false)
      # Return the config that was passed during initialization
      # This is used for template resolution and other configuration needs
      @config
    end

    def test_connection
      puts "🧪 Testing GitHub API connection..."
      begin
        user = make_api_request('GET', '/user')
        puts "✅ Authentication successful as #{user['login']}"
        repo = @github_config['repo']
        repo_data = make_api_request('GET', "/repos/#{repo}")
        puts "✅ Access to repository #{repo_data['full_name']}"
        true
      rescue => e
        puts "❌ GitHub connection test failed: #{e.message}"
        false
      end
    end

    private

    def parse_issue_input(input)
      if input =~ %r{^https?://}
        uri = URI.parse(input)
        parts = uri.path.split('/').reject(&:empty?)
        if parts.length >= 4 && ['issues', 'pull'].include?(parts[2])
          repo = "#{parts[0]}/#{parts[1]}"
          number = parts[3]
          return [repo, number]
        else
          raise GitHubApiError, "Could not parse issue from URL: #{input}"
        end
      elsif input.to_s =~ /^#?(\d+)$/
        repo = @github_config['repo']
        raise GitHubApiError, 'Repository not configured' unless repo
        return [repo, $1]
      else
        raise GitHubApiError, "Invalid issue format: #{input}"
      end
    rescue URI::InvalidURIError
      raise GitHubApiError, "Invalid URL format: #{input}"
    end

    def make_api_request(method, path, body = nil)
      uri = URI.parse("#{@api_base}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      request = case method.upcase
                when 'GET'
                  Net::HTTP::Get.new(uri.request_uri)
                when 'POST'
                  r = Net::HTTP::Post.new(uri.request_uri)
                  r.body = body.to_json if body
                  r
                else
                  raise GitHubApiError, "Unsupported HTTP method: #{method}"
                end
      request['Authorization'] = "token #{@github_config['access_token']}"
      request['User-Agent'] = 'n2b'
      request['Accept'] = 'application/vnd.github+json'
      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        raise GitHubApiError, "GitHub API Error: #{response.code} #{response.message} - #{response.body}"
      end
      response.body.empty? ? {} : JSON.parse(response.body)
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError,
           Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError => e
      raise GitHubApiError, "GitHub API request failed: #{e.class} - #{e.message}"
    end

    def format_issue_for_requirements(repo, issue_data, comments)
      comments_section = format_comments_for_requirements(comments)
      <<~OUT
      Repository: #{repo}
      Issue Number: #{issue_data['number']}
      Title: #{issue_data['title']}
      State: #{issue_data['state']}
      Author: #{issue_data.dig('user', 'login')}

      --- Full Description ---
      #{issue_data['body']}

      #{comments_section}
      OUT
    end

    def format_comments_for_requirements(comments)
      return "" unless comments.is_a?(Array) && comments.any?
      formatted = ["--- Comments with Additional Context ---"]
      comments.each_with_index do |comment, idx|
        created = comment['created_at'] || 'Unknown'
        formatted_date = begin
                           Time.parse(created).strftime('%Y-%m-%d %H:%M')
                         rescue
                           created
                         end
        formatted << "\nComment #{idx + 1} (#{comment.dig('user', 'login')}, #{formatted_date}):"
        formatted << comment['body'].to_s.strip
      end
      formatted.join("\n")
    end

    def fetch_dummy_issue_data(repo, number)
      <<~DUMMY.strip
      Repository: #{repo}
      Issue Number: #{number}
      Title: Dummy issue #{number}
      State: open
      Author: Dummy

      --- Full Description ---
      This is dummy issue content used when GitHub API access fails.
      DUMMY
    end
  end
end
