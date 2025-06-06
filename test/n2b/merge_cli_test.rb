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
    N2B::MergeCLI.any_instance.stubs(:get_config).returns(@config)
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
end
