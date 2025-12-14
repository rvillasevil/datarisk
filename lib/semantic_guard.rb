# lib/semantic_guard.rb
# frozen_string_literal: true
require "http"
require "json"

module SemanticGuard
  extend self

  MODEL    = "gpt-4o-mini"
  ENDPOINT = "https://api.openai.com/v1/chat/completions"
  HEADERS  = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json"
  }.freeze

  # ----------------------------------------------------------------------------
  # validate: su único propósito es detectar incompatibilidades de la nueva respuesta
  # frente a todos los pares confirmados en 'context'.  
  #
  # Parámetros:
  #  • question:   texto exacto de la pregunta que hizo el asistente (no se usa aquí, 
  #                pero se deja para trazabilidad).
  #  • answer:     texto de la respuesta que ha dado el usuario.
  #  • context:    listado (string) con todos los pares “campo: valor” ya confirmados.
  #  • risk_assistant: la instancia, en caso de que quieras extender lógica después.
  #  • thread_id:  id del hilo actual para filtrar (opcionalmente) mensajes.
  #
  # Devuelve:
  #  • nil    → si NO hay ninguna incompatibilidad.
  #  • String → si hay incompatibilidad, el texto debe empezar por “Validador: <motivo>”.
  # ----------------------------------------------------------------------------
  def validate(question:, answer:, context:, risk_assistant:, thread_id:)
    # 1) Buscamos la última pregunta ABIERTA en este hilo
    last_q = risk_assistant.messages
                             .where(sender:    "assistant",
                                    role:      "assistant",
                                    thread_id: thread_id)
                             .where.not(field_asked: nil)  # tiene asignado un field_asked
                             .where(key: nil)               # aún no confirmado
                             .order(:created_at)
                             .last

    return nil unless last_q

    # 2) El único objetivo de este validador es comparar la nueva respuesta (answer)
    #    contra todos los datos confirmados en 'context'.  
    #    Construimos un prompt muy simple para que el LLM decida:
    prompt = <<~PROMPT
      Eres un validador encargado de comprobar si la última respuesta del usuario
      se correlaciona con los datos ya confirmados. Debes usar el sentido común y
      detectar posibles incoherencias o falta de relación con ese contexto.

      ### Datos confirmados (contexto):
      #{context}

      ### Pregunta al usuario
      #{question}

      ### Nueva respuesta del usuario:
      #{answer}

      Si la respuesta no se relaciona bien con el contexto o es incoherente,
      devuelve **exactamente**:
        Aviso: <desarrolla el motivo en un mínimo de 100 palabras y un máximo de 2 párrafos>.
      Si todo se correlaciona correctamente, devuelve **exactamente**:
        OK
      Si el usuario confirma la incoherencia, devuelve **exactamente**:
        OK
      Si el usuario indica siguiente pregunta, expresa desconocimiento a la respuesta, contestar: OK
    PROMPT

    Rails.logger.debug { "SemanticGuard ▶ Prompt:\n#{prompt.truncate(5000)}" }

    body = {
      model:       MODEL,
      temperature: 0.3,
      messages: [
        { role: "user", content: prompt }
      ]
    }

    resp_txt = HTTP.headers(HEADERS)
                   .post(ENDPOINT, json: body)
                   .parse
                   .dig("choices", 0, "message", "content")
                   .to_s
                   .strip

    Rails.logger.debug { "SemanticGuard ◀ Response: #{resp_txt.inspect}" }
    normalized = resp_txt.strip.gsub(/[.!\s]/, '').casecmp('ok').zero?
    normalized ? nil : resp_txt
  rescue => e
    Rails.logger.error "SemanticGuard error: #{e.message}"
    nil
  end
end
