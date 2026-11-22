import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'main.dart';
import 'progress_manager.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _pulseController;

  final _numeroController = TextEditingController();
  final _passwordController = TextEditingController();

  // Cores da Simbiose (Profitecla + Saúde)
  final Color _azulProfitecla = const Color(0xFF008AD8);
  final Color _azulClinico = const Color(
    0xFFE1F0FA,
  ); // Fundo super leve e esterilizado
  final Color _cinzaTexto = const Color(0xFF333333);

  // Padrão fixo para simular as barras de um código de barras real (espessuras variadas)
  final List<double> _barcodePattern = [
    2,
    4,
    1,
    3,
    2,
    1,
    4,
    2,
    1,
    3,
    4,
    1,
    2,
    2,
    3,
    1,
    4,
    2,
    1,
    3,
    2,
    4,
    1,
    2,
    3,
    1,
    4,
    2,
    2,
    1,
    4,
    3,
    1,
    2,
    4,
    2,
    2,
    1,
    3,
    1,
    4,
    2,
    1,
    3,
    4,
    2,
    1,
    2,
    3,
    1,
    4,
    2,
    1,
    3,
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Adiciona listener para o código de barras reativo atualizar o ecrã
    _numeroController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _numeroController.dispose();
    _passwordController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      ),
    );
  }

  void _navigateToMenu() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MenuScreen()),
    );
  }

  Future<void> _processLogin() async {
    final numeroStr = _numeroController.text.trim();
    final password = _passwordController.text.trim();

    if (numeroStr.isEmpty || password.isEmpty) {
      _showError('Prescrição incompleta: Faltam dados.');
      return;
    }

    final numeroInvertido = numeroStr.split('').reversed.join('');
    if (password != numeroInvertido) {
      _showError(
        'Fórmula rejeitada. Dica: A password é o teu número ao contrário.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();

      if (cred.user != null) {
        final uid = cred.user!.uid;
        final docRef = FirebaseFirestore.instance
            .collection('comunidade_users')
            .doc(uid);
        final doc = await docRef.get();

        if (!doc.exists) {
          await docRef.set({
            'numero': numeroStr,
            'name': 'Utente $numeroStr',
            'curso': 'Comunidade Profitecla',
            'audience': 2,
            'xp': 0,
            'level': 1,
            'careerTitle': 'Cidadão da Saúde',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (cred.user!.displayName == null) {
          await cred.user!.updateDisplayName('Utente $numeroStr');
        }

        await ProgressManager().loadUserData();
        _navigateToMenu();
      }
    } catch (e) {
      _showError('Erro de sistema: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Fundo com cruzes de farmácia subtis misturadas com estética escolar
  Widget _buildClinicalWatermark(
    IconData icon,
    double size,
    double opacity,
    double angle,
  ) {
    return Transform.rotate(
      angle: angle,
      child: Icon(
        icon,
        size: size,
        color: _azulProfitecla.withValues(alpha: opacity),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _azulClinico,
      body: Stack(
        children: [
          // MARCAS D'ÁGUA DA SIMBIOSE (Farmácia + Escola)
          Positioned(
            top: -20,
            right: -40,
            child: _buildClinicalWatermark(
              Icons.local_pharmacy_rounded,
              250,
              0.04,
              math.pi / 6,
            ),
          ),
          Positioned(
            bottom: -60,
            left: -40,
            child: _buildClinicalWatermark(
              Icons.school_rounded,
              300,
              0.03,
              -math.pi / 8,
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16.0,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // LOGO REDONDO CLÁSSICO
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _azulProfitecla.withValues(alpha: 0.15),
                              blurRadius: 25,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/logo_splash.png',
                          height: 100,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // CARTÃO DE SAÚDE ESCOLAR
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _azulProfitecla.withValues(alpha: 0.12),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // HEADER DO CARTÃO (Identidade Profitecla + Farmácia)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 24,
                              ),
                              decoration: BoxDecoration(
                                color: _azulProfitecla,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'CARTÃO DE SAÚDE ESCOLAR',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Icon(
                                    Icons.health_and_safety_rounded,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // CAMPO: NÚMERO DE UTENTE/ALUNO
                                  _buildPillTextField(
                                    controller: _numeroController,
                                    label: 'N.º de Utente (Escola)',
                                    icon: Icons.person_outline_rounded,
                                    isPassword: false,
                                  ),

                                  const SizedBox(height: 24),

                                  // CAMPO: FÓRMULA REVERSA
                                  _buildPillTextField(
                                    controller: _passwordController,
                                    label: 'Fórmula Reversa (Password)',
                                    icon: Icons.vaccines_rounded,
                                    isPassword: true,
                                  ),

                                  const SizedBox(height: 16),

                                  // POSOLOGIA (Dica)
                                  AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) {
                                      return Opacity(
                                        opacity:
                                            0.5 +
                                            (_pulseController.value * 0.5),
                                        child: Text(
                                          'Posologia: Insere o teu número ao contrário na password.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _azulProfitecla.withValues(
                                              alpha: 0.8,
                                            ),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                  const SizedBox(height: 32),

                                  // BOTÃO TIPO CÁPSULA (Totalmente Arredondado)
                                  if (_isLoading)
                                    const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(
                                          0xFF008AD8,
                                        ), // Azul Profitecla forçado
                                      ),
                                    )
                                  else
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _azulProfitecla,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                        ),
                                        elevation: 6,
                                        shadowColor: _azulProfitecla.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                      onPressed: _processLogin,
                                      child: const Center(
                                        child: Text(
                                          'ATIVAR CUIDADOS',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                    ),

                                  // ESPAÇAMENTO DEPOIS DO BOTÃO
                                  const SizedBox(height: 36),

                                  // CÓDIGO DE BARRAS (Largo e Sem Números)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: _barcodePattern
                                        .map(
                                          (width) => Container(
                                            // Reduzi a margem para 1.0 para as barras ficarem mais juntas
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 1.0,
                                            ),
                                            width:
                                                width *
                                                1.5, // Multipliquei a largura original para tornar tudo mais espesso e largo
                                            height:
                                                45, // Aumentei a altura para impor mais presença
                                            color: Colors.grey.shade400,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),

                      // COPYRIGHT ORIGINAL RESTAURADO
                      const Text(
                        'Pharma Inc. ©',
                        style: TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Inputs desenhados como "Cápsulas" de fármacos
  Widget _buildPillTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isPassword,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: TextInputType.number,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: _cinzaTexto,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        prefixIcon: Icon(
          icon,
          color: _azulProfitecla.withValues(alpha: 0.7),
          size: 22,
        ),
        filled: true,
        fillColor: _azulClinico.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30), // Formato de Cápsula
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: _azulProfitecla, width: 2),
        ),
      ),
    );
  }
}
