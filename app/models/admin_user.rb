class AdminUser < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable, :trackable
  
  validates :name, presence: true, length: { minimum: 2, maximum: 50 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  
  # Admin-specific methods
  def display_name
    name.present? ? name : email.split('@').first.humanize
  end
  
  def initials
    if name.present?
      name.split.map(&:first).join.upcase[0..1]
    else
      email[0..1].upcase
    end
  end
  
  def last_sign_in_humanized
    return "Never" unless last_sign_in_at
    
    time_ago = Time.current - last_sign_in_at
    
    case time_ago
    when 0..1.hour
      "#{time_ago.to_i / 60} minutes ago"
    when 1.hour..1.day
      "#{time_ago.to_i / 3600} hours ago"
    when 1.day..1.week
      "#{time_ago.to_i / 86400} days ago"
    else
      last_sign_in_at.strftime("%B %d, %Y")
    end
  end
end
