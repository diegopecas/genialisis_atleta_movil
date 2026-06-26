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
    await db.insert(
      'instituciones',
      i.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    await db.insert(
      'atletas',
      a.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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