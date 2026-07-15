import bcrypt

# User details
name = 'Test User'
email = 'test@example.com'
password = 'test1234'
role = 'customer'
phone = '1234567890'

# Hash the password
hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
print(f"INSERT INTO users (name, email, password, role, phone) VALUES ('{name}', '{email}', '{hashed.decode()}', '{role}', '{phone}');")
