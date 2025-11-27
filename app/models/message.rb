class Message < ApplicationRecord
  belongs_to :risk_assistant
  has_many_attached :files  

  validates :sender, presence: true
  validates :content, presence: true
  validates :key, uniqueness: { scope: :risk_assistant_id }, allow_blank: true
  #validates :field_asked, inclusion: { in: RiskFieldSet.by_id.keys.map(&:to_s) }, allow_nil: true  

  # "assistant_guard" messages are now visible to users
  INTERNAL_SENDERS = %w[
    assistant_confirmation
    assistant_raw
    assistant_flag
    assistant_summary
  ].freeze

  # Messages that should be displayed to the end user
  scope :visible_to_user, -> { where.not(role: "developer").where.not(sender: INTERNAL_SENDERS) }


  # Saves or updates a message identified by key for the given risk assistant.
  # Existing records with the same key will be overwritten to keep keys unique.
  def self.save_unique!(risk_assistant:, key:, **attrs)
    msg = risk_assistant.messages.find_or_initialize_by(key: key)
    if key.present?
      attrs[:value_state]  ||= 'confirmado'
      attrs[:value_source] ||= 'assistant'
    end
    msg.assign_attributes(attrs)
    msg.save!
    msg
  end
end