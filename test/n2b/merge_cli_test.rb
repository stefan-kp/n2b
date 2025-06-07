require 'minitest/autorun'
require 'fileutils'
require 'stringio'
require_relative '../test_helper'
require 'n2b/merge_cli'

class MergeCLITest < Minitest::Test
  def setup
    @tmp_dir = File.expand_path('./tmp_merge_cli', Dir.pwd)
    FileUtils.mkdir_p(@tmp_dir)
    @file_path = File.join(@tmp_dir, 'conflict.txt')
    @config = { 'llm' => 'openai', 'merge_log_enabled' => false }
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def write(content)
    File.write(@file_path, content)
  end

  def test_resolve_accept
    write(<<~TEXT)
      line1
      <<<<<<< HEAD
      foo = 1
      =======
      foo = 2
      >>>>>>> feature
      line2
    TEXT

    cli = N2B::MergeCLI.new([@file_path])
    cli.stubs(:call_llm_for_merge).returns('{"merged_code":"foo = 3","reason":"merge"}')

    input = StringIO.new("y\n")
    $stdin = input
    begin
      cli.execute
    ensure
      $stdin = STDIN
    end

    result = File.read(@file_path)
    assert_match 'foo = 3', result
  end

  def test_abort_keeps_file
    original = <<~TEXT
      line1
      <<<<<<< HEAD
      foo = 1
      =======
      foo = 2
      >>>>>>> feature
      line2
    TEXT
    write(original)

    cli = N2B::MergeCLI.new([@file_path])
    cli.stubs(:call_llm_for_merge).returns('{"merged_code":"foo = 3","reason":"merge"}')

    input = StringIO.new("a\n")
    $stdin = input
    begin
      cli.execute
    ensure
      $stdin = STDIN
    end

    result = File.read(@file_path)
    assert_equal original, result
  end

  def test_execute_vcs_command_with_timeout_success
    cli = N2B::MergeCLI.new([])

    result = cli.send(:execute_vcs_command_with_timeout, "echo 'test'", 5)

    assert result[:success]
    assert_equal "test\n", result[:stdout]
  end

  def test_execute_vcs_command_with_timeout_failure
    cli = N2B::MergeCLI.new([])

    result = cli.send(:execute_vcs_command_with_timeout, "false", 5)

    refute result[:success]
    assert_includes result[:error], "Command failed"
  end

  def test_execute_vcs_command_with_timeout_timeout
    cli = N2B::MergeCLI.new([])

    # Use a command that will definitely timeout
    result = cli.send(:execute_vcs_command_with_timeout, "sleep 10", 1)

    refute result[:success]
    assert_includes result[:error], "timed out"
  end
end
