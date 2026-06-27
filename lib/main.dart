import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

// Manejar notificaciones en background
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> _inicializarNotificaciones() async {
  const AndroidNotificationChannel canal = AndroidNotificationChannel(
    'sismoapp_alertas',
    'Alertas de Sismo',
    description: 'Notificaciones de actividad sísmica',
    importance: Importance.max,
  );

  final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
      localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(canal);

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await localNotifications.initialize(initSettings);

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final notif = message.notification;
    if (notif == null) return;

    localNotifications.show(
      0,
      notif.title,
      notif.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'sismoapp_alertas',
          'Alertas de Sismo',
          channelDescription: 'Notificaciones de actividad sísmica',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await _inicializarNotificaciones();

  // Guardar token FCM en Firebase para que el ESP32 pueda usarlo
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    FirebaseDatabase.instance.ref('/dispositivo/fcmToken').set(token);
    debugPrint('FCM Token: $token');
  }

  runApp(const SismoApp());
}

class SismoApp extends StatelessWidget {
  const SismoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SismoApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      ),
      home: const HomePage(),
    );
  }
}

class SismoEvento {
  final String nivel;
  final double vibracion;
  final String timestamp;

  SismoEvento({required this.nivel, required this.vibracion, required this.timestamp});

  factory SismoEvento.fromMap(Map map) {
    return SismoEvento(
      nivel:     map['nivel']      ?? 'DESCONOCIDO',
      vibracion: (map['vibracion'] as num?)?.toDouble() ?? 0.0,
      timestamp: map['timestamp']  ?? '0',
    );
  }
}

// ─────────────────────────────────────────
// Barra de estado del ESP32
// ─────────────────────────────────────────
class BarraEstadoESP32 extends StatelessWidget {
  const BarraEstadoESP32({super.key});

  void _enviarComando(String path) {
    FirebaseDatabase.instance.ref(path).set(true);
  }

  void _confirmarAccion(BuildContext context, String titulo, String mensaje, String path) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(titulo, style: const TextStyle(color: Colors.white)),
        content: Text(mensaje, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _enviarComando(path);
            },
            child: const Text('Confirmar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('/dispositivo/online');

    return StreamBuilder(
      stream: ref.onValue,
      builder: (context, snapshot) {
        final online = snapshot.hasData &&
            snapshot.data!.snapshot.value == true;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF1A1A1A),
          child: Row(
            children: [
              Icon(
                online ? Icons.wifi : Icons.wifi_off,
                color: online ? Colors.greenAccent : Colors.redAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                online ? 'ESP32 conectado' : 'ESP32 desconectado',
                style: TextStyle(
                  color: online ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (!online)
                TextButton.icon(
                  onPressed: () => _confirmarAccion(
                    context,
                    'Modo AP',
                    '¿Activar modo AP para reconfigurar WiFi?',
                    '/dispositivo/modoAP',
                  ),
                  icon: const Icon(Icons.settings_ethernet, size: 16, color: Colors.orangeAccent),
                  label: const Text('Modo AP', style: TextStyle(color: Colors.orangeAccent, fontSize: 13)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              if (online)
                TextButton.icon(
                  onPressed: () => _confirmarAccion(
                    context,
                    'Reiniciar ESP32',
                    '¿Seguro que quieres reiniciar el dispositivo?',
                    '/dispositivo/reiniciar',
                  ),
                  icon: const Icon(Icons.restart_alt, size: 16, color: Colors.white54),
                  label: const Text('Reiniciar', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────
// Home
// ─────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _paginaActual = 0;

  final List<Widget> _paginas = const [
    PantallaAlerta(),
    PantallaHistorial(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('SismoApp', style: TextStyle(letterSpacing: 2)),
        centerTitle: true,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(40),
          child: BarraEstadoESP32(),
        ),
      ),
      body: _paginas[_paginaActual],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: Colors.redAccent,
        unselectedItemColor: Colors.grey,
        currentIndex: _paginaActual,
        onTap: (i) => setState(() => _paginaActual = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.warning_amber), label: 'Alerta'),
          BottomNavigationBarItem(icon: Icon(Icons.history),        label: 'Historial'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Pantalla Alerta
// ─────────────────────────────────────────
class PantallaAlerta extends StatelessWidget {
  const PantallaAlerta({super.key});

  Color _colorNivel(String nivel) {
    switch (nivel) {
      case 'FUERTE':   return Colors.red;
      case 'MODERADO': return Colors.orange;
      case 'LIGERO':   return Colors.green;
      default:         return Colors.grey;
    }
  }

  IconData _iconoNivel(String nivel) {
    switch (nivel) {
      case 'FUERTE':   return Icons.crisis_alert;
      case 'MODERADO': return Icons.warning_amber;
      case 'LIGERO':   return Icons.notification_important;
      default:         return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('/sismos/ultimo');

    return StreamBuilder(
      stream: ref.onValue,
      builder: (context, snapshot) {
        String nivel     = 'SIN DATOS';
        double vibracion = 0.0;

        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final data = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
          nivel     = data['nivel']      ?? 'SIN DATOS';
          vibracion = (data['vibracion'] as num?)?.toDouble() ?? 0.0;
        }

        final color = _colorNivel(nivel);

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('ÚLTIMO SISMO',
                style: TextStyle(color: Colors.grey, fontSize: 14, letterSpacing: 3)),
              const SizedBox(height: 40),
              Icon(_iconoNivel(nivel), size: 120, color: color),
              const SizedBox(height: 24),
              Text(nivel,
                style: TextStyle(
                  color: color, fontSize: 48,
                  fontWeight: FontWeight.bold, letterSpacing: 4,
                )),
              const SizedBox(height: 16),
              Text('${vibracion.toStringAsFixed(4)} m/s²',
                style: const TextStyle(color: Colors.white54, fontSize: 18)),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────
// Pantalla Historial
// ─────────────────────────────────────────
class PantallaHistorial extends StatelessWidget {
  const PantallaHistorial({super.key});

  Color _colorNivel(String nivel) {
    switch (nivel) {
      case 'FUERTE':   return Colors.red;
      case 'MODERADO': return Colors.orange;
      case 'LIGERO':   return Colors.green;
      default:         return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('/sismos/historial');

    return StreamBuilder(
      stream: ref.onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(
            child: Text('Sin historial aún',
              style: TextStyle(color: Colors.grey, fontSize: 16)));
        }

        final rawMap = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
        final eventos = rawMap.values
          .map((e) => SismoEvento.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        return Column(
          children: [
            const SizedBox(height: 20),
            const Text('HISTORIAL',
              style: TextStyle(color: Colors.grey, fontSize: 14, letterSpacing: 3)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: eventos.length,
                itemBuilder: (context, i) {
                  final e     = eventos[i];
                  final color = _colorNivel(e.nivel);
                  return ListTile(
                    leading: Icon(Icons.circle, color: color, size: 14),
                    title: Text(e.nivel,
                      style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                    subtitle: Text('${e.vibracion.toStringAsFixed(4)} m/s²',
                      style: const TextStyle(color: Colors.white54)),
                    trailing: Text(
                      DateTime.fromMillisecondsSinceEpoch(
                        int.tryParse(e.timestamp) ?? 0
                      ).toString().substring(0, 19),
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}