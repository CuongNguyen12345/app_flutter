import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:iot_controller/ai_backend_config.dart';

void main() => runApp(const SmartFarmApp());

// ─── THEME COLORS ───────────────────────────────────────────────────────────
const kBgDark = Color(0xFF071A0D);
const kBgMid = Color(0xFF0D4A1E);
const kGreen1 = Color(0xFF2EB85C);
const kGreen2 = Color(0xFF6DE69A);
const kGlassBg = Color(0x1AFFFFFF);
const kGlassBdr = Color(0x38FFFFFF);
const kTextPrim = Color(0xFFE8F5E9);
const kTextSec = Color(0xB3E8F5E9);
const kTotalPlantPositions = 8;
final kAiPredictUrl = resolveAiPredictUrl(
  configuredUrl: const String.fromEnvironment('AI_PREDICT_URL'),
  pageProtocol: html.window.location.protocol,
  pageHostname: html.window.location.hostname ?? 'localhost',
);
const kDefaultPlantDisease =
    'có dấu hiệu bất thường, nghi ngờ nấm lá, sâu bệnh hoặc thiếu dinh dưỡng';
const kDefaultPlantSolution =
    'Kiểm tra lá, thân và độ ẩm tại vị trí đó; cách ly cây nếu cần, cắt bỏ phần hư, bổ sung dinh dưỡng và phun thuốc sinh học phù hợp.';

// ─── APP ROOT ────────────────────────────────────────────────────────────────
class SmartFarmApp extends StatelessWidget {
  const SmartFarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '🌿 Smart Farm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
            seedColor: kGreen1, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

// ─── MAIN SHELL (bottom nav + pages) ─────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // Shared state
  bool mqttConnected = false;
  bool espConnected = false;
  Timer? espTimer;
  List<int> sickPlants = [];
  double temp = 0, hum = 0;
  int soil = 0;
  String soilStatus = '--';
  String pump = 'OFF';
  String mode = 'AUTO';
  String plantDisease = kDefaultPlantDisease;
  String plantSolution = kDefaultPlantSolution;
  String? _lastPlantAlertSignature;
  List<String> logs = [];

  @override
  void initState() {
    super.initState();
    _initMqtt();
  }

  void _log(String msg) {
    setState(() {
      logs.insert(0, '${DateTime.now().toString().substring(11, 19)} → $msg');
      if (logs.length > 80) logs.removeLast();
    });
  }

  void _initMqtt() {
    final script = html.ScriptElement()
      ..src = 'https://unpkg.com/mqtt/dist/mqtt.min.js';
    script.onLoad.listen((_) => _connectMqtt());
    html.document.head!.append(script);
  }

  void _connectMqtt() {
    const broker = 'wss://broker.hivemq.com:8884/mqtt';
    const subTopic = 'iot/plant/data';
    const pubTopic = 'iot/plant/control';

    js.context.callMethod('eval', [
      '''
      window.sfMqtt = mqtt.connect('$broker', {
        clientId: 'app_' + Math.random().toString(16).substr(2,8)
      });
      window.sfMqtt.on('connect', function() {
        window.dispatchEvent(new CustomEvent('sf_connected'));
        window.sfMqtt.subscribe('$subTopic');
      });
      window.sfMqtt.on('close', function() {
        window.dispatchEvent(new CustomEvent('sf_disconnected'));
      });
      window.sfMqtt.on('offline', function() {
        window.dispatchEvent(new CustomEvent('sf_disconnected'));
      });
      window.sfMqtt.on('message', function(topic, message) {
        window.dispatchEvent(new CustomEvent('sf_message', {
          detail: { topic: topic, payload: message.toString() }
        }));
      });
      window.sfSend = function(cmd) {
        try {
          window.sfMqtt.publish('$pubTopic', cmd);
        } catch(e){ console.error(e); }
      };
    '''
    ]);

    html.window.addEventListener('sf_connected', (_) {
      if (mounted) {
        setState(() => mqttConnected = true);
      }
      _log('✅ Kết nối broker thành công');
    });

    html.window.addEventListener('sf_disconnected', (_) {
      if (mounted && mqttConnected) {
        setState(() => mqttConnected = false);
        _log('❌ Mất kết nối broker');
      }
    });

    html.window.addEventListener('sf_message', (event) {
      final detail = (event as html.CustomEvent).detail;
      _handleMessage(detail['topic'] as String, detail['payload'] as String);
    });
  }

  List<int> _readSickPlants(Map<String, dynamic> data) {
    final raw = data['sick_plants'] ??
        data['sickPlants'] ??
        data['sick_plant'] ??
        data['sickPlant'] ??
        data['sick_position'] ??
        data['sickPosition'] ??
        data['plant_position'] ??
        data['plantPosition'] ??
        data['warning_position'] ??
        data['warningPosition'] ??
        data['plant_status'] ??
        data['plantStatus'] ??
        data['plants'] ??
        data['position'];
    return _normalizePlantPositions(raw);
  }

  List<int> _normalizePlantPositions(dynamic raw) {
    final positions = <int>{};

    void addPosition(dynamic value) {
      if (value == null) return;
      if (value is Map) {
        addPosition(value['position'] ??
            value['id'] ??
            value['plant'] ??
            value['plant_position']);
        return;
      }
      final found =
          value is num ? value.toInt() : int.tryParse(value.toString());
      if (found != null && found >= 1 && found <= kTotalPlantPositions) {
        positions.add(found);
      }
    }

    if (raw is List) {
      for (final value in raw) {
        addPosition(value);
      }
    } else if (raw is Map) {
      raw.forEach((key, value) {
        final valueText = value.toString().toLowerCase();
        final isUnhealthy = value == true ||
            valueText.contains('sick') ||
            valueText.contains('bad') ||
            valueText.contains('benh') ||
            valueText.contains('bệnh') ||
            valueText.contains('hu') ||
            valueText.contains('hư') ||
            valueText.contains('abnormal') ||
            valueText.contains('bất thường') ||
            valueText.contains('warning');
        if (isUnhealthy) addPosition(key);
      });
    } else {
      addPosition(raw);
    }

    final result = positions.toList()..sort();
    return result;
  }

  String _readPlantDisease(Map<String, dynamic> data) {
    return (data['plant_disease'] ??
            data['plantDisease'] ??
            data['disease'] ??
            data['suspected_disease'] ??
            data['suspectedDisease'] ??
            data['warning_reason'] ??
            data['warningReason'] ??
            kDefaultPlantDisease)
        .toString();
  }

  String _readPlantSolution(Map<String, dynamic> data) {
    return (data['plant_solution'] ??
            data['plantSolution'] ??
            data['solution'] ??
            data['recommendation'] ??
            data['treatment'] ??
            kDefaultPlantSolution)
        .toString();
  }

  void _notifyPlantAlert(
    List<int> plants,
    String disease,
    String solution,
  ) {
    if (plants.isEmpty) {
      _lastPlantAlertSignature = null;
      return;
    }

    final signature = '${plants.join(',')}|$disease|$solution';
    if (_lastPlantAlertSignature == signature) return;
    _lastPlantAlertSignature = signature;

    final plantText = plants.join(', ');
    final body =
        'Vườn cây đang không tốt. Cây ở vị trí số $plantText đang có dấu hiệu bất thường, nghi ngờ $disease. Hướng xử lý: $solution';
    _log('Cảnh báo: $body');

    final titleJson = jsonEncode('Cảnh báo vườn cây');
    final bodyJson = jsonEncode(body);
    js.context.callMethod('eval', [
      '''
      (function() {
        if (!('Notification' in window)) return;
        const show = function() {
          new Notification($titleJson, { body: $bodyJson });
        };
        if (Notification.permission === 'granted') {
          show();
        } else if (Notification.permission !== 'denied') {
          Notification.requestPermission().then(function(permission) {
            if (permission === 'granted') show();
          });
        }
      })();
      '''
    ]);
  }

  void _handleMessage(String topic, String payload) async {
    _log('📩 $payload');
    try {
      final d = jsonDecode(payload);
      final data = Map<String, dynamic>.from(d as Map);
      final nextSickPlants = _readSickPlants(data);
      final nextPlantDisease = _readPlantDisease(data);
      final nextPlantSolution = _readPlantSolution(data);
      if (mounted) {
        setState(() {
          espConnected = true;
          temp = double.tryParse(data['temp']?.toString() ?? '0') ?? 0;
          hum = double.tryParse(data['hum']?.toString() ?? '0') ?? 0;
          soil = int.tryParse(
                  (data['soil_percent'] ?? data['soil'] ?? 0).toString()) ??
              0;
          soilStatus = data['status'] ?? '--';
          sickPlants = nextSickPlants;
          plantDisease = nextPlantDisease;
          plantSolution = nextPlantSolution;
          if (data['pump'] != null) {
            pump = data['pump'].toString().toUpperCase();
          }
          if (data['mode'] != null) {
            mode = data['mode'].toString().toUpperCase();
          }
        });
        _notifyPlantAlert(nextSickPlants, nextPlantDisease, nextPlantSolution);

        espTimer?.cancel();
        espTimer = Timer(const Duration(seconds: 15), () {
          if (mounted) setState(() => espConnected = false);
        });
      }

      // Save to backend (optional)
      await http
          .post(
            Uri.parse('http://localhost:8080/api/save'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'temp': temp,
              'hum': hum,
              'soil': soil,
              'status': soilStatus,
              'pump': pump
            }),
          )
          .catchError((_) {});
    } catch (e) {
      _log('⚠️ Lỗi parse: $e');
    }
  }

  void _sendCommand(String cmd) {
    if (mqttConnected) js.context.callMethod('sfSend', [cmd]);
    _log('📤 Lệnh: $cmd');
    setState(() {
      mode = (cmd == 'AUTO') ? 'AUTO' : 'MANUAL';
      if (cmd != 'AUTO') pump = cmd;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        mqttConnected: mqttConnected,
        espConnected: espConnected,
        sickPlants: sickPlants,
        plantDisease: plantDisease,
        plantSolution: plantSolution,
        temp: temp,
        hum: hum,
        soil: soil,
        soilStatus: soilStatus,
        pump: pump,
        mode: mode,
        onCommand: _sendCommand,
      ),
      CameraPage(
        temp: temp,
        hum: hum,
        soil: soil,
        mqttConnected: mqttConnected,
      ),
    ];

    return Scaffold(
      backgroundColor: kBgDark,
      body: Stack(
        children: [
          // Gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.6, -0.8),
                radius: 1.4,
                colors: [Color(0xFF1A7A3A), Color(0xFF071A0D)],
              ),
            ),
          ),
          // Page content
          pages[_currentIndex],
          // Bottom nav
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomNav(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── BOTTOM NAV ───────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xCC071A0D),
          border: Border(top: BorderSide(color: kGlassBdr, width: 1)),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 20)
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
                icon: '🏠',
                label: 'Trang chủ',
                active: currentIndex == 0,
                onTap: () => onTap(0)),
            _NavItem(
                icon: '📷',
                label: 'Camera',
                active: currentIndex == 1,
                onTap: () => onTap(1)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String icon, label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: active ? kGreen1.withOpacity(.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: active ? Border.all(color: kGreen2.withOpacity(.3)) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? kGreen2 : kTextSec,
                )),
          ],
        ),
      ),
    );
  }
}

// ─── GLASS CARD ───────────────────────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20.0,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kGlassBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor ?? kGlassBdr, width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))
        ],
      ),
      child: child,
    );
  }
}

// ─── DASHBOARD PAGE ───────────────────────────────────────────────────────────
class DashboardPage extends StatelessWidget {
  final bool mqttConnected;
  final bool espConnected;
  final List<int> sickPlants;
  final String plantDisease;
  final String plantSolution;
  final double temp, hum;
  final int soil;
  final String soilStatus, pump, mode;
  final ValueChanged<String> onCommand;

  const DashboardPage({
    super.key,
    required this.mqttConnected,
    required this.espConnected,
    required this.sickPlants,
    required this.plantDisease,
    required this.plantSolution,
    required this.temp,
    required this.hum,
    required this.soil,
    required this.soilStatus,
    required this.pump,
    required this.mode,
    required this.onCommand,
  });

  @override
  Widget build(BuildContext context) {
    final pumpOn = pump == 'ON';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER
          Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kGreen1, kBgMid]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: kGreen1.withOpacity(.4), blurRadius: 16)
                ],
              ),
              child: const Center(
                  child: Text('🌿', style: TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 14),
            const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Smart Farm',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: kTextPrim)),
                  Text('Nông nghiệp thông minh',
                      style: TextStyle(fontSize: 12, color: kTextSec)),
                ]),
            const Spacer(),
            // Connection badge
            Builder(builder: (context) {
              String statusText;
              Color badgeBg;
              Color statusColor;

              if (!mqttConnected && !espConnected) {
                statusText = 'Offline';
                badgeBg = Colors.red.withOpacity(.18);
                statusColor = Colors.redAccent;
              } else if (!mqttConnected) {
                statusText = 'MQTT\nDisconnect';
                badgeBg = Colors.orange.withOpacity(.18);
                statusColor = Colors.orangeAccent;
              } else if (!espConnected) {
                statusText = 'ESP32\nDisconnect';
                badgeBg = Colors.orange.withOpacity(.18);
                statusColor = Colors.orangeAccent;
              } else {
                statusText = 'Online';
                badgeBg = kGreen1.withOpacity(.22);
                statusColor = kGreen2;
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: statusColor.withOpacity(.35)),
                ),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                            color: statusColor.withOpacity(.6), blurRadius: 6)
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ]),
              );
            }),
          ]),
          const SizedBox(height: 28),

          // ── METRICS GRID
          Row(children: [
            Expanded(
                child: _MetricCard(
                    icon: '🌱',
                    label: 'Độ ẩm đất',
                    value: '$soil',
                    unit: '%',
                    accent: kGreen1)),
            const SizedBox(width: 14),
            Expanded(
                child: _MetricCard(
                    icon: '🌡️',
                    label: 'Nhiệt độ',
                    value: temp.toStringAsFixed(1),
                    unit: '°C',
                    accent: const Color(0xFFF97316))),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _MetricCard(
                    icon: '💧',
                    label: 'Độ ẩm KK',
                    value: hum.toStringAsFixed(0),
                    unit: '%',
                    accent: const Color(0xFF38BDF8))),
            const SizedBox(width: 14),
            Expanded(
                child: _MetricCard(
                    icon: '🌾',
                    label: 'Đất',
                    value: soilStatus,
                    unit: '',
                    accent: const Color(0xFFA37C52))),
          ]),
          const SizedBox(height: 20),

          // ── PLANT NOTIFICATION
          GlassCard(
            padding: const EdgeInsets.all(18),
            borderColor: sickPlants.isEmpty
                ? kGreen1.withOpacity(.5)
                : Colors.redAccent.withOpacity(.5),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: sickPlants.isEmpty
                      ? kGreen1.withOpacity(.3)
                      : Colors.red.withOpacity(.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                    child: Text(sickPlants.isEmpty ? '🌿' : '⚠️',
                        style: const TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tình trạng vườn cây',
                          style: TextStyle(fontSize: 12, color: kTextSec)),
                      const SizedBox(height: 4),
                      Text(
                        sickPlants.isEmpty
                            ? 'Vườn cây hiện đang tốt'
                            : 'Cây ở vị trí số ${sickPlants.join(', ')} bị bệnh/hư',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color:
                              sickPlants.isEmpty ? kTextPrim : Colors.redAccent,
                        ),
                      ),
                    ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          PlantAlertCard(
            sickPlants: sickPlants,
            disease: plantDisease,
            solution: plantSolution,
          ),
          const SizedBox(height: 20),

          // ── PUMP STATUS
          GlassCard(
            padding: const EdgeInsets.all(18),
            borderColor: pumpOn ? kGreen1.withOpacity(.5) : kGlassBdr,
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: pumpOn
                      ? kGreen1.withOpacity(.3)
                      : Colors.red.withOpacity(.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                    child: Text(pumpOn ? '💧' : '🚫',
                        style: const TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Máy bơm',
                    style: TextStyle(fontSize: 12, color: kTextSec)),
                Text(
                  pumpOn ? 'ĐANG CHẠY' : 'TẮT',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: pumpOn ? kGreen2 : Colors.redAccent,
                  ),
                ),
              ]),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: mode == 'AUTO'
                      ? const Color(0x3338BDF8)
                      : const Color(0x33FBBF24),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: mode == 'AUTO'
                          ? const Color(0x557DD3FC)
                          : const Color(0x55FCD34D)),
                ),
                child: Text(mode,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: mode == 'AUTO'
                            ? const Color(0xFF7DD3FC)
                            : const Color(0xFFFCD34D))),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // ── PUMP BUTTONS
          Row(children: [
            Expanded(
                child: _PumpButton(
              icon: '💧',
              label: 'BẬT BƠM\nNGAY',
              isOn: true,
              enabled: mqttConnected,
              onTap: () => onCommand('ON'),
            )),
            const SizedBox(width: 14),
            Expanded(
                child: _PumpButton(
              icon: '🚫',
              label: 'TẮT BƠM\nNGAY',
              isOn: false,
              enabled: mqttConnected,
              onTap: () => onCommand('OFF'),
            )),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _PumpButton(
              icon: '⚙️',
              label: 'CHẾ ĐỘ TỰ ĐỘNG',
              isOn: null,
              enabled: mqttConnected,
              onTap: () => onCommand('AUTO'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── METRIC CARD ─────────────────────────────────────────────────────────────
class PlantAlertCard extends StatelessWidget {
  final List<int> sickPlants;
  final String disease;
  final String solution;

  const PlantAlertCard({
    super.key,
    required this.sickPlants,
    required this.disease,
    required this.solution,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlert = sickPlants.isNotEmpty;
    final positionText = sickPlants.join(', ');

    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderColor:
          hasAlert ? Colors.redAccent.withOpacity(.5) : kGreen1.withOpacity(.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: hasAlert
                  ? Colors.red.withOpacity(.2)
                  : kGreen1.withOpacity(.3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(hasAlert ? '⚠️' : '🌿',
                  style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Sơ đồ vị trí cây',
                  style: TextStyle(fontSize: 12, color: kTextSec)),
              const SizedBox(height: 4),
              Text(
                hasAlert ? 'Vườn cây đang không tốt' : 'Vườn cây hiện đang tốt',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: hasAlert ? Colors.redAccent : kTextPrim,
                ),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Column(
          children: [
            for (final row in const [
              [1, 2, 3, 4],
              [5, 6, 7, 8],
            ]) ...[
              Row(
                children: [
                  for (final position in row) ...[
                    Expanded(
                      child: _PlantPositionTile(
                        position: position,
                        isSick: sickPlants.contains(position),
                      ),
                    ),
                    if (position != row.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              if (row.first == 1) const SizedBox(height: 8),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Text(
          hasAlert
              ? 'Vườn cây đang không tốt. Cây ở vị trí số $positionText đang có dấu hiệu bất thường, nghi ngờ $disease.'
              : 'Vườn cây đang tốt. Chưa phát hiện cây bất thường trong 8 vị trí đã định nghĩa.',
          style: TextStyle(
            color: hasAlert ? const Color(0xFFFCA5A5) : kTextPrim,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kGlassBdr),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hướng giải quyết',
                style: TextStyle(
                    fontSize: 12,
                    color: kTextSec,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              hasAlert
                  ? solution
                  : 'Tiếp tục theo dõi cảm biến, duy trì độ ẩm phù hợp và kiểm tra định kỳ từng vị trí cây.',
              style: const TextStyle(
                color: kTextPrim,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _PlantPositionTile extends StatelessWidget {
  final int position;
  final bool isSick;

  const _PlantPositionTile({
    required this.position,
    required this.isSick,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSick ? Colors.redAccent : kGreen2;
    return AspectRatio(
      aspectRatio: 1.35,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withOpacity(isSick ? .22 : .14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(isSick ? .7 : .35)),
        ),
        child: Text(
          '$position',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String icon, label, value, unit;
  final Color accent;
  const _MetricCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.unit,
      required this.accent});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(icon, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: kTextSec, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        RichText(
            text: TextSpan(
          text: value,
          style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: accent,
              shadows: [Shadow(color: accent.withOpacity(.4), blurRadius: 12)]),
          children: [
            TextSpan(
                text: ' $unit',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: kTextSec)),
          ],
        )),
      ]),
    );
  }
}

// ─── PUMP BUTTON ─────────────────────────────────────────────────────────────
class _PumpButton extends StatelessWidget {
  final String icon, label;
  final bool? isOn;
  final bool enabled;
  final VoidCallback onTap;
  const _PumpButton(
      {required this.icon,
      required this.label,
      required this.isOn,
      required this.enabled,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color bg1, bg2, textColor;
    if (isOn == null) {
      bg1 = const Color(0xFF1E40AF);
      bg2 = const Color(0xFF1D4ED8);
      textColor = Colors.white;
    } else if (isOn == true) {
      bg1 = const Color(0xFF16A34A);
      bg2 = const Color(0xFF15803D);
      textColor = Colors.white;
    } else {
      bg1 = kGlassBg;
      bg2 = kGlassBg;
      textColor = Colors.redAccent;
    }

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: enabled ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [bg1, bg2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            border: isOn == false
                ? Border.all(color: Colors.redAccent.withOpacity(.35))
                : null,
            boxShadow: isOn == true
                ? [
                    BoxShadow(
                        color: kGreen1.withOpacity(.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6))
                  ]
                : isOn == null
                    ? [
                        const BoxShadow(
                            color: Color(0x551D4ED8),
                            blurRadius: 16,
                            offset: Offset(0, 6))
                      ]
                    : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Flexible(
                  child: Text(label.replaceAll('\n', ' '),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800))),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── BLINK DOT ───────────────────────────────────────────────────────────────
class _BlinkDot extends StatefulWidget {
  const _BlinkDot();
  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _ctrl,
        child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(4))),
      );
}

// ─── CAMERA PAGE ─────────────────────────────────────────────────────────────
class CameraPage extends StatefulWidget {
  final double temp, hum;
  final int soil;
  final bool mqttConnected;
  const CameraPage(
      {super.key,
      required this.temp,
      required this.hum,
      required this.soil,
      required this.mqttConnected});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final TextEditingController _urlCtrl =
      TextEditingController(text: 'http://192.168.x.x:81/stream');
  String? _activeUrl;

  bool _useWebcam = false;
  bool _isLoadingWebcam = false;
  String _webcamViewId = 'webcam-view-id';
  html.VideoElement? _webcamVideoElement;
  List<html.MediaDeviceInfo> _cameraDevices = [];
  String? _selectedCameraDeviceId;
  String? _cameraError;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _aiResult;
  String? _aiError;

  Future<void> _loadCameraDevices() async {
    try {
      final devices =
          await html.window.navigator.mediaDevices?.enumerateDevices();
      final cameraDevices = (devices ?? [])
          .whereType<html.MediaDeviceInfo>()
          .where((device) => device.kind == 'videoinput')
          .toList();
      if (!mounted) return;

      final hasSelectedDevice = cameraDevices.any(
        (device) => device.deviceId == _selectedCameraDeviceId,
      );

      setState(() {
        _cameraDevices = cameraDevices;
        if (!hasSelectedDevice) {
          _selectedCameraDeviceId =
              cameraDevices.isNotEmpty ? cameraDevices.first.deviceId : null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Khong the lay danh sach camera: $e';
      });
    }
  }

  Future<void> _startWebcam({String? deviceId}) async {
    _stopWebcam();
    if (!mounted) return;

    setState(() {
      _isLoadingWebcam = true;
      _cameraError = null;
      _aiError = null;
      _aiResult = null;
    });

    try {
      final mediaStream =
          await html.window.navigator.mediaDevices?.getUserMedia({
        'video': deviceId != null && deviceId.isNotEmpty
            ? {
                'deviceId': {'exact': deviceId}
              }
            : true,
        'audio': false,
      });
      if (mediaStream != null) {
        _webcamViewId =
            'webcam-view-id-${DateTime.now().millisecondsSinceEpoch}';

        _webcamVideoElement = html.VideoElement()
          ..autoplay = true
          ..muted = true
          ..setAttribute('playsinline', 'true')
          ..style.border = 'none'
          ..style.height = '100%'
          ..style.width = '100%'
          ..style.objectFit = 'cover'
          ..srcObject = mediaStream;

        ui_web.platformViewRegistry.registerViewFactory(_webcamViewId,
            (int viewId) {
          return _webcamVideoElement!;
        });

        await _loadCameraDevices();
        if (!mounted) return;

        setState(() {
          _useWebcam = true;
          _activeUrl = null;
          _selectedCameraDeviceId ??= deviceId;
          _isLoadingWebcam = false;
        });

        await _webcamVideoElement!.play();
      } else if (mounted) {
        setState(() {
          _isLoadingWebcam = false;
          _cameraError = 'Khong mo duoc camera da chon.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingWebcam = false;
        _cameraError = 'Khong the bat camera: $e';
      });
      print("Cannot start webcam: $e");
    }
  }

  void _stopWebcam() {
    final stream = _webcamVideoElement?.srcObject as html.MediaStream?;
    if (stream != null) {
      for (var track in stream.getTracks()) {
        track.stop();
      }
    }
    _webcamVideoElement?.srcObject = null;
  }

  @override
  void initState() {
    super.initState();
    _startWebcam();
  }

  @override
  void dispose() {
    _stopWebcam();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectWebcam(String? deviceId) async {
    if (deviceId == null || deviceId == _selectedCameraDeviceId) return;
    setState(() {
      _selectedCameraDeviceId = deviceId;
    });
    await _startWebcam(deviceId: deviceId);
  }

  void _useMjpegStream() {
    final nextUrl = _urlCtrl.text.trim();
    _stopWebcam();
    if (!mounted) return;
    setState(() {
      _useWebcam = false;
      _activeUrl = nextUrl.isEmpty ? null : nextUrl;
      _cameraError = null;
      _aiError = null;
      _aiResult = null;
    });
  }

  Future<void> _analyzeCurrentFrame() async {
    final video = _webcamVideoElement;
    final width = video?.videoWidth ?? 0;
    final height = video?.videoHeight ?? 0;
    if (!_useWebcam || video == null || width <= 0 || height <= 0) {
      setState(() {
        _aiError = 'Hay chon camera laptop/webcam truoc khi phan tich AI.';
      });
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _aiError = null;
    });

    try {
      final canvas = html.CanvasElement(width: width, height: height);
      canvas.context2D.drawImageScaled(video, 0, 0, width, height);
      final dataUrl = canvas.toDataUrl('image/jpeg', 0.9);
      final bytes = base64Decode(dataUrl.split(',').last);
      final request = http.MultipartRequest('POST', Uri.parse(kAiPredictUrl))
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'webcam-frame.jpg',
        ));

      final response =
          await request.send().timeout(const Duration(seconds: 45));
      final body = await response.stream.bytesToString();
      if (response.statusCode != 200) {
        throw Exception('AI backend ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(body);
      if (!mounted) return;
      setState(() {
        _aiResult = Map<String, dynamic>.from(decoded as Map);
        _isAnalyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _aiError = formatAiBackendConnectionError(e, kAiPredictUrl);
      });
    }
  }

  String _cameraDeviceLabel(html.MediaDeviceInfo device, int index) {
    final label = device.label?.trim() ?? '';
    if (label.isNotEmpty) return label;
    return index == 0 ? 'Camera laptop' : 'Webcam roi ${index + 1}';
  }

  html.MediaDeviceInfo? get _laptopCamera {
    if (_cameraDevices.isEmpty) return null;
    return _cameraDevices.first;
  }

  html.MediaDeviceInfo? get _externalWebcam {
    if (_cameraDevices.length < 2) return null;
    return _cameraDevices[1];
  }

  bool _isDeviceSelected(html.MediaDeviceInfo? device) {
    if (!_useWebcam || device == null) return false;
    return _selectedCameraDeviceId == device.deviceId;
  }

  String get _currentSourceLabel {
    if (_useWebcam) {
      final activeIndex = _cameraDevices.indexWhere(
        (device) => device.deviceId == _selectedCameraDeviceId,
      );
      if (activeIndex >= 0) {
        return _cameraDeviceLabel(_cameraDevices[activeIndex], activeIndex);
      }
      return 'Camera may tinh';
    }
    if (_activeUrl != null && _activeUrl!.isNotEmpty) {
      return 'MJPEG URL';
    }
    return 'Chua chon';
  }

  List<dynamic> get _aiDetections {
    final raw = _aiResult?['detections'];
    return raw is List ? raw : const [];
  }

  Map<String, dynamic>? get _aiSummary {
    final raw = _aiResult?['summary'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kGreen1, kBgMid]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: kGreen1.withOpacity(.4), blurRadius: 16)
                ],
              ),
              child: const Center(
                  child: Text('📷', style: TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Camera',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: kTextPrim)),
                  Text('Xem trực tiếp sân vườn',
                      style: TextStyle(fontSize: 11, color: kTextSec)),
                ]),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.75),
                  borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [
                _BlinkDot(),
                SizedBox(width: 4),
                Text('LIVE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(12),
            borderRadius: 14,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Nguon camera',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kTextSec)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _laptopCamera == null
                        ? null
                        : () => _selectWebcam(_laptopCamera!.deviceId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: _isDeviceSelected(_laptopCamera)
                            ? const LinearGradient(colors: [kGreen1, kBgMid])
                            : null,
                        color: _isDeviceSelected(_laptopCamera)
                            ? null
                            : Colors.white
                                .withOpacity(_laptopCamera == null ? .02 : .05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x38FFFFFF)),
                      ),
                      child: Text('Cam laptop',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: _laptopCamera == null
                                  ? kTextSec.withOpacity(.5)
                                  : kTextPrim,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: _externalWebcam == null
                        ? null
                        : () => _selectWebcam(_externalWebcam!.deviceId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: _isDeviceSelected(_externalWebcam)
                            ? const LinearGradient(colors: [kGreen1, kBgMid])
                            : null,
                        color: _isDeviceSelected(_externalWebcam)
                            ? null
                            : Colors.white.withOpacity(
                                _externalWebcam == null ? .02 : .05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x38FFFFFF)),
                      ),
                      child: Text('Webcam',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: _externalWebcam == null
                                  ? kTextSec.withOpacity(.5)
                                  : kTextPrim,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              if (_cameraDevices.isNotEmpty)
                Text(
                  _cameraDevices.length > 1
                      ? 'Da tim thay ${_cameraDevices.length} camera tren may.'
                      : 'Chi tim thay camera laptop tren may.',
                  style: const TextStyle(fontSize: 11, color: kTextSec),
                )
              else
                const Text('Khong tim thay camera nao tren may.',
                    style: TextStyle(fontSize: 11, color: kTextSec)),
              if (_cameraError != null) ...[
                const SizedBox(height: 8),
                Text(_cameraError!,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFFCA5A5),
                        fontWeight: FontWeight.w500)),
              ],
            ]),
          ),
          const SizedBox(height: 12),

          // ── CAMERA FRAME
          GlassCard(
            padding: EdgeInsets.zero,
            borderRadius: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_isLoadingWebcam)
                      const Center(
                        child: CircularProgressIndicator(color: kGreen2),
                      )
                    else if (_useWebcam)
                      HtmlElementView(viewType: _webcamViewId)
                    else if (_activeUrl != null)
                      Image.network(_activeUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _NoCamera())
                    else
                      _NoCamera(),
                    if (_aiResult != null)
                      CustomPaint(
                        painter: _AiDetectionPainter(
                          detections: _aiDetections,
                          image: Map<String, dynamic>.from(
                              _aiResult?['image'] as Map? ?? const {}),
                        ),
                      ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: GestureDetector(
                        onTap: _isAnalyzing ? null : _analyzeCurrentFrame,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            gradient: _isAnalyzing
                                ? null
                                : const LinearGradient(
                                    colors: [kGreen1, kBgMid]),
                            color: _isAnalyzing
                                ? Colors.white.withOpacity(.08)
                                : null,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x66FFFFFF)),
                          ),
                          child: Text(
                              _isAnalyzing ? 'Dang xu ly' : 'Phan tich AI',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12)),
                        ),
                      ),
                    ),
                    if (_aiSummary != null || _aiError != null)
                      Positioned(
                        left: 10,
                        right: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xCC071A0D),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x38FFFFFF)),
                          ),
                          child: Text(
                            _aiError ??
                                '${_aiSummary?['disease_name_vi'] ?? _aiSummary?['message'] ?? 'Chua co ket qua'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _aiError != null
                                  ? const Color(0xFFFCA5A5)
                                  : (_aiSummary?['has_disease'] == true
                                      ? Colors.orangeAccent
                                      : kGreen2),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    if (_isAnalyzing)
                      Container(
                        color: Colors.black45,
                        child: const Center(
                          child: CircularProgressIndicator(color: kGreen2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── URL INPUT
          GlassCard(
            padding: const EdgeInsets.all(12),
            borderRadius: 14,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🔗 Địa chỉ camera (MJPEG)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kTextSec)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(color: kTextPrim, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'http://192.168.x.x:81/stream',
                      hintStyle: TextStyle(
                          color: kTextSec.withOpacity(.5), fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withOpacity(.06),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kGlassBdr),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kGlassBdr),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _useMjpegStream,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [kGreen1, kBgMid]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Kết nối',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 10),

          // ── INFO CARDS
          Row(children: [
            Expanded(
                child: GlassCard(
                    padding: const EdgeInsets.all(11),
                    borderRadius: 14,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('📡 Nguồn',
                              style: TextStyle(fontSize: 10, color: kTextSec)),
                          const SizedBox(height: 3),
                          Text(_currentSourceLabel,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: kGreen2)),
                        ]))),
            const SizedBox(width: 10),
            Expanded(
                child: GlassCard(
                    padding: const EdgeInsets.all(11),
                    borderRadius: 14,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🖥️ Độ phân giải',
                              style: TextStyle(fontSize: 10, color: kTextSec)),
                          const SizedBox(height: 3),
                          const Text('1920×1080',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: kTextPrim)),
                        ]))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: GlassCard(
                    padding: const EdgeInsets.all(11),
                    borderRadius: 14,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🌡️ Nhiệt độ',
                              style: TextStyle(fontSize: 10, color: kTextSec)),
                          const SizedBox(height: 3),
                          Text('${widget.temp.toStringAsFixed(1)}°C',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF97316))),
                        ]))),
            const SizedBox(width: 10),
            Expanded(
                child: GlassCard(
                    padding: const EdgeInsets.all(11),
                    borderRadius: 14,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🌱 Độ ẩm đất',
                              style: TextStyle(fontSize: 10, color: kTextSec)),
                          const SizedBox(height: 3),
                          Text('${widget.soil}%',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: kGreen2)),
                        ]))),
          ]),
        ],
      ),
    );
  }
}

// ─── NO CAMERA PLACEHOLDER ───────────────────────────────────────────────────
class _NoCamera extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child:
          const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('🎥', style: TextStyle(fontSize: 48)),
        SizedBox(height: 10),
        Text('Camera chưa kết nối',
            style: TextStyle(
                color: kTextSec, fontSize: 14, fontWeight: FontWeight.w600)),
        SizedBox(height: 4),
        Text('Nhập địa chỉ MJPEG phía dưới',
            style: TextStyle(color: kTextSec, fontSize: 12)),
      ]),
    );
  }
}

class _AiDetectionPainter extends CustomPainter {
  final List<dynamic> detections;
  final Map<String, dynamic> image;

  _AiDetectionPainter({required this.detections, required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    final imageWidth = (image['width'] as num?)?.toDouble() ?? 0;
    final imageHeight = (image['height'] as num?)?.toDouble() ?? 0;
    if (imageWidth <= 0 || imageHeight <= 0) return;

    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;
    final boxPaint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final fillPaint = Paint()
      ..color = Colors.black.withOpacity(.58)
      ..style = PaintingStyle.fill;

    for (final item in detections) {
      if (item is! Map) continue;
      final box = item['box'];
      if (box is! List || box.length < 4) continue;

      final left = ((box[0] as num).toDouble() * scaleX).clamp(0.0, size.width);
      final top = ((box[1] as num).toDouble() * scaleY).clamp(0.0, size.height);
      final right =
          ((box[2] as num).toDouble() * scaleX).clamp(0.0, size.width);
      final bottom =
          ((box[3] as num).toDouble() * scaleY).clamp(0.0, size.height);
      final rect = Rect.fromLTRB(left, top, right, bottom);
      canvas.drawRect(rect, boxPaint);

      final label =
          '${item['disease_name_vi'] ?? item['disease'] ?? 'leaf'} ${(100 * ((item['disease_confidence'] as num?)?.toDouble() ?? 0)).toStringAsFixed(0)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - left - 8);
      final labelRect = Rect.fromLTWH(
        left,
        (top - textPainter.height - 7).clamp(0.0, size.height),
        textPainter.width + 8,
        textPainter.height + 5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(5)),
        fillPaint,
      );
      textPainter.paint(canvas, Offset(labelRect.left + 4, labelRect.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _AiDetectionPainter oldDelegate) {
    return oldDelegate.detections != detections || oldDelegate.image != image;
  }
}
