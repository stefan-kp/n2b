module N2B
  module MessageUtils
    MAX_MESSAGE_LENGTH = 500
    TRUNCATION_NOTICE = "... (truncated)"

    # Validates the message length.
    # Truncates if it exceeds MAX_MESSAGE_LENGTH.
    def self.validate_message(message_str)
      return nil if message_str.nil?
      # Ensure message is a string before calling length
      message = String(message_str)
      if message.length > MAX_MESSAGE_LENGTH
        return message[0...(MAX_MESSAGE_LENGTH - TRUNCATION_NOTICE.length)] + TRUNCATION_NOTICE
      end
      message
    end

    # Performs basic sanitization on the message.
    def self.sanitize_message(message_str)
      return nil if message_str.nil?
      message = String(message_str) # Ensure it's a string

      # Strip leading/trailing whitespace
      sanitized = message.strip

      # Replace triple backticks with single backticks to prevent code block formatting issues in prompts
      sanitized.gsub!('```', '`')

      # Remove multiple consecutive newlines, leaving only single newlines
      # This helps prevent prompt injection or excessive spacing.
      sanitized.gsub!(/\n{2,}/, "\n")

      # Example: Escape specific control characters if needed, e.g., null bytes
      # sanitized.gsub!(/\x00/, '') # Remove null bytes

      # Add more sanitization rules here as needed, e.g.:
      # - Removing or escaping other characters that might break formatting or cause security issues.
      # - For now, keeping it relatively simple.

      sanitized
    end

    # Logs the message to STDOUT.
    # level can be :info, :debug, :warn, :error
    def self.log_message(message, level = :info)
      return if message.nil? || message.strip.empty?

      prefix = case level
               when :debug then "[N2B Message DEBUG]"
               when :warn  then "[N2B Message WARN]"
               when :error then "[N2B Message ERROR]"
               else "[N2B Message INFO]" # Default to info
               end

      output_stream = (level == :error || level == :warn) ? $stderr : $stdout
      output_stream.puts "#{prefix} #{message}"
    end
  end
end
