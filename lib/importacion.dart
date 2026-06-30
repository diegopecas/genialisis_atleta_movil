import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'tema.dart';
import 'db.dart';
import 'widgets_metricas.dart';
import 'importacion_logica.dart';

class ImportacionScreen extends StatefulWidget {
  const ImportacionScreen({super.key});

  @override
  State<ImportacionScreen> createState() => _ImportacionScreenState();
}

class _ImportacionScreenState extends State<ImportacionScreen> {
  Map<String, dynamic>? _archivo;
  ExistenciaImport? _existe;
  bool _procesando = false;

  // Selecciones
  final Set<String> _cargar = {};
  final Set<String> _reemplazar = {};

  // Expansión
  final Set<String> _exp = {};

  Future<void> _elegirArchivo() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (res == null || res.files.single.path == null) return;
    try {
      final txt = await File(res.files.single.path!).readAsString();
      final data = jsonDecode(txt) as Map<String, dynamic>;
      final existe = await ExistenciaImport.cargar();
      setState(() {
        _archivo = data;
        _existe = existe;
        _cargar.clear();
        _reemplazar.clear();
        _exp.clear();
      });
      _marcarTodoPorDefecto();
    } catch (e) {
      _toast('Archivo inválido: $e', error: true);
    }
  }

  // Por defecto: todo marcado para Cargar y (si existe) Reemplazar.
  void _marcarTodoPorDefecto() {
    final a = _archivo!;
    final ex = _existe!;
    final cat = a['catalogos'] as Map<String, dynamic>?;
    if (cat != null) {
      if ((cat['tipos_umbral'] as List?)?.isNotEmpty ?? false) {
        _cargar.add('cat_tu');
        _reemplazar.add('cat_tu');
      }
      if ((cat['tipos_metrica'] as List?)?.isNotEmpty ?? false) {
        _cargar.add('cat_tm');
        _reemplazar.add('cat_tm');
      }
    }
    for (final inst in (a['instituciones'] as List? ?? [])) {
      final idInst = inst['id'] as String;
      _cargar.add('inst:$idInst');
      if (ex.instituciones.contains(idInst)) _reemplazar.add('inst:$idInst');
      for (final atl in (inst['atletas'] as List? ?? [])) {
        final idAtl = atl['id'] as String;
        _cargar.add('atl:$idAtl');
        if (ex.atletas.contains(idAtl)) _reemplazar.add('atl:$idAtl');
        if ((atl['umbrales'] as List?)?.isNotEmpty ?? false) {
          _cargar.add('cal:$idAtl');
          if (ex.atletasConCalibracion.contains(idAtl)) {
            _reemplazar.add('cal:$idAtl');
          }
        }
        for (final s in (atl['sesiones'] as List? ?? [])) {
          final idSes = s['id'] as String;
          _cargar.add('ses:$idSes');
          if (ex.sesiones.contains(idSes)) _reemplazar.add('ses:$idSes');
        }
      }
    }
    setState(() {});
  }

  Future<void> _importar() async {
    setState(() => _procesando = true);
    try {
      final res = await aplicarImportacion(
        archivo: _archivo!,
        cargar: _cargar,
        reemplazar: _reemplazar,
        existe: _existe!,
      );
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kPanel,
            title: const Text('Importación completa'),
            content: Text(
              'Instituciones: ${res.instituciones}\n'
              'Atletas: ${res.atletas}\n'
              'Calibraciones: ${res.calibraciones}\n'
              'Sesiones: ${res.sesiones}\n'
              'Catálogos: ${res.catalogos}',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: kGold),
                child: const Text('Listo'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _toast('Error al importar: $e', error: true);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? kDanger : kPanel,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------- selección con propagación ----------
  void _setCargar(List<String> claves, bool on) {
    setState(() {
      for (final k in claves) {
        on ? _cargar.add(k) : _cargar.remove(k);
      }
    });
  }

  void _setReemplazar(List<String> claves, bool on) {
    setState(() {
      for (final k in claves) {
        on ? _reemplazar.add(k) : _reemplazar.remove(k);
      }
    });
  }

  bool? _tri(List<String> claves, Set<String> conjunto) {
    if (claves.isEmpty) return false;
    final n = claves.where(conjunto.contains).length;
    if (n == 0) return false;
    if (n == claves.length) return true;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar'), backgroundColor: kBg),
      body: _archivo == null
          ? _vistaElegir()
          : Column(
              children: [
                Expanded(child: _arbol()),
                _barraInferior(),
              ],
            ),
    );
  }

  Widget _vistaElegir() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.upload_file, color: kGold, size: 56),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Elige un archivo JSON exportado para ver qué contiene e importarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kGold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            icon: const Icon(Icons.folder_open),
            label: const Text('Elegir archivo'),
            onPressed: _elegirArchivo,
          ),
        ],
      ),
    );
  }

  Widget _arbol() {
    final a = _archivo!;
    final filas = <Widget>[];

    // Catálogos
    final cat = a['catalogos'] as Map<String, dynamic>?;
    if (cat != null) {
      filas.add(const Padding(
        padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Text('CATÁLOGOS',
            style: TextStyle(
                color: kGold, fontSize: 11, letterSpacing: 2)),
      ));
      if ((cat['tipos_umbral'] as List?)?.isNotEmpty ?? false) {
        filas.add(_fila(
          nivel: 0,
          clave: 'cat_tu',
          titulo: 'Tipos de umbral',
          icono: Icons.tune,
          existe: _existe!.tiposUmbral.isNotEmpty,
        ));
      }
      if ((cat['tipos_metrica'] as List?)?.isNotEmpty ?? false) {
        filas.add(_fila(
          nivel: 0,
          clave: 'cat_tm',
          titulo: 'Tipos de métrica',
          icono: Icons.analytics,
          existe: _existe!.tiposMetrica.isNotEmpty,
        ));
      }
      filas.add(const Divider(color: Colors.white12));
    }

    filas.add(const Padding(
      padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Text('DATOS',
          style:
              TextStyle(color: kGold, fontSize: 11, letterSpacing: 2)),
    ));

    for (final inst in (a['instituciones'] as List? ?? [])) {
      filas.addAll(_filasInstitucion(Map<String, dynamic>.from(inst)));
    }

    return ListView(padding: const EdgeInsets.all(8), children: filas);
  }

  List<Widget> _filasInstitucion(Map<String, dynamic> inst) {
    final id = inst['id'] as String;
    final key = 'inst:$id';
    final atletas = (inst['atletas'] as List? ?? []);
    // claves descendientes para propagación
    final desc = <String>[key];
    final descExist = <String>[];
    for (final atl in atletas) {
      desc.addAll(_clavesAtleta(Map<String, dynamic>.from(atl)));
    }
    for (final k in desc) {
      if (_existeClave(k)) descExist.add(k);
    }

    final expandido = _exp.contains(key);
    final filas = <Widget>[
      _filaCompuesta(
        nivel: 0,
        titulo: inst['nombre'] as String,
        icono: Icons.apartment,
        clavesCargar: desc,
        clavesReemplazar: descExist,
        existe: _existe!.instituciones.contains(id),
        expandible: atletas.isNotEmpty,
        expandido: expandido,
        onExpand: () => setState(() =>
            expandido ? _exp.remove(key) : _exp.add(key)),
      ),
    ];
    if (expandido) {
      for (final atl in atletas) {
        filas.addAll(_filasAtleta(Map<String, dynamic>.from(atl)));
      }
    }
    return filas;
  }

  List<String> _clavesAtleta(Map<String, dynamic> atl) {
    final idAtl = atl['id'] as String;
    final claves = <String>['atl:$idAtl'];
    if ((atl['umbrales'] as List?)?.isNotEmpty ?? false) {
      claves.add('cal:$idAtl');
    }
    for (final s in (atl['sesiones'] as List? ?? [])) {
      claves.add('ses:${s['id']}');
    }
    return claves;
  }

  bool _existeClave(String k) {
    final ex = _existe!;
    if (k.startsWith('inst:')) return ex.instituciones.contains(k.substring(5));
    if (k.startsWith('atl:')) return ex.atletas.contains(k.substring(4));
    if (k.startsWith('cal:')) {
      return ex.atletasConCalibracion.contains(k.substring(4));
    }
    if (k.startsWith('ses:')) return ex.sesiones.contains(k.substring(4));
    return false;
  }

  List<Widget> _filasAtleta(Map<String, dynamic> atl) {
    final idAtl = atl['id'] as String;
    final key = 'atl:$idAtl';
    final claves = _clavesAtleta(atl);
    final clavesExist = claves.where(_existeClave).toList();
    final expandido = _exp.contains(key);

    final filas = <Widget>[
      _filaCompuesta(
        nivel: 1,
        titulo: atl['nombre'] as String,
        icono: Icons.person,
        clavesCargar: claves,
        clavesReemplazar: clavesExist,
        existe: _existe!.atletas.contains(idAtl),
        expandible: true,
        expandido: expandido,
        onExpand: () => setState(
            () => expandido ? _exp.remove(key) : _exp.add(key)),
      ),
    ];

    if (expandido) {
      if ((atl['umbrales'] as List?)?.isNotEmpty ?? false) {
        filas.add(_fila(
          nivel: 2,
          clave: 'cal:$idAtl',
          titulo: 'Calibración',
          icono: Icons.tune,
          existe: _existe!.atletasConCalibracion.contains(idAtl),
        ));
      }
      final sesiones = (atl['sesiones'] as List? ?? []);
      for (final s in sesiones) {
        final idSes = s['id'] as String;
        filas.add(_fila(
          nivel: 2,
          clave: 'ses:$idSes',
          titulo: fmtFecha(s['inicio'] as int),
          icono: Icons.history,
          existe: _existe!.sesiones.contains(idSes),
        ));
      }
    }
    return filas;
  }

  // Fila de una hoja (una sola clave).
  Widget _fila({
    required int nivel,
    required String clave,
    required String titulo,
    required IconData icono,
    required bool existe,
  }) {
    return _filaCompuesta(
      nivel: nivel,
      titulo: titulo,
      icono: icono,
      clavesCargar: [clave],
      clavesReemplazar: existe ? [clave] : [],
      existe: existe,
    );
  }

  // Fila que controla una o varias claves (para propagación en padres).
  Widget _filaCompuesta({
    required int nivel,
    required String titulo,
    required IconData icono,
    required List<String> clavesCargar,
    required List<String> clavesReemplazar,
    required bool existe,
    bool expandible = false,
    bool expandido = false,
    VoidCallback? onExpand,
  }) {
    final cargarVal = _tri(clavesCargar, _cargar);
    final reempVal =
        clavesReemplazar.isEmpty ? null : _tri(clavesReemplazar, _reemplazar);

    return Padding(
      padding: EdgeInsets.only(left: nivel * 16.0, top: 1, bottom: 1),
      child: Row(
        children: [
          Checkbox(
            value: cargarVal,
            tristate: true,
            activeColor: kGold,
            checkColor: Colors.black,
            onChanged: (_) => _setCargar(clavesCargar, cargarVal != true),
          ),
          Icon(icono, color: kGold, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(titulo,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
          if (existe)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Reemp.',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                Checkbox(
                  value: reempVal,
                  tristate: true,
                  activeColor: kGoldBright,
                  checkColor: Colors.black,
                  onChanged: (_) =>
                      _setReemplazar(clavesReemplazar, reempVal != true),
                ),
              ],
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('nuevo',
                  style: TextStyle(color: kGoldBright, fontSize: 11)),
            ),
          if (expandible)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(expandido ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white38),
              onPressed: onExpand,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _barraInferior() {
    final hay = _cargar.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPanel,
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        top: false,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: hay ? kGold : Colors.white12,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _procesando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.download),
          label: Text(_procesando ? 'Importando…' : 'Importar selección'),
          onPressed: (hay && !_procesando) ? _importar : null,
        ),
      ),
    );
  }
}