import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'main.dart';
import 'progress_manager.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoading = false;

  /// Dígitos introduzidos pelo utilizador, SEM o "0" inicial (que é fixo no visor).
  /// - Docentes: 2 a 4 dígitos (3 a 5 com o "0")
  /// - Alunos: 6 dígitos (7 com o "0")
  String _numeroAtual = '';

  static const int _maxDigitos = 6;
  static const int _digitosAluno = 6;
  static const int _minDigitosDocente = 2;
  static const int _maxDigitosDocente = 4;

  // Cores da Simbiose (Profitecla + Saúde)
  final Color _azulProfitecla = const Color(0xFF008AD8);
  final Color _azulClinico = const Color(0xFFE1F0FA);
  final Color _cinzaTexto = const Color(0xFF333333);

  // Padrão fixo para simular as barras de um código de barras real
  final List<double> _barcodePattern = [
    2, 4, 1, 3, 2, 1, 4, 2, 1, 3, 4, 1, 2, 2, 3, 1, 4, 2, 1, 3, 2, 4, 1, 2, 3,
    1, 4, 2, 2, 1, 4, 3, 1, 2, 4, 2, 2, 1, 3, 1, 4, 2, 1, 3, 4, 2, 1, 2, 3, 1,
    4, 2, 1, 3,
  ];

  // ---------------------------------------------------------------------------
  // Regras do número de identificação
  // ---------------------------------------------------------------------------

  bool get _isAluno => _numeroAtual.length == _digitosAluno;

  bool get _isProfessor =>
      _numeroAtual.length >= _minDigitosDocente &&
      _numeroAtual.length <= _maxDigitosDocente;

  /// Número completo, tal como consta no cartão (com o "0" inicial). Só para apresentação.
  String get _numeroCompleto => '0$_numeroAtual';

  // ---------------------------------------------------------------------------
  // Teclado
  // ---------------------------------------------------------------------------

  void _onDigitTap(String digit) {
    if (_isLoading) return;
    if (_numeroAtual.length >= _maxDigitos) return;
    HapticFeedback.lightImpact();
    setState(() {
      _numeroAtual += digit;
    });
  }

  void _onBackspace() {
    if (_isLoading) return;
    if (_numeroAtual.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _numeroAtual = _numeroAtual.substring(0, _numeroAtual.length - 1);
    });
  }

  void _onClear() {
    if (_isLoading) return;
    if (_numeroAtual.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _numeroAtual = '';
    });
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

  // ---------------------------------------------------------------------------
  // Login
  // ---------------------------------------------------------------------------

  Future<void> _processLogin() async {
    if (_isLoading) return;

    // numeroStr = número SEM o "0" inicial. É o que está guardado na base de dados
    // (studentId e sufixo do documento "user_<numeroStr>").
    final String numeroStr = _numeroAtual.trim();

    if (numeroStr.isEmpty) {
      _showError('Marca o teu número no painel.');
      return;
    }

    final bool isAluno = _isAluno;
    final bool isProfessor = _isProfessor;

    if (!isAluno && !isProfessor) {
      _showError('Número de identificação incompleto.');
      return;
    }

    final String numeroCompleto = _numeroCompleto;

    setState(() => _isLoading = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        user = cred.user;
      }

      if (user != null) {
        final firestore = FirebaseFirestore.instance;
        final users = firestore.collection('users');

        // Documento pré-carregado (pauta): user_<numero sem o "0">
        String preloadedDocId = 'user_$numeroStr';
        DocumentReference<Map<String, dynamic>> preloadedRef =
            users.doc(preloadedDocId);
        DocumentSnapshot<Map<String, dynamic>> preloadedSnap =
            await preloadedRef.get();

        // Compatibilidade: registos antigos criados com o "0" no ID (user_0<numero>).
        // Evita duplicar o mesmo utilizador com e sem "0".
        if (!preloadedSnap.exists) {
          final legacyId = 'user_0$numeroStr';
          final legacyRef = users.doc(legacyId);
          final legacySnap = await legacyRef.get();
          if (legacySnap.exists) {
            preloadedDocId = legacyId;
            preloadedRef = legacyRef;
            preloadedSnap = legacySnap;
          }
        }

        final sessionRef = users.doc(user.uid);
        final sessionSnap = await sessionRef.get();
        final sessionData = sessionSnap.data();

        // A sessão já está ligada a este mesmo número? (mesmo dispositivo/conta anónima)
        final bool jaLigado = sessionSnap.exists &&
            sessionData != null &&
            sessionData['linkedDocId'] == preloadedDocId;

        String displayName;

        if (preloadedSnap.exists) {
          final data = preloadedSnap.data()!;
          displayName = (data['name'] ?? 'Utente $numeroCompleto').toString();

          if (jaLigado) {
            // Mantém o progresso da sessão (xp, casosJogados, audience, ...).
            // Só atualiza identidade e último acesso, para não repor o xp a 0.
            await sessionRef.set({
              'name': data['name'] ?? sessionData['name'] ?? displayName,
              if (data['fullName'] != null) 'fullName': data['fullName'],
              if (data['course'] != null) 'course': data['course'],
              if (data['class'] != null) 'class': data['class'],
              'studentId': numeroStr,
              'linkedDocId': preloadedDocId,
              'lastLogin': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else {
            // Sessão nova ou que estava ligada a outro número: substitui o documento
            // por completo (sem merge) para não misturar progresso de contas diferentes.
            await sessionRef.set({
              ...data,
              'studentId': numeroStr,
              'linkedDocId': preloadedDocId,
              'lastLogin': FieldValue.serverTimestamp(),
            });
          }

          await user.updateDisplayName(displayName);
        } else if (isProfessor) {
          // Docente ainda não registado: cria o registo (ID sem o "0", como os alunos).
          final profName = 'Prof. $numeroCompleto';
          final profData = <String, dynamic>{
            'name': profName,
            'fullName': profName,
            'studentId': numeroStr,
            'course': 'Professores',
            'class': 'Docentes',
            'audience': 11,
            'xp': 0,
            'level': 1,
            'careerTitle': 'Docente Profitecla',
            'capsuleTop': 4278225624,
            'capsuleBottom': 4278213790,
            'createdAt': FieldValue.serverTimestamp(),
          };

          await preloadedRef.set(profData);

          if (jaLigado) {
            await sessionRef.set({
              ...profData,
              'xp': sessionData['xp'] ?? 0,
              'linkedDocId': preloadedDocId,
              'lastLogin': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else {
            await sessionRef.set({
              ...profData,
              'linkedDocId': preloadedDocId,
              'lastLogin': FieldValue.serverTimestamp(),
            });
          }

          await user.updateDisplayName(profName);
        } else {
          _showError(
            'Número ($numeroCompleto) não encontrado na pauta ativa.',
          );
          if (mounted) setState(() => _isLoading = false);
          return;
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

  String? _getDetectedRoleBadge() {
    if (_isAluno) return 'ALUNO';
    if (_isProfessor) return 'DOCENTE';
    return null;
  }

  /// Visor: "0" fixo à esquerda + dígitos introduzidos (ou texto de ajuda se vazio).
  Widget _buildVisorTexto() {
  final bool vazio = _numeroAtual.isEmpty;

  return FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // "0" permanente
        Text(
          '0',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            height: 1.0,
            letterSpacing: 2.0,
            color: _azulProfitecla,
          ),
        ),
        const SizedBox(width: 8),
        if (vazio)
          Text(
            'N.º da Escola',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.0,
              color: Colors.grey.shade500,
            ),
          )
        else
          Text(
            _numeroAtual.split('').join(' '),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              height: 1.0,
              letterSpacing: 2.0,
              color: _cinzaTexto,
            ),
          ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final roleBadge = _getDetectedRoleBadge();
    final int activeBarsCount =
        ((_numeroAtual.length / _maxDigitos) * _barcodePattern.length).round();

    return Scaffold(
      backgroundColor: _azulClinico,
      body: Stack(
        children: [
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
                  vertical: 12.0,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // LOGO REDONDO COMPACTO
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _azulProfitecla.withValues(alpha: 0.15),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/logo_splash.png',
                          height: 76,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // CARTÃO DE SAÚDE ESCOLAR
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
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
                            // HEADER DO CARTÃO
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 22,
                              ),
                              decoration: BoxDecoration(
                                color: _azulProfitecla,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(24),
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
                                      letterSpacing: 1.4,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Icon(
                                    Icons.health_and_safety_rounded,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // VISOR DIGITAL (CÁPSULA DE LEITURA)
                                  Container(
                                    height: 58,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _azulClinico.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: _numeroAtual.isNotEmpty
                                            ? _azulProfitecla.withValues(
                                                alpha: 0.5,
                                              )
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.badge_outlined,
                                          color: _azulProfitecla,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(child: _buildVisorTexto()),
                                        if (roleBadge != null)
                                          AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _azulProfitecla
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              roleBadge,
                                              style: TextStyle(
                                                color: _azulProfitecla,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 18),

                                  // BLISTER NUMÉRICO (NUMPAD DISRUPTIVO)
                                  _buildBlisterNumpad(),

                                  const SizedBox(height: 20),

                                  // BOTÃO TIPO CÁPSULA
                                  if (_isLoading)
                                    const SizedBox(
                                      height: 50,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: Color(0xFF008AD8),
                                        ),
                                      ),
                                    )
                                  else
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: roleBadge != null
                                            ? _azulProfitecla
                                            : _azulProfitecla.withValues(
                                                alpha: 0.45,
                                              ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                        ),
                                        elevation: roleBadge != null ? 6 : 0,
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

                                  const SizedBox(height: 22),

                                  // CÓDIGO DE BARRAS REATIVO E CENTRADO
                                  Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: List.generate(
                                          _barcodePattern.length,
                                          (index) {
                                            final bool isLit =
                                                index < activeBarsCount;
                                            return AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 180,
                                              ),
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 1.0,
                                              ),
                                              width:
                                                  _barcodePattern[index] * 1.4,
                                              height: 36,
                                              color: isLit
                                                  ? _azulProfitecla
                                                  : Colors.grey.shade300,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        'Pharma Inc. Community ©',
                        style: TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
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

  Widget _buildBlisterNumpad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: row.map((key) {
              final bool isAction = key == 'C' || key == '⌫';
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Material(
                    color: isAction
                        ? _azulClinico.withValues(alpha: 0.7)
                        : const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      splashColor: _azulProfitecla.withValues(alpha: 0.15),
                      highlightColor: _azulProfitecla.withValues(alpha: 0.08),
                      onTap: () {
                        if (key == 'C') {
                          _onClear();
                        } else if (key == '⌫') {
                          _onBackspace();
                        } else {
                          _onDigitTap(key);
                        }
                      },
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isAction
                                ? _azulProfitecla.withValues(alpha: 0.2)
                                : Colors.grey.shade200,
                            width: 1.2,
                          ),
                        ),
                        child: Center(
                          child: key == '⌫'
                              ? Icon(
                                  Icons.backspace_outlined,
                                  size: 19,
                                  color: _azulProfitecla,
                                )
                              : Text(
                                  key,
                                  style: TextStyle(
                                    fontSize: isAction ? 15 : 19,
                                    fontWeight: FontWeight.w800,
                                    color: isAction
                                        ? _azulProfitecla
                                        : _cinzaTexto,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}