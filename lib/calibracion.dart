import 'package:flutter/material.dart';

import 'tema.dart';
import 'modelos.dart';
import 'db.dart';
import 'captura.dart';
import 'calibracion_logica.dart';

class CalibracionScreen extends StatefulWidget {
  final Atleta atleta;
  const CalibracionScreen({super.key, required this.atleta});

  @override
  State<CalibracionScreen> createState() => _CalibracionScreenState();
}

class _CalibracionScreenState extends State<CalibracionScreen> {
  Map<String, double> _umbrales = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final u = await DB.instance.getUmbralesAtleta(widget.atleta.id);
    if (mounted) {
      setState(() {
        _umbrales = u;
        _cargando = false;
      });
    }
  }

  Future<void> _abrirPrueba(String tipo) async {
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _PruebaGuiadaScreen(
          atleta: widget.atleta,
          tipo: tipo,
        ),
      ),
    );
    if (guardado == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibración'),
        backgroundColor: kBg,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.atleta.nombre,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Cada prueba se puede repetir si no quedó bien.',
                  style: TextStyle(color: Colors.white54),
                ),
                const SizedBox(height: 20),
                _PruebaCard(
                  icono: Icons.height,
                  titulo: 'Salto',
                  descripcion: 'Mide la fuerza de tus saltos',
                  valor: _umbrales['SALTO'],
                  unidad: 'm/s²',
                  onTap: () => _abrirPrueba('SALTO'),
                ),
                const SizedBox(height: 12),
                _PruebaCard(
                  icono: Icons.speed,
                  titulo: 'Velocidad',
                  descripcion: 'Mide tu velocidad máxima',
                  valor: _umbrales['SPRINT'],
                  unidad: 'm/s',
                  onTap: () => _abrirPrueba('SPRINT'),
                ),
                const SizedBox(height: 12),
                _PruebaCard(
                  icono: Icons.bolt,
                  titulo: 'Aceleración',
                  descripcion: 'Mide tus arranques y frenazos',
                  valor: _umbrales['ACELERACION'],
                  unidad: 'm/s²',
                  onTap: () => _abrirPrueba('ACELERACION'),
                ),
                const SizedBox(height: 24),
                if (_umbrales.length >= 3)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kGold.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: kGold),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Atleta calibrado. Ya puede capturar sesiones.',
                            style: TextStyle(color: kGoldBright),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PruebaCard extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final double? valor;
  final String unidad;
  final VoidCallback onTap;

  const _PruebaCard({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.valor,
    required this.unidad,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hecho = valor != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hecho
                ? kGold.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(icono, color: hecho ? kGold : Colors.white38, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    hecho
                        ? 'Calibrado: ${valor!.toStringAsFixed(valor! < 10 ? 2 : 1)} $unidad'
                        : descripcion,
                    style: TextStyle(
                      color: hecho ? kGoldBright : Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (hecho)
              const Icon(Icons.check_circle, color: kGold)
            else
              const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Flujo guiado de una prueba
// ---------------------------------------------------------------------

enum _Estado { instrucciones, capturando, procesando, resultado }

class _PruebaGuiadaScreen extends StatefulWidget {
  final Atleta atleta;
  final String tipo; // SALTO | SPRINT | ACELERACION
  const _PruebaGuiadaScreen({required this.atleta, required this.tipo});

  @override
  State<_PruebaGuiadaScreen> createState() => _PruebaGuiadaScreenState();
}

class _PruebaGuiadaScreenState extends State<_PruebaGuiadaScreen> {
  _Estado _estado = _Estado.instrucciones;
  String _tiempo = '0:00';
  ResultadoUmbral? _resultado;

  @override
  void initState() {
    super.initState();
    MotorCaptura.instance.onActualizacion = (d) {
      if (!mounted) return;
      setState(() => _tiempo = d['tiempo'] as String? ?? _tiempo);
    };
  }

  @override
  void dispose() {
    MotorCaptura.instance.onActualizacion = null;
    super.dispose();
  }

  String get _titulo {
    switch (widget.tipo) {
      case 'SALTO':
        return 'Calibrar salto';
      case 'SPRINT':
        return 'Calibrar velocidad';
      default:
        return 'Calibrar aceleración';
    }
  }

  String get _instrucciones {
    switch (widget.tipo) {
      case 'SALTO':
        return 'Ponte el celular en la pechera.\n\n'
            'Al comenzar, puedes bloquear la pantalla. '
            'Haz 5 saltos lo más fuertes que puedas, con una pausa entre cada uno.\n\n'
            'Al terminar, desbloquea y presiona Detener.';
      case 'SPRINT':
        return 'Ponte el celular en la pechera.\n\n'
            'Al comenzar, puedes bloquear la pantalla. '
            'Corre lo más rápido que puedas unos 20-30 metros.\n\n'
            'Al terminar, desbloquea y presiona Detener.';
      default:
        return 'Ponte el celular en la pechera.\n\n'
            'Al comenzar, puedes bloquear la pantalla. '
            'Arranca a correr lo más fuerte que puedas unos 5-10 metros y frena en seco. '
            'Repite 3 veces.\n\n'
            'Al terminar, desbloquea y presiona Detener.';
    }
  }

  Future<void> _comenzar() async {
    final ok = await MotorCaptura.instance.pedirPermisos();
    if (!ok) {
      _toast(
          'Faltan permisos: ubicación "Permitir todo el tiempo" y notificaciones',
          error: true);
      return;
    }
    await MotorCaptura.instance.iniciar(etiqueta: _titulo);
    if (mounted) {
      setState(() {
        _estado = _Estado.capturando;
        _tiempo = '0:00';
      });
    }
  }

  Future<void> _detener() async {
    setState(() => _estado = _Estado.procesando);
    final datos = await MotorCaptura.instance.detener();
    if (!mounted) return;

    if (datos == null) {
      setState(() {
        _estado = _Estado.resultado;
        _resultado = ResultadoUmbral(
            0, 'No se recibieron datos. Revisa permisos y reintenta.',
            confiable: false);
      });
      return;
    }

    ResultadoUmbral res;
    if (widget.tipo == 'SALTO') {
      final n = await _preguntarSaltos();
      if (n == null) {
        // canceló: vuelve a instrucciones
        setState(() => _estado = _Estado.instrucciones);
        return;
      }
      res = calcularUmbralSalto(datos.motion, n);
    } else if (widget.tipo == 'SPRINT') {
      res = calcularUmbralSprint(datos.gps);
    } else {
      res = calcularUmbralAceleracion(datos.gps);
    }

    setState(() {
      _estado = _Estado.resultado;
      _resultado = res;
    });
  }

  Future<int?> _preguntarSaltos() async {
    final ctrl = TextEditingController(text: '5');
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanel,
        title: const Text('¿Cuántos saltos hiciste?'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Número de saltos'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, (n != null && n > 0) ? n : null);
            },
            style: TextButton.styleFrom(foregroundColor: kGold),
            child: const Text('Calcular'),
          ),
        ],
      ),
    );
  }

  Future<void> _guardar() async {
    final res = _resultado;
    if (res == null) return;
    await DB.instance.setUmbralAtleta(widget.atleta.id, widget.tipo, res.valor);
    if (mounted) Navigator.pop(context, true);
  }

  void _reintentar() {
    setState(() {
      _estado = _Estado.instrucciones;
      _resultado = null;
      _tiempo = '0:00';
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
        title: Text(_titulo),
        backgroundColor: kBg,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _contenido(),
      ),
    );
  }

  Widget _contenido() {
    switch (_estado) {
      case _Estado.instrucciones:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Text(_instrucciones,
                style: const TextStyle(fontSize: 16, height: 1.5)),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _comenzar,
              child: const Text('Comenzar',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        );

      case _Estado.capturando:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Capturando…',
                style: TextStyle(color: kGoldBright, fontSize: 18)),
            const SizedBox(height: 8),
            Text(_tiempo,
                style: const TextStyle(
                    fontSize: 48, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Puedes bloquear el celular',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 40),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kDanger,
                padding: const EdgeInsets.symmetric(
                    vertical: 16, horizontal: 40),
              ),
              onPressed: _detener,
              child: const Text('Detener',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        );

      case _Estado.procesando:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: kGold),
              SizedBox(height: 16),
              Text('Procesando…', style: TextStyle(color: Colors.white54)),
            ],
          ),
        );

      case _Estado.resultado:
        final res = _resultado!;
        final ok = res.valor > 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Icon(
              ok
                  ? (res.confiable ? Icons.check_circle : Icons.warning_amber)
                  : Icons.error_outline,
              color: ok ? (res.confiable ? kGold : Colors.orange) : kDanger,
              size: 56,
            ),
            const SizedBox(height: 16),
            if (ok)
              Text(
                'Umbral: ${res.valor.toStringAsFixed(res.valor < 10 ? 2 : 1)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(res.detalle,
                  style: const TextStyle(fontSize: 14, height: 1.4)),
            ),
            if (!res.confiable && ok) ...[
              const SizedBox(height: 12),
              const Text(
                'El resultado no se ve confiable. Te recomiendo reintentar.',
                style: TextStyle(color: Colors.orange),
              ),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _reintentar,
                    child: const Text('Reintentar'),
                  ),
                ),
                if (ok) const SizedBox(width: 12),
                if (ok)
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kGold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _guardar,
                      child: const Text('Guardar',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ],
        );
    }
  }
}