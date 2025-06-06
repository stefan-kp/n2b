require 'minitest/autorun'
require 'fileutils'
require_relative '../test_helper'
require 'n2b/merge_conflict_parser'

class MergeConflictParserTest < Minitest::Test
  def setup
    @tmp_dir = File.expand_path('./tmp_merge_parser_test', Dir.pwd)
    FileUtils.mkdir_p(@tmp_dir)
    @file_path = File.join(@tmp_dir, 'conflict.txt')
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def write(content)
    File.write(@file_path, content)
  end

  def test_parse_single_conflict
    write(<<~TEXT)
      line1
      <<<<<<< HEAD
      foo = 1
      =======
      foo = 2
      >>>>>>> feature
      line2
    TEXT

    parser = N2B::MergeConflictParser.new(context_lines: 1)
    blocks = parser.parse(@file_path)

    assert_equal 1, blocks.size
    block = blocks.first
    assert_equal 2, block.start_line
    assert_equal 6, block.end_line
    assert_equal "foo = 1", block.base_content.strip
    assert_equal "foo = 2", block.incoming_content.strip
    assert_equal "line1", block.context_before.strip
    assert_equal "line2", block.context_after.strip
    assert_equal 'HEAD', block.base_label
    assert_equal 'feature', block.incoming_label
  end

  def test_parse_no_conflict
    write("just text\nno conflict here")
    parser = N2B::MergeConflictParser.new
    assert_empty parser.parse(@file_path)
  end
end
