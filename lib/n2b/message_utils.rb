module N2B
  module MessageUtils
    MAX_LENGTH = 500

    def self.sanitize(message)
      return nil if message.nil?
      clean = message.to_s.gsub(/\r?\n/, ' ').strip
      clean = clean[0, MAX_LENGTH] if clean.length > MAX_LENGTH
      clean
    end
  end
end

