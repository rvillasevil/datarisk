  class RiskAssistantsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_client!
    before_action :require_authorized_user!
    before_action :set_risk_assistant, only: [:show, :generate_report, :report, :update_message, :create_message, :summary, :destroy_file]    
    
    def index
      @risk_assistants = owner_or_self.risk_assistants
    end
  
    def show
      @risk_assistants = owner_or_self.risk_assistants
      @messages = @risk_assistant.messages
      @company_name = @messages.where("key LIKE ?", "%Nombre de la empresa%").last

      # Hash de estados de campos para enviar al LLM cuando sea necesario
      @campos = @risk_assistant.campos
      @final_summary = final_confirmation(@campos)

      #Completados
      @completed = @risk_assistant.messages
                                   .where.not(key: [nil, ""])
                                   .where.not(value: [nil, ""])
                                   .order(:created_at)

      # Catálogo de secciones definido en config/risk_assistant/*
      catalogue = RiskFieldSet.all

      # Títulos de las secciones en el orden configurado
      @sections = catalogue.map { |_id, sec| sec[:title] }

      # ------------------------------------------------------------
      # 1. Mensajes con clave (key) y valor (value) no vacíos
      # ------------------------------------------------------------
      keyed = @risk_assistant
                .messages
                .where.not(key: [nil, ""])
                .where.not(value: [nil, ""])      # evita «valor vacío»
                .order(:created_at)

      # — normalizamos label → id:
      completed_by_id = {}
      keyed.each do |msg|
        raw_label = msg.key.to_s.strip.downcase          # ej. "nombre de la empresa..."
        id_sym    = RiskFieldSet.label_to_id[raw_label]  # ⇒ :nombre  |  nil si no mapea
        next unless id_sym

        completed_by_id[id_sym] = msg.value
      end

      # ------------------------------------------------------------
      # 2. Catálogo de secciones
      # ------------------------------------------------------------
      catalogue = RiskFieldSet.all

      @sections_data = catalogue.map do |sec_id, sec_h|
        ids         = sec_h[:fields].map { |f| f[:id].to_sym }
        completed_h = completed_by_id.slice(*ids)
        pending_arr = sec_h[:fields].reject { |f| completed_h.key?(f[:id].to_sym) }

        { id: sec_id, title: sec_h[:title], completed: completed_h, pending: pending_arr }
      end

      # --------------------------
      # 1) ids de campos completados
      # --------------------------
      filled_ids = @risk_assistant
                    .messages
                    .where.not(key: nil)          # key guarda el id del campo
                    .pluck(:key)                  # => ["nombre", "direccion_riesgo", ...]
                    .map(&:to_sym)
                    .to_set                        # búsqueda O(1)

      # --------------------------
      # 2) progreso por sección
      # --------------------------
      @progress_by_section = catalogue.each_with_object({}) do |(sec_key, sec_cfg), h|
        total = sec_cfg[:fields].size
        done  = sec_cfg[:fields].count { |f| filled_ids.include?(f[:id].to_sym) }
        pct   = total.zero? ? 0 : ((done * 100.0) / total).round
        h[sec_key] = { title: sec_cfg[:title], done:, total:, pct: }
      end

      # --------------------------
      # 3) progreso global (opcional)
      # --------------------------
      total_fields = RiskFieldSet.flat_fields.size
      total_done   = filled_ids.size
      @overall_pct = total_fields.zero? ? 0 : ((total_done * 100.0) / total_fields).round    
    end

    def new
      @risk_assistant = owner_or_self.risk_assistants.new
    end
  
    def create
      @risk_assistant = owner_or_self.risk_assistants.new(risk_assistant_params)
  
      if @risk_assistant.save
        redirect_to risk_assistant_path(@risk_assistant), notice: 'RiskAssistant creado con éxito.'
        create_openai_thread(@risk_assistant)
      else
        flash.now[:alert] = "No se pudo crear el RiskAssistant: #{@risk_assistant.errors.full_messages.join(', ')}"
        render :new, status: :unprocessable_entity
      end
    end
  
    def destroy
      @risk_assistant = current_user.risk_assistants.find(params[:id])
  
      if @risk_assistant.destroy
        flash[:notice] = "RiskAssistant eliminado con éxito."
      else
        flash[:error] = "No se pudo eliminar el RiskAssistant."
      end
  
      redirect_to risk_assistants_path
    end
    
    def report
      @risk_assistant = owner_or_self.risk_assistants.find(params[:id])
      @messages = @risk_assistant.messages
      @message = @risk_assistant.messages.last
      @report_markdown = fetch_response_from_openai(@message)
      # Ahora @report_markdown está disponible en la vista
    end

    def generate_report
      @message         = @risk_assistant.messages.last
      @report_markdown = fetch_response_from_openai(@message)

      # Renderiza la misma vista show, con @report_markdown disponible
      render :report
    end

    # GET /risk_assistants/:id/resume
    def resume
      @risk_assistant = owner_or_self.risk_assistants.find(params[:id])
      # Columnas del modelo Message
      @columns = Message.column_names
      # Solo los mensajes de este RiskAssistant
      @records = @risk_assistant.messages.order(:created_at)
    end

    # PATCH /risk_assistants/:id/update_message
    def update_message
      # Encuentra el mensaje concreto
      message = @risk_assistant.messages.find(params[:message_id])
      if request.delete?
        message.destroy
        redirect_to tabla_datos_risk_assistant_path(@risk_assistant), notice: "Mensaje ##{message.id} eliminado."
        return
      end
      # Actualiza solo los campos permitidos
      if message.update(message_params)
        redirect_to tabla_datos_risk_assistant_path(@risk_assistant),
                    notice: "Mensaje ##{message.id} actualizado."
      else
        flash.now[:alert] = "No se pudo actualizar el mensaje ##{message.id}."
        # recarga datos para re-render
        @columns = Message.column_names
        @records = @risk_assistant.messages.order(:created_at)
        render :tabla_datos
      end
    end

    # POST /risk_assistants/:id/create_message
    def create_message
      msg = Message.save_unique!(
        risk_assistant: @risk_assistant,
        key:           params[:key],
        value:         params[:value],
        sender:        params[:sender] || 'user',
        role:          params[:role]  || 'user',
        content:       params[:content] || params[:value]
      )
      if msg.persisted?
        redirect_to risk_assistant_resume_path(@risk_assistant), notice: "Mensaje ##{msg.id} añadido."
      else
        flash.now[:alert] = "No se pudo crear el mensaje: #{msg.errors.full_messages.join(', ')}"
        @records = @risk_assistant.messages.order(:created_at)
        render :resume
      end
    end

    def summary
      # Aquí cargamos todo lo que necesitemos para la vista
      @sections = RiskFieldSet.all
      @messages = @risk_assistant.messages
      render :summary
    end

    def destroy_file
      file = @risk_assistant.uploaded_files.find(params[:file_id])
      file.purge
      redirect_to risk_assistant_path(@risk_assistant), notice: "Archivo eliminado."
    end


    private
  
    # Si todos los campos están confirmados, devuelve un hash con los
    # pares key/value para mostrar al usuario como resumen final.
    # En caso contrario, devuelve un hash vacío.
    def final_confirmation(campos)
      return {} unless campos.values.all? { |s| s == "confirmado" }
      @risk_assistant.messages.where.not(key: [nil, ""]).pluck(:key, :value).to_h
    end

    def risk_assistant_params
      params.require(:risk_assistant).permit(:name, :thread_id)
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

    def create_openai_thread(risk_assistant)

      base_url = "https://api.openai.com/v1"
      headers = {
        "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
        "Content-Type" => "application/json",
        "OpenAI-Beta" => "assistants=v2"
      }

      response = HTTP.post("#{base_url}/threads", headers: headers, body: {}.to_json)
      thread_id = response.parse["id"]
      @risk_assistant.update!(thread_id: thread_id)

      Rails.logger.debug("🔍 Content: #{response["content"].inspect}")

      Rails.logger.debug(response)
    end

    def set_risk_assistant
      @risk_assistant = risk_assistants_scope.find(params[:id])
    end

    # Permite editar todos los campos de Message excepto id, conversation_id, created_at, updated_at
    def message_params
      params.require(:message).permit(Message.column_names - %w[id risk_assistant_id created_at updated_at])
    end

    def fetch_response_from_openai(message)
      previous_messages = collect_messages_for_context(@risk_assistant)
      prompt_messages   = format_previous_messages(previous_messages)

      context = <<~CTX
        Eres un analista de riesgos para el sector asegurador. Convierte la información proporcionada en la conversación del usuario (que puede estar incompleta) en un informe estructurado en español. Sigue este formato:

        # Informe Descriptivo de Riesgos para el Sector Asegurador

        ## 1. Resumen Ejecutivo  
        [Sintetiza en 3-5 líneas los hallazgos clave, riesgos dominantes y nivel de exposición general. Incluye advertencias críticas si las hay.]

        ---

        ## 2. Métricas Clave  
        ### A. Datos Identificativos  
        - **Nombre del asegurado**: [valor o "Incompleto"]  
        - **Dirección**: [valor o "Incompleto"]  
        - **CIF/NIF**: [valor o "Incompleto"]  
        - **Sector de actividad**: [valor o "Incompleto"]  

        ### B. Edificios Construcción  
        - **Tipo de construcción**: [Ej: Hormigón/acero]  
        - **Año de construcción**: [valor o "Incompleto"]  
        - **Superficie total**: [valor]  
        - **Estado de conservación**: [valor]  

        ### C. Actividad y Proceso  
        - **Procesos principales**: [detallar]  
        - **Materiales almacenados**: [listar]  
        - **Volumen de producción anual**: [valor o "Incompleto"]  

        ### D. Instalaciones Auxiliares  
        - **Generadores eléctricos**: [especificar capacidad]  
        - **Sistemas de ventilación**: [tipo/certificación]  
        #### D.1 Mantenimiento  
        - **Frecuencia de mantenimiento**: [valor]  
        - **Última inspección**: [fecha o "Incompleto"]  

        ### E. Riesgo de Incendio  
        #### E.1 Protección contra Incendios  
        - **Extintores**: [cantidad/tipo]  
        - **Sistema de rociadores**: [Sí/No/Incompleto]  
        #### E.2 Prevención de Incendios  
        - **Protocolos de manipulación de materiales**: [detalle]  
        - **Inspecciones eléctricas**: [frecuencia o "Incompleto"]  

        ### F. Riesgo de Robo  
        - **Sistemas de seguridad**: [detallar]  
        - **Horario de actividad**: [horas/días]  

        ### G. Riesgo de Interrupción de Negocio  
        - **Plan de continuidad**: [Sí/No/Incompleto]  
        - **Beneficio anual estimado**: [valor]  

        ---

        ## 3. Lagunas de Información  
        [Enumera en bullet points los datos faltantes clave usando **negritas** para las categorías, ej: "**Datos identificativos**: Falta CIF/NIF"]  

        ---

        ## 4. Conclusiones y Recomendaciones  
        ### Conclusiones  
        [3-5 puntos sobre riesgos prioritarios y su impacto]  

        ### Recomendaciones  
        [Acciones concretas para mitigar riesgos y completar información]  

        ---

        **Reglas**:  
        1. Usa **Markdown** puro.  
        2. Negritas solo en títulos y categorías de lagunas.  
        3. Datos numéricos en formato estándar (ej: €1.2M, 5,000 m²).  
        4. Marca “Incompleto” donde falte información.
      CTX

      prompt = prompt_messages

      response = HTTP.post(
        "https://api.openai.com/v1/chat/completions",
        headers: {
          "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
          "Content-Type"  => "application/json"
        },
        json: {
          model:       "gpt-4o-mini",
          messages: [
            { role: "developer", content: context },
            { role: "user",      content: prompt  }
          ],
          max_tokens:  5000,
          temperature: 0.8
        }
      )

      response.parse.dig("choices", 0, "message", "content")&.strip ||
        "No se recibió una respuesta válida."
    end

  end