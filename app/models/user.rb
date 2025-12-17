class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role: { owner: 0, client: 1, guest: 2 }

  MAX_CLIENTS = 20
  MAX_GUEST_RISK_ASSISTANTS = 3

  after_initialize { self.role ||= :client }

  belongs_to :owner, class_name: 'User', optional: true
  has_many :clients, class_name: 'User', foreign_key: :owner_id, dependent: :nullify
  has_many :client_invitations, class_name: 'ClientInvitation', foreign_key: :owner_id, dependent: :destroy

  after_commit :sync_risk_assistants_client_owned, if: -> { saved_change_to_role? } 

  has_one_attached :logo
  
  has_many :risk_assistants, class_name: 'RiskAssistant', dependent: :destroy
  has_many :policy_analyses, dependent: :destroy

  validates :role, presence: true
  validates :role, inclusion: { in: roles.keys }  
  validates :company_name, presence: true, if: :owner?
  validates :owner, presence: true, if: -> { client? || guest? }
  validate :only_one_admin_allowed, if: :admin?

  def admin?
    self[:admin]
  end

  def can_create_risk_assistant?
    return true if admin?
    return risk_assistants.count < MAX_GUEST_RISK_ASSISTANTS if guest?

    true
  end

  def can_add_client?
    return false unless admin?

    client_invitations.pending.count < MAX_CLIENTS
  end

  private

  def only_one_admin_allowed
    existing_admin = User.where(admin: true).where.not(id: id).exists?
    errors.add(:admin, 'ya existe un administrador configurado.') if existing_admin
  end

  def sync_risk_assistants_client_owned
    return unless risk_assistants.klass.column_names.include?("client_owned")
    risk_assistants.update_all(client_owned: client?)
  end
end
