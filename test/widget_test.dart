import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_controller/main.dart';

void main() {
  testWidgets('IoT Plant Dashboard smoke test', (WidgetTester tester) async {
    // Build app
    await tester.pumpWidget(SmartFarmApp());

    // 1️⃣ Kiểm tra appBar
    expect(find.text('🌿 Smart Farm'), findsOneWidget);

    // 2️⃣ Kiểm tra thông tin trạng thái MQTT
    expect(find.textContaining('Connecting'), findsOneWidget);

    // 3️⃣ Kiểm tra các info cards có tồn tại
    expect(find.textContaining('🌡 Nhiệt độ'), findsOneWidget);
    expect(find.textContaining('💧 Độ ẩm không khí'), findsOneWidget);
    expect(find.textContaining('🌱 Độ ẩm đất'), findsOneWidget);
    expect(find.textContaining('🌾 Trạng thái đất'), findsOneWidget);
    expect(find.textContaining('💦 Bơm'), findsOneWidget);
    expect(find.textContaining('⚙️ Chế độ'), findsOneWidget);

    // 4️⃣ Kiểm tra các nút điều khiển bơm
    expect(find.text('BẬT BƠM'), findsOneWidget);
    expect(find.text('TẮT BƠM'), findsOneWidget);
    expect(find.text('TỰ ĐỘNG'), findsOneWidget);

    // 5️⃣ Kiểm tra log panel
    expect(find.textContaining('→'), findsNothing); // Log rỗng lúc khởi động

    // 6️⃣ Nhấn nút "BẬT BƠM" và "TẮT BƠM"
    await tester.tap(find.text('BẬT BƠM'));
    await tester.pump();
    await tester.tap(find.text('TẮT BƠM'));
    await tester.pump();

    // Không có lỗi crash
  });
}
