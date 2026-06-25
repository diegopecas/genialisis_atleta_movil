import 'dart:math';

/// Resultado de una calibración: el valor del umbral + un texto explicativo.
class ResultadoUmbral {
  final double valor;
  final String detalle;
  final bool confiable;

  ResultadoUmbral(this.valor, this.detalle, {this.confiable = true});
}

/// SALTO → umbral de magnitud de aceleración de aterrizaje (m/s²).
/// Detecta los picos más fuertes y pone el umbral un poco por debajo del
/// salto más suave de los [numSaltos] que el atleta dijo haber hecho.
ResultadoUmbral calcularUmbralSalto(
    List<Map<String, dynamic>> motion, int numSaltos) {
  if (motion.length < 10 || numSaltos < 1) {
    return ResultadoUmbral(
        18.0, 'Datos insuficientes. Se usó el valor por defecto (18 m/s²).',
        confiable: false);
  }

  final serie = <List<num>>[];
  for (final m in motion) {
    final ax = (m['ax'] as num).toDouble();
    final ay = (m['ay'] as num).toDouble();
    final az = (m['az'] as num).toDouble();
    serie.add([m['t'] as int, sqrt(ax * ax + ay * ay + az * az)]);
  }

  const refractarioMs = 400;
  final picos = <double>[];
  int ultimo = -1000000;
  for (var i = 1; i < serie.length - 1; i++) {
    final t = serie[i][0] as int;
    final mag = serie[i][1].toDouble();
    final prev = serie[i - 1][1].toDouble();
    final next = serie[i + 1][1].toDouble();
    if (mag >= prev && mag >= next && mag > 5 && (t - ultimo) > refractarioMs) {
      picos.add(mag);
      ultimo = t;
    }
  }

  if (picos.isEmpty) {
    return ResultadoUmbral(
        18.0, 'No se detectaron saltos. Valor por defecto (18 m/s²).',
        confiable: false);
  }

  picos.sort((a, b) => b.compareTo(a));
  final top = picos.take(numSaltos).toList();
  final masSuave = top.last;
  final umbral = masSuave * 0.9;

  return ResultadoUmbral(
    double.parse(umbral.toStringAsFixed(1)),
    'Picos detectados: ${picos.length}. '
    'Salto más suave de los $numSaltos: ${masSuave.toStringAsFixed(1)} m/s². '
    'Umbral fijado: ${umbral.toStringAsFixed(1)} m/s².',
    confiable: picos.length >= numSaltos,
  );
}

/// SPRINT → velocidad mínima (m/s) para contar un sprint.
/// Se fija en el 70 % de la velocidad máxima personal (zona individual).
ResultadoUmbral calcularUmbralSprint(List<Map<String, dynamic>> gps) {
  final vels = <double>[];
  for (final p in gps) {
    final acc = (p['acc'] is num) ? (p['acc'] as num).toDouble() : 999.0;
    final v = (p['vel'] is num) ? (p['vel'] as num).toDouble() : 0.0;
    if (acc <= 20) vels.add(v); // solo lecturas GPS confiables
  }

  if (vels.isEmpty) {
    return ResultadoUmbral(
        2.2, 'Sin datos GPS confiables. Valor por defecto (2.2 m/s).',
        confiable: false);
  }

  final vmax = vels.reduce(max);
  if (vmax < 1.0) {
    return ResultadoUmbral(
        2.2,
        'Velocidad muy baja (${(vmax * 3.6).toStringAsFixed(1)} km/h). '
            'Valor por defecto (2.2 m/s).',
        confiable: false);
  }

  final umbral = vmax * 0.7;
  return ResultadoUmbral(
    double.parse(umbral.toStringAsFixed(2)),
    'Velocidad máxima: ${(vmax * 3.6).toStringAsFixed(1)} km/h. '
    'Umbral de sprint (70 %): ${(umbral * 3.6).toStringAsFixed(1)} km/h.',
    confiable: true,
  );
}

/// ACELERACIÓN → magnitud (m/s²) para contar un arranque/frenazo fuerte.
/// Se calcula derivando la velocidad del GPS (Δv/Δt) en los arranques y frenazos.
/// El GPS es ruidoso, así que el valor se mantiene en un rango sensato.
ResultadoUmbral calcularUmbralAceleracion(List<Map<String, dynamic>> gps) {
  final pts = gps
      .where((p) =>
          (p['acc'] is num) ? (p['acc'] as num).toDouble() <= 20 : false)
      .toList();

  if (pts.length < 3) {
    return ResultadoUmbral(
        2.5, 'Datos GPS insuficientes. Valor por defecto (2.5 m/s²).',
        confiable: false);
  }

  final accs = <double>[];
  for (var i = 1; i < pts.length; i++) {
    final dt = ((pts[i]['t'] as int) - (pts[i - 1]['t'] as int)) / 1000.0;
    if (dt <= 0) continue;
    final dv = (pts[i]['vel'] as num).toDouble() -
        (pts[i - 1]['vel'] as num).toDouble();
    accs.add((dv / dt).abs());
  }

  if (accs.isEmpty) {
    return ResultadoUmbral(
        2.5, 'No se pudo calcular. Valor por defecto (2.5 m/s²).',
        confiable: false);
  }

  accs.sort((a, b) => b.compareTo(a));
  final maxAcc = accs.first;
  // Hasta 6 eventos fuertes: 3 arranques + 3 frenazos.
  final top = accs.take(6).toList();
  var umbral = top.last * 0.9;
  if (umbral < 1.5) umbral = 1.5;
  if (umbral > 4.0) umbral = 4.0;

  return ResultadoUmbral(
    double.parse(umbral.toStringAsFixed(1)),
    'Aceleración máxima: ${maxAcc.toStringAsFixed(1)} m/s². '
    'Umbral fijado: ${umbral.toStringAsFixed(1)} m/s².',
    confiable: maxAcc >= 1.5,
  );
}