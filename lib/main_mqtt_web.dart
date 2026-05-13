import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Lab Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home: const IoTDashboardPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class IoTDashboardPage extends StatefulWidget {
  const IoTDashboardPage({super.key});
  @override
  State<IoTDashboardPage> createState() => _IoTDashboardPageState();
}

class _IoTDashboardPageState extends State<IoTDashboardPage> {
  bool brokerConnected = false;
  bool deviceOnline = false;

  String temperature = '--°C';
  String humidity = '--%';
  String lux = '-- lux';
  String fanState = 'off';
  String lightState = 'off';
  String rssi = '-- dBm';
  String firmware = '--';
  String lastUpdate = '--';

  @override
  void initState() {
    super.initState();
    _initMQTT();
  }

  void _initMQTT() {
    html.document.head!.append(html.ScriptElement()
      ..src = 'https://unpkg.com/mqtt/dist/mqtt.min.js'
      ..onLoad.listen((_) => _connectMQTT()));
  }

  void _connectMQTT() {
    const broker = 'wss://broker.emqx.io:8084/mqtt';
    const topicNs = 'lab/room1';

    js.context.callMethod('eval', [
      '''
      const topics = {
        sensor: "$topicNs/sensor/state",
        device: "$topicNs/device/state",
        online: "$topicNs/sys/online",
        command: "$topicNs/device/cmd"
      };

      window.flutterMqttClient = mqtt.connect("$broker", {
        clientId: "flutter_web_" + Math.random().toString(16).substr(2,8),
        keepalive: 30,
        reconnectPeriod: 5000
      });

      window.flutterMqttClient.on('connect', function() {
        console.log("MQTT connected");
        window.dispatchEvent(new CustomEvent('mqtt_connected'));
        window.flutterMqttClient.subscribe([
          topics.sensor, topics.device, topics.online
        ]);
      });

      window.flutterMqttClient.on('message', function(topic, message) {
        const msg = message.toString();
        window.dispatchEvent(new CustomEvent('mqtt_message', { detail: { topic, msg } }));
      });

      window.flutterMqttClient.on('close', () => window.dispatchEvent(new CustomEvent('mqtt_disconnected')));
      window.flutterMqttClient.on('error', () => window.dispatchEvent(new CustomEvent('mqtt_disconnected')));

      window.sendMqttCommand = function(cmd) {
        const payload = JSON.stringify(cmd);
        window.flutterMqttClient.publish(topics.command, payload);
        console.log("Sent JSON command:", payload);
      };
      '''
    ]);

    html.window.addEventListener('mqtt_connected', (event) {
      if (mounted) setState(() => brokerConnected = true);
    });

    html.window.addEventListener('mqtt_disconnected', (event) {
      if (mounted) {
        setState(() {
          brokerConnected = false;
          deviceOnline = false;
        });
      }
    });

    html.window.addEventListener('mqtt_message', (event) {
      final detail = (event as html.CustomEvent).detail;
      final topic = detail['topic'] as String;
      final msg = detail['msg'] as String;
      _handleMessage(topic, msg);
    });
  }

  void _handleMessage(String topic, String msg) {
    try {
      if (topic.endsWith('/sensor/state')) {
        final data = jsonDecode(msg);
        setState(() {
          if (data['temp_c'] != null)
            temperature = '${data['temp_c'].toStringAsFixed(1)}°C';
          if (data['hum_pct'] != null)
            humidity = '${data['hum_pct'].toStringAsFixed(1)}%';
          if (data['lux'] != null) lux = '${data['lux']} lux';
          lastUpdate = TimeOfDay.now().format(context);
        });
      } else if (topic.endsWith('/device/state')) {
        final data = jsonDecode(msg);
        setState(() {
          if (data['fan'] != null) fanState = data['fan'];
          if (data['led'] != null) lightState = data['led']; // LED/light
          if (data['rssi'] != null) rssi = '${data['rssi']} dBm';
          if (data['fw'] != null) firmware = data['fw'];
          lastUpdate = TimeOfDay.now().format(context);
        });
      } else if (topic.endsWith('/sys/online')) {
        final data = jsonDecode(msg);
        setState(() {
          deviceOnline = data['online'] == true;
        });
      }
    } catch (e) {
      print('MQTT parse error: $e');
    }
  }

  void _sendCommand(String deviceKey) {
    if (!brokerConnected || !deviceOnline) return;

    if (deviceKey != 'led') return; // chỉ LED/light

    final newState = lightState == 'on' ? 'off' : 'on';
    final cmd = {'led': newState};

    js.context.callMethod('sendMqttCommand', [cmd]);

    setState(() {
      lightState = newState;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sent command: led → $newState'),
        backgroundColor: Colors.indigo,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏠 IoT Lab Monitor'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _statusTile('Broker', brokerConnected)),
                const SizedBox(width: 12),
                Expanded(child: _statusTile('Device', deviceOnline)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: [
                  _infoCard('🌡️ Sensor Data', [
                    _infoRow('Temperature', temperature),
                    _infoRow('Humidity', humidity),
                    _infoRow('Light Level', lux),
                  ]),
                  const SizedBox(height: 20),
                  _infoCard('🎛️ Device Status', [
                    _deviceRow('Fan', fanState, Colors.green, null),
                    _deviceRow('Led', lightState, Colors.yellow.shade700,
                        () => _sendCommand('led')),
                    _infoRow('WiFi Signal', rssi),
                  ]),
                  const SizedBox(height: 20),
                  _infoCard('⚙️ System Info', [
                    _infoRow('Firmware', firmware),
                    _infoRow('Online', deviceOnline ? 'Yes' : 'No'),
                    _infoRow('Last Update', lastUpdate),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusTile(String label, bool active) {
    return Card(
      elevation: 6,
      color: active ? Colors.green.shade400 : Colors.red.shade400,
      child: SizedBox(
        height: 70,
        child: Center(
          child: Text(
            '$label: ${active ? "Connected" : "Disconnected"}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _infoCard(String title, List<Widget> children) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.indigo)),
            const SizedBox(height: 10),
            ...children
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.black87)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w500, color: Colors.indigo)),
        ],
      ),
    );
  }

  Widget _deviceRow(
      String name, String state, Color color, VoidCallback? onTap) {
    final isOn = state == 'on';
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isOn ? color : Colors.grey,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(isOn ? 'ON' : 'OFF',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
