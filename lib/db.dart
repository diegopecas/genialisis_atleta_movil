import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'modelos.dart';

class DB {
  DB._();
  static final DB instance = DB._();
  static Database? _db;

  Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final ruta = p.join(await getDatabasesPath(), 'genialisis_atleta.db');
    return openDatabase(
      ruta,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE instituciones(
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        tenant_genialisis TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE atletas(
        id TEXT PRIMARY KEY,
        id_institucion TEXT NOT NULL,
        nombre TEXT NOT NULL,
        identificacion TEXT,
        genero TEXT,
        fecha_nacimiento TEXT,
        calibrado INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (id_institucion) REFERENCES instituciones(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE tipos_umbral(
        id_umbral INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo TEXT NOT NULL UNIQUE,
        nombre TEXT NOT NULL,
        descripcion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE atletas_umbrales(
        id TEXT PRIMARY KEY,
        id_atleta TEXT NOT NULL,
        id_umbral INTEGER NOT NULL,
        valor REAL NOT NULL,
        FOREIGN KEY (id_atleta) REFERENCES atletas(id) ON DELETE CASCADE,
        FOREIGN KEY (id_umbral) REFERENCES tipos_umbral(id_umbral)
      )
    ''');

    await db.execute('''
      CREATE TABLE tipos_metrica(
        id_metrica INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo TEXT NOT NULL UNIQUE,
        nombre TEXT NOT NULL,
        unidad TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sesiones(
        id TEXT PRIMARY KEY,
        id_atleta TEXT NOT NULL,
        inicio INTEGER NOT NULL,
        fin INTEGER NOT NULL,
        datos_crudos TEXT,
        FOREIGN KEY (id_atleta) REFERENCES atletas(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE sesiones_metricas(
        id TEXT PRIMARY KEY,
        id_sesion TEXT NOT NULL,
        id_metrica INTEGER NOT NULL,
        valor REAL NOT NULL,
        umbral_usado REAL,
        FOREIGN KEY (id_sesion) REFERENCES sesiones(id) ON DELETE CASCADE,
        FOREIGN KEY (id_metrica) REFERENCES tipos_metrica(id_metrica)
      )
    ''');

    await _precargarCatalogos(db);
  }

  // Catálogos iniciales. A futuro se sincronizarán desde la API de GENIALISIS.
  Future<void> _precargarCatalogos(Database db) async {
    const umbrales = [
      {
        'codigo': 'SALTO',
        'nombre': 'Salto',
        'descripcion': 'Magnitud de aceleración de aterrizaje (m/s²)'
      },
      {
        'codigo': 'SPRINT',
        'nombre': 'Sprint',
        'descripcion': 'Velocidad mínima para contar un sprint (m/s)'
      },
      {
        'codigo': 'ACELERACION',
        'nombre': 'Aceleración',
        'descripcion': 'Aceleración/desaceleración fuerte (m/s²)'
      },
    ];
    for (final u in umbrales) {
      await db.insert('tipos_umbral', u);
    }

    const metricas = [
      {'codigo': 'DISTANCIA', 'nombre': 'Distancia recorrida', 'unidad': 'm'},
      {'codigo': 'VEL_MAX', 'nombre': 'Velocidad máxima', 'unidad': 'km/h'},
      {'codigo': 'VEL_PROM', 'nombre': 'Velocidad promedio', 'unidad': 'km/h'},
      {'codigo': 'SPRINTS', 'nombre': 'Sprints', 'unidad': 'conteo'},
      {'codigo': 'DIST_SPRINT', 'nombre': 'Distancia en sprint', 'unidad': 'm'},
      {'codigo': 'SALTOS', 'nombre': 'Saltos', 'unidad': 'conteo'},
      {'codigo': 'ACELERACIONES', 'nombre': 'Aceleraciones fuertes', 'unidad': 'conteo'},
      {
        'codigo': 'DESACELERACIONES',
        'nombre': 'Desaceleraciones fuertes',
        'unidad': 'conteo'
      },
      {'codigo': 'PLAYER_LOAD', 'nombre': 'Carga del jugador', 'unidad': 'u.a.'},
    ];
    for (final m in metricas) {
      await db.insert('tipos_metrica', m);
    }
  }

  // ---------------- Instituciones ----------------
  Future<List<Institucion>> getInstituciones() async {
    final db = await database;
    final rows = await db.query('instituciones', orderBy: 'nombre');
    return rows.map(Institucion.fromMap).toList();
  }

  Future<void> upsertInstitucion(Institucion i) async {
    final db = await database;
    final existe = await db.query('instituciones',
        columns: ['id'], where: 'id = ?', whereArgs: [i.id], limit: 1);
    if (existe.isEmpty) {
      await db.insert('instituciones', i.toMap());
    } else {
      await db.update(
        'instituciones',
        {'nombre': i.nombre, 'tenant_genialisis': i.tenantGenialisis},
        where: 'id = ?',
        whereArgs: [i.id],
      );
    }
  }

  Future<void> deleteInstitucion(String id) async {
    final db = await database;
    await db.delete('instituciones', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Atletas ----------------
  Future<List<Atleta>> getAtletas({String? idInstitucion}) async {
    final db = await database;
    final rows = idInstitucion == null
        ? await db.query('atletas', orderBy: 'nombre')
        : await db.query('atletas',
            where: 'id_institucion = ?',
            whereArgs: [idInstitucion],
            orderBy: 'nombre');
    return rows.map(Atleta.fromMap).toList();
  }

  Future<int> contarAtletas(String idInstitucion) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM atletas WHERE id_institucion = ?',
      [idInstitucion],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<void> upsertAtleta(Atleta a) async {
    final db = await database;
    final existe = await db.query('atletas',
        columns: ['id'], where: 'id = ?', whereArgs: [a.id], limit: 1);

    if (existe.isEmpty) {
      // Nuevo: inserta normalmente.
      await db.insert('atletas', a.toMap());
    } else {
      // Existente: actualiza SOLO los campos editables.
      // No se toca 'calibrado' para no perder la calibración, y se usa UPDATE
      // (no replace) para no disparar el ON DELETE CASCADE de los umbrales.
      await db.update(
        'atletas',
        {
          'id_institucion': a.idInstitucion,
          'nombre': a.nombre,
          'identificacion': a.identificacion,
          'genero': a.genero,
          'fecha_nacimiento': a.fechaNacimiento,
        },
        where: 'id = ?',
        whereArgs: [a.id],
      );
    }
  }

  Future<void> deleteAtleta(String id) async {
    final db = await database;
    await db.delete('atletas', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Umbrales por atleta ----------------
  /// Devuelve un mapa {codigo_umbral: valor} con los umbrales calibrados.
  Future<Map<String, double>> getUmbralesAtleta(String idAtleta) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT tu.codigo AS codigo, au.valor AS valor
      FROM atletas_umbrales au
      JOIN tipos_umbral tu ON tu.id_umbral = au.id_umbral
      WHERE au.id_atleta = ?
    ''', [idAtleta]);
    final map = <String, double>{};
    for (final r in rows) {
      map[r['codigo'] as String] = (r['valor'] as num).toDouble();
    }
    return map;
  }

  /// Guarda (o reemplaza) un umbral del atleta por código.
  /// Recalcula el estado 'calibrado' (true cuando tiene todos los tipos).
  Future<void> setUmbralAtleta(
      String idAtleta, String codigoUmbral, double valor) async {
    final db = await database;
    final t = await db.query('tipos_umbral',
        where: 'codigo = ?', whereArgs: [codigoUmbral]);
    if (t.isEmpty) return;
    final idUmbral = t.first['id_umbral'] as int;

    await db.delete('atletas_umbrales',
        where: 'id_atleta = ? AND id_umbral = ?',
        whereArgs: [idAtleta, idUmbral]);
    await db.insert('atletas_umbrales', {
      'id': const Uuid().v4(),
      'id_atleta': idAtleta,
      'id_umbral': idUmbral,
      'valor': valor,
    });

    final distintos = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(DISTINCT id_umbral) FROM atletas_umbrales WHERE id_atleta = ?',
          [idAtleta],
        )) ??
        0;
    final total = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM tipos_umbral')) ??
        0;
    await db.update(
      'atletas',
      {'calibrado': (total > 0 && distintos >= total) ? 1 : 0},
      where: 'id = ?',
      whereArgs: [idAtleta],
    );
  }

  /// Borra todos los umbrales del atleta y lo marca como no calibrado.
  Future<void> borrarCalibracion(String idAtleta) async {
    final db = await database;
    await db.delete('atletas_umbrales',
        where: 'id_atleta = ?', whereArgs: [idAtleta]);
    await db.update('atletas', {'calibrado': 0},
        where: 'id = ?', whereArgs: [idAtleta]);
  }

  // ---------------- Sesiones ----------------
  /// Guarda una sesión con sus métricas. [metricas] es una lista de mapas
  /// {codigo, valor, umbral}. Devuelve el id de la sesión creada.
  Future<String> guardarSesion({
    required String idAtleta,
    required int inicio,
    required int fin,
    required String datosCrudos,
    required List<Map<String, dynamic>> metricas,
  }) async {
    final db = await database;
    final idSesion = const Uuid().v4();

    await db.insert('sesiones', {
      'id': idSesion,
      'id_atleta': idAtleta,
      'inicio': inicio,
      'fin': fin,
      'datos_crudos': datosCrudos,
    });

    final tipos = await db.query('tipos_metrica');
    final mapTipo = {
      for (final t in tipos) t['codigo'] as String: t['id_metrica'] as int
    };

    for (final m in metricas) {
      final idMet = mapTipo[m['codigo']];
      if (idMet == null) continue;
      await db.insert('sesiones_metricas', {
        'id': const Uuid().v4(),
        'id_sesion': idSesion,
        'id_metrica': idMet,
        'valor': m['valor'],
        'umbral_usado': m['umbral'],
      });
    }
    return idSesion;
  }

  Future<List<Map<String, dynamic>>> getSesiones(String idAtleta) async {
    final db = await database;
    return db.query('sesiones',
        where: 'id_atleta = ?', whereArgs: [idAtleta], orderBy: 'inicio DESC');
  }

  /// Sesiones del atleta con un par de métricas destacadas (distancia, saltos)
  /// para mostrarlas en la lista sin abrir cada una.
  Future<List<Map<String, dynamic>>> getResumenSesiones(
      String idAtleta) async {
    final db = await database;
    return db.rawQuery('''
      SELECT s.id AS id, s.inicio AS inicio, s.fin AS fin,
        MAX(CASE WHEN tm.codigo = 'DISTANCIA' THEN sm.valor END) AS distancia,
        MAX(CASE WHEN tm.codigo = 'SALTOS' THEN sm.valor END) AS saltos
      FROM sesiones s
      LEFT JOIN sesiones_metricas sm ON sm.id_sesion = s.id
      LEFT JOIN tipos_metrica tm ON tm.id_metrica = sm.id_metrica
      WHERE s.id_atleta = ?
      GROUP BY s.id
      ORDER BY s.inicio DESC
    ''', [idAtleta]);
  }

  Future<List<Map<String, dynamic>>> getMetricasSesion(String idSesion) async {
    final db = await database;
    return db.rawQuery('''
      SELECT tm.codigo AS codigo, tm.nombre AS nombre, tm.unidad AS unidad,
             sm.valor AS valor, sm.umbral_usado AS umbral_usado
      FROM sesiones_metricas sm
      JOIN tipos_metrica tm ON tm.id_metrica = sm.id_metrica
      WHERE sm.id_sesion = ?
      ORDER BY tm.id_metrica
    ''', [idSesion]);
  }

  Future<void> deleteSesion(String id) async {
    final db = await database;
    await db.delete('sesiones', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Catálogos ----------------
  Future<List<TipoUmbral>> getTiposUmbral() async {
    final db = await database;
    final rows = await db.query('tipos_umbral', orderBy: 'id_umbral');
    return rows.map(TipoUmbral.fromMap).toList();
  }

  Future<List<TipoMetrica>> getTiposMetrica() async {
    final db = await database;
    final rows = await db.query('tipos_metrica', orderBy: 'id_metrica');
    return rows.map(TipoMetrica.fromMap).toList();
  }
}