class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_risk_assistant

  require "fileutils"
  require "risk_field_set"

  MISSING_FIELD_TEMPLATES = RiskFieldSet.by_id.transform_values do |field|
    question = RiskFieldSet.question_for(field[:id], include_tips: false)
    question = question.lines.reject { |l| l.start_with?("Contexto:") }.join
    reason   = field[:why].to_s.strip
    msg      = "⚠️ Falta el dato #{field[:label]}."
    msg += " #{reason}" unless reason.empty?
    "#{msg}\n\n#{question}"
  end.freeze

  CONFIRMED_CONTEXT_LIMIT = 100   

  # ------------------------------------------------------------------
  # POST /risk_assistants/:risk_assistant_id/messages
  # ------------------------------------------------------------------

  def create
    current_thread   = @risk_assistant.thread_id
    assistant_output = nil

    return redirect_blank_message if message_blank?

    last_question   = @risk_assistant.messages
                                  .where(role: "assistant", key: nil)
                                  .where.not(field_asked: nil)
                                  .last
    requested_field = params.dig(:message, :field_asked)
    expected_field  = requested_field.presence || last_question&.field_asked

    if requested_field.present? && !RiskFieldSet.by_id.key?(requested_field.to_sym)
      Rails.logger.warn("MessagesController#create: invalid field_asked '#{requested_field}'")
      expected_field = last_question&.field_asked
      unless expected_field
        head :unprocessable_entity
        return
      end
    end

    @message = save_user_message(expected_field)

    if skip_message?(@message.content)
      handle_skip(current_thread)
      assistant_output = assistant_output_for_snapshot(current_thread)
      redirect_to @risk_assistant
      return
    end

    if handle_file_upload(params[:file], current_thread)
      assistant_output = assistant_output_for_snapshot(current_thread)
      redirect_to risk_assistant_path(@risk_assistant)
      return
    end

    assistant_output = assistant_interaction(current_thread)
    redirect_to @risk_assistant

  rescue => e
    Rails.logger.error "💥 Error en MessagesController#create: #{e.class} – #{e.message}"
    flash[:error] = "Se produjo un error\n     al procesar tu mensaje."
    redirect_to risk_assistant_path(@risk_assistant)
  ensure
    persist_snapshot!(thread_id: current_thread, assistant_output: assistant_output)
  end

  private

  def message_blank?
    params.dig(:message, :content).blank? && params[:file].blank?
  end

  def redirect_blank_message
    flash[:error] = "El mensaje no puede estar vacío (o adjunte un archivo)."
    redirect_to risk_assistant_path(@risk_assistant)
  end

  def save_user_message(expected_field)
    @risk_assistant.messages.create!(
      message_params.merge(
        sender:      "user",
        role:        "user",
        thread_id:   @risk_assistant.thread_id,
        field_asked: expected_field
      )
    )
  end


  def skip_message?(content)
    content.to_s.strip.downcase.in?(%w[saltar skip])
  end

  def handle_skip(current_thread)
    @message.update!(role: "developer")

    Message.save_unique!(
      risk_assistant: @risk_assistant,
      key:           @message.field_asked,
      value:         "SALTADO",
      content:       "Campo omitido.",
      sender:        "assistant",
      role:          "developer",
      value_state:   "omitido",
      value_source:  "sistema", 
      field_asked:   @message.field_asked,
      thread_id:     current_thread
    )

    label = RiskFieldSet.label_for(@message.field_asked)
    @risk_assistant.messages.create!(
      sender: "assistant",
      role:   "assistant",
      content: "Se omitió el campo #{label}.",
      thread_id: current_thread
    )

    AssistantRunner.new(@risk_assistant).ask_next!
  end

  # Returns true if a redirect happened
  def handle_file_upload(file, current_thread)
    return false unless file.present?

    field_key = @message.field_asked

    file.rewind
    @message = Message.save_unique!(
      risk_assistant: @risk_assistant,
      key:           field_key,
      value:         file.original_filename,
      content:       "Archivo subido correctamente.",
      sender:        "assistant",
      role:          "assistant",
      value_source:  "archivo",
      field_asked:   field_key,
      thread_id:     current_thread
    )
    @message.files.attach(file)

    if image_file?(file)
      answered   = @risk_assistant.messages.where.not(key: nil).pluck(:key, :value).to_h
      next_field = RiskFieldSet.next_field_hash(answered)
      if next_field
        display_text = RiskFieldSet.question_for(next_field[:id], include_tips: true)

        @risk_assistant.messages.create!(
          sender:      "assistant",
          role:        "assistant",
          content:     display_text,
          field_asked: next_field[:id],
          thread_id:   current_thread
        )

        redirect_to risk_assistant_path(@risk_assistant)
        return true
      end
    end
   
    extracted_text = TextExtractor.call(file)

    doc_type = nil
    if extracted_text.present?
      doc_type = DocumentTypeClassifier.call(extracted_text)
    end    
    
    file.rewind
    @risk_assistant.uploaded_files.attach(file)

    Message.save_unique!(
      risk_assistant: @risk_assistant,
      key:           "document_type",
      value:         doc_type,
      content:       "El documento parece ser una #{doc_type}.",
      sender:        "assistant",
      role:          "assistant",
      value_state:   "confirmado",
      value_source:  "documento",
      field_asked:   @message.field_asked,
      thread_id:     current_thread
    )

    if extracted_text.present?
      Message.save_unique!(
        risk_assistant: @risk_assistant,
        key:           "document_type",
        value:         doc_type,
        content:       "El documento parece ser una #{doc_type}.",
        sender:        "assistant",
        role:          "assistant",
        value_state:   "confirmado",
        value_source:  "documento",
        thread_id:     current_thread
      )

      @risk_assistant.messages.create!(
        sender:    "assistant",
        role:      "developer",
        content:   "[EXTRAÍDO]\n#{extracted_text}",
        thread_id: current_thread
      )
    end

    result   = DocumentFieldExtractor.call(extracted_text)
    values   = result[:values]   || {}
    warnings = result[:warnings] || {}

    if values.any?
      summary_lines = []
      values.each do |campo_id, valor|
        label = RiskFieldSet.label_for(campo_id)
        Message.save_unique!(
          risk_assistant: @risk_assistant,
          key:           campo_id,
          value:         valor,
          content:       "✅ Perfecto, #{label} es &&#{valor}&&.",
          sender:        "assistant",
          role:          "developer",
          value_state:   "confirmado",
          value_source:  "documento",
          field_asked:   campo_id,
          thread_id:     current_thread
        )
        summary_lines << "✅ #{label}: #{valor}"
      end

      warnings.each do |campo_id, msg|
        @risk_assistant.messages.create!(
          sender:    'assistant_flag',
          role:      'developer',
          content:   "⚠️ #{RiskFieldSet.label_for(campo_id)}: #{msg} ⚠️",
          thread_id: current_thread
        )
      end

      todos_confirmaciones = summary_lines.join("\n")
      @risk_assistant.messages.create!(
        sender:    "assistant",
        role:      "assistant",
        content:   "He extraído y confirmado automáticamente los siguientes campos del documento:\n\n#{todos_confirmaciones}",
        thread_id: current_thread
      )

      redirect_to risk_assistant_path(@risk_assistant)
      return true  
    end

    next_field_id = RiskFieldSet.next_field_hash(
                      @risk_assistant.messages.where.not(key: nil).pluck(:key, :value).to_h
                    )&.dig(:id)
    next_label = next_field_id ? RiskFieldSet.label_for(next_field_id) : "campo pendiente"

    @risk_assistant.messages.create!(
      sender:    "assistant",
      role:      "assistant",
      content:   "He extraído el texto del documento, pero no encontré datos para los campos solicitados.\n" \
                 "Por favor, indícame directamente el campo \"#{next_label}\".",
      field_asked: next_field_id,
      thread_id: current_thread
    )

    redirect_to risk_assistant_path(@risk_assistant)
    true
  end
  end

  def assistant_interaction(current_thread)
    runner = AssistantRunner.new(@risk_assistant)
    runner.submit_user_message(content: @message.content, file_id: nil)

    assistant_text = runner.run_and_wait.to_s.strip
    assistant_response_for_snapshot = assistant_text


    if assistant_text.blank?
      Rails.logger.warn("MessagesController#assistant_interaction: respuesta vacía del asistente")

      @risk_assistant.messages.create!(
        sender:      "assistant",
        role:        "assistant",
        content:     "No he recibido respuesta del asistente. Por favor, inténtalo de nuevo.",
        field_asked: @message.field_asked,
        thread_id:   runner.thread_id
      )

      return
    end 

    parsed = AssistantResponseParser.call(assistant_text)

    # Intentar interpretar la respuesta como JSON estructurado
    begin
      parsed = JSON.parse(assistant_text)
    rescue JSON::ParserError
      parsed = nil
    end

    campo_actual = parsed.is_a?(Hash) ? parsed["campo_actual"] : nil
    @message.update!(field_asked: campo_actual) if campo_actual.present?

    if parsed.is_a?(Hash) && parsed["mensaje_para_usuario"].present?
      estado       = parsed["estado_del_campo"]
      valor        = parsed["valor"] || @message.content
      mensaje      = parsed["mensaje_para_usuario"]
      explicacion  = parsed["explicacion_normativa"]      
      siguiente    = parsed["siguiente_campo"]

      # Determine which field should be asked next. By default we keep the
      # current field, but if the field was confirmed we only move to the next
      # one if it's present and valid according to RiskFieldSet.
      field_for_question = campo_actual

      siguiente_valido = siguiente.present? && RiskFieldSet.by_id.key?(siguiente.to_sym)
      transition_without_confirmation = false      

      if estado == "confirmado"
        field_for_question = siguiente if siguiente_valido
        field_for_question = nil unless siguiente_valido
      elsif siguiente_valido && mensaje.to_s.include?("?")
        field_for_question = siguiente
        transition_without_confirmation = true
      end

      if transition_without_confirmation
        @message.update!(field_asked: field_for_question)
        Rails.logger.info("MessagesController#assistant_interaction: transición sin confirmación hacia #{field_for_question}")        
      end

      runner.set_last_field(field_for_question) if field_for_question
      
      if estado == "confirmado" && campo_actual.present?
        Message.save_unique!(
          risk_assistant: @risk_assistant,
          key:           campo_actual,
          value:         valor,
          content:       "✅ Perfecto, #{RiskFieldSet.label_for(campo_actual)} es &&#{valor}&&.",
          sender:        "assistant_confirmation",
          role:          "developer",
          value_state:   estado,
          value_source:  "usuario",
          field_asked:   campo_actual,
          thread_id:     runner.thread_id
        )
      end

      mensaje = "#{mensaje}\nExplicación normativa: #{explicacion}" if explicacion.present?

      @risk_assistant.messages.create!(
        sender:      "assistant",
        role:        "assistant",
        content:     mensaje,
        field_asked: field_for_question,
        thread_id:   runner.thread_id
      )

      return assistant_response_for_snapshot
    end


    last_q = @risk_assistant.messages
                            .where(sender: ["assistant", "assistant_guard"], role: "assistant", thread_id: runner.thread_id)
                            .where.not(field_asked: nil)
                            .where(key: nil)
                            .order(:created_at)
                            .last

    pairs = assistant_text.scan(/##(?<field_id>[^#()]+?)(?:\s*\((?<item_label>[^)]+)\))?##.*?&&\s*(?<value>.*?)\s*&&/m)
    flags = assistant_text.scan(/⚠️\s*(.*?)\s*⚠️/m).flatten
    sanitized_text = assistant_text.gsub(/(?:\u2705[^#]*?)?##[^#]+##.*?&&.*?&&\s*[.,]?/m, "")
    sanitized_text = sanitized_text.gsub(/##[^#]+##/, '')
    sanitized_text = ActionController::Base.helpers.strip_tags(sanitized_text).strip
    confirmations = []
    confirmed_fields = []    

    pairs.each do |field_id, item_label, value|
      clean_id = field_id.to_s.strip

      if last_q && clean_id !~ /\.\d+\./
        expected = last_q.field_asked.to_s
        clean_id = expected if expected.gsub(/\.\d+/, '') == clean_id
      end

      Message.save_unique!(
        risk_assistant: @risk_assistant,
        key:           clean_id,
        value:         value,
        item_label:    item_label,
        content:       "✅ Perfecto, #{RiskFieldSet.label_for(clean_id)} es &&#{value}&&.",
        sender:        "assistant_confirmation",
        role:          "developer",
        value_state:   "confirmado",
        value_source:  "assistant",
        field_asked:   nil,
        thread_id:     runner.thread_id
      )

      confirmations << "✅ #{RiskFieldSet.label_for(clean_id)}: #{value}"
      confirmed_fields << clean_id      
    end
  

    flags.each do |msg|
      @risk_assistant.messages.create!(
        sender:    "assistant_flag",
        role:      "developer",
        content:   "⚠️ #{msg} ⚠️",
        thread_id: runner.thread_id
      )
    end

    field_for_question = runner.last_field_id

    if field_for_question && confirmed_fields.include?(field_for_question.to_s)
      field_for_question = nil
    end

    field_for_question ||= last_q&.field_asked.presence ||
                          @message.field_asked.presence

    field_for_question ||= begin
      answered = @risk_assistant.messages.where.not(key: nil).pluck(:key, :value).to_h
      RiskFieldSet.next_field_hash(answered)&.dig(:id)
    end
    return unless field_for_question
    field_for_question = field_for_question.to_s

    return unless RiskFieldSet.by_id.key?(field_for_question.to_sym)
    question_field = field_for_question
    runner.set_last_field(question_field)


    @risk_assistant.messages.create!(
      sender:    "assistant_raw",
      role:      "developer",
      content:   assistant_text,
      field_asked: question_field,
      thread_id: runner.thread_id
    )

    assistant_instructions = RiskFieldSet.by_id[question_field.to_sym][:assistant_instructions]
    tips  = RiskFieldSet.normative_tips_for(question_field)

    base_question = sanitized_text.presence ||
                    RiskFieldSet.question_for(question_field.to_sym, include_tips: false)

    question_text = if sanitized_text.present?
                      sanitized_text
                    else
                      ParagraphGenerator.generate(
                        question: base_question,
                        instructions: assistant_instructions.to_s,
                        normative_tips: tips,
                        confirmations: confirmations
                      ).presence || base_question
                    end

    parts = [question_text]
    norm_explanation = NormativeExplanationGenerator.generate(question_field, question: question_text)
    parts << "Explicación normativa: #{norm_explanation}"

    final_content = parts.join("\n")

    @risk_assistant.messages.create!(
      sender: "assistant",
      role: "assistant",
      content: final_content,
      field_asked: question_field,
      thread_id: runner.thread_id
    )

    assistant_response_for_snapshot = final_content    

    if confirmations.any?

      @risk_assistant.messages.create!(
        sender: "assistant_summary",
        role: "developer",
        content: confirmations.join("\n"),
        field_asked: question_field,
        thread_id: runner.thread_id
      )
    end

    assistant_response_for_snapshot    

  end

  def message_params
    params.require(:message).permit(:content, :thread_id, :section, :field_asked)
  end

  def set_risk_assistant
    @risk_assistant = owner_or_self.risk_assistants.find(params[:risk_assistant_id])
  end

  # ---------- subida de fichero + asociación al thread ----------
  def uploader_to_openai(file)
    tmp = Tempfile.new(
            [File.basename(file.original_filename, '.*'),
            File.extname(file.original_filename)],
            binmode: true                                  # ← Windows friendly
          )

    tmp.write file.read
    tmp.flush                                            # asegura disco
    tmp.rewind
    tmp.close                                            # <-- CERRAR ANTES de enviar

    Rails.logger.debug { "Uploader: subiendo #{tmp.path}" }

    resp = HTTP
          .headers(
            "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
            "OpenAI-Beta"   => "assistants=v2"
          )
          .post(
            "#{AssistantRunner::BASE_URL}/files",
            form: {
              file: HTTP::FormData::File.new(tmp.path),  # ya está cerrado
              purpose: "assistants",
            }
          )

    body    = JSON.parse(resp.body.to_s)
    file_id = body["id"]
    Rails.logger.debug { "Uploader: file_id #{file_id}" }

    file_id
  ensure
    # Siempre intentar borrar (solo posible si está cerrado)
    if tmp && !tmp.closed?      # si hubo excepción antes del close
      tmp.close
    end
    tmp&.unlink                # en Windows hay que cerrar *antes* de unlink
    Rails.logger.debug { "Uploader: eliminado #{tmp.path}" }
  end
  
  def attach_to_thread(thread_id, file_id)
    HTTP.headers(AssistantRunner::HEADERS)
        .post("https://api.openai.com/v1/threads/#{thread_id}/files",
              json: { file_id: file_id })
  end

  def format_previous_messages(messages)
    messages.map do |message|
      "[#{message[:role].capitalize}]: #{message[:content]}"
    end.join("\n")
  end

  def collect_messages_for_context(risk_assistant)
    risk_assistant.messages.order(:created_at).pluck(:role, :content).map do |role, content|
      { role: role, content: content }
    end
  end

  def assistant_output_for_snapshot(thread_id)
    @risk_assistant.messages
                   .where(thread_id: thread_id, sender: %w[assistant assistant_confirmation assistant_summary assistant_raw])
                   .order(:created_at)
                   .last
                   &.content
  end

  def persist_snapshot!(thread_id:, assistant_output:)
    return unless @risk_assistant

    assistant_content = assistant_output.presence || assistant_output_for_snapshot(thread_id)

    normalized_payload = ConversationNormalizer.call(
      risk_assistant: @risk_assistant,
      last_user_message: @message&.content,
      last_assistant_message: assistant_content.to_s
    )

    ConversationSnapshot.create!(
      risk_assistant: @risk_assistant,
      thread_id: thread_id,
      last_user_message: @message&.content,
      last_assistant_message: assistant_content,
      messages_dump: collect_messages_for_context(@risk_assistant),
      normalized_payload: normalized_payload,
      status: normalized_payload.present? ? "normalized" : "captured"
    )
  rescue => e
    Rails.logger.error "ConversationSnapshot error: #{e.class} – #{e.message}"
  end


  def image_file?(file)
    file.content_type.to_s.start_with?("image/")
  end


  def fetch_response_from_openai(messages)

    previous_messages = collect_messages_for_context(@risk_assistant)
    prompt_messages = format_previous_messages(previous_messages)

    # Construir el context
    context = <<~PROMPT
      Con toda la información recabada en esta conversación, por favor:
      1. Haz un **resumen ejecutivo de cada apartado desde un punto de vista de un informe descriptivo de ingeniería de riesgos**.
      2. Extrae las **métricas clave** (campos del formulario).
      3. Identifica **lagunas de información** si las hubiera.
      4. Ofrece **conclusiones y recomendaciones**.
      Devuélvelo como un informe estructurado en Markdown.
      Preguntas realizadas por ti y las respuestas del usuario: #{prompt_messages}
    PROMPT

    Rails.logger.debug { "context built: #{context.inspect}" }

    # Construir el prompt completo
    prompt = @message.content

    #enviar la solicitud a openai
    response = HTTP.post(
      "https://api.openai.com/v1/chat/completions",
      headers: {
        "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
        "Content-Type" => "application/json"
      },
      body: {
        model: "gpt-4o-mini",
        messages: [
          { role: "developer", content: context },
          { role: "user", content: prompt }
        ],
        max_tokens: 600,
        temperature: 0.7
      }.to_json
    )

    Rails.logger.debug("🔍 Content: #{response["content"].inspect}")
    response.parse["choices"]&.first&.dig("message", "content")&.strip || "No se recibió una respuesta válida."
  end

  def parse_response(response_content)
    # Verificar si la respuesta contiene un formato esperado
    if response_content.include?(':')
      response_content.split("\n").map do |line|
        key_value = line.split(': ').map(&:strip)
        next if key_value.size != 2
        [key_value[0].to_sym, key_value[1]]
      end.compact.to_h
    else
      Rails.logger.warn("Respuesta genérica o no estructurada: #{response_content}")
      {}
    end

    #Guardar en la base de datos las respuesta de chatgpt

  rescue StandardError => e
    Rails.logger.error("Error al procesar la respuesta: #{e.message}")
    {}
  end

