# app/services/policy_analyzer.rb
require "net/http"
require "uri"
require "json"

class PolicyAnalyzer
  OPENAI_URL = "https://api.openai.com/v1/chat/completions"
  MODEL      = "gpt-4o-mini"
  MAX_RETRIES = 3

  def initialize(policy_analysis)
    @analysis = policy_analysis
    @api_key  = ENV.fetch("OPENAI_API_KEY")
    Rails.logger.info "[PolicyAnalyzer] Inicializado para Analysis##{@analysis.id}"
  end

  def run!
    Rails.logger.info "[PolicyAnalyzer##{@analysis.id}] Comenzando run!"
    docs = @analysis.documents
    Rails.logger.debug "[PolicyAnalyzer##{@analysis.id}] Documentos a procesar: #{docs.map(&:filename).join(', ')}"

    structured = docs.map do |doc|
      filename = doc.filename.to_s
      Rails.logger.info "[PolicyAnalyzer##{@analysis.id}] Procesando #{filename}"

      text = TextExtractor.call(doc)
      Rails.logger.debug "[PolicyAnalyzer##{@analysis.id}] Texto extraído (#{filename}): #{text.truncate(100)}"

      #secciones = extract_sections(text)
      #Rails.logger.info "[PolicyAnalyzer##{@analysis.id}] Secciones extraídas (#{filename}): #{secciones.size}"

      parametros = extract_parameters(text)
      Rails.logger.info "[PolicyAnalyzer##{@analysis.id}] Parámetros extraídos (#{filename}): #{parametros.size}"

      #{ filename: filename, secciones: secciones, parametros: parametros }
      { filename: filename, parametros: parametros }
    end

    Rails.logger.info "[PolicyAnalyzer##{@analysis.id}] Llamando a rank_offers con #{structured.size} pólizas"
    ranking = rank_offers(structured.map { |d| d[:parametros].map{ |p| p["contenido"] }.join("\n") })
    Rails.logger.info "[PolicyAnalyzer##{@analysis.id}] Ranking recibido"

    Rails.logger.info "[PolicyAnalyzer##{@analysis.id}] Guardando resultados en la base"
    @analysis.update!(
      extractions: structured.to_json,
      rating:      ranking
    )
    Rails.logger.info "[PolicyAnalyzer##{@analysis.id}] Actualización completada"
  rescue => e
    Rails.logger.error "[PolicyAnalyzer##{@analysis.id}] ERROR en run!: #{e.class} – #{e.message}"
    raise
  end

  private

    def extract_json_block(text)
    cleaned = text.gsub(/\A```(?:json)?/i, '').gsub(/```\Z/, '').strip
    cleaned.gsub!(/\A[\r\n]+|[\r\n]+\Z/, '')
    # Forzar cierre de array si empieza con [ y no termina con ]
    if cleaned.strip.start_with?('[') && !cleaned.strip.end_with?(']')
        cleaned = cleaned + ']'
    end
    cleaned
    end


  def extract_sections(text)
    prompt = <<~SYS
      Extrae las secciones de la póliza con su título, contenido y número de página.
      Responde *solo* con JSON:
      [
        {
          "titulo": "...",
          "pagina": [n, ...],
          "contenido": "...",
          "subsecciones": [
            { "titulo": "...", "pagina": [n,...], "contenido": "..." },
            ...
          ]
        },
        ...
      ]
    SYS

    Rails.logger.debug "[PolicyAnalyzer##{@analysis.id}] → extract_sections OpenAI"
    json_str = with_retries { call_openai_raw(prompt, text) }
    Rails.logger.debug "[PolicyAnalyzer##{@analysis.id}] ← extract_sections raw: #{json_str.truncate(100)}"
    JSON.parse(json_str)
  rescue JSON::ParserError => e
    Rails.logger.error "[PolicyAnalyzer##{@analysis.id}] JSON error in extract_sections: #{e.message}"
    []
  end

  def extract_parameters(text)
    prompt = <<~SYS
      Ahora, eres un experto en seguros y extraes la información de cada uno de estos parámetros en la póliza:

            Valor de nuevo (reposición a nuevo)",
            Valor real (valor venal o depreciado)",
            Seguro a primer riesgo",
            Seguro a valor total",
            "Seguro a valor parcial",
            "Regla proporcional (cláusula de infraseguro)",
            "Suma asegurada y límite máximo por siniestro",
            "Sublímites",
            "Gastos de alquiler de local provisional (desalojamiento)",
            "Gastos de obtención de permisos y licencias",
            "Daños en jardines y áreas verdes",
            "Incendio",
            "Explosión",
            "Caída del rayo",
            "Ondas sónicas",
            "Fenómenos atmosféricos (lluvia, viento, pedrisco, nieve)",
            "Actos vandálicos o malintencionados",
            "Inundación (riesgo ordinario)",
            "Daños por humo",
            "Daños por agua (escapes, fugas y derrames)",
            "Localización y reparación de averías de agua",
            "Rotura de cristales, espejos y rótulos",
            "Robo y expoliación",
            "Desperfectos por robo (daños por robo)",
            "Transporte externo de fondos",
            "Todo riesgo accidental (daño accidental súbito)",
            "Daños eléctricos",
            "Avería de maquinaria",
            "Avería de equipos electrónicos",
            "Derrame de líquidos",
            "Derrumbe",
            "Pérdida de beneficios",
            "Contingencias especiales (lucro cesante)",
            "Gastos permanentes asegurados (cobertura de costes fijos)",
            "Margen bruto asegurado",
            "Indemnización diaria",
            "Pérdida de alquileres (como modalidad de lucro cesante)",
            "Margen preventivo",
            "Responsabilidad Civil de explotación (RC general)",
            "Responsabilidad Civil inmobiliaria",
            "Responsabilidad Civil patronal",
            "Responsabilidad Civil de productos y post-trabajos",
            "Responsabilidad Civil de objetos confiados",
            "Responsabilidad Civil por contaminación accidental",
            "Responsabilidad Civil de trabajos de instalación (RC del instalador)",
            "Límite de indemnización en RC (por siniestro y anual)",
            "Sublímite por víctima en RC patronal",
            "Gastos de retirada de productos defectuosos",
            "Ámbito territorial de la RC de productos",
            "Gastos de defensa y fianzas en RC",
            "Franquicia en responsabilidad civil",
            "Reclamación de daños (defensa jurídica)",
            "Defensa penal del asegurado",
            "Defensa jurídica como arrendatario o propietario",
            "Asistencia 24 horas (servicio de asistencia urgente)",
            "Asistencia informática",
            "Servicio de información comercial (ej.: Iberinform)",
            "Cobertura de riesgos extraordinarios (Consorcio de Compensación de Seguros)",
            "Exclusión de riesgos de guerra y conflictos armados",
            "Exclusión de contaminación nuclear o radiactiva",
            "Exclusión de daños ambientales y polución",
            "Exclusión de desgaste, vicio propio y deterioro paulatino",
            "Exclusión de actos dolosos o culpa grave del asegurado",
            "Exclusión de bienes no descritos o fuera de situación asegurada"
      Extrae *solo* los parámetros presentes en la póliza, con nombre, contenido y páginas.
      Responde *solo* con JSON:
      [
        { "parametro": "...", "contenido": "...", "paginas": [n,...] },
        ...
      ]
    SYS

    Rails.logger.debug "[PolicyAnalyzer##{@analysis.id}] → extract_parameters OpenAI"
    raw = call_openai_raw(prompt, text)
    json_str = extract_json_block(raw)
    Rails.logger.debug "[PolicyAnalyzer##{@analysis.id}] ← extract_parameters raw: #{json_str.truncate(100)}"
    JSON.parse(json_str)
  rescue JSON::ParserError => e
    Rails.logger.error "[PolicyAnalyzer##{@analysis.id}] JSON error in extract_parameters: #{e.message}"
    []
  end

  def rank_offers(texts)
    prompt = <<~SYS
      Eres un evaluador de ofertas. Recibes varios bloques de texto de pólizas.
      Ordénalos por idoneidad (mejor cobertura + menor prima) y responde listando:
      1) Nombre de la póliza (según orden de subida)
      2) Breve justificación
    SYS

    joined = texts.map.with_index(1){|t,i|"Póliza #{i}:\n#{t}"}.join("\n\n")
    Rails.logger.debug "[PolicyAnalyzer##{@analysis.id}] → rank_offers OpenAI"
    result = with_retries { call_openai_raw(prompt, joined) }.strip
    Rails.logger.debug "[PolicyAnalyzer##{@analysis.id}] ← Ranking recibido: #{result.truncate(100)}"
    result
  end

  # Este método hace la llamada HTTP y devuelve el content directamente
  def call_openai_raw(system, user)
    uri = URI(OPENAI_URL)
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@api_key}"
    req["Content-Type"]  = "application/json"
    req.body = {
      model: MODEL,
      messages: [
        { role: "system",  content: system },
        { role: "user",    content: user   }
      ],
      temperature: 0.0
    }.to_json

    Rails.logger.debug "[PolicyAnalyzer##{@analysis.id}] → HTTP a OpenAI (model=#{MODEL}, tokens=2000, temp=0.0)"
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    Rails.logger.debug "[PolicyAnalyzer##{@analysis.id}] ← HTTP status: #{res.code}"
    body = JSON.parse(res.body) rescue {}
    body.dig("choices", 0, "message", "content") || ""
  rescue => e
    Rails.logger.error "[PolicyAnalyzer##{@analysis.id}] OpenAI API error: #{e.class} – #{e.message}"
    raise
  end

  # Wrapper que reintenta Net::ReadTimeout hasta MAX_RETRIES veces
  def with_retries
    tries = 0
    begin
      return yield
    rescue Net::ReadTimeout => e
      tries += 1
      if tries <= MAX_RETRIES
        sleep 2**(tries - 1)
        Rails.logger.warn "[PolicyAnalyzer##{@analysis.id}] ReadTimeout, reintentando #{tries}/#{MAX_RETRIES}..."
        retry
      else
        Rails.logger.error "[PolicyAnalyzer##{@analysis.id}] agotados los reintentos por ReadTimeout"
        return ""  # fallback vacío
      end
    end
  end
end



