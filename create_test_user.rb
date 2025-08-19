User.create!(
  email: 'test@example.com', 
  password: 'oldpassword123', 
  first_name: 'Test', 
  last_name: 'User', 
  confirmed_at: Time.current
)
puts "Test user created successfully!"