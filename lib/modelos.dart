// Modelos de datos de la app.

class Institucion {
  final String id;
  String nombre;
  String? tenantGenialisis;

  Institucion({
    required this.id,
    required this.nombre,
    this.tenantGenialisis,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'tenant_genialisis': tenantGenialisis,
      };

  factory Institucion.fromMap(Map<String, dynamic> m) => Institucion(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        tenantGenialisis: m['tenant_genialisis'] as String?,
      );
}

class Atleta {
  final String id;
  String idInstitucion;
  String nombre;
  String? identificacion;
  String? genero;
  String? fechaNacimiento; // 'YYYY-MM-DD'
  bool calibrado;

  Atleta({
    required this.id,
    required this.idInstitucion,
    required this.nombre,
    this.identificacion,
    this.genero,
    this.fechaNacimiento,
    this.calibrado = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'id_institucion': idInstitucion,
        'nombre': nombre,
        'identificacion': identificacion,
        'genero': genero,
        'fecha_nacimiento': fechaNacimiento,
        'calibrado': calibrado ? 1 : 0,
      };

  factory Atleta.fromMap(Map<String, dynamic> m) => Atleta(
        id: m['id'] as String,
        idInstitucion: m['id_institucion'] as String,
        nombre: m['nombre'] as String,
        identificacion: m['identificacion'] as String?,
        genero: m['genero'] as String?,
        fechaNacimiento: m['fecha_nacimiento'] as String?,
        calibrado: ((m['calibrado'] as int?) ?? 0) == 1,
      );
}

class TipoUmbral {
  final int idUmbral;
  final String codigo;
  final String nombre;
  final String? descripcion;

  TipoUmbral({
    required this.idUmbral,
    required this.codigo,
    required this.nombre,
    this.descripcion,
  });

  factory TipoUmbral.fromMap(Map<String, dynamic> m) => TipoUmbral(
        idUmbral: m['id_umbral'] as int,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        descripcion: m['descripcion'] as String?,
      );
}

class TipoMetrica {
  final int idMetrica;
  final String codigo;
  final String nombre;
  final String? unidad;

  TipoMetrica({
    required this.idMetrica,
    required this.codigo,
    required this.nombre,
    this.unidad,
  });

  factory TipoMetrica.fromMap(Map<String, dynamic> m) => TipoMetrica(
        idMetrica: m['id_metrica'] as int,
        codigo: m['codigo'] as String,
        nombre: m['nombre'] as String,
        unidad: m['unidad'] as String?,
      );
}