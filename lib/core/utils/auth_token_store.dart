class AuthTokenStore {
  static final AuthTokenStore _instance = AuthTokenStore._internal();
  factory AuthTokenStore() => _instance;
  AuthTokenStore._internal();

  String? token;
  // Store the logged-in user's id (as string). Set after successful login.
  String? userId;
}
