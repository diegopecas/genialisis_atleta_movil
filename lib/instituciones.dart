import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'tema.dart';
import 'modelos.dart';
import 'db.dart';

class InstitucionesScreen extends StatefulWidget {
  const InstitucionesScreen({super.key});

  @override
  State<InstitucionesScreen> createState() => _InstitucionesScreenState();
}

class _InstitucionesScreenState extends State<InstitucionesScreen> {
  List<Institucion> _lista = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final lista = await DB.instance.getInstituciones();
    if (mounted) {
      setState(() {
        _lista = lista;
        _cargando = false;
      });
    }
  }

  Future<void> _editar({Institucion? actual}) async {
    final nombreCtrl = TextEditingController(text: actual?.nombre ?? '');
    final tenantCtrl =
        TextEditingController(text: actual?.tenantGenialisis ?? '');

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanel,
        title: Text(actual == null ? 'Nueva institución' : 'Editar institución'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tenantCtrl,
              decoration: const InputDecoration(
                labelText: 'Tenant GENIALISIS',
                hintText: 'Identificador del tenant',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: kGold),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (guardar != true) return;
    final nombre = nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _toast('El nombre es obligatorio', error: true);
      return;
    }
    final inst = Institucion(
      id: actual?.id ?? const Uuid().v4(),
      nombre: nombre,
      tenantGenialisis: tenantCtrl.text.trim().isEmpty
          ? null
          : tenantCtrl.text.trim(),
    );
    await DB.instance.upsertInstitucion(inst);
    await _cargar();
  }

  Future<void> _eliminar(Institucion i) async {
    final cuantos = await DB.instance.contarAtletas(i.id);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanel,
        title: const Text('Eliminar institución'),
        content: Text(
          cuantos > 0
              ? 'Tiene $cuantos atleta(s) que también se eliminarán. Esta acción no se puede deshacer.'
              : 'Esta acción no se puede deshacer.',
        ),
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
    await DB.instance.deleteInstitucion(i.id);
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
        title: const Text('Instituciones'),
        backgroundColor: kBg,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kGold,
        foregroundColor: Colors.black,
        onPressed: () => _editar(),
        child: const Icon(Icons.add),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _lista.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay instituciones. Agrega la primera con el botón +.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _lista.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final inst = _lista[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07)),
                      ),
                      child: ListTile(
                        title: Text(inst.nombre,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          inst.tenantGenialisis == null
                              ? 'Sin tenant'
                              : 'Tenant: ${inst.tenantGenialisis}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        onTap: () => _editar(actual: inst),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: kDanger),
                          onPressed: () => _eliminar(inst),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}