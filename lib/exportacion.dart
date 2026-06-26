import 'package:flutter/material.dart';

import 'tema.dart';
import 'modelos.dart';
import 'db.dart';
import 'widgets_metricas.dart';
import 'exportacion_logica.dart';

class ExportacionScreen extends StatefulWidget {
  const ExportacionScreen({super.key});

  @override
  State<ExportacionScreen> createState() => _ExportacionScreenState();
}

class _ExportacionScreenState extends State<ExportacionScreen> {
  bool _cargando = true;
  bool _exportando = false;

  List<Institucion> _instituciones = [];
  List<Atleta> _atletas = [];
  // atleta id -> lista de sesiones (mapas con id, inicio, fin)
  final Map<String, List<Map<String, dynamic>>> _sesionesPorAtleta = {};

  // Selección
  bool _catalogos = false;
  final Set<String> _calSel = {};
  final Set<String> _sesSel = {};

  // Expansión visual
  final Set<String> _expInst = {};
  final Set<String> _expAtl = {};
  final Set<String> _expSes = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final inst = await DB.instance.getInstituciones();
    final atl = await DB.instance.getAtletas();
    for (final a in atl) {
      final s = await DB.instance.getResumenSesiones(a.id);
      _sesionesPorAtleta[a.id] = s;
    }
    if (mounted) {
      setState(() {
        _instituciones = inst;
        _atletas = atl;
        _cargando = false;
      });
    }
  }

  List<Atleta> _atletasDe(String idInst) =>
      _atletas.where((a) => a.idInstitucion == idInst).toList();

  List<String> _sesionIdsDe(String idAtl) =>
      (_sesionesPorAtleta[idAtl] ?? []).map((s) => s['id'] as String).toList();

  // ----- Estado tri-state -----
  bool? _estadoAtleta(String idAtl) {
    final sesiones = _sesionIdsDe(idAtl);
    final total = 1 + sesiones.length; // calibración + sesiones
    var sel = _calSel.contains(idAtl) ? 1 : 0;
    sel += sesiones.where(_sesSel.contains).length;
    if (sel == 0) return false;
    if (sel == total) return true;
    return null;
  }

  bool? _estadoInst(String idInst) {
    final atletas = _atletasDe(idInst);
    if (atletas.isEmpty) return false;
    final estados = atletas.map((a) => _estadoAtleta(a.id)).toList();
    if (estados.every((e) => e == true)) return true;
    if (estados.every((e) => e == false)) return false;
    return null;
  }

  bool? _estadoApp() {
    if (_instituciones.isEmpty) return false;
    final estados = _instituciones.map((i) => _estadoInst(i.id)).toList();
    if (estados.every((e) => e == true)) return true;
    if (estados.every((e) => e == false)) return false;
    return null;
  }

  // ----- Toggles con propagación -----
  void _toggleAtleta(String idAtl, bool encender) {
    if (encender) {
      _calSel.add(idAtl);
      _sesSel.addAll(_sesionIdsDe(idAtl));
    } else {
      _calSel.remove(idAtl);
      for (final s in _sesionIdsDe(idAtl)) {
        _sesSel.remove(s);
      }
    }
  }

  void _toggleInst(String idInst, bool encender) {
    for (final a in _atletasDe(idInst)) {
      _toggleAtleta(a.id, encender);
    }
  }

  void _onTapAtleta(String idAtl) {
    setState(() => _toggleAtleta(idAtl, _estadoAtleta(idAtl) != true));
  }

  void _onTapInst(String idInst) {
    setState(() => _toggleInst(idInst, _estadoInst(idInst) != true));
  }

  void _onTapApp() {
    final encender = _estadoApp() != true;
    setState(() {
      for (final i in _instituciones) {
        _toggleInst(i.id, encender);
      }
    });
  }

  bool get _haySeleccion =>
      _catalogos || _calSel.isNotEmpty || _sesSel.isNotEmpty;

  Future<void> _exportar() async {
    setState(() => _exportando = true);
    try {
      final tipo = _estadoApp() == true ? 'app' : 'seleccion';
      final sesionesPorAtleta = {
        for (final e in _sesionesPorAtleta.entries)
          e.key: e.value.map((s) => s['id'] as String).toList()
      };
      final data = await construirExport(
        tipo: tipo,
        catalogos: _catalogos,
        instituciones: _instituciones,
        atletas: _atletas,
        calSel: _calSel,
        sesSel: _sesSel,
        sesionesPorAtleta: sesionesPorAtleta,
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      await compartirJson(data, 'genialisis_atleta_export_$ts.json');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar'),
        backgroundColor: kBg,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : Column(
              children: [
                Expanded(child: _arbol()),
                _barraInferior(),
              ],
            ),
    );
  }

  Widget _arbol() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Catálogos (independiente)
        _fila(
          nivel: 0,
          valor: _catalogos,
          titulo: 'Catálogos',
          subtitulo: 'Tipos de umbral y métrica',
          icono: Icons.category,
          onCheck: () => setState(() => _catalogos = !_catalogos),
        ),
        const Divider(color: Colors.white12),
        // Toda la app
        _fila(
          nivel: 0,
          valor: _estadoApp(),
          titulo: 'Toda la app',
          icono: Icons.smartphone,
          onCheck: _onTapApp,
        ),
        // Instituciones
        ..._instituciones.expand(_filasInstitucion),
      ],
    );
  }

  List<Widget> _filasInstitucion(Institucion inst) {
    final expandido = _expInst.contains(inst.id);
    final filas = <Widget>[
      _fila(
        nivel: 1,
        valor: _estadoInst(inst.id),
        titulo: inst.nombre,
        icono: Icons.apartment,
        expandible: _atletasDe(inst.id).isNotEmpty,
        expandido: expandido,
        onExpand: () => setState(() {
          expandido ? _expInst.remove(inst.id) : _expInst.add(inst.id);
        }),
        onCheck: () => _onTapInst(inst.id),
      ),
    ];
    if (expandido) {
      filas.addAll(_atletasDe(inst.id).expand(_filasAtleta));
    }
    return filas;
  }

  List<Widget> _filasAtleta(Atleta a) {
    final expandido = _expAtl.contains(a.id);
    final sesiones = _sesionesPorAtleta[a.id] ?? [];
    final sesExpandido = _expSes.contains(a.id);
    final filas = <Widget>[
      _fila(
        nivel: 2,
        valor: _estadoAtleta(a.id),
        titulo: a.nombre,
        icono: Icons.person,
        expandible: true,
        expandido: expandido,
        onExpand: () => setState(() {
          expandido ? _expAtl.remove(a.id) : _expAtl.add(a.id);
        }),
        onCheck: () => _onTapAtleta(a.id),
      ),
    ];
    if (expandido) {
      // Calibración
      filas.add(_fila(
        nivel: 3,
        valor: _calSel.contains(a.id),
        titulo: 'Calibración',
        icono: Icons.tune,
        onCheck: () => setState(() {
          _calSel.contains(a.id)
              ? _calSel.remove(a.id)
              : _calSel.add(a.id);
        }),
      ));
      // Sesiones (colapsadas por defecto)
      filas.add(_fila(
        nivel: 3,
        valor: _estadoSesionesAtleta(a.id),
        titulo: 'Sesiones (${sesiones.length})',
        icono: Icons.history,
        expandible: sesiones.isNotEmpty,
        expandido: sesExpandido,
        onExpand: () => setState(() {
          sesExpandido ? _expSes.remove(a.id) : _expSes.add(a.id);
        }),
        onCheck: () => setState(() {
          final ids = _sesionIdsDe(a.id);
          final todas = ids.every(_sesSel.contains);
          if (todas) {
            for (final s in ids) {
              _sesSel.remove(s);
            }
          } else {
            _sesSel.addAll(ids);
          }
        }),
      ));
      if (sesExpandido) {
        for (final s in sesiones) {
          final sid = s['id'] as String;
          filas.add(_fila(
            nivel: 4,
            valor: _sesSel.contains(sid),
            titulo: fmtFecha(s['inicio'] as int),
            icono: Icons.fiber_manual_record,
            onCheck: () => setState(() {
              _sesSel.contains(sid)
                  ? _sesSel.remove(sid)
                  : _sesSel.add(sid);
            }),
          ));
        }
      }
    }
    return filas;
  }

  bool? _estadoSesionesAtleta(String idAtl) {
    final ids = _sesionIdsDe(idAtl);
    if (ids.isEmpty) return false;
    final sel = ids.where(_sesSel.contains).length;
    if (sel == 0) return false;
    if (sel == ids.length) return true;
    return null;
  }

  Widget _fila({
    required int nivel,
    required bool? valor,
    required String titulo,
    String? subtitulo,
    required IconData icono,
    required VoidCallback onCheck,
    bool expandible = false,
    bool expandido = false,
    VoidCallback? onExpand,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: nivel * 18.0, top: 2, bottom: 2),
      child: Row(
        children: [
          Checkbox(
            value: valor,
            tristate: true,
            activeColor: kGold,
            checkColor: Colors.black,
            onChanged: (_) => onCheck(),
          ),
          Icon(icono, color: kGold, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onCheck,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontSize: 14)),
                  if (subtitulo != null)
                    Text(subtitulo,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
          ),
          if (expandible)
            IconButton(
              icon: Icon(
                expandido ? Icons.expand_less : Icons.expand_more,
                color: Colors.white38,
              ),
              onPressed: onExpand,
            ),
        ],
      ),
    );
  }

  Widget _barraInferior() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPanel,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        top: false,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _haySeleccion ? kGold : Colors.white12,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _exportando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.ios_share),
          label: Text(_exportando ? 'Exportando…' : 'Exportar selección'),
          onPressed: (_haySeleccion && !_exportando) ? _exportar : null,
        ),
      ),
    );
  }
}