# app/services/text_extractor.rb
require 'pdf-reader'

class TextExtractor
  def self.call(file)
    # 1) Obtener los bytes del fichero: si el objeto responde a `download` (ActiveStorage),
    #    usarlo; si no, asumimos que viene de params[:file] y usamos `read`.
    raw_bytes =
      if file.respond_to?(:download)
        file.download
      else
        file.read
      end

    return "" if raw_bytes.blank?

    Rails.logger.info "TextExtractor: Processing file type='#{file.content_type}' size=#{raw_bytes.bytesize}"

    # 2) Si es PDF, extraer con PDF::Reader; en caso contrario, asumimos texto plano.
    text =
      if file.content_type&.start_with?('image/')
        Rails.logger.info "TextExtractor: Skipping image"
        ''
      elsif file.content_type.to_s.downcase.include?('pdf')
        Rails.logger.info "TextExtractor: Delegating to extract_pdf_text"
        extract_pdf_text(raw_bytes)
      else
        Rails.logger.info "TextExtractor: Fallback to plain text (scrubbing)"
        str = raw_bytes.dup.force_encoding('UTF-8')
        unless str.valid_encoding?
           str = str.scrub
        end
        str
      end

    if text.nil?
       Rails.logger.warn "TextExtractor: text was NIL, returning empty"
       return ""
    end

    Rails.logger.info "TextExtractor: Extraction complete (length=#{text.length})"
    
    # Ensure text is valid UTF-8 before doing string operations like delete!
    text = text.force_encoding('UTF-8')
    unless text.valid_encoding?
       Rails.logger.warn "TextExtractor: Detected invalid encoding, scrubbing..."
       text = text.scrub
    end

    text.delete!("\u0000")
    text
  rescue => e
    Rails.logger.error "TextExtractor error: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    ""
  end

  private_class_method def self.extract_pdf_text(raw_bytes)
    io = StringIO.new(raw_bytes)
    reader = PDF::Reader.new(io)
    reader.pages.map(&:text).join("\n\n")
  rescue => e
    Rails.logger.error "TextExtractor PDF error: #{e.message}"
    ""
  end
end
