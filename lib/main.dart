import 'package:flutter/material.dart';

import 'tema.dart';
import 'instituciones.dart';
import 'atletas.dart';
import 'captura.dart';
import 'captura_sesion.dart';
import 'sesiones.dart';
import 'exportacion.dart';
import 'importacion.dart';

const String kVersion = 'v1.0.9';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MotorCaptura.instance.configurar();
  await MotorCaptura.instance.limpiarSiCorre();
  runApp(const GenialisisAtletaApp());
}

class GenialisisAtletaApp extends StatelessWidget {
  const GenialisisAtletaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GENIALISIS Atleta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kGold,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[
      _MenuItem(Icons.play_circle_fill, 'Capturar', 'Grabar sesión',
          () => const CapturaSesionScreen()),
      _MenuItem(Icons.bar_chart, 'Sesiones', 'Historial',
          () => const SesionesSelectorScreen()),
      _MenuItem(Icons.groups, 'Atletas', 'Deportistas',
          () => const AtletasScreen()),
      _MenuItem(Icons.apartment, 'Instituciones', 'Escuelas',
          () => const InstitucionesScreen()),
      _MenuItem(Icons.ios_share, 'Exportar', 'Generar JSON',
          () => const ExportacionScreen()),
      _MenuItem(Icons.download, 'Importar', 'Cargar JSON',
          () => const ImportacionScreen()),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Image.asset(
                'assets/logo.png',
                height: 80,
                errorBuilder: (_, __, ___) => const SizedBox(height: 80),
              ),
              const SizedBox(height: 8),
              const Text(
                'GENIALISIS · ATLETA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kGold,
                  fontSize: 13,
                  letterSpacing: 4,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.05,
                  children: items
                      .map((it) => _MenuCuadro(
                            item: it,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => it.pantalla()),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  kVersion,
                  style: const TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final Widget Function() pantalla;
  _MenuItem(this.icono, this.titulo, this.subtitulo, this.pantalla);
}

class _MenuCuadro extends StatelessWidget {
  final _MenuItem item;
  final VoidCallback onTap;

  const _MenuCuadro({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kGold.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icono, color: kGold, size: 40),
            const SizedBox(height: 12),
            Text(item.titulo,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(item.subtitulo,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}