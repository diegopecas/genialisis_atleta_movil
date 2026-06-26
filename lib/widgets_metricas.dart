import 'package:flutter/material.dart';

import 'tema.dart';

IconData iconoMetrica(String codigo) {
  switch (codigo) {
    case 'DISTANCIA':
      return Icons.straighten;
    case 'VEL_MAX':
      return Icons.speed;
    case 'VEL_PROM':
      return Icons.av_timer;
    case 'SPRINTS':
      return Icons.directions_run;
    case 'DIST_SPRINT':
      return Icons.bolt;
    case 'SALTOS':
      return Icons.height;
    case 'ACELERACIONES':
      return Icons.trending_up;
    case 'DESACELERACIONES':
      return Icons.trending_down;
    case 'PLAYER_LOAD':
      return Icons.fitness_center;
    default:
      return Icons.analytics;
  }
}

String formatearValor(double v, String unidad) {
  final n = (unidad == 'conteo' || v == v.roundToDouble())
      ? v.toInt().toString()
      : v.toStringAsFixed(1);
  if (unidad.isEmpty || unidad == 'conteo') return n;
  return '$n $unidad';
}

String fmtDuracion(int ms) {
  final s = ms ~/ 1000;
  final m = s ~/ 60;
  return '$m:${(s % 60).toString().padLeft(2, '0')} min';
}

String fmtFecha(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}

class MetricaCard extends StatelessWidget {
  final String nombre;
  final String codigo;
  final double valor;
  final String unidad;

  const MetricaCard({
    super.key,
    required this.nombre,
    required this.codigo,
    required this.valor,
    required this.unidad,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: (MediaQuery.of(context).size.width - 40 - 12) / 2,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGold.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconoMetrica(codigo), color: kGold, size: 24),
          const SizedBox(height: 10),
          Text(
            formatearValor(valor, unidad),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            nombre,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}