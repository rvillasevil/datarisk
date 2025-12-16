# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2025_12_15_182652) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "actividad_procesos", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.string "actividad_principal"
    t.string "actividad_secundaria"
    t.integer "anio_inicio"
    t.string "jornada_laboral"
    t.decimal "produccion_anual"
    t.decimal "facturacion_anual"
    t.text "procesos_peligrosos"
    t.string "certificaciones"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id"], name: "index_actividad_procesos_on_risk_assistant_id"
  end

  create_table "almacenamientos", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.text "materias_primas"
    t.decimal "carga_fuego"
    t.string "tipo_almacenamiento"
    t.decimal "altura_almacenamiento"
    t.boolean "congestion"
    t.boolean "productos_combustibles"
    t.boolean "estabilidad_almacenamiento"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id"], name: "index_almacenamientos_on_risk_assistant_id"
  end

  create_table "assistant_run_logs", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.string "run_id"
    t.string "endpoint", null: false
    t.jsonb "request_payload", default: {}, null: false
    t.jsonb "response_payload", default: {}, null: false
    t.integer "http_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id", "endpoint"], name: "index_assistant_run_logs_on_risk_assistant_id_and_endpoint"
    t.index ["risk_assistant_id", "run_id"], name: "index_assistant_run_logs_on_risk_assistant_id_and_run_id"
    t.index ["risk_assistant_id"], name: "index_assistant_run_logs_on_risk_assistant_id"
  end

  create_table "client_invitations", force: :cascade do |t|
    t.string "email"
    t.string "token"
    t.bigint "owner_id", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_client_invitations_on_owner_id"
  end

  create_table "clients", force: :cascade do |t|
    t.string "name"
    t.boolean "inactive", default: false, null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_clients_on_user_id"
  end

  create_table "conversation_snapshots", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.string "thread_id"
    t.text "last_user_message"
    t.text "last_assistant_message"
    t.jsonb "messages_dump", default: []
    t.jsonb "normalized_payload", default: {}
    t.string "status", default: "captured", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id"], name: "index_conversation_snapshots_on_risk_assistant_id"
    t.index ["thread_id"], name: "index_conversation_snapshots_on_thread_id"
  end

  create_table "edificios_construccions", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.decimal "superficie_construida"
    t.decimal "superficie_parcela"
    t.integer "anio_construccion"
    t.string "regimen_propiedad"
    t.boolean "espacios_confinados"
    t.boolean "galerias_subterraneas"
    t.text "elementos_combustibles"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id"], name: "index_edificios_construccions_on_risk_assistant_id"
  end

  create_table "field_catalogue_messages", force: :cascade do |t|
    t.bigint "field_catalogue_id", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field_catalogue_id"], name: "index_field_catalogue_messages_on_field_catalogue_id"
    t.index ["role"], name: "index_field_catalogue_messages_on_role"
  end

  create_table "field_catalogues", force: :cascade do |t|
    t.bigint "owner_id", null: false
    t.string "status", default: "draft", null: false
    t.string "thread_id"
    t.jsonb "generated_catalogue", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "instructions_injected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id", "status"], name: "index_field_catalogues_on_owner_id_and_status"
    t.index ["owner_id"], name: "index_field_catalogues_on_owner_id"
  end

  create_table "field_definitions", force: :cascade do |t|
    t.bigint "field_section_id", null: false
    t.string "identifier", null: false
    t.string "label", null: false
    t.text "prompt"
    t.string "field_type", default: "string", null: false
    t.jsonb "options", default: [], null: false
    t.text "example"
    t.text "why"
    t.text "context"
    t.jsonb "validation", default: {}, null: false
    t.text "assistant_instructions"
    t.text "normative_tips"
    t.string "parent_identifier"
    t.boolean "array_of_objects", default: false, null: false
    t.string "item_label_template"
    t.string "array_count_source_field_id"
    t.jsonb "row_index_path", default: [], null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field_section_id", "identifier"], name: "index_field_definitions_on_section_and_identifier", unique: true
    t.index ["field_section_id"], name: "index_field_definitions_on_field_section_id"
    t.index ["identifier"], name: "index_field_definitions_on_identifier"
  end

  create_table "field_sections", force: :cascade do |t|
    t.bigint "field_catalogue_id", null: false
    t.string "identifier", null: false
    t.string "title", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field_catalogue_id", "identifier"], name: "index_field_sections_on_catalogue_and_identifier", unique: true
    t.index ["field_catalogue_id"], name: "index_field_sections_on_field_catalogue_id"
  end

  create_table "identificacions", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.string "nombre"
    t.string "direccion"
    t.string "codigo_postal"
    t.string "localidad"
    t.string "provincia"
    t.json "coordenadas"
    t.date "fecha_inspeccion"
    t.date "fecha_informe"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id"], name: "index_identificacions_on_risk_assistant_id"
  end

  create_table "instalaciones_auxiliares", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.string "estado_sistema_electrico"
    t.boolean "proteccion_electrica"
    t.date "ultima_revision_electrica"
    t.boolean "termografias"
    t.integer "transformadores_numero"
    t.decimal "transformadores_potencia"
    t.decimal "calderas_potencia"
    t.string "calderas_ubicacion"
    t.boolean "calderas_critico"
    t.decimal "frio_capacidad"
    t.string "frio_uso"
    t.integer "aire_compresores_numero"
    t.decimal "aire_presion_maxima"
    t.string "agua_almacenamiento"
    t.decimal "agua_capacidad"
    t.boolean "proteccion_incendios"
    t.decimal "generadores_capacidad"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id"], name: "index_instalaciones_auxiliares_on_risk_assistant_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.string "token", null: false
    t.bigint "owner_id", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_invitations_on_owner_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.string "sender"
    t.text "content"
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "key"
    t.string "value"
    t.string "thread_id"
    t.string "section"
    t.string "field_asked"
    t.string "item_label"
    t.string "value_state"
    t.string "value_source"
    t.index ["risk_assistant_id", "field_asked", "created_at"], name: "index_messages_on_assistant_field_created_at"
    t.index ["risk_assistant_id"], name: "index_messages_on_risk_assistant_id"
  end

  create_table "policy_analyses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.json "extractions"
    t.json "rating"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_policy_analyses_on_user_id"
  end

  create_table "recomendaciones", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.text "accion"
    t.string "estado"
    t.string "prioridad"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id"], name: "index_recomendaciones_on_risk_assistant_id"
  end

  create_table "riesgos_especificos", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.boolean "incendio"
    t.boolean "robo"
    t.boolean "interrupcion_negocio"
    t.boolean "responsabilidad_civil"
    t.text "riesgos_naturales"
    t.text "otros_riesgos"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id"], name: "index_riesgos_especificos_on_risk_assistant_id"
  end

  create_table "risk_assistants", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.jsonb "sections_completed"
    t.string "thread_id"
    t.boolean "initialised", default: false, null: false
    t.boolean "client_owned", default: false, null: false
    t.string "field_catalog_version"
    t.jsonb "data", default: {}
    t.string "guest_token"
    t.index ["data"], name: "index_risk_assistants_on_data", using: :gin
    t.index ["guest_token"], name: "index_risk_assistants_on_guest_token"
    t.index ["user_id"], name: "index_risk_assistants_on_user_id"
    t.index ["user_id"], name: "index_risk_assistants_on_user_id_unique_for_client", unique: true, where: "client_owned"
  end

  create_table "siniestralidads", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.date "fecha"
    t.text "causa"
    t.decimal "costo"
    t.text "medidas_adoptadas"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id"], name: "index_siniestralidads_on_risk_assistant_id"
  end

  create_table "ubicacion_configuracions", force: :cascade do |t|
    t.bigint "risk_assistant_id", null: false
    t.string "ubicacion"
    t.string "configuracion"
    t.text "actividades_colindantes"
    t.text "comentarios_generales"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["risk_assistant_id"], name: "index_ubicacion_configuracions_on_risk_assistant_id"
  end

  create_table "user_field_definitions", force: :cascade do |t|
    t.bigint "user_field_section_id", null: false
    t.string "field_key", null: false
    t.string "label", null: false
    t.text "prompt"
    t.string "field_type", default: "string", null: false
    t.jsonb "options", default: [], null: false
    t.text "example"
    t.text "why"
    t.text "context"
    t.text "assistant_instructions"
    t.text "normative_tips"
    t.jsonb "validation", default: {}, null: false
    t.string "parent_field_key"
    t.boolean "array_of_objects", default: false, null: false
    t.string "item_label_template"
    t.string "array_count_source_field_key"
    t.jsonb "row_index_path", default: [], null: false
    t.integer "position", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_field_section_id", "field_key"], name: "index_user_field_defs_on_section_and_field_key", unique: true
    t.index ["user_field_section_id", "position"], name: "index_user_field_defs_on_section_and_position"
    t.index ["user_field_section_id"], name: "index_user_field_definitions_on_user_field_section_id"
  end

  create_table "user_field_sections", force: :cascade do |t|
    t.bigint "user_field_set_id", null: false
    t.string "key", null: false
    t.string "title", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_field_set_id", "key"], name: "index_user_field_sections_on_set_and_key", unique: true
    t.index ["user_field_set_id", "position"], name: "index_user_field_sections_on_set_and_position"
    t.index ["user_field_set_id"], name: "index_user_field_sections_on_user_field_set_id"
  end

  create_table "user_field_sets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.text "description"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_field_sets_on_user_id"
    t.index ["user_id"], name: "index_user_field_sets_on_user_id_active", unique: true, where: "active"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.integer "role", default: 0, null: false
    t.string "company_name"
    t.bigint "owner_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["owner_id"], name: "index_users_on_owner_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "actividad_procesos", "risk_assistants"
  add_foreign_key "almacenamientos", "risk_assistants"
  add_foreign_key "assistant_run_logs", "risk_assistants"
  add_foreign_key "client_invitations", "users", column: "owner_id"
  add_foreign_key "clients", "users"
  add_foreign_key "conversation_snapshots", "risk_assistants"
  add_foreign_key "edificios_construccions", "risk_assistants"
  add_foreign_key "field_catalogue_messages", "field_catalogues"
  add_foreign_key "field_catalogues", "users", column: "owner_id"
  add_foreign_key "field_definitions", "field_sections"
  add_foreign_key "field_sections", "field_catalogues"
  add_foreign_key "identificacions", "risk_assistants"
  add_foreign_key "instalaciones_auxiliares", "risk_assistants"
  add_foreign_key "invitations", "users", column: "owner_id"
  add_foreign_key "messages", "risk_assistants"
  add_foreign_key "policy_analyses", "users"
  add_foreign_key "recomendaciones", "risk_assistants"
  add_foreign_key "riesgos_especificos", "risk_assistants"
  add_foreign_key "risk_assistants", "users"
  add_foreign_key "siniestralidads", "risk_assistants"
  add_foreign_key "ubicacion_configuracions", "risk_assistants"
  add_foreign_key "user_field_definitions", "user_field_sections"
  add_foreign_key "user_field_sections", "user_field_sets"
  add_foreign_key "user_field_sets", "users"
  add_foreign_key "users", "users", column: "owner_id"
end
