class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role: { owner: 0, client: 1, guest: 2 }

  MAX_CLIENTS = 20

  after_initialize { self.role ||= :client }

  belongs_to :owner, class_name: 'User', optional: true
  has_many :clients, class_name: 'User', foreign_key: :owner_id, dependent: :nullify
  has_many :client_invitations, class_name: 'ClientInvitation', foreign_key: :owner_id, dependent: :destroy

  after_commit :sync_risk_assistants_client_owned, if: -> { saved_change_to_role? } 

  has_one_attached :logo
  
  has_many :risk_assistants, class_name: 'RiskAssistant', dependent: :destroy
  has_many :policy_analyses, dependent: :destroy

  has_many :client_records, class_name: 'Client', dependent: :destroy

  validates :role, presence: true
  validates :role, inclusion: { in: roles.keys }  
  validates :company_name, presence: true, if: :owner?
  validates :owner, presence: true, if: -> { client? || guest? }

  def can_add_client?
    return false unless owner?

    client_invitations.pending.count < MAX_CLIENTS
  end

  private

  def sync_risk_assistants_client_owned
    return unless risk_assistants.klass.column_names.include?("client_owned")
    risk_assistants.update_all(client_owned: client?)
  end
end