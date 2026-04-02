import 'dart:math';
import 'package:flutter/material.dart';

class FireParticles extends StatefulWidget {
  const FireParticles({super.key});

  @override
  State<FireParticles> createState() => _FireParticlesState();
}

class _FireParticlesState extends State<FireParticles> with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<FireParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(seconds: 3), vsync: this)..repeat();

    _controller.addListener(_updateParticles);
    _generateParticles();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _generateParticles() {
    for (int i = 0; i < 30; i++) {
      _particles.add(
        FireParticle(
          x: _random.nextDouble(),
          y: 1.0,
          size: _random.nextDouble() * 1.5 + 0.5,
          speed: _random.nextDouble() * 0.015 + 0.005,
          life: _random.nextDouble(),
          direction: _random.nextDouble() > 0.5 ? 1.0 : -1.0,
          wavePhase: _random.nextDouble() * 2 * pi,
          waveSpeed: 0.11 + _random.nextDouble() * 0.09,
        ),
      );
    }
  }

  void _updateParticles() {
    setState(() {
      for (var particle in _particles) {
        particle.y -= particle.speed;
        particle.life -= 0.008;
        particle.x += particle.direction * particle.speed * 0.3;
        particle.wavePhase += particle.waveSpeed;

        if (particle.life <= 0 || particle.y <= 0) {
          particle.y = 1.0;
          particle.life = 1.0;
          particle.x = _random.nextDouble();
          particle.direction = _random.nextDouble() > 0.5 ? 1.0 : -1.0;
          particle.wavePhase = _random.nextDouble() * 2 * pi;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: FireParticlePainter(_particles), size: Size.infinite);
  }
}

class FireParticle {
  double x;
  double y;
  double size;
  double speed;
  double life;
  double direction;
  double wavePhase;
  double waveSpeed;

  FireParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.life,
    required this.direction,
    required this.wavePhase,
    required this.waveSpeed,
  });
}

class FireParticlePainter extends CustomPainter {
  final List<FireParticle> particles;

  FireParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      final opacity = (particle.life * 0.72 + 0.38).clamp(0.45, 1.0);
      final wobblePx = sin(particle.wavePhase) * (10.0 + particle.size * 5.0);
      final x = particle.x * size.width + wobblePx;
      final y = particle.y * size.height;
      final radius = particle.size;

      final centerPaint =
          Paint()
            ..color = Color.fromRGBO(255, 50, 0, opacity)
            ..style = PaintingStyle.fill;

      final outerPaint =
          Paint()
            ..color = Color.fromRGBO(255, 215, 0, (opacity * 0.94).clamp(0.0, 1.0))
            ..style = PaintingStyle.fill
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(Offset(x, y), radius, centerPaint);
      canvas.drawCircle(Offset(x, y), radius * 1.5, outerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
