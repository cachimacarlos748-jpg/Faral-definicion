class AppConfig {
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  
  static void assertConfigured() {
    // No-op for now
  }
}
