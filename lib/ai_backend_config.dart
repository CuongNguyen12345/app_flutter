const aiBackendPort = 8000;
const aiPredictPath = '/predict';

String resolveAiPredictUrl({
  required String configuredUrl,
  required String pageProtocol,
  required String pageHostname,
}) {
  final explicitUrl = configuredUrl.trim();
  if (explicitUrl.isNotEmpty) return explicitUrl;

  final hostname =
      pageHostname.trim().isEmpty ? 'localhost' : pageHostname.trim();
  final normalizedHost = hostname.contains(':') && !hostname.startsWith('[')
      ? '[$hostname]'
      : hostname;

  return 'http://$normalizedHost:$aiBackendPort$aiPredictPath';
}

String formatAiBackendConnectionError(Object error, String predictUrl) {
  final message = error.toString();
  if (message.contains('Failed to fetch') ||
      message.contains('XMLHttpRequest') ||
      message.contains('Connection refused')) {
    return 'Khong ket noi duoc AI backend tai $predictUrl. '
        'Hay chay FastAPI port 8000 hoac truyen --dart-define=AI_PREDICT_URL=<url>/predict.';
  }

  return 'Khong phan tich duoc anh: $message';
}
