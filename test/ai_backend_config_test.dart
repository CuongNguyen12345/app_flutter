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
}
