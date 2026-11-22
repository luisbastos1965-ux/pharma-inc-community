import 'package:flutter/material.dart';
import 'dart:math' as math;

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // Cores Oficiais Light Mode
  static const Color kProfiteclaBlue = Color(0xFF008AD8);
  static const Color kTextDark = Color(0xFF333333);
  static const Color kTextMuted = Color(0xFF757575);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCirc));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Fundo claro coeso
      body: Stack(
        children: [
          // Elementos moleculares de fundo em Azul Profitecla (muito subtis)
          Positioned(top: -60, left: -60, child: _buildMolecule(kProfiteclaBlue.withValues(alpha: 0.05), 220)),
          Positioned(bottom: 50, right: -70, child: _buildMolecule(kProfiteclaBlue.withValues(alpha: 0.08), 260)),

          SafeArea(
            child: Column(
              children: [
                // 1. CABEÇALHO DO MANUAL
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(50),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kProfiteclaBlue.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                            border: Border.all(color: kProfiteclaBlue.withValues(alpha: 0.15)),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, color: kProfiteclaBlue, size: 20),
                        ),
                      ),
                      const SizedBox(width: 42), // Espaçador para centrar o título
                    ],
                  ),
                ),

                // 2. CONTEÚDO DAS REGRAS
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bula da\nComunidade',
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900,
                                      color: kTextDark,
                                      letterSpacing: -0.8,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 36),

                                  // Regra 1 - Scanner
                                  _buildProtocolCard(
                                    index: '01',
                                    title: '1. O Leitor de QR Codes',
                                    description: 'Usa o grande botão azul no menu principal para leres os códigos QR disponibilizados.',
                                    icon: Icons.qr_code_scanner_rounded,
                                    accentColor: kProfiteclaBlue,
                                  ),
                                  const SizedBox(height: 20),

                                  // Regra 2 - Cartões
                                  _buildProtocolCard(
                                    index: '02',
                                    title: '2. Desafios Práticos',
                                    description: 'Cada leitura revela um caso clínico ou desafio adaptado aos vários cursos. Analisa bem a situação antes de escolheres a resposta.',
                                    icon: Icons.style_rounded,
                                    accentColor: const Color(0xFF00A86B), // Verde Esmeralda
                                  ),
                                  const SizedBox(height: 20),

                                  // Regra 3 - Progressão (Removidos os cargos, regresso aos Miligramas - mg)
                                  _buildProtocolCard(
                                    index: '03',
                                    title: '3. Princípio Ativo (mg)',
                                    description: 'Respostas corretas dão-te Miligramas (mg) de Princípio Ativo. Acumula mg para dominares a Escala geral.',
                                    icon: Icons.science_rounded,
                                    accentColor: const Color(0xFFFF9800), // Laranja
                                  ),
                                  const SizedBox(height: 20),

                                  // Regra 4 - Feedback
                                  _buildProtocolCard(
                                    index: '04',
                                    title: '4. Aprendizagem Contínua',
                                    description: 'Quer acertes ou erres, receberás sempre a justificação técnica. O objetivo principal é testares os teus conhecimentos na prática.',
                                    icon: Icons.school_rounded,
                                    accentColor: const Color(0xFF9C27B0), // Roxo
                                  ),
                                  const SizedBox(height: 48),

                                  // Botão de fechar/entender (Light Mode)
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 18),
                                        backgroundColor: kProfiteclaBlue,
                                        foregroundColor: Colors.white,
                                        elevation: 8,
                                        shadowColor: kProfiteclaBlue.withValues(alpha: 0.4),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(30),
                                        ),
                                      ),
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text(
                                        'LI E COMPREENDI A BULA',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMolecule(Color color, double size) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size / 3),
          border: Border.all(color: color, width: 4),
        ),
        child: Center(
          child: Container(
            width: size / 2, height: size / 2,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 4)),
          ),
        ),
      ),
    );
  }

  Widget _buildProtocolCard({
    required String index,
    required String title,
    required String description,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: accentColor, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kTextMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
