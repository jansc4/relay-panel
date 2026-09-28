import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// Adres brokera i PIN podawane przy budowaniu:
//   flutter build apk --dart-define=MQTT_BROKER=192.168.1.10 --dart-define=KIOSK_PIN=1234
const String mqttBroker =
    String.fromEnvironment('MQTT_BROKER', defaultValue: '192.168.1.100');
const String deviceId = 'pico1';
const int relayCount = 8;

// Mapowanie: nr światła -> (indeks przekaźnika ON, indeks przekaźnika OFF)
// Przekaźniki bistabilne w instalacji, więc to impuls, nie trzymany stan.
const Map<int, List<int>> lightRelayMap = {
  1: [0, 1], // IN1=ON, IN2=OFF
  2: [2, 3], // IN3=ON, IN4=OFF
  3: [4, 5], // IN5=ON, IN6=OFF
};

// PIN do wyjścia z trybu kiosk
const String kioskPin = String.fromEnvironment('KIOSK_PIN', defaultValue: '0000');

const MethodChannel kioskChannel = MethodChannel('relay_panel/kiosk');

void main() {
  runApp(const RelayPanelApp());
}

class RelayPanelApp extends StatelessWidget {
  const RelayPanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Relay Panel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late MqttServerClient client;
  bool connected = false;
  String statusText = 'Łączenie z MQTT...';
  final List<bool> relayState = List.filled(relayCount, false);

  // Timer trzymający zaplanowaną próbę ponownego połączenia.
  // Jeśli != null, to znaczy "już czekamy na retry", żeby nie mnożyć timerów.
  Timer? _reconnectTimer;

  // "Symulowane uśpienie" ekranu — zamiast pozwolić Androidowi realnie
  // zgasić ekran (co usuwa digitizer i tap-to-wake przestaje działać),
  // sami przygaszamy jasność do zera po czasie bezczynności.
  Timer? _idleTimer;
  bool _dimmed = false;
  static const Duration _idleTimeout = Duration(seconds: 15);

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_dimmed) _wakeScreen();
    _idleTimer = Timer(_idleTimeout, _dimScreen);
  }

  Future<void> _dimScreen() async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(0.01);
    } catch (e) {
      debugPrint('Nie udało się przygasić ekranu: $e');
    }
    setState(() => _dimmed = true);
  }

  Future<void> _wakeScreen() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (e) {
      debugPrint('Nie udało się przywrócić jasności: $e');
    }
    setState(() => _dimmed = false);
  }

  @override
  void initState() {
    super.initState();
    // Zapisujemy się jako obserwator cyklu życia apki (resumed/paused/...)
    WidgetsBinding.instance.addObserver(this);
    // Nie pozwalamy Androidowi realnie usypiać ekranu — sami symulujemy
    // uśpienie przygaszaniem, więc digitizer (dotyk) zawsze jest żywy.
    WakelockPlus.enable();
    _enterKioskMode();
    _connectMqtt();
    _resetIdleTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _idleTimer?.cancel();
    WakelockPlus.disable();
    client.disconnect();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Wywoływane przez Flutter, gdy apka wraca na pierwszy plan,
    // np. po zgaszeniu i włączeniu ekranu.
    if (state == AppLifecycleState.resumed) {
      final status = client.connectionStatus?.state;
      if (status != MqttConnectionState.connected) {
        setState(() => statusText = 'Wracam online...');
        _reconnectNow();
      }
    }
  }

  // Natychmiastowa próba połączenia — używana przy wybudzeniu/dotyku.
  void _reconnectNow() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectMqtt();
  }

  // Zaplanowana próba połączenia z opóźnieniem — używana gdy coś
  // samo się rozłączy w tle (np. system ubił socket).
  void _scheduleReconnect({Duration delay = const Duration(seconds: 3)}) {
    if (_reconnectTimer != null) return; // retry już zaplanowany
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connectMqtt();
    });
  }

  Future<void> _enterKioskMode() async {
    // Chowa pasek statusu i nawigacyjny
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Blokuje Home / Recent Apps (bez ręcznego przypinania)
    try {
      await kioskChannel.invokeMethod('startLockTask');
    } catch (e) {
      debugPrint('Nie udało się włączyć lock task: $e');
    }
  }

  Future<void> _exitKioskMode() async {
    try {
      await kioskChannel.invokeMethod('stopLockTask');
    } catch (e) {
      debugPrint('Nie udało się wyłączyć lock task: $e');
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemNavigator.pop();
  }

  Future<void> _showPinDialog() async {
    final controller = TextEditingController();
    String error = '';

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Podaj PIN aby wyjść'),
              content: TextField(
                controller: controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  errorText: error.isEmpty ? null : error,
                ),
                onSubmitted: (_) => _checkPin(
                  controller.text,
                  setDialogState,
                  (msg) => error = msg,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Anuluj'),
                ),
                TextButton(
                  onPressed: () {
                    if (controller.text == kioskPin) {
                      Navigator.pop(context);
                      _exitKioskMode();
                    } else {
                      setDialogState(() => error = 'Zły PIN');
                    }
                  },
                  child: const Text('Wyjdź'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _checkPin(
    String value,
    StateSetter setDialogState,
    Function(String) setError,
  ) {
    if (value != kioskPin) {
      setDialogState(() => setError('Zły PIN'));
    }
  }

  Future<void> _connectMqtt() async {
    client = MqttServerClient(mqttBroker, 'flutter_$deviceId');
    client.port = 1883;
    client.keepAlivePeriod = 20;
    client.logging(on: false);
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;

    try {
      await client.connect();
    } catch (e) {
      setState(() => statusText = 'Błąd połączenia: $e');
      client.disconnect();
      _scheduleReconnect(); // spróbuj ponownie za chwilę zamiast się poddawać
      return;
    }

    client.subscribe('home/$deviceId/status', MqttQos.atMostOnce);

    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      final recMess = messages[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      setState(() => statusText = payload);
    });
  }

  void _onConnected() {
    // Połączyliśmy się skutecznie — jeśli wisiał gdzieś zaplanowany retry, anuluj go.
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    setState(() {
      connected = true;
      statusText = 'Połączono z $deviceId';
    });
  }

  void _onDisconnected() {
    setState(() {
      connected = false;
      statusText = 'Rozłączono';
    });
    _scheduleReconnect(); // MQTT samo się rozłączyło (np. system ubił socket) — spróbuj wrócić
  }

  void _publishRelay(int index, bool state) {
    final payload = jsonEncode({'relay': index, 'state': state});
    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);
    client.publishMessage(
      'home/$deviceId/relay/set',
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  void _toggleRelay(int index) {
    final newState = !relayState[index];
    setState(() => relayState[index] = newState);
    _publishRelay(index, newState);
  }

  Future<void> _pulseRelay(int index, {int ms = 300}) async {
    setState(() => relayState[index] = true);
    _publishRelay(index, true);
    await Future.delayed(Duration(milliseconds: ms));
    setState(() => relayState[index] = false);
    _publishRelay(index, false);
  }

  void _lightOn(int lightNumber) {
    final relayIndex = lightRelayMap[lightNumber]![0];
    _pulseRelay(relayIndex);
  }

  void _lightOff(int lightNumber) {
    final relayIndex = lightRelayMap[lightNumber]![1];
    _pulseRelay(relayIndex);
  }

  final PageController _pageController = PageController();
  int _currentPage = 0;

  Widget _buildLightsPage() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: lightRelayMap.keys.map((lightNumber) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.amber[700], size: 32),
                      const SizedBox(width: 12),
                      Text(
                        '$lightNumber',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: connected ? () => _lightOn(lightNumber) : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('WŁĄCZ', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: connected ? () => _lightOff(lightNumber) : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[300],
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('WYŁĄCZ', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDebugPage() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.4,
      ),
      itemCount: relayCount,
      itemBuilder: (context, index) {
        final isOn = relayState[index];
        return ElevatedButton(
          onPressed: connected ? () => _toggleRelay(index) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isOn ? Colors.teal : Colors.grey[300],
            foregroundColor: isOn ? Colors.white : Colors.black87,
          ),
          child: Text(
            'Przekaźnik ${index + 1}\n${isOn ? "WŁ" : "WYŁ"}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        );
      },
    );
  }

  // Wywoływane przy KAŻDYM dotknięciu ekranu (translucent = nie blokuje
  // przycisków pod spodem, tylko dodatkowo "podsłuchuje" gest).
  void _onScreenTouched() {
    _resetIdleTimer(); // dotyk = aktywność, odlicz od nowa i przywróć jasność
    final status = client.connectionStatus?.state;
    if (status != MqttConnectionState.connected) {
      _reconnectNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _onScreenTouched,
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _showPinDialog();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_currentPage == 0 ? 'Oświetlenie' : 'Debug — przekaźniki'),
          backgroundColor: connected ? Colors.teal : Colors.redAccent,
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(statusText, style: const TextStyle(fontSize: 14)),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildLightsPage(),
                  _buildDebugPage(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(2, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == i ? Colors.teal : Colors.grey[300],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
      ), // koniec PopScope
        ), // koniec GestureDetector
        if (_dimmed)
          // Nakładka łapiąca PIERWSZY dotyk gdy ekran jest przygaszony.
          // "opaque" = pochłania dotyk, nie przepuszcza go do przycisków pod spodem.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onScreenTouched,
              child: Container(color: Colors.black),
            ),
          ),
      ],
    );
  }
}
