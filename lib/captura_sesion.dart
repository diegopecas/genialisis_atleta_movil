import 'dart:convert';

import 'package:flutter/material.dart';

import 'tema.dart';
import 'modelos.dart';
import 'db.dart';
import 'captura.dart';
import 'metricas_logica.dart';
import 'calibracion.dart';
import 'widgets_metricas.dart';

enum _Fase {
  cargando,
  sinAtletas,
  seleccion,
  noCalibrado,
  listo,
  capturando,
  procesando,
  resumen,
}

class CapturaSesionScreen extends StatefulWidget {
  const CapturaSesionScreen({super.key});

  @override
  State<CapturaSesionScreen> createState() => _CapturaSesionScreenState();
}

class _CapturaSesionScreenState extends State<CapturaSesionScreen> {
  _Fase _fase = _Fase.cargando;

  List<Institucion> _instituciones = [];
  List<Atleta> _atletas = [];
  Institucion? _inst;
  Atleta? _atleta;
  Map<String, double> _umbrales = {};

  // En vivo
  String _tiempo = '0:00';
  String _vel = '0.0';
  String _dist = '0';

  // Resumen
  List<Map<String, dynamic>> _resumen = [];

  @override
  void initState() {
    super.initState();
    MotorCaptura.instance.onActualizacion = (d) {
      if (!mounted) return;
      setState(() {
        _tiempo = d['tiempo'] as String? ?? _tiempo;
        _vel = d['vel'] as String? ?? _vel;
        _dist = (d['dist'] ?? _dist).toString();
      });
    };
    _cargar();
  }

  @override
  void dispose() {
    MotorCaptura.instance.onActualizacion = null;
    super.dispose();
  }

  Future<void> _cargar() async {
    final inst = await DB.instance.getInstituciones();
    final atl = await DB.instance.getAtletas();
    _instituciones = inst;
    _atletas = atl;

    if (atl.isEmpty) {
      setState(() => _fase = _Fase.sinAtletas);
      return;
    }

    // Resolución inteligente.
    if (inst.length == 1) _inst = inst.first;
    final delInst = _inst == null
        ? atl
        : atl.where((a) => a.idInstitucion == _inst!.id).toList();

    if (_inst != null && delInst.length == 1) {
      await _seleccionarAtleta(delInst.first);
    } else {
      setState(() => _fase = _Fase.seleccion);
    }
  }

  Future<void> _seleccionarAtleta(Atleta a) async {
    _atleta = a;
    _umbrales = await DB.instance.getUmbralesAtleta(a.id);
    setState(() {
      _fase = a.calibrado ? _Fase.listo : _Fase.noCalibrado;
    });
  }

  Future<void> _iniciar() async {
    final ok = await MotorCaptura.instance.pedirPermisos();
    if (!ok) {
      _toast(
          'Faltan permisos: ubicación "Permitir todo el tiempo" y notificaciones',
          error: true);
      return;
    }
    await MotorCaptura.instance.iniciar(etiqueta: _atleta!.nombre);
    setState(() {
      _fase = _Fase.capturando;
      _tiempo = '0:00';
      _vel = '0.0';
      _dist = '0';
    });
  }

  Future<void> _detener() async {
    setState(() => _fase = _Fase.procesando);
    final datos = await MotorCaptura.instance.detener();
    if (!mounted) return;

    if (datos == null) {
      _toast('No se recibieron datos de la captura', error: true);
      setState(() => _fase = _Fase.listo);
      return;
    }

    final metricas = calcularMetricas(datos, _umbrales);

    // Guardado automático.
    await DB.instance.guardarSesion(
      idAtleta: _atleta!.id,
      inicio: datos.inicio,
      fin: datos.fin,
      datosCrudos: jsonEncode(datos.toJson()),
      metricas: metricas.map((m) => m.toMap()).toList(),
    );

    // Para el resumen, leemos los nombres/unidades del catálogo.
    final tipos = await DB.instance.getTiposMetrica();
    final mapNombre = {for (final t in tipos) t.codigo: t};
    final resumen = metricas.map((m) {
      final tipo = mapNombre[m.codigo];
      return {
        'codigo': m.codigo,
        'nombre': tipo?.nombre ?? m.codigo,
        'unidad': tipo?.unidad ?? '',
        'valor': m.valor,
      };
    }).toList();

    setState(() {
      _resumen = resumen;
      _fase = _Fase.resumen;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capturar sesión'),
        backgroundColor: kBg,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _contenido(),
      ),
    );
  }

  Widget _contenido() {
    switch (_fase) {
      case _Fase.cargando:
        return const Center(child: CircularProgressIndicator(color: kGold));

      case _Fase.sinAtletas:
        return const Center(
          child: Text(
            'No hay atletas. Crea y calibra un atleta antes de capturar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        );

      case _Fase.seleccion:
        return _vistaSeleccion();

      case _Fase.noCalibrado:
        return _vistaNoCalibrado();

      case _Fase.listo:
        return _vistaListo();

      case _Fase.capturando:
        return _vistaCapturando();

      case _Fase.procesando:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: kGold),
              SizedBox(height: 16),
              Text('Calculando métricas…',
                  style: TextStyle(color: Colors.white54)),
            ],
          ),
        );

      case _Fase.resumen:
        return _vistaResumen();
    }
  }

  Widget _vistaSeleccion() {
    final delInst = _inst == null
        ? _atletas
        : _atletas.where((a) => a.idInstitucion == _inst!.id).toList();
    return ListView(
      children: [
        const Text('Selecciona el atleta',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        if (_instituciones.length > 1)
          DropdownButtonFormField<String>(
            initialValue: _inst?.id,
            decoration: const InputDecoration(labelText: 'Institución'),
            dropdownColor: kPanel,
            items: _instituciones
                .map((i) =>
                    DropdownMenuItem(value: i.id, child: Text(i.nombre)))
                .toList(),
            onChanged: (v) => setState(() {
              _inst = _instituciones.firstWhere((i) => i.id == v);
            }),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _atleta?.id,
          decoration: const InputDecoration(labelText: 'Atleta'),
          dropdownColor: kPanel,
          items: delInst
              .map((a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(a.calibrado ? a.nombre : '${a.nombre} (sin calibrar)'),
                  ))
              .toList(),
          onChanged: (v) {
            final a = delInst.firstWhere((e) => e.id == v);
            _seleccionarAtleta(a);
          },
        ),
      ],
    );
  }

  Widget _vistaNoCalibrado() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.warning_amber, color: Colors.orange, size: 56),
        const SizedBox(height: 16),
        Text('${_atleta!.nombre} no está calibrado',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
          'Para capturar una sesión, primero hay que calibrar al atleta.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: kGold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          icon: const Icon(Icons.tune),
          label: const Text('Calibrar ahora'),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CalibracionScreen(atleta: _atleta!),
              ),
            );
            // Al volver, recargamos el estado del atleta.
            final atl = await DB.instance.getAtletas();
            final actualizado = atl.firstWhere((a) => a.id == _atleta!.id);
            await _seleccionarAtleta(actualizado);
          },
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _fase = _Fase.seleccion),
          child: const Text('Elegir otro atleta'),
        ),
      ],
    );
  }

  Widget _vistaListo() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Text(_atleta!.nombre,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Calibrado · listo para capturar',
            style: TextStyle(color: kGoldBright)),
        const Spacer(),
        Center(
          child: GestureDetector(
            onTap: _iniciar,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(colors: [kGoldBright, kGold]),
              ),
              child: const Center(
                child: Text('INICIAR',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => setState(() => _fase = _Fase.seleccion),
          child: const Text('Cambiar atleta'),
        ),
      ],
    );
  }

  Widget _vistaCapturando() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Text(_atleta!.nombre,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        Text(_tiempo,
            style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold)),
        const Text('Puedes bloquear el celular',
            style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _vivo('Velocidad', '$_vel km/h'),
            _vivo('Distancia', '$_dist m'),
          ],
        ),
        const Spacer(),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: kDanger,
            padding:
                const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
          ),
          onPressed: _detener,
          child: const Text('Detener',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _vivo(String k, String v) {
    return Column(
      children: [
        Text(k, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 4),
        Text(v,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _vistaResumen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        const Icon(Icons.check_circle, color: kGold, size: 48),
        const SizedBox(height: 8),
        Text('Sesión de ${_atleta!.nombre}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Guardada automáticamente',
            textAlign: TextAlign.center,
            style: TextStyle(color: kGoldBright, fontSize: 13)),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _resumen.map((m) {
                return MetricaCard(
                  nombre: m['nombre'] as String,
                  codigo: m['codigo'] as String,
                  valor: (m['valor'] as num).toDouble(),
                  unidad: (m['unidad'] as String?) ?? '',
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: kGold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => setState(() {
            _fase = _atleta!.calibrado ? _Fase.listo : _Fase.noCalibrado;
          }),
          child: const Text('Nueva captura',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver al inicio'),
        ),
      ],
    );
  }
}