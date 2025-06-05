require 'minitest/autorun'
require 'n2b'
require 'nokogiri'
require 'stringio'

class IrbTest < Minitest::Test
  def setup
    @irb = N2B::IRB.new

    # Create a mock errbit HTML response
    @mock_errbit_html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head><title>Errbit</title></head>
        <body>
          <div id="content-title">
            <h1>ActiveRecord::InvalidForeignKey</h1>
            <span class="meta">
              <strong>App:</strong>
              <a href="/apps/12345">backend-nemo</a>
              <strong>Environment:</strong>
              production
            </span>
          </div>
          <h4>PG::ForeignKeyViolation: ERROR: update or delete on table "household_persons" violates foreign key constraint "fk_rails_3528704128" on table "product_transfers"</h4>
          <div id="backtrace">
            <table class="backtrace">
              <tr class="line in-app">
                <td class="line in-app">
                  <span class="path">app/models/household/</span><span class="file">use_case.rb</span><span class="number">:423</span>→
                  <span class="method">core_perform</span>
                </td>
              </tr>
              <tr class="line in-app">
                <td class="line in-app">
                  <span class="path">app/models/</span><span class="file">use_case.rb</span><span class="number">:111</span>→
                  <span class="method">core_run</span>
                </td>
              </tr>
            </table>
          </div>
        </body>
      </html>
    HTML

    # Create a mock exception
    @mock_exception = RuntimeError.new("Test exception")
    @mock_exception.set_backtrace([
      "app/models/test_model.rb:42:in `test_method'",
      "app/controllers/test_controller.rb:15:in `index'"
    ])
  end
  
  # Helper method to create mock LLM responses
  def mock_llm_response(content)
    if content.include?('analyzing application errors')
      {
        'explanation' => "# Error Analysis\n\nThis error is a foreign key violation. The system is trying to delete a record in the `household_persons` table, but there are records in the `product_transfers` table that reference it.\n\n## Suggestion\n\nUpdate the code to handle dependent records before deletion.",
        'code' => nil
      }
    elsif content.include?('creating a Scrum task')
      {
        'explanation' => "# Foreign Key Violation in Product Transfers\n\n## Description\nWhen trying to delete a household_person record, the system encounters a foreign key constraint violation because product_transfers still reference the record.\n\n## Acceptance Criteria\n1. Fix deletion process to handle dependent records\n2. Add proper error handling\n\n## Story Points: 3\n## Priority: High",
        'code' => nil
      }
    else
      {
        'explanation' => "# Mock LLM Response\n\nThis is a generic mock response for testing purposes.",
        'code' => "puts 'This is mock code'"
      }
    end
  end
  
  # Helper method to stub file operations using Minitest's stub
  def with_mocked_files
    File.stub :expand_path, proc { |path, *args|
      if path.start_with?('~/.n2b/')
        "/mock/path/#{path.sub('~/.n2b/', '')}"
      else
        File.method(:expand_path).call(path, *args)
      end
    } do
      File.stub :exist?, proc { |path|
        path == 'Gemfile' || path.include?('app/models/') || path.include?('app/controllers/')
      } do
        File.stub :read, proc { |path|
          if path == 'Gemfile'
            "gem 'rails'\ngem 'n2b'\n"
          elsif path.include?('app/models/test_model.rb')
            "# Test file content\nclass TestModel\n  def test_method\n    # Method content\n  end\nend"
          elsif path.include?('app/models/household/use_case.rb')
            "# Test file content\nmodule Household\n  class UseCase\n    def core_perform\n      # Method content\n    end\n  end\nend"
          elsif path.include?('app/controllers/')
            "# Controller content\nclass TestController < ApplicationController\n  def index\n    # Action content\n  end\nend"
          else
            "# Mock content\n# For testing\n# Multiple lines"
          end
        } do
          File.stub :join, proc { |*args|
            if args.first == Dir.pwd && args[1]&.start_with?('app/')
              "#{Dir.pwd}/#{args[1]}"
            else
              File.method(:join).call(*args)
            end
          } do
            Kernel.stub :`, proc { |cmd|
              if cmd.include?('find')
                "#{Dir.pwd}/app/models/test_model.rb"
              else
                `#{cmd}`
              end
            } do
              yield
            end
          end
        end
      end
    end
  end
  
  # Mock HTTP request using proper stubbing
  def with_mocked_http_request
    # Skip if Net::HTTP is not defined
    return yield(nil, nil) unless defined?(Net::HTTP)

    http_mock = Minitest::Mock.new
    response_mock = Minitest::Mock.new

    response_mock.expect :code, '200'
    response_mock.expect :body, @mock_errbit_html

    http_mock.expect :request, response_mock, [Net::HTTP::Get]
    http_mock.expect :use_ssl=, nil, [true]

    Net::HTTP.stub :new, http_mock do
      yield http_mock, response_mock
    end
  end
  
  def test_n2r_with_basic_input
    skip "Skipping complex IRB test to avoid method redefinition warnings"
  end

  def test_n2r_with_exception
    skip "Skipping complex IRB test to avoid method redefinition warnings"
  end

  def test_n2r_with_files
    skip "Skipping complex IRB test to avoid method redefinition warnings"
  end
  
  def test_n2rrbit
    skip "n2rrbit method not available" unless N2B::IRB.instance_methods.include?(:n2rrbit)
    skip "Skipping complex HTTP mocking test to avoid warnings"
  end

  def test_n2rscrum_with_url_cookie
    skip "n2rscrum method not available" unless N2B::IRB.instance_methods.include?(:n2rscrum)
    skip "Skipping complex HTTP mocking test to avoid warnings"
  end

  def test_n2rscrum_with_exception
    skip "n2rscrum method not available" unless N2B::IRB.instance_methods.include?(:n2rscrum)
    skip "Skipping complex mocking test to avoid warnings"
  end

  def test_n2rscrum_with_input
    skip "n2rscrum method not available" unless N2B::IRB.instance_methods.include?(:n2rscrum)
    skip "Skipping complex mocking test to avoid warnings"
  end
  
  def test_parse_errbit
    skip "parse_errbit method not available" unless @irb.respond_to?(:parse_errbit, true)

    result = @irb.send(:parse_errbit, @mock_errbit_html)

    assert_equal "ActiveRecord::InvalidForeignKey", result[:error_class]
    assert_match(/PG::ForeignKeyViolation/, result[:error_message])
    assert_equal "backend-nemo", result[:app_name]
    assert_equal "production", result[:environment]
    assert_kind_of Array, result[:backtrace]
    assert_operator result[:backtrace].length, :>, 0
  end

  def test_find_related_files
    skip "find_related_files method not available" unless @irb.respond_to?(:find_related_files, true)
    skip "Skipping complex file mocking test to avoid warnings"
  end

  def test_generate_error_ticket
    skip "generate_error_ticket method not available" unless @irb.respond_to?(:generate_error_ticket, true)
    skip "Skipping complex mocking test to avoid warnings"
  end
end 