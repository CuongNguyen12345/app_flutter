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

String resolveAiBackendBaseUrl(String predictUrl) {
  final trimmed = predictUrl.trim();
  if (trimmed.endsWith(aiPredictPath)) {
    return trimmed.substring(0, trimmed.length - aiPredictPath.length);
  }

  final uri = Uri.parse(trimmed);
  final segments = uri.pathSegments;
  if (segments.isEmpty) return trimmed;

  final baseSegments = segments.take(segments.length - 1).toList();
  return uri
      .replace(pathSegments: baseSegments, query: '', fragment: '')
      .toString();
}

bool isBackendWebcamUnavailableError(Object? error) {
  final message = error?.toString().toLowerCase() ?? '';
  return message.contains('khong mo duoc webcam') ||
      message.contains('cannot open webcam') ||
      message.contains('camera index out of range');
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
