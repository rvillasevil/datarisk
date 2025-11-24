class RiskAssistant < ApplicationRecord
  belongs_to :user
  has_many :messages, class_name: "Message", dependent: :destroy

  has_one :report

  validates :user_id, uniqueness: true, if: -> { user.client? }
  validates :name, presence: true

  before_validation :sync_client_owned

  has_one :identificacion, class_name: 'Identificacion', dependent: :destroy
  has_one :ubicacion_configuracion, dependent: :destroy
  has_one :edificios_construccion, dependent: :destroy
  has_one :actividad_proceso, dependent: :destroy
  has_one :almacenamiento, dependent: :destroy
  has_one :instalaciones_auxiliare, dependent: :destroy
  has_one :riesgos_especifico, dependent: :destroy
  has_one :siniestralidad, dependent: :destroy
  has_one :recomendacione, dependent: :destroy

  has_many_attached :uploaded_files

  accepts_nested_attributes_for :identificacion, :ubicacion_configuracion, :edificios_construccion,
                                :actividad_proceso, :almacenamiento, :instalaciones_auxiliare,
                                :riesgos_especifico, :siniestralidad, :recomendacione

  def campos
    confirmados = messages.where.not(key: nil).pluck(:key, :value).to_h

    resultado = {}
    confirmados.each do |key, value|
      resultado[key] = { estado: 'confirmado', valor: value }
    end

    RiskFieldSet.flat_fields.each do |field|
      field_id = field[:id].to_s
      resultado[field_id] ||= { estado: 'pendiente', valor: nil }
    end

    resultado
  end                                

  alias_attribute :initialised?, :initialised   # permite usar “?” al final

  private

  def sync_client_owned
    return unless has_attribute?(:client_owned)
    self.client_owned = user&.client? || false
  end
end
