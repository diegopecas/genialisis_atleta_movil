import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

import 'modelos.dart';
import 'db.dart';

/// Construye el JSON de exportación a partir de una selección.
///
/// [calSel]  = ids de atletas cuya calibración se incluye.
/// [sesSel]  = ids de sesiones que se incluyen.
/// Un atleta se exporta si tiene calibración o alguna sesión seleccionada.
Future<Map<String, dynamic>> construirExport({
  required String tipo,
  required bool catalogos,
  required List<Institucion> instituciones,
  required List<Atleta> atletas,
  required Set<String> calSel,
  required Set<String> sesSel,
  required Map<String, List<String>> sesionesPorAtleta,
}) async {
  final out = <String, dynamic>{
    'exportado_en': DateTime.now().toIso8601String(),
    'tipo': tipo,
  };

  if (catalogos) {
    final tu = await DB.instance.getTiposUmbral();
    final tm = await DB.instance.getTiposMetrica();
    out['catalogos'] = {
      'tipos_umbral': tu
          .map((e) => {
                'codigo': e.codigo,
                'nombre': e.nombre,
                'descripcion': e.descripcion,
              })
          .toList(),
      'tipos_metrica': tm
          .map((e) => {
                'codigo': e.codigo,
                'nombre': e.nombre,
                'unidad': e.unidad,
              })
          .toList(),
    };
  }

  final instList = <Map<String, dynamic>>[];

  for (final inst in instituciones) {
    final atlsInst = atletas.where((a) => a.idInstitucion == inst.id).toList();
    final atlExport = <Map<String, dynamic>>[];

    for (final a in atlsInst) {
      final incluirCal = calSel.contains(a.id);
      final sesionesDeA =
          (sesionesPorAtleta[a.id] ?? []).where(sesSel.contains).toList();

      if (!incluirCal && sesionesDeA.isEmpty) continue;

      final am = <String, dynamic>{
        'id': a.id,
        'nombre': a.nombre,
        'identificacion': a.identificacion,
        'genero': a.genero,
        'fecha_nacimiento': a.fechaNacimiento,
        'calibrado': a.calibrado,
      };

      if (incluirCal) {
        final umbrales = await DB.instance.getUmbralesAtleta(a.id);
        am['umbrales'] = umbrales.entries
            .map((e) => {'codigo': e.key, 'valor': e.value})
            .toList();
      }

      final sesList = <Map<String, dynamic>>[];
      for (final sid in sesionesDeA) {
        final row = await DB.instance.getSesion(sid);
        if (row == null) continue;
        final mets = await DB.instance.getMetricasSesion(sid);
        final crudosStr = row['datos_crudos'] as String?;
        sesList.add({
          'id': sid,
          'inicio': row['inicio'],
          'fin': row['fin'],
          'metricas': mets
              .map((m) => {
                    'codigo': m['codigo'],
                    'valor': m['valor'],
                    'umbral_usado': m['umbral_usado'],
                  })
              .toList(),
          'datos_crudos':
              crudosStr != null ? jsonDecode(crudosStr) : null,
        });
      }
      am['sesiones'] = sesList;
      atlExport.add(am);
    }

    if (atlExport.isNotEmpty) {
      instList.add({
        'id': inst.id,
        'nombre': inst.nombre,
        'tenant_genialisis': inst.tenantGenialisis,
        'atletas': atlExport,
      });
    }
  }

  out['instituciones'] = instList;
  return out;
}

/// Escribe el JSON a un archivo temporal y abre el menú de compartir.
Future<void> compartirJson(
    Map<String, dynamic> data, String nombreArchivo) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$nombreArchivo');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  await Share.shareXFiles([XFile(f.path)],
      text: 'Exportación GENIALISIS Atleta');
}

/// Exporta una sola sesión (usado desde el detalle de la sesión).
Future<void> exportarSesionUnica(Atleta atleta, String idSesion) async {
  final inst = await DB.instance.getInstituciones();
  final institucion = inst.where((i) => i.id == atleta.idInstitucion).toList();
  final data = await construirExport(
    tipo: 'sesion',
    catalogos: false,
    instituciones: institucion,
    atletas: [atleta],
    calSel: {},
    sesSel: {idSesion},
    sesionesPorAtleta: {
      atleta.id: [idSesion]
    },
  );
  await compartirJson(
      data, 'sesion_${atleta.nombre}_$idSesion.json'.replaceAll(' ', '_'));
}