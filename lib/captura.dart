import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ---- Muestreo / notificación ----
const String kNotifChannel = 'captura_genialisis';
const int kNotifId = 888;
const int kMotionMinIntervalMs = 15; // limita ráfagas del acelerómetro

/// Resultado crudo de una captura (sin procesar).
class DatosCrudos {
  final int inicio;
  final int fin;
  final List<Map<String, dynamic>> gps;
  final List<Map<String, dynamic>> motion;

  DatosCrudos({
    required this.inicio,
    required this.fin,
    required this.gps,
    required this.motion,
  });

  factory DatosCrudos.fromJson(Map<String, dynamic> j) => DatosCrudos(
        inicio: j['inicio'] as int,
        fin: j['fin'] as int,
        gps: (j['gps'] as List).cast<Map<String, dynamic>>(),
        motion: (j['motion'] as List).cast<Map<String, dynamic>>(),
      );

  Map<String, dynamic> toJson() => {
        'inicio': inicio,
        'fin': fin,
        'gps': gps,
        'motion': motion,
      };
}

double haversine(Map<String, dynamic> a, Map<String, dynamic> b) {
  const R = 6371000.0;
  double toRad(double x) => x * pi / 180.0;
  final dLat = toRad((b['lat'] as double) - (a['lat'] as double));
  final dLng = toRad((b['lng'] as double) - (a['lng'] as double));
  final s = pow(sin(dLat / 2), 2) +
      cos(toRad(a['lat'] as double)) *
          cos(toRad(b['lat'] as double)) *
          pow(sin(dLng / 2), 2);
  return 2 * R * asin(sqrt(s));
}

String _fmtDur(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

// =====================================================================
//  SERVICIO EN SEGUNDO PLANO (isolate separado)
// =====================================================================

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async => true;

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  bool capturing = false;
  String etiqueta = '';
  int inicio = 0;
  final gps = <Map<String, dynamic>>[];
  final motion = <Map<String, dynamic>>[];
  double distAcum = 0;
  double vmax = 0;
  Map<String, dynamic>? lastGps;
  int lastMotionT = 0;
  double gx = 0, gy = 0, gz = 0;

  StreamSubscription<Position>? gpsSub;
  StreamSubscription<UserAccelerometerEvent>? accSub;
  StreamSubscription<GyroscopeEvent>? gyrSub;
  Timer? uiTimer;

  void detenerStreams() {
    gpsSub?.cancel();
    accSub?.cancel();
    gyrSub?.cancel();
    uiTimer?.cancel();
    gpsSub = null;
    accSub = null;
    gyrSub = null;
    uiTimer = null;
  }

  service.on('iniciar').listen((data) {
    if (capturing) return;
    etiqueta = (data?['etiqueta'] as String?) ?? 'Captura';
    gps.clear();
    motion.clear();
    distAcum = 0;
    vmax = 0;
    lastGps = null;
    lastMotionT = 0;
    inicio = DateTime.now().millisecondsSinceEpoch;
    capturing = true;

    gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    ).listen((pos) {
      final t = DateTime.now().millisecondsSinceEpoch;
      double vel = pos.speed;
      final punto = <String, dynamic>{
        't': t,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'alt': pos.altitude,
        'acc': pos.accuracy,
        'vel': vel,
      };
      if (vel <= 0 && lastGps != null) {
        final dt = (t - (lastGps!['t'] as int)) / 1000.0;
        if (dt > 0) {
          vel = haversine(lastGps!, punto) / dt;
          punto['vel'] = vel;
        }
      }
      if (lastGps != null) distAcum += haversine(lastGps!, punto);
      if ((punto['vel'] as double) > vmax) vmax = punto['vel'] as double;
      lastGps = punto;
      gps.add(punto);
    });

    gyrSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((e) {
      gx = e.x;
      gy = e.y;
      gz = e.z;
    });

    accSub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((e) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastMotionT < kMotionMinIntervalMs) return;
      lastMotionT = now;
      motion.add({
        't': now,
        'ax': double.parse(e.x.toStringAsFixed(2)),
        'ay': double.parse(e.y.toStringAsFixed(2)),
        'az': double.parse(e.z.toStringAsFixed(2)),
        'gx': double.parse(gx.toStringAsFixed(2)),
        'gy': double.parse(gy.toStringAsFixed(2)),
        'gz': double.parse(gz.toStringAsFixed(2)),
      });
    });

    uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - inicio;
      final velAct = lastGps != null ? (lastGps!['vel'] as double) : 0.0;
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'GENIALISIS · Capturando',
          content: '$etiqueta · ${_fmtDur(elapsed)}',
        );
      }
      service.invoke('update', {
        'tiempo': _fmtDur(elapsed),
        'vel': (velAct * 3.6).toStringAsFixed(1),
        'dist': distAcum.round(),
        'max': (vmax * 3.6).toStringAsFixed(1),
        'gps': gps.length,
        'mot': motion.length,
      });
    });

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'GENIALISIS · Capturando',
        content: '$etiqueta · 0:00',
      );
    }
  });

  // Detener guardando: escribe los datos crudos a un archivo temporal y avisa.
  service.on('detener').listen((data) async {
    if (!capturing) {
      service.stopSelf();
      return;
    }
    capturing = false;
    detenerStreams();
    final fin = DateTime.now().millisecondsSinceEpoch;
    final datos = DatosCrudos(
      inicio: inicio,
      fin: fin,
      gps: List<Map<String, dynamic>>.from(gps),
      motion: List<Map<String, dynamic>>.from(motion),
    );
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/captura_$fin.json');
      await f.writeAsString(jsonEncode(datos.toJson()));
      service.invoke('listo', {'path': f.path});
    } catch (e) {
      service.invoke('listo', {'path': null});
    }
    service.stopSelf();
  });

  // Cancelar sin guardar (para abortar o limpiar zombie).
  service.on('cancelar').listen((data) {
    capturing = false;
    detenerStreams();
    service.stopSelf();
  });
}

// =====================================================================
//  API PARA LA UI (isolate principal)
// =====================================================================

class MotorCaptura {
  MotorCaptura._();
  static final MotorCaptura instance = MotorCaptura._();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  Completer<DatosCrudos?>? _completerDetener;

  /// Callback de métricas en vivo (tiempo, vel, dist, max, gps, mot).
  void Function(Map<String, dynamic> datos)? onActualizacion;

  bool _configurado = false;

  /// Llamar una sola vez en main() antes de runApp.
  Future<void> configurar() async {
    if (_configurado) return;
    _configurado = true;

    final fln = FlutterLocalNotificationsPlugin();
    const canal = AndroidNotificationChannel(
      kNotifChannel,
      'Captura GENIALISIS',
      description: 'Notificación mientras se captura una sesión',
      importance: Importance.low,
    );
    await fln
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canal);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: kNotifChannel,
        initialNotificationTitle: 'GENIALISIS',
        initialNotificationContent: 'Preparando captura…',
        foregroundServiceNotificationId: kNotifId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _service.on('update').listen((data) {
      if (data != null) onActualizacion?.call(data);
    });

    _service.on('listo').listen((data) async {
      DatosCrudos? d;
      final path = data?['path'] as String?;
      if (path != null) {
        try {
          final txt = await File(path).readAsString();
          d = DatosCrudos.fromJson(jsonDecode(txt) as Map<String, dynamic>);
          await File(path).delete();
        } catch (_) {}
      }
      _completerDetener?.complete(d);
      _completerDetener = null;
    });
  }

  /// Pide los permisos necesarios. Devuelve true si se pueden capturar.
  Future<bool> pedirPermisos() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final notif = await Permission.notification.request();
    if (!notif.isGranted) return false;
    final cuando = await Permission.locationWhenInUse.request();
    if (!cuando.isGranted) return false;
    await Permission.locationAlways.request();
    return true;
  }

  Future<bool> estaCorriendo() => _service.isRunning();

  /// Mata cualquier servicio colgado (zombie) de una sesión anterior.
  Future<void> limpiarSiCorre() async {
    try {
      if (await _service.isRunning()) {
        _service.invoke('cancelar');
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } catch (_) {}
  }

  /// Inicia la captura. [etiqueta] es lo que se muestra en la notificación.
  Future<void> iniciar({required String etiqueta}) async {
    await limpiarSiCorre();
    await _service.startService();
    await Future.delayed(const Duration(milliseconds: 600));
    _service.invoke('iniciar', {'etiqueta': etiqueta});
  }

  /// Detiene la captura y devuelve los datos crudos (o null si falla).
  Future<DatosCrudos?> detener() {
    _completerDetener = Completer<DatosCrudos?>();
    _service.invoke('detener');
    return _completerDetener!.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        _completerDetener = null;
        return null;
      },
    );
  }

  /// Aborta sin guardar.
  void cancelar() {
    _service.invoke('cancelar');
  }
}