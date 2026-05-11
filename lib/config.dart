class AppConfig {
  // Varsayılan değer — emülatör/geliştirme için
  static String _baseUrl = 'http://localhost:3000';

  static String get baseUrl => _baseUrl;

  static void setBaseUrl(String ip, {int port = 3000}) {
    _baseUrl = 'http://$ip:$port';
  }

  static String get currentIp {
    final uri = Uri.parse(_baseUrl);
    return uri.host;
  }
}