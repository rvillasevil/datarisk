# frozen_string_literal: true

class ConversationNormalizer
  OPENAI_URL = "https://api.openai.com/v1/chat/completions".freeze
  MODEL = "gpt-4o-mini"
  HEADERS = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json"
  }.freeze

  def self.call(risk_assistant:, last_user_message:, last_assistant_message:)
    messages = risk_assistant.messages.order(:created_at).pluck(:role, :content)
    confirmed = risk_assistant.messages
                              .where.not(key: nil)
                              .order(:created_at)
                              .pluck(:key, :value)
                              .map { |key, value| "#{key}: #{value}" }

    prompt = <<~PROMPT
      Actúa como verificador y homogenizador de conversación.
      Recibirás el histórico de mensajes (en orden) y el último intercambio.
      Devuelve un JSON con las claves:
        - resumen_general: párrafo breve coherente con todos los datos.
        - campos_confirmados: lista de pares "campo: valor" consistentes y normalizados.
        - lagunas_detectadas: lista de campos faltantes o dudosos.
        - alertas_coherencia: avisos sobre contradicciones o valores improbables.
      Si detectas ruido, purga la información y quédate solo con hechos verificables.

      Mensajes históricos:
      #{messages.map { |role, content| "[#{role}] #{content}" }.join("\n")}

      Último mensaje del usuario: #{last_user_message}
      Última respuesta del asistente: #{last_assistant_message}
      Confirmaciones previas: #{confirmed.join('; ')}
    PROMPT

    body = {
      model: MODEL,
      temperature: 0,
      messages: [
        { role: "system", content: "Devuelve siempre JSON válido." },
        { role: "user", content: prompt }
      ]
    }

    response = HTTP.headers(HEADERS).post(OPENAI_URL, json: body)
    parsed_text = response.parse.dig("choices", 0, "message", "content").to_s.strip
    JSON.parse(parsed_text)
  rescue JSON::ParserError => e
    Rails.logger.warn("ConversationNormalizer: respuesta no JSON: #{e.message}")
    {}
  rescue => e
    Rails.logger.error("ConversationNormalizer error: #{e.class} – #{e.message}")
    {}
  end
end