import 'package:flutter/material.dart';

import 'tema.dart';
import 'instituciones.dart';
import 'atletas.dart';

const String kVersion = 'v1.0.1';

void main() {
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text(
                'GENIALISIS · ATLETA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kGold,
                  fontSize: 14,
                  letterSpacing: 4,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Rendimiento deportivo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 40),
              _MenuCard(
                icon: Icons.play_circle_fill,
                titulo: 'Capturar',
                subtitulo: 'Disponible en el siguiente paso',
                habilitado: false,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('La captura se activa en el siguiente paso'),
                      backgroundColor: kPanel,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              _MenuCard(
                icon: Icons.groups,
                titulo: 'Atletas',
                subtitulo: 'Gestionar deportistas y calibración',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AtletasScreen()),
                ),
              ),
              const SizedBox(height: 14),
              _MenuCard(
                icon: Icons.apartment,
                titulo: 'Instituciones',
                subtitulo: 'Gestionar escuelas y tenant',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InstitucionesScreen()),
                ),
              ),
              const Spacer(),
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

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;
  final bool habilitado;

  const _MenuCard({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    this.habilitado = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: habilitado ? 0.05 : 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: habilitado
                ? kGold.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: habilitado ? kGold : Colors.white24, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: habilitado ? Colors.white : Colors.white38,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitulo,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: habilitado ? Colors.white38 : Colors.white12),
          ],
        ),
      ),
    );
  }
}