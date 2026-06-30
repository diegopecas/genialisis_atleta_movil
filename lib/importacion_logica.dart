import 'db.dart';

/// Resultado resumido de una importación.
class ResultadoImport {
  int instituciones = 0;
  int atletas = 0;
  int calibraciones = 0;
  int sesiones = 0;
  int catalogos = 0;
}

/// Estado de existencia de los datos del archivo respecto a la base actual.
class ExistenciaImport {
  final Set<String> instituciones;
  final Set<String> atletas;
  final Set<String> sesiones;
  final Set<String> atletasConCalibracion;
  final Set<String> tiposUmbral;
  final Set<String> tiposMetrica;

  ExistenciaImport({
    required this.instituciones,
    required this.atletas,
    required this.sesiones,
    required this.atletasConCalibracion,
    required this.tiposUmbral,
    required this.tiposMetrica,
  });

  static Future<ExistenciaImport> cargar() async {
    return ExistenciaImport(
      instituciones: await DB.instance.idsInstituciones(),
      atletas: await DB.instance.idsAtletas(),
      sesiones: await DB.instance.idsSesiones(),
      atletasConCalibracion: await DB.instance.atletasConCalibracion(),
      tiposUmbral: await DB.instance.codigosTipoUmbral(),
      tiposMetrica: await DB.instance.codigosTipoMetrica(),
    );
  }
}

/// Aplica la importación según las selecciones del árbol.
/// [cargar] = claves de nodos a importar.
/// [reemplazar] = claves de nodos existentes que deben sobrescribirse.
/// Claves: inst:{id} atl:{id} cal:{atlId} ses:{id} cat_tu cat_tm
Future<ResultadoImport> aplicarImportacion({
  required Map<String, dynamic> archivo,
  required Set<String> cargar,
  required Set<String> reemplazar,
  required ExistenciaImport existe,
}) async {
  final res = ResultadoImport();

  // --- Catálogos ---
  final catalogos = archivo['catalogos'] as Map<String, dynamic>?;
  if (catalogos != null) {
    if (cargar.contains('cat_tu')) {
      for (final tu in (catalogos['tipos_umbral'] as List? ?? [])) {
        final codigo = tu['codigo'] as String;
        final yaEsta = existe.tiposUmbral.contains(codigo);
        if (!yaEsta || reemplazar.contains('cat_tu')) {
          await DB.instance.importarTipoUmbral(Map<String, dynamic>.from(tu));
          res.catalogos++;
        }
      }
    }
    if (cargar.contains('cat_tm')) {
      for (final tm in (catalogos['tipos_metrica'] as List? ?? [])) {
        final codigo = tm['codigo'] as String;
        final yaEsta = existe.tiposMetrica.contains(codigo);
        if (!yaEsta || reemplazar.contains('cat_tm')) {
          await DB.instance.importarTipoMetrica(Map<String, dynamic>.from(tm));
          res.catalogos++;
        }
      }
    }
  }

  // --- Instituciones > atletas > calibración + sesiones ---
  for (final inst in (archivo['instituciones'] as List? ?? [])) {
    final instMap = Map<String, dynamic>.from(inst);
    final idInst = instMap['id'] as String;
    final instKey = 'inst:$idInst';
    final instExiste = existe.instituciones.contains(idInst);

    // Aplicar institución si está marcada para cargar.
    if (cargar.contains(instKey)) {
      if (!instExiste || reemplazar.contains(instKey)) {
        await DB.instance.importarInstitucion(instMap);
        res.instituciones++;
      }
    }

    for (final atl in (instMap['atletas'] as List? ?? [])) {
      final atlMap = Map<String, dynamic>.from(atl);
      final idAtl = atlMap['id'] as String;
      final atlKey = 'atl:$idAtl';
      final calKey = 'cal:$idAtl';
      final atlExiste = existe.atletas.contains(idAtl);

      final cargarAtl = cargar.contains(atlKey);
      final tieneUmbrales = (atlMap['umbrales'] as List?)?.isNotEmpty ?? false;
      final cargarCal = cargar.contains(calKey) && tieneUmbrales;

      final sesionesArchivo = (atlMap['sesiones'] as List? ?? []);
      final sesionesSel = sesionesArchivo
          .where((s) => cargar.contains('ses:${s['id']}'))
          .toList();

      final necesitaAtleta =
          cargarAtl || cargarCal || sesionesSel.isNotEmpty;
      if (!necesitaAtleta) continue;

      // Garantizar institución (FK).
      await DB.instance.ensureInstitucion(instMap);

      // Aplicar atleta.
      if (cargarAtl) {
        if (!atlExiste || reemplazar.contains(atlKey)) {
          await DB.instance.importarAtleta(idInst, atlMap);
          res.atletas++;
        }
      } else {
        await DB.instance.ensureAtleta(idInst, atlMap); // FK para hijos
      }

      // Calibración.
      if (cargarCal) {
        final calExiste = existe.atletasConCalibracion.contains(idAtl);
        if (!calExiste || reemplazar.contains(calKey)) {
          await DB.instance
              .importarCalibracion(idAtl, atlMap['umbrales'] as List);
          res.calibraciones++;
        }
      }

      // Sesiones.
      for (final s in sesionesSel) {
        final sMap = Map<String, dynamic>.from(s);
        final idSes = sMap['id'] as String;
        final sesExiste = existe.sesiones.contains(idSes);
        if (!sesExiste || reemplazar.contains('ses:$idSes')) {
          await DB.instance.importarSesion(idAtl, sMap);
          res.sesiones++;
        }
      }
    }
  }

  return res;
}