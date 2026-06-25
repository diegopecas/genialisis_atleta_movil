import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'tema.dart';
import 'modelos.dart';
import 'db.dart';

class AtletasScreen extends StatefulWidget {
  const AtletasScreen({super.key});

  @override
  State<AtletasScreen> createState() => _AtletasScreenState();
}

class _AtletasScreenState extends State<AtletasScreen> {
  List<Atleta> _atletas = [];
  List<Institucion> _instituciones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final inst = await DB.instance.getInstituciones();
    final atl = await DB.instance.getAtletas();
    if (mounted) {
      setState(() {
        _instituciones = inst;
        _atletas = atl;
        _cargando = false;
      });
    }
  }

  String _nombreInstitucion(String id) {
    final i = _instituciones.where((e) => e.id == id);
    return i.isEmpty ? '—' : i.first.nombre;
  }

  Future<void> _nuevoOEditar({Atleta? actual}) async {
    if (_instituciones.isEmpty) {
      _toast('Primero crea una institución', error: true);
      return;
    }
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _AtletaForm(
          instituciones: _instituciones,
          actual: actual,
        ),
      ),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _eliminar(Atleta a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanel,
        title: const Text('Eliminar atleta'),
        content: const Text(
            'Se eliminarán también sus sesiones. Esta acción no se puede deshacer.'),
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
    await DB.instance.deleteAtleta(a.id);
    await _cargar();
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
        title: const Text('Atletas'),
        backgroundColor: kBg,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kGold,
        foregroundColor: Colors.black,
        onPressed: () => _nuevoOEditar(),
        child: const Icon(Icons.add),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _atletas.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay atletas. Agrega el primero con el botón +.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
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
                        subtitle: Text(
                          _nombreInstitucion(a.idInstitucion),
                          style: const TextStyle(color: Colors.white54),
                        ),
                        leading: CircleAvatar(
                          backgroundColor:
                              a.calibrado ? kGold : Colors.white24,
                          foregroundColor: Colors.black,
                          child: Icon(
                            a.calibrado ? Icons.check : Icons.priority_high,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!a.calibrado)
                              const Text('sin calibrar',
                                  style: TextStyle(
                                      color: kDanger, fontSize: 12)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: kDanger),
                              onPressed: () => _eliminar(a),
                            ),
                          ],
                        ),
                        onTap: () => _nuevoOEditar(actual: a),
                      ),
                    );
                  },
                ),
    );
  }
}

class _AtletaForm extends StatefulWidget {
  final List<Institucion> instituciones;
  final Atleta? actual;

  const _AtletaForm({required this.instituciones, this.actual});

  @override
  State<_AtletaForm> createState() => _AtletaFormState();
}

class _AtletaFormState extends State<_AtletaForm> {
  late TextEditingController _nombreCtrl;
  late TextEditingController _idCtrl;
  String? _idInstitucion;
  String? _genero;
  DateTime? _fechaNac;

  @override
  void initState() {
    super.initState();
    final a = widget.actual;
    _nombreCtrl = TextEditingController(text: a?.nombre ?? '');
    _idCtrl = TextEditingController(text: a?.identificacion ?? '');
    _idInstitucion = a?.idInstitucion ??
        (widget.instituciones.isNotEmpty
            ? widget.instituciones.first.id
            : null);
    _genero = a?.genero;
    if (a?.fechaNacimiento != null) {
      _fechaNac = DateTime.tryParse(a!.fechaNacimiento!);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  String _fmtFecha(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _fechaNac ?? DateTime(ahora.year - 12),
      firstDate: DateTime(ahora.year - 80),
      lastDate: ahora,
    );
    if (d != null) setState(() => _fechaNac = d);
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _toast('El nombre es obligatorio', error: true);
      return;
    }
    if (_idInstitucion == null) {
      _toast('Selecciona una institución', error: true);
      return;
    }
    final a = Atleta(
      id: widget.actual?.id ?? const Uuid().v4(),
      idInstitucion: _idInstitucion!,
      nombre: nombre,
      identificacion: _idCtrl.text.trim().isEmpty ? null : _idCtrl.text.trim(),
      genero: _genero,
      fechaNacimiento: _fechaNac == null ? null : _fmtFecha(_fechaNac!),
      calibrado: widget.actual?.calibrado ?? false,
    );
    await DB.instance.upsertAtleta(a);
    if (mounted) Navigator.pop(context, true);
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
        title: Text(widget.actual == null ? 'Nuevo atleta' : 'Editar atleta'),
        backgroundColor: kBg,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _idInstitucion,
            decoration: const InputDecoration(labelText: 'Institución'),
            dropdownColor: kPanel,
            items: widget.instituciones
                .map((i) =>
                    DropdownMenuItem(value: i.id, child: Text(i.nombre)))
                .toList(),
            onChanged: (v) => setState(() => _idInstitucion = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nombreCtrl,
            decoration: const InputDecoration(labelText: 'Nombre completo'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _idCtrl,
            decoration:
                const InputDecoration(labelText: 'Número de identificación'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _genero,
            decoration: const InputDecoration(labelText: 'Género'),
            dropdownColor: kPanel,
            items: const [
              DropdownMenuItem(value: 'Masculino', child: Text('Masculino')),
              DropdownMenuItem(value: 'Femenino', child: Text('Femenino')),
              DropdownMenuItem(value: 'Otro', child: Text('Otro')),
            ],
            onChanged: (v) => setState(() => _genero = v),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _elegirFecha,
            child: InputDecorator(
              decoration:
                  const InputDecoration(labelText: 'Fecha de nacimiento'),
              child: Text(
                _fechaNac == null ? 'Seleccionar' : _fmtFecha(_fechaNac!),
                style: TextStyle(
                  color: _fechaNac == null ? Colors.white38 : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kGold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _guardar,
            child: const Text('Guardar',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}