require 'net/http'
require 'uri'
require 'json'

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

    def update_issue(issue_input, comment)
      repo, number = parse_issue_input(issue_input)
      body = { 'body' => comment }
      make_api_request('POST', "/repos/#{repo}/issues/#{number}/comments", body)
      puts "✅ Successfully added comment to GitHub issue #{repo}##{number}"
      true
    rescue GitHubApiError => e
      puts "❌ Failed to update GitHub issue #{repo}##{number}: #{e.message}"
      false
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
        if parts.length >= 4 && ['issues', 'pull'].include?(parts[3])
          repo = "#{parts[0]}/#{parts[1]}"
          number = parts[4]
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
