# frozen_string_literal: true
require "http"
require "json"

class AssistantRunner
  BASE_URL = "https://api.openai.com/v1".freeze
  HEADERS  = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json",
    "OpenAI-Beta"   => "assistants=v2"
  }.freeze

  CONTROL_JSON_SCHEMA = {
    type: "object",
    required: %w[campo_actual estado_del_campo valor siguiente_campo mensaje_para_usuario explicacion_normativa],
    properties: {
      campo_actual: { type: %w[string null] },
      estado_del_campo: { type: "string", enum: %w[confirmado pendiente desconocido inconsistente omitido] },
      valor: { type: %w[string number boolean null object array] },
      siguiente_campo: { type: %w[string null] },
      mensaje_para_usuario: { type: "string" },
      explicacion_normativa: { type: %w[string null] }
    }
  }.freeze

  attr_reader :risk_assistant, :thread_id, :last_field_id
  def initialize(risk_assistant)
    @risk_assistant = risk_assistant
    @thread_id      = risk_assistant.thread_id.presence || create_thread
    @fields_json    = build_fields_json

    if risk_assistant.respond_to?(:field_catalog_version) &&
       risk_assistant.field_catalog_version != RiskFieldSet.catalog_version
      risk_assistant.update!(field_catalog_version: RiskFieldSet.catalog_version)
    end
    inject_instructions_once if !risk_assistant.initialised?
  end

  def set_last_field(field_id)
    @last_field_id = field_id
  end

  def inject_instructions_once
    dev = <<~SYS
      **LISTA DE CAMPOS (interno)**

      ```json
      #{@fields_json}
      ```

      **Instrucciones al Assistant:**
      1. Cuando reconozcas un campo, responde EXACTAMENTE:
          ✅ El campo ##id_del_campo## es &&Valor&&.
      2. **Antes** de dar por bueno un valor, **analiza** si la respuesta cumple el formato y la información mínima que se está solicitando en la pregunta.
        - Para direcciones, comprueba al menos calle, número, CP y población.
        - Para fechas/años, comprueba 4 dígitos válidos.
        - Para porcentajes, comprueba “%” y valor entre 0–100.    
      3. Si falta algún dato, **no completes el campo** y pregunta de forma específica por el dato faltante, ej:
        – “Habría que indicar también el código postal, ¿me lo puedes dar?”            
      4. No pidas dos campos a la vez.
      5. Valida tipos; si no encaja, pide aclaración.
      6. **Al preguntar**, usa `RiskFieldSet.question_for(id)` y 'assistant_instructions' para formular la pregunta.
        - Incluye “Opciones disponibles” si `options` está definido.
        - Incluye “Ejemplo: …” si `example` está definido.
        - Incluye normative_tips si está definido.
      7. Si la respuesta es ambigua, reitera el ejemplo u opciones.
      8. Si la respuesta no guarda relación con el campo preguntado, repite la misma pregunta indicando que la respuesta no es válida.
        - Ejemplos de respuestas no válidas: "no lo sé", "ninguna", "¿qué es esto?", "otro tema".
      9. Si el usuario responde "no aplica", "siguiente pregunta", o desconoce el dato, valida el campo como "desconocido"."
      10. Se adjuntarán documentos, para cada uno de ellos, analiza todo el documento y localiza el contenido de campos de la lista de campos:  ```json#{@fields_json} ``` dentro del documento, de la mayor parte de campos posibles. La respuesta debe contener cada uno de los campos encontrado con su valor, con el siguiente formato de salida: ✅ Perfecto, el campo ##Campo## es &&Valor&&. Importante los ## y && para capturar el valor. Y pregunta por el siguiente campo.    
    SYS

    HTTP.headers(HEADERS)
        .post("#{BASE_URL}/threads/#{thread_id}/messages",
              json: { role: "developer", content: dev })

    risk_assistant.update!(initialised: true)
  end  

  def submit_user_message(content:, file_id: nil)
    payload = { role: "user", content: content }
    if file_id.present?
      payload[:attachments] = [{ file_id: file_id, tools: [{ type: "file_search" }] }]
    end
    Rails.logger.debug "→ Enviando mensaje de usuario: #{content.inspect}"
    Rails.logger.debug "→ Payload adjunto (si lo hay): #{payload.to_json}"    
    post("#{BASE_URL}/threads/#{thread_id}/messages", payload)
  end

  # ⇒ dentro de la clase AssistantRunner
  def ask_next!
    answers = risk_assistant.messages.where.not(key: nil).pluck(:key, :value).to_h
    field    = RiskFieldSet.next_field_hash(answers)   # helper de RiskFieldSet

    # Estados actuales de los campos para proporcionar contexto al LLM
    states_json = risk_assistant.campos.to_json

    
    unless field
      summary = ConversationSummarizer.summarize(risk_assistant)
      @last_field_id = nil      
      if summary.present?
        risk_assistant.messages.create!(
          sender:    "assistant",
          role:      "assistant",
          content:   summary,
          thread_id: thread_id
        )
      end
      return
    end                               # ya no quedan

    if field
      field_id = field[:id].to_s
      question = RiskFieldSet.question_for(field_id.to_sym, include_tips: true)
      @last_field_id = field_id      
      instr    = field[:assistant_instructions].to_s.strip
      tips = RiskFieldSet.normative_tips_for(field_id)
    # guarda la PREGUNTA para que el guardia pueda validarla

      risk_assistant.messages.create!(
        sender:      "assistant_guard",
        role:        "assistant",
        field_asked: field_id,
        key:         nil,
        content:     question,
        thread_id:   thread_id
      )

      confirmations = risk_assistant.messages
                                    .where.not(key: nil)
                                    .order(:created_at)
                                    .map { |m| "✅ #{RiskFieldSet.label_for(m.key)}: #{m.value}" }

      history_block = confirmations.any? ? "### Historial de respuestas confirmadas:\n#{confirmations.join("\n")}\n\n" : ""

      extra = +""
      extra << "### Estados de campos:\n#{states_json}\n\n"
      extra << history_block
      extra << "### Instrucciones de campo:\n#{instr}\n\n" if instr.present?
      extra << "### Tip normativo:\n#{tips}\n\n" if tips.present?
      extra << "### Pregunta:\n#{question}\n\n"
      extra << "### Formato de respuesta:\n" \
               "Devuelve un JSON con las claves `campo_actual` (valor `#{field_id}`), `estado_del_campo`, `valor`, `siguiente_campo`, `mensaje_para_usuario` y `explicacion_normativa`.\n" \
               "No pases al siguiente campo hasta que `estado_del_campo` sea 'confirmado'. Si cambias de campo, establece `estado_del_campo` como 'confirmado' para el campo anterior.\n"
        extra << "### Contrato JSON obligatorio:\n" \
                 "Usa response_format=json_schema (strict=true) y respeta este esquema: #{JSON.pretty_generate(CONTROL_JSON_SCHEMA)}\n"
      extra << "⚠️ Tras confirmar, responde SOLO \"OK\" y espera la siguiente instrucción."
      extra << "\nAntes de formular la siguiente pregunta, revisa este historial y señala cualquier contradicción detectada."

      
      expanded = ParagraphGenerator.generate(question: question,
                                             instructions: instr,
                                             normative_tips: tips,
                                             confirmations: confirmations)

      norm_explanation = NormativeExplanationGenerator.generate(field_id, question: expanded)     
      parts = [expanded]
      parts << "Tip normativo: #{tips}" if tips.present?
      parts << "Explicación normativa: #{norm_explanation}"      

      risk_assistant.messages.create!(
        sender:    "assistant",
        role:      "assistant",
        content:   parts.join("\n"),
        field_asked: field_id,
        thread_id: thread_id
      )
    end
    post("#{BASE_URL}/threads/#{thread_id}/runs",
        assistant_id:            ENV['OPENAI_ASSISTANT_ID'],
        additional_instructions: extra,
        temperature:             0,
        response_format:         {
          type: "json_schema",
          json_schema: {
            name: "control_json_schema",
            schema: CONTROL_JSON_SCHEMA,
            strict: true
          }
        })
    @last_field_id
  end

  # Inicia la run y devuelve el TEXTO del último mensaje
  def run_and_wait(timeout: 40)
    run_id = start_run_with_instructions

    status = nil
    timeout.times do
      sleep 1
      status = run_status(run_id)
      break if %w[completed failed expired].include?(status)
    end

    return "" unless %w[completed failed expired].include?(status)

    extract_text(last_message(run_id: run_id))
  end

  private

  def create_thread
    resp = post("#{BASE_URL}/threads", {})
    id   = resp["id"]
    risk_assistant.update!(thread_id: id)
    id
  end

  def build_fields_json
    Rails.logger.info "AssistantRunner: generando lista de campos…"
    # Enviamos TODO lo que el modelo necesita:
    RiskFieldSet.flat_fields.map { |f|
      {
        id:          f[:id],
        label:       f[:label],
        type:        f[:type],
        options:     f[:options],
        context:     f[:context],
        validation:  f[:validation],
        assistant_instructions: f[:assistant_instructions],
        normative_tips: f[:normative_tips]
      }
    }.to_json
  end

    # ------------------------------------------------------------
    # Encuentra el siguiente campo que NO tenga valor en BD
    # ------------------------------------------------------------
  def next_pending_field
    answers = @risk_assistant.messages.where.not(key: nil).pluck(:key, :value).to_h
    h = RiskFieldSet.next_field_hash(answers)
    h && h[:id].to_sym
  end 

  # ------------------------------------------------------------
  # Lanza la run con instrucciones + la PREGUNTA exacta
  # ------------------------------------------------------------
  def start_run_with_instructions
    
    field    = next_pending_field
    return unless field
    question = RiskFieldSet.question_for(field, include_tips: true)   # ← YA incluye opciones
    @last_field_id = field  
    # ↓ Recupera las instrucciones privadas que el JSON trae para ese campo

    # 3) Recuperamos las instrucciones privadas para este campo (sin índice si lo hubiera)
    #    Ej.: si field == :"constr_edificios_detalles_array.0.edif_nombre_uso",
    #    querem<os buscar en JSON por :"constr_edificios_detalles_array.edif_nombre_uso"
    base_key = field.to_s.include?(".") ?
                 field.to_s.sub(/\.\d+\.(.+)$/, '.\1').to_sym :
                 field.to_sym
    info  = RiskFieldSet.by_id[base_key]
    instr = info ? info[:assistant_instructions].to_s.strip : ""
    tips = RiskFieldSet.normative_tips_for(field)
    # El asistente generará la pregunta exacta como parte de la respuesta,
    # por lo que aquí no la publicamos para evitar duplicidades en el chat.         

    # Acceso seguro al label del siguiente campo pendiente
    npf = next_pending_field
    label = ""
    if npf
      byid = RiskFieldSet.by_id[npf.to_sym]
      label = byid[:label].to_s.strip if byid
    end

    confirmations = risk_assistant.messages
                                  .where.not(key: nil)
                                  .order(:created_at)
                                  .map { |m| "✅ #{RiskFieldSet.label_for(m.key)}: #{m.value}" }

    history_block = confirmations.any? ? "Historial de respuestas confirmadas:\n#{confirmations.join("\n")}\n\n" : ""

    states_block = risk_assistant.campos.to_json    

    extra = <<~SYS
      Estados de campos:
      #{states_block}

      #{history_block}
      Lista interna de campos (no mostrar al usuario):
      ```json
      #{@fields_json}
      ```
      Instrucciones para el assistant:
      1. Reconoce SOLO los campos anteriores.
      2. No pidas más de un campo a la vez.
      

      3. Genera la siguiente consulta desarrollando como máximo en cuatro párrafos. Usa Instrucciones para formular la pregunta e incluye los tipos normativos en el desarrollo:
         #{question}
         (Incluye las opciones si existen para ese campo.)

      3.1 Antes de formular la pregunta añade siempre un contexto descriptivo que explique qué información se va a pedir y por qué es importante. Incluye ejemplos concretos cuando sirvan para ilustrar mejor la solicitud.         

      4. Añade a la pregunta las siguientes indicaciones al usuario:
         #{instr.presence ? instr : "ninguna"}

      4.1 Añade justo después de la pregunta, una explicación de la pregunta de como mínimo 2 párrafos y máximo 3 párrafos, de no más de 500 palabras en total, que ayude al usuario a entender qué información se le está pidiendo y por qué es importante. Usa un lenguaje claro y sencillo, evitando tecnicismos y jerga compleja. Si el campo tiene tip normativo, incluye una explicación breve de la normativa relacionada con ese campo.

      4.2 Incluye toda la narrativa (pregunta, explicaciones y aclaraciones) dentro del valor de `mensaje_para_usuario` del JSON de salida.

      5. Incluye siempre en un párrafo independiente el desarrollo de la normativa relacionada con la pregunta del punto 3:
          Normativa: #{tips.presence ? tips : "ninguna"}
      5.1 Coloca el desarrollo normativo en la clave `explicacion_normativa` del JSON de salida.

      6. Antes de validar un valor:
         – Si el campo es *select*, comprueba que la respuesta esté en
           las opciones. Si no, muestra de nuevo la lista.
         – Aplica también las reglas de `context`, `validation`, etc.

      7. Tras ✅ confirmar, no hagas otra pregunta hasta que la app te
         envíe la siguiente instrucción.
      8. Usa la plantilla indicada en assistant_instructions si existe.
      9. Si se adjunta un archivo, busca la información relacionada con cada uno de los campos y valida cada uno de ellos.
      10. Revisa el historial y señala cualquier contradicción antes de formular la siguiente pregunta.
      11. Devuelve SIEMPRE un JSON con las claves `campo_actual`, `estado_del_campo`, `valor`, `siguiente_campo`, `mensaje_para_usuario` y `explicacion_normativa` respetando este esquema:
          #{JSON.pretty_generate(CONTROL_JSON_SCHEMA)}
    SYS
 
    resp = post(
      "#{BASE_URL}/threads/#{thread_id}/runs",
      assistant_id:           ENV.fetch("OPENAI_ASSISTANT_ID"),
      additional_instructions: extra,
      temperature: 0,
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "control_json_schema",
          schema: CONTROL_JSON_SCHEMA,
          strict: true
        }
      }
    )
    Rails.logger.debug "↳ Instrucciones de campo: #{instr.truncate(120)}" if instr.present?
    resp["id"]
  end

 

  def run_status(run_id)
    get("#{BASE_URL}/threads/#{thread_id}/runs/#{run_id}")["status"]
  end

  def last_message(run_id: nil)
    url = "#{BASE_URL}/threads/#{thread_id}/messages"
    if run_id
      url += "?run_id=#{run_id}"
    else
      url += "?order=desc"
    end
    get(url)["data"].first
  end

  def extract_text(msg)
    return "" unless msg
    msg["content"]
      .select { |c| c["type"] == "text" }
      .map    { |c| c.dig("text", "value") }
      .join("\n")
      .strip
  end

  def post(url, body)
    Rails.logger.debug "→ HTTP POST to #{url} with body:\n#{JSON.pretty_generate(body)}"
    response  = HTTP.headers(HEADERS).post(url, json: body)
    resp_body = response.body.to_s
    Rails.logger.debug "← Response: #{resp_body.truncate(200).gsub("\n"," ")}" 
    parsed = JSON.parse(resp_body)
    log_assistant_interaction(url: url, request_body: body, response_body: parsed, status: response.status.to_i)
    parsed
  end

  def get(url)
    Rails.logger.debug "→ HTTP GET to #{url}"
    resp = HTTP.headers(HEADERS).get(url).body.to_s
    Rails.logger.debug "← Response: #{resp.truncate(200).gsub("\n", " ")}"
    JSON.parse(resp)
  rescue StandardError => e
    Rails.logger.debug "← Error fetching #{url}: #{e.class}: #{e.message}"
    raise
  end


  def log_assistant_interaction(url:, request_body:, response_body:, status:)
    return unless risk_assistant && url.start_with?(BASE_URL)

    endpoint = url.delete_prefix(BASE_URL)
    return unless endpoint.include?("/runs") || endpoint.include?("/messages")

    AssistantRunLog.create!(
      risk_assistant:  risk_assistant,
      run_id:          response_body["id"] || request_body[:run_id],
      endpoint:        endpoint,
      request_payload: request_body,
      response_payload: response_body,
      http_status:     status
    )
  rescue StandardError => e
    Rails.logger.warn "AssistantRunner: no se pudo registrar la auditoría: #{e.message}"
  end


end




