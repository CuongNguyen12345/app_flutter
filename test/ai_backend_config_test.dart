import 'package:flutter_test/flutter_test.dart';
import 'package:iot_controller/ai_backend_config.dart';

void main() {
  group('resolveAiPredictUrl', () {
    test('uses explicit dart-define URL when provided', () {
      expect(
        resolveAiPredictUrl(
          configuredUrl: 'http://10.0.0.8:9000/predict',
          pageProtocol: 'http:',
          pageHostname: '192.168.1.20',
        ),
        'http://10.0.0.8:9000/predict',
      );
    });

    test('defaults to the current page host on port 8000', () {
      expect(
        resolveAiPredictUrl(
          configuredUrl: '',
          pageProtocol: 'http:',
          pageHostname: '192.168.1.20',
        ),
        'http://192.168.1.20:8000/predict',
      );
    });

    test('keeps localhost for local Flutter web development', () {
      expect(
        resolveAiPredictUrl(
          configuredUrl: '',
          pageProtocol: 'http:',
          pageHostname: 'localhost',
        ),
        'http://localhost:8000/predict',
      );
    });
  });

  group('resolveAiBackendBaseUrl', () {
    test('strips the predict path from the default AI URL', () {
      expect(
        resolveAiBackendBaseUrl('http://localhost:8000/predict'),
        'http://localhost:8000',
      );
    });

    test('trims the last URL segment for a nonstandard explicit predict URL', () {
      expect(
        resolveAiBackendBaseUrl('http://10.0.0.8:9000/api/predict-leaf'),
        'http://10.0.0.8:9000/api',
      );
    });
  });

  group('isBackendWebcamUnavailableError', () {
    test('detects backend webcam open failures', () {
      expect(
        isBackendWebcamUnavailableError('Khong mo duoc webcam index 0.'),
        isTrue,
      );
    });

    test('ignores unrelated backend errors', () {
      expect(
        isBackendWebcamUnavailableError('Khong doc duoc frame tu webcam.'),
        isFalse,
      );
    });
  });
}
