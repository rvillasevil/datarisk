module ApplicationHelper
  # Removes confirmation patterns like "##field## ... &&value&&" from a message
  # so that assistant2 messages are displayed without internal markers.
  def sanitized_content(message)
    return message.content unless message.sender == "assistant"

    message.content.gsub(/(?:\u2705[^#]*?)?##[^#]+##.*?&&.*?&&\s*[.,]?/m, "").strip
  end

  def file_icon_for(file)
    ext = File.extname(file.filename.to_s).downcase
    case ext
    when ".pdf"
      "bi-file-earmark-pdf"
    when ".doc", ".docx"
      "bi-file-earmark-word"
    when ".xls", ".xlsx", ".csv"
      "bi-file-earmark-spreadsheet"
    when ".png", ".jpg", ".jpeg", ".gif"
      "bi-file-earmark-image"
    when ".zip", ".rar"
      "bi-file-earmark-zip"
    else
      "bi-file-earmark"
    end
  end

  # Helper for safe data access into JSONB structure
  # Given a key like "section.subsection.field", it digs into the hash
  def fetch_data(data, key)
    return nil if data.nil?
    parts = key.to_s.split(".")
    parts.reduce(data) do |current, part|
      break nil unless current.is_a?(Hash) || (current.is_a?(Array) && part.match?(/\A\d+\z/))
      if current.is_a?(Array)
        current[part.to_i]
      else
        current[part]
      end
    end
  end
end
