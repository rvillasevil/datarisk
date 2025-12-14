# app/services/document_field_extractor.rb
require "json"
require "http"

class DocumentFieldExtractor
  OPENAI_URL    = "https://api.openai.com/v1/chat/completions".freeze
  OPENAI_MODEL  = "gpt-4o-mini"
  OPENAI_HEADERS = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json"
  }.freeze

  # Dado un texto extraído de uno o varios ficheros, devuelve un hash con dos claves:
  #   :values    => { campo_id => valor }
  #   :warnings  => { campo_id => mensaje_de_advertencia }
  # Para todos los campos del JSON que aparezcan en dicho texto.
  def self.call(extracted_text)
    return {} if extracted_text.blank?

    # 1) Construir el array reducido de campos: solo id y label
    fields_info = RiskFieldSet.flat_fields.map do |f|
      { "id" => f[:id].to_s, "label" => f[:label].to_s }
    end

    # 2) Armar el prompt para que el LLM extraiga todos los campos del texto.
    prompt = <<~PROMPT
      Tienes una lista de campos (id + label) en formato JSON:
      #{fields_info.to_json}

      A continuación tienes un texto extraído de uno o varios documentos:
      -----------------------------------------------------------------
      #{extracted_text}
      -----------------------------------------------------------------

      Tu tarea es:  
      – Buscar la información relativa a los campos.  
      – Para cada campo que encuentres información relativa, devolverás una línea EXACTA con:
          ##<campo_id>## &&<valor extraído>&&
        donde `<campo_id>` es el id del campo tal como aparece en el JSON,  
        y `<valor extraído>` son los fragmentos de texto asociado a ese campo.  
      – Solo debes incluir los campos que de verdad estén presentes en el texto.  
      – Cada línea debe seguir exactamente este patrón:  
          ##campo_id## &&valor&&  
      – Si no encuentras ningún campo en el texto, respondes exactamente (sin nada más):  
          Ningún dato encontrado

      Ejemplo de salida (solo si se detecta “nombre_empresa”: “ACME S.A.” y “direccion”: “Calle Falsa 123”):  
      ##nombre_empresa## &&ACME S.A.&&  
      ##direccion## &&Calle Falsa 123&&

      => Ahora analiza el texto proporcionado.
    PROMPT

    # 3) Llamar a OpenAI
    body = {
      model: OPENAI_MODEL,
      temperature: 0.7,
      messages: [
        { role: "user", content: prompt }
      ]
    }

    response = HTTP
                 .headers(OPENAI_HEADERS)
                 .post(OPENAI_URL, json: body)
    Rails.logger.debug "[DocumentFieldExtractor] ← Response body: #{response.body.to_s.truncate(500)}"
    content = response.parse.dig("choices", 0, "message", "content") || ""
    raw = content.to_s.strip

    return {} if raw.blank? || raw.match?(/ningún dato encontrado/i)

    # 4) Parsear líneas con el patrón ##campo_id## &&valor&&
    pairs = raw.scan(/##(.*?)##\s*&&\s*(.*?)\s*&&/m)
    return {} if pairs.empty?
    values = pairs.to_h

    # 5) Verificación de formato mediante LLM
    warnings = verify_with_llm(values)

    { values: values, warnings: warnings }
  rescue => e
    Rails.logger.error "DocumentFieldExtractor error: #{e.message}"
    {}
  end

  # Verifica con un LLM que cada valor coincida con el formato esperado.
  # Devuelve un hash { campo_id => advertencia } para los campos problemáticos.
  def self.verify_with_llm(values)
    return {} if values.empty?

    info = values.map do |id, val|
      f = RiskFieldSet.by_id[id.to_sym] || {}
      {
        id: id,
        label: f[:label].to_s,
        type: f[:type].to_s,
        options: f[:options],
        validation: f[:validation],
        value: val
      }
    end

    prompt = <<~PROMPT
      A continuación tienes información de campos con su valor extraído:
      #{info.to_json}

      Tu tarea es verificar si "value" cumple con el tipo/validación descritos.
      Para cada campo devuelve una línea EXACTA con:
      ##<id>## &&<ok o descripción del problema>&&
      Usa "ok" si el valor es válido.
    PROMPT

    body = {
      model: OPENAI_MODEL,
      temperature: 0,
      messages: [
        { role: "user", content: prompt }
      ]
    }

    response = HTTP.headers(OPENAI_HEADERS).post(OPENAI_URL, json: body)
    Rails.logger.debug "[DocumentFieldExtractor] ← Verification body: #{response.body.to_s.truncate(500)}"
    content = response.parse.dig("choices", 0, "message", "content") || ""
    raw = content.to_s.strip

    pairs = raw.scan(/##(.*?)##\s*&&\s*(.*?)\s*&&/m)
    pairs.each_with_object({}) do |(id, msg), h|
      h[id] = msg unless msg.strip.downcase == "ok"
    end
  rescue => e
    Rails.logger.error "DocumentFieldExtractor verification error: #{e.message}"
    {}
  end  
end
