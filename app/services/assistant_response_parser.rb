class AssistantResponseParser
  REQUIRED_KEYS = %w[campo_actual estado_del_campo valor siguiente_campo mensaje_para_usuario explicacion_normativa].freeze
  VALID_STATES  = %w[confirmado pendiente desconocido inconsistente omitido].freeze

  def self.call(raw_response)
    return unless raw_response.present?

    clean_json = raw_response.to_s.gsub(/^```json\s*|```$/, "").strip
    parsed = JSON.parse(clean_json)
    return unless parsed.is_a?(Hash)

    missing = REQUIRED_KEYS - parsed.keys
    raise ArgumentError, "Faltan claves en la respuesta del asistente: #{missing.join(', ')}" if missing.any?

    parsed["estado_del_campo"] = normalize_state(parsed["estado_del_campo"])
    parsed
  rescue JSON::ParserError => e
    Rails.logger.warn("AssistantResponseParser: respuesta no es JSON válido (#{e.message})")
    
    # Fallback: asumir que es texto plano del asistente
    {
      "campo_actual"          => nil,
      "estado_del_campo"      => "pendiente",
      "valor"                 => nil,
      "siguiente_campo"       => nil,
      "mensaje_para_usuario"  => raw_response,
      "explicacion_normativa" => nil
    }
  rescue ArgumentError => e
    Rails.logger.warn("AssistantResponseParser: #{e.message}")
    nil
  end

  def self.normalize_state(value)
    state = value.to_s.downcase.strip
    return state if VALID_STATES.include?(state)

    state.blank? ? "pendiente" : state
  end
end