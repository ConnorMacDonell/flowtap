# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "🌱 Seeding database..."

# Only seed development and test environments
unless Rails.env.production?
  puts "📝 Creating sample data for #{Rails.env} environment..."
  
  # Create demo user
  if defined?(User)
    User.find_or_create_by!(email: "demo@example.com") do |user|
      user.password = "password123"
      user.password_confirmation = "password123"
      user.first_name = "Demo"
      user.last_name = "User"
      user.confirmed_at = Time.current
    end
    puts "✅ Created demo user (demo@example.com / password123)"
  end
  
  if defined?(AdminUser)
    AdminUser.find_or_create_by!(email: "admin@example.com") do |admin|
      admin.password = "admin_password123"
      admin.password_confirmation = "admin_password123"
      admin.name = "Admin User"
    end
    puts "✅ Created admin user (admin@example.com / admin_password123)"
  end
  
  puts "🎉 Development seeds completed!"
else
  puts "⚠️  Production environment - skipping sample data creation"
end

puts "✨ Seeding complete!"
