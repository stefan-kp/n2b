module N2B
  # Parses files containing Git or Mercurial merge conflict markers.
  # Returns an array of ConflictBlock objects with context information.
  class MergeConflictParser
    ConflictBlock = Struct.new(
      :start_line, :end_line,
      :base_content, :incoming_content,
      :context_before, :context_after,
      :base_label, :incoming_label,
      keyword_init: true
    )

    DEFAULT_CONTEXT_LINES = 10

    def initialize(context_lines: DEFAULT_CONTEXT_LINES)
      @context_lines = context_lines
    end

    def parse(file_path)
      raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

      lines = File.readlines(file_path, chomp: true)
      blocks = []
      i = 0
      while i < lines.length
        line = lines[i]
        unless line.start_with?('<<<<<<<')
          i += 1
          next
        end

        start_line = i + 1
        base_label = line.sub('<<<<<<<', '').strip
        i += 1
        base_lines = []
        while i < lines.length && !lines[i].start_with?('=======')
          base_lines << lines[i]
          i += 1
        end
        i += 1 # skip ======= line
        incoming_lines = []
        while i < lines.length && !lines[i].start_with?('>>>>>>>')
          incoming_lines << lines[i]
          i += 1
        end
        incoming_label = lines[i].sub('>>>>>>>', '').strip if i < lines.length
        end_line = i + 1

        context_before_start = [start_line - @context_lines - 1, 0].max
        context_before = lines[context_before_start...(start_line - 1)].join("\n")
        context_after_end = [end_line + @context_lines - 1, lines.length - 1].min
        context_after = lines[(end_line)..context_after_end].join("\n")

        blocks << ConflictBlock.new(
          start_line: start_line,
          end_line: end_line,
          base_content: base_lines.join("\n"),
          incoming_content: incoming_lines.join("\n"),
          context_before: context_before,
          context_after: context_after,
          base_label: base_label,
          incoming_label: incoming_label
        )
        i += 1
      end

      blocks
    end
  end
end
