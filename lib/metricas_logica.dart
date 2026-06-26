import 'dart:math';

import 'captura.dart'; // haversine, DatosCrudos

/// Una métrica calculada de la sesión.
class MetricaCalculada {
  final String codigo;
  final double valor;
  final double? umbralUsado;

  MetricaCalculada(this.codigo, this.valor, this.umbralUsado);

  Map<String, dynamic> toMap() => {
        'codigo': codigo,
        'valor': valor,
        'umbral': umbralUsado,
      };
}

// Filtros anti-ruido del GPS.
const double kAccPrecisionMax = 20.0; // descarta lecturas con error > 20 m
const double kVelMinMovimiento = 0.5; // < 0.5 m/s se considera "quieto"
const double kVelMaxRealista = 12.0; // > 43 km/h se considera ruido GPS

/// Calcula todas las métricas a partir de los datos crudos y los umbrales
/// calibrados del atleta. Las que no dependen de umbral llevan umbral nulo.
List<MetricaCalculada> calcularMetricas(
    DatosCrudos datos, Map<String, double> umbrales) {
  final gps = datos.gps;
  final motion = datos.motion;

  final umbralSprint = umbrales['SPRINT'] ?? 2.2; // m/s
  final umbralSalto = umbrales['SALTO'] ?? 18.0; // m/s²
  final umbralAcc = umbrales['ACELERACION'] ?? 2.5; // m/s²

  // --- GPS filtrado por precisión ---
  final pts = gps.where((p) {
    final acc = (p['acc'] is num) ? (p['acc'] as num).toDouble() : 999.0;
    return acc <= kAccPrecisionMax;
  }).toList();

  // Velocidades
  double vmax = 0, vsum = 0;
  int vcount = 0;
  for (final p in pts) {
    final v = (p['vel'] is num) ? (p['vel'] as num).toDouble() : 0.0;
    if (v > vmax && v <= kVelMaxRealista) vmax = v;
    if (v >= kVelMinMovimiento && v <= kVelMaxRealista) {
      vsum += v;
      vcount++;
    }
  }
  final vprom = vcount > 0 ? vsum / vcount : 0.0;

  // Distancia (solo segmentos en movimiento y descartando saltos imposibles)
  double dist = 0, distSprint = 0;
  for (var i = 1; i < pts.length; i++) {
    final v = (pts[i]['vel'] is num) ? (pts[i]['vel'] as num).toDouble() : 0.0;
    if (v < kVelMinMovimiento) continue; // anti-drift
    final dt = ((pts[i]['t'] as int) - (pts[i - 1]['t'] as int)) / 1000.0;
    if (dt <= 0) continue;
    final d = haversine(pts[i - 1], pts[i]);
    if ((d / dt) > kVelMaxRealista) continue; // segmento ruidoso
    dist += d;
    if (v >= umbralSprint) distSprint += d;
  }

  // Sprints: cruces ascendentes del umbral de velocidad
  int sprints = 0;
  bool dentroSprint = false;
  for (final p in pts) {
    final v = (p['vel'] is num) ? (p['vel'] as num).toDouble() : 0.0;
    if (!dentroSprint && v >= umbralSprint && v <= kVelMaxRealista) {
      sprints++;
      dentroSprint = true;
    } else if (dentroSprint && v < umbralSprint) {
      dentroSprint = false;
    }
  }

  // Saltos: detector de firma (ventana de vuelo + golpe de aterrizaje)
  final saltos = _contarSaltos(motion, umbralSalto);

  // Aceleraciones / desaceleraciones fuertes (desde la velocidad del GPS)
  int acel = 0, desacel = 0;
  bool enAcel = false, enDesacel = false;
  for (var i = 1; i < pts.length; i++) {
    final dt = ((pts[i]['t'] as int) - (pts[i - 1]['t'] as int)) / 1000.0;
    if (dt <= 0) continue;
    final dv = (pts[i]['vel'] as num).toDouble() -
        (pts[i - 1]['vel'] as num).toDouble();
    final a = dv / dt;
    if (a >= umbralAcc) {
      if (!enAcel) {
        acel++;
        enAcel = true;
      }
    } else {
      enAcel = false;
    }
    if (a <= -umbralAcc) {
      if (!enDesacel) {
        desacel++;
        enDesacel = true;
      }
    } else {
      enDesacel = false;
    }
  }

  // Player Load (carga del acelerómetro)
  final playerLoad = _playerLoad(motion);

  return [
    MetricaCalculada('DISTANCIA', dist.roundToDouble(), null),
    MetricaCalculada(
        'VEL_MAX', double.parse((vmax * 3.6).toStringAsFixed(1)), null),
    MetricaCalculada(
        'VEL_PROM', double.parse((vprom * 3.6).toStringAsFixed(1)), null),
    MetricaCalculada('SPRINTS', sprints.toDouble(), umbralSprint),
    MetricaCalculada('DIST_SPRINT', distSprint.roundToDouble(), umbralSprint),
    MetricaCalculada('SALTOS', saltos.toDouble(), umbralSalto),
    MetricaCalculada('ACELERACIONES', acel.toDouble(), umbralAcc),
    MetricaCalculada('DESACELERACIONES', desacel.toDouble(), umbralAcc),
    MetricaCalculada(
        'PLAYER_LOAD', double.parse(playerLoad.toStringAsFixed(1)), null),
  ];
}

int _contarSaltos(List<Map<String, dynamic>> motion, double umbralLand) {
  const flightMax = 10.0;
  const airMin = 80, airMax = 400, refractory = 400;
  final serie = <List<num>>[];
  for (final m in motion) {
    final ax = (m['ax'] as num).toDouble();
    final ay = (m['ay'] as num).toDouble();
    final az = (m['az'] as num).toDouble();
    serie.add([m['t'] as int, sqrt(ax * ax + ay * ay + az * az)]);
  }
  int saltos = 0, ultimo = 0;
  for (var i = 0; i < serie.length; i++) {
    final t = serie[i][0] as int;
    final mag = serie[i][1].toDouble();
    if (mag < umbralLand || (t - ultimo) <= refractory) continue;
    double suma = 0;
    int n = 0;
    for (var j = i - 1; j >= 0; j--) {
      final dt = t - (serie[j][0] as int);
      if (dt > airMax) break;
      if (dt >= airMin) {
        suma += serie[j][1].toDouble();
        n++;
      }
    }
    if (n >= 3 && (suma / n) <= flightMax) {
      saltos++;
      ultimo = t;
    }
  }
  return saltos;
}

double _playerLoad(List<Map<String, dynamic>> motion) {
  double acc = 0;
  for (var i = 1; i < motion.length; i++) {
    final dax =
        (motion[i]['ax'] as num).toDouble() - (motion[i - 1]['ax'] as num).toDouble();
    final day =
        (motion[i]['ay'] as num).toDouble() - (motion[i - 1]['ay'] as num).toDouble();
    final daz =
        (motion[i]['az'] as num).toDouble() - (motion[i - 1]['az'] as num).toDouble();
    acc += sqrt(dax * dax + day * day + daz * daz);
  }
  return acc / 100.0;
}