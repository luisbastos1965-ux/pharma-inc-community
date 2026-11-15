import 'package:flutter/material.dart';
import 'dart:math' as math;

class GabineteScreen extends StatelessWidget {
  const GabineteScreen({super.key});

  // Cores Oficiais Light Mode
  static const Color kProfiteclaBlue = Color(0xFF008AD8);
  static const Color kTextDark = Color(0xFF333333);
  static const Color kTextMuted = Color(0xFF757575);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Fundo claro coeso
      body: Stack(
        children: [
          // Elementos moleculares de fundo em Azul Profitecla (muito subtis)
          Positioned(top: -60, right: -60, child: _buildMolecule(kProfiteclaBlue.withValues(alpha: 0.05), 220)),
          Positioned(bottom: 50, left: -70, child: _buildMolecule(kProfiteclaBlue.withValues(alpha: 0.08), 260)),
          
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // CABEÇALHO DO GABINETE
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
                    ],
                  ),
                ),
                
                // CONTEÚDO (CRÉDITOS E PARCERIAS)
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gabinete',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: kTextDark, letterSpacing: -0.8),
                        ),
                        // Removido o subtítulo "Equipa e Parcerias..."
                        const SizedBox(height: 32),
                        
                        // BLOCO 1: Autoras do Projeto
                        _buildCreditCard(
                          title: 'Autoras do Projeto (PAP)', 
                          names: 'Ana Rodrigues, Catarina Almeida, Mafalda Cruz e Duda Fernandes',
                          role: 'Alunas do Curso Técnico Profissional de Farmácia', 
                          icon: Icons.science_rounded, 
                          highlightColor: kProfiteclaBlue,
                        ),
                        const SizedBox(height: 16),
                        
                        // BLOCO 2: SPO
                        _buildCreditCard(
                          title: 'Parceria SPO', 
                          names: 'Cláudia Silva e Filipa Miranda',
                          role: 'Serviço de Psicologia e Orientação (Profitecla)', 
                          icon: Icons.psychology_rounded, 
                          highlightColor: const Color(0xFF00A86B), // Verde Esmeralda
                        ),
                        const SizedBox(height: 16),
                        
                        // BLOCO 3: PoweredByCTE
                        _buildCreditCard(
                          title: 'Parceria PoweredByCTE', 
                          names: 'Luís Bastos e Narciso Monteiro',
                          role: 'Consultoria Tecnológica e Estruturação Digital', 
                          icon: Icons.developer_mode_rounded, 
                          highlightColor: const Color(0xFFFF9800), // Laranja
                        ),
                        
                        const SizedBox(height: 40),
                      ],
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

  Widget _buildCreditCard({
    required String title, 
    required String names, 
    required String role, 
    required IconData icon, 
    required Color highlightColor
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: highlightColor.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: highlightColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: highlightColor.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: highlightColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(), 
                  style: const TextStyle(
                    fontWeight: FontWeight.w900, 
                    fontSize: 10, 
                    color: kTextMuted, 
                    letterSpacing: 1.2
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  names, 
                  style: const TextStyle(
                    color: kTextDark, 
                    fontWeight: FontWeight.w800, 
                    fontSize: 14, 
                    height: 1.3
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role, 
                  style: const TextStyle(
                    color: kTextMuted, 
                    fontStyle: FontStyle.italic, 
                    fontSize: 12, 
                    height: 1.4
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