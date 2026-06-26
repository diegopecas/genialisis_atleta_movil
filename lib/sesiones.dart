import 'package:flutter/material.dart';

import 'tema.dart';
import 'modelos.dart';
import 'db.dart';
import 'widgets_metricas.dart';
import 'exportacion_logica.dart';

// ---------------------------------------------------------------------
//  Lista de sesiones de un atleta
// ---------------------------------------------------------------------
class SesionesAtletaScreen extends StatefulWidget {
  final Atleta atleta;
  const SesionesAtletaScreen({super.key, required this.atleta});

  @override
  State<SesionesAtletaScreen> createState() => _SesionesAtletaScreenState();
}

class _SesionesAtletaScreenState extends State<SesionesAtletaScreen> {
  List<Map<String, dynamic>> _sesiones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final s = await DB.instance.getResumenSesiones(widget.atleta.id);
    if (mounted) {
      setState(() {
        _sesiones = s;
        _cargando = false;
      });
    }
  }

  Future<void> _abrirDetalle(Map<String, dynamic> s) async {
    final borrada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SesionDetalleScreen(
          idSesion: s['id'] as String,
          atleta: widget.atleta,
          inicio: s['inicio'] as int,
          fin: s['fin'] as int,
        ),
      ),
    );
    if (borrada == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sesiones · ${widget.atleta.nombre}'),
        backgroundColor: kBg,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _sesiones.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Este atleta aún no tiene sesiones capturadas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _sesiones.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = _sesiones[i];
                    final dur = (s['fin'] as int) - (s['inicio'] as int);
                    final dist = (s['distancia'] as num?)?.toDouble() ?? 0;
                    final saltos = (s['saltos'] as num?)?.toInt() ?? 0;
                    return InkWell(
                      onTap: () => _abrirDetalle(s),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.07)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fmtFecha(s['inicio'] as int),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _chip(Icons.timer, fmtDuracion(dur)),
                                const SizedBox(width: 8),
                                _chip(Icons.straighten,
                                    '${dist.toInt()} m'),
                                const SizedBox(width: 8),
                                _chip(Icons.height, '$saltos saltos'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _chip(IconData icono, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: kGold, size: 14),
          const SizedBox(width: 5),
          Text(texto,
              style: const TextStyle(color: kGoldBright, fontSize: 12)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Detalle de una sesión
// ---------------------------------------------------------------------
class SesionDetalleScreen extends StatefulWidget {
  final String idSesion;
  final Atleta atleta;
  final int inicio;
  final int fin;

  const SesionDetalleScreen({
    super.key,
    required this.idSesion,
    required this.atleta,
    required this.inicio,
    required this.fin,
  });

  @override
  State<SesionDetalleScreen> createState() => _SesionDetalleScreenState();
}

class _SesionDetalleScreenState extends State<SesionDetalleScreen> {
  List<Map<String, dynamic>> _metricas = [];
  bool _cargando = true;
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final m = await DB.instance.getMetricasSesion(widget.idSesion);
    if (mounted) {
      setState(() {
        _metricas = m;
        _cargando = false;
      });
    }
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanel,
        title: const Text('Eliminar sesión'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: kDanger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DB.instance.deleteSesion(widget.idSesion);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _exportar() async {
    setState(() => _exportando = true);
    try {
      await exportarSesionUnica(widget.atleta, widget.idSesion);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: kDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dur = widget.fin - widget.inicio;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de sesión'),
        backgroundColor: kBg,
        actions: [
          IconButton(
            icon: _exportando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kGold))
                : const Icon(Icons.ios_share, color: kGold),
            onPressed: _exportando ? null : _exportar,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: kDanger),
            onPressed: _eliminar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(widget.atleta.nombre,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${fmtFecha(widget.inicio)} · ${fmtDuracion(dur)}',
                    style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _metricas.map((m) {
                    return MetricaCard(
                      nombre: m['nombre'] as String,
                      codigo: m['codigo'] as String,
                      valor: (m['valor'] as num).toDouble(),
                      unidad: (m['unidad'] as String?) ?? '',
                    );
                  }).toList(),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------
//  Selector de atleta (para el acceso desde el menú de inicio)
// ---------------------------------------------------------------------
class SesionesSelectorScreen extends StatefulWidget {
  const SesionesSelectorScreen({super.key});

  @override
  State<SesionesSelectorScreen> createState() =>
      _SesionesSelectorScreenState();
}

class _SesionesSelectorScreenState extends State<SesionesSelectorScreen> {
  List<Atleta> _atletas = [];
  List<Institucion> _instituciones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final inst = await DB.instance.getInstituciones();
    final atl = await DB.instance.getAtletas();
    if (!mounted) return;

    // Selección inteligente: si solo hay un atleta, ir directo a sus sesiones.
    if (atl.length == 1) {
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SesionesAtletaScreen(atleta: atl.first),
        ),
      );
      return;
    }

    setState(() {
      _instituciones = inst;
      _atletas = atl;
      _cargando = false;
    });
  }

  String _nombreInst(String id) {
    final i = _instituciones.where((e) => e.id == id);
    return i.isEmpty ? '—' : i.first.nombre;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesiones'),
        backgroundColor: kBg,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _atletas.isEmpty
              ? const Center(
                  child: Text('No hay atletas.',
                      style: TextStyle(color: Colors.white54)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _atletas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = _atletas[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07)),
                      ),
                      child: ListTile(
                        title: Text(a.nombre,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(_nombreInst(a.idInstitucion),
                            style: const TextStyle(color: Colors.white54)),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.white38),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SesionesAtletaScreen(atleta: a),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}