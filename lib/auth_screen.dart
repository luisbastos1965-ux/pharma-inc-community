import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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

  final Color _azulProfitecla = const Color(0xFF008AD8);
  final Color _azulClinico = const Color(0xFFE1F0FA);
  final Color _cinzaTexto = const Color(0xFF333333);
  final Color _azulClaro = const Color(0xFF29B6F6);

  /// Estado que o código de barras "cristalino" traduz visualmente.
  _EstadoBarcode _estadoBarcode = _EstadoBarcode.idle;
  Timer? _erroTimer;

  final List<double> _barcodePattern = [
    2, 4, 1, 3, 2, 1, 4, 2, 1, 3, 4, 1, 2, 2, 3, 1, 4, 2, 1, 3, 2, 4, 1, 2, 3,
    1, 4, 2, 2, 1, 4, 3, 1, 2, 4, 2, 2, 1, 3, 1, 4, 2, 1, 3, 4, 2, 1, 2, 3, 1,
    4, 2, 1, 3,
  ];

  bool get _isAluno => _numeroAtual.length == _digitosAluno;

  bool get _isProfessor =>
      _numeroAtual.length >= _minDigitosDocente &&
      _numeroAtual.length <= _maxDigitosDocente;

  String get _numeroCompleto => '0$_numeroAtual';

  @override
  void dispose() {
    _erroTimer?.cancel();
    super.dispose();
  }

  /// Se o utilizador voltar a mexer no teclado, o estado de erro termina logo.
  void _limparErroBarcode() {
    if (_estadoBarcode == _EstadoBarcode.erro) {
      _erroTimer?.cancel();
      _estadoBarcode = _EstadoBarcode.idle;
    }
  }

  /// Faz o código de barras "estilhaçar" em vermelho e regressar ao repouso.
  void _sinalizarErroBarcode() {
    if (!mounted) return;
    _erroTimer?.cancel();
    setState(() => _estadoBarcode = _EstadoBarcode.erro);
    _erroTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted && _estadoBarcode == _EstadoBarcode.erro) {
        setState(() => _estadoBarcode = _EstadoBarcode.idle);
      }
    });
  }

  void _onDigitTap(String digit) {
    if (_isLoading) return;
    if (_numeroAtual.length >= _maxDigitos) return;
    HapticFeedback.lightImpact();
    setState(() {
      _limparErroBarcode();
      _numeroAtual += digit;
    });
  }

  void _onBackspace() {
    if (_isLoading) return;
    if (_numeroAtual.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _limparErroBarcode();
      _numeroAtual = _numeroAtual.substring(0, _numeroAtual.length - 1);
    });
  }

  void _onClear() {
    if (_isLoading) return;
    if (_numeroAtual.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _limparErroBarcode();
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
    _sinalizarErroBarcode();
  }

  void _navigateToMenu() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MenuScreen()),
    );
  }

  /// Normaliza o número introduzido: remove tudo o que não seja dígito
  /// (espaços, etc.) e retira os zeros à esquerda. Ex.: "0999" -> "999".
  String _normalizarNumero(String raw) {
    final apenasDigitos = raw.replaceAll(RegExp(r'\D'), '');
    return apenasDigitos.replaceFirst(RegExp(r'^0+'), '');
  }

  Future<void> _processLogin() async {
    // Proteção contra cliques duplicados / chamadas repetidas ao Firestore.
    if (_isLoading) return;

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

    // ID do documento: user_<número sem zeros à esquerda>
    final String numeroNormalizado = _normalizarNumero(numeroStr);
    if (numeroNormalizado.isEmpty) {
      _showError('Número não encontrado. Verifica o teu número de aluno/docente.');
      return;
    }
    final String docId = 'user_$numeroNormalizado';
    final String numeroCompleto = '0$numeroNormalizado';

    setState(() {
      _isLoading = true;
      _estadoBarcode = _EstadoBarcode.validando;
    });

    // Indica se a sessão anónima foi criada nesta tentativa (para a poder
    // terminar caso o número não exista, evitando sessões "órfãs").
    bool sessaoCriadaNestaTentativa = false;

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        user = cred.user;
        sessaoCriadaNestaTentativa = true;
      }

      if (user != null) {
        final docRef = FirebaseFirestore.instance.collection('users').doc(docId);
        final doc = await docRef.get();

        // Número não registado: bloquear entrada, sem gravar nada.
        if (!doc.exists) {
          if (sessaoCriadaNestaTentativa) {
            await FirebaseAuth.instance.signOut();
          }
          _showError(
            'Número não encontrado. Verifica o teu número de aluno/docente.',
          );
          return; // o `finally` repõe _isLoading = false
        }

        // Número registado: prosseguir normalmente.
        final data = doc.data() ?? <String, dynamic>{};
        final displayName =
            (data['name'] ?? 'Utente $numeroCompleto').toString();
        await user.updateDisplayName(displayName);

        await ProgressManager().loadUserData(pautaId: docId);

        // Pequena celebração: a onda de cristalização percorre o código
        // de barras antes de abrir o menu.
        if (mounted) setState(() => _estadoBarcode = _EstadoBarcode.sucesso);
        await Future.delayed(const Duration(milliseconds: 520));
        _navigateToMenu();
      }
    } catch (e) {
      _showError('Erro de sistema: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_estadoBarcode == _EstadoBarcode.validando) {
            _estadoBarcode = _EstadoBarcode.idle;
          }
        });
      }
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

  Widget _buildVisorTexto() {
    final bool vazio = _numeroAtual.isEmpty;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
                                  _buildBlisterNumpad(),
                                  const SizedBox(height: 20),
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
                                  Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: _CrystalBarcode(
                                        pattern: _barcodePattern,
                                        digitCount: _numeroAtual.length,
                                        maxDigits: _maxDigitos,
                                        estado: _estadoBarcode,
                                        corPrincipal: _azulProfitecla,
                                        corClara: _azulClaro,
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

// ─────────────────────────────────────────────────────────────────────────────
// CÓDIGO DE BARRAS "CRISTALIZAÇÃO"
//
// Em repouso, as barras são "ruído" cinzento-azulado que respira (alturas
// irregulares). Cada dígito introduzido faz nascer uma "semente" numa zona
// diferente do código; à volta dela as barras cristalizam (ficam altas, alinhadas
// e azuis). A proporção n/6 lê-se na fração de barras cristalizadas e na quantidade
// de ruído que resta, não numa frente que avança da esquerda para a direita.
// ─────────────────────────────────────────────────────────────────────────────

enum _EstadoBarcode { idle, validando, sucesso, erro }

double _c01(double v) => v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
double _smooth(double u) => u * u * (3 - 2 * u);
Color _mix(Color a, Color b, double t) => Color.lerp(a, b, _c01(t))!;

class _BarcodeLayout {
  _BarcodeLayout({
    required this.xs,
    required this.ws,
    required this.xn,
    required this.ph1,
    required this.ph2,
    required this.larguraTotal,
    required this.seedCenters,
  });

  final List<double> xs; // x de cada barra (px)
  final List<double> ws; // largura de cada barra (px)
  final List<double> xn; // centro normalizado 0..1
  final List<double> ph1; // fases do ruído
  final List<double> ph2;
  final double larguraTotal;
  final List<double> seedCenters; // centro normalizado de cada semente (1 por dígito)

  factory _BarcodeLayout.from(
    List<double> pattern,
    int maxDigits,
    double escala,
    double margem,
  ) {
    final rnd = math.Random(11);
    final xs = <double>[];
    final ws = <double>[];
    double x = 0;
    for (final p in pattern) {
      final w = p * escala;
      xs.add(x + margem);
      ws.add(w);
      x += w + margem * 2;
    }
    final total = x;
    final xn = <double>[];
    final ph1 = <double>[];
    final ph2 = <double>[];
    for (var i = 0; i < xs.length; i++) {
      xn.add((xs[i] + ws[i] / 2) / total);
      ph1.add(rnd.nextDouble() * math.pi * 2);
      ph2.add(rnd.nextDouble() * math.pi * 2);
    }
    // Ordem em que as zonas "acendem": espalhadas, nunca a escorrer num só sentido.
    final ordem = maxDigits == 6
        ? const [2, 5, 0, 3, 1, 4]
        : List<int>.generate(maxDigits, (k) => k);
    return _BarcodeLayout(
      xs: xs,
      ws: ws,
      xn: xn,
      ph1: ph1,
      ph2: ph2,
      larguraTotal: total,
      seedCenters: [for (final seg in ordem) (seg + 0.5) / maxDigits],
    );
  }
}

class _CrystalBarcode extends StatefulWidget {
  const _CrystalBarcode({
    required this.pattern,
    required this.digitCount,
    required this.maxDigits,
    required this.estado,
    required this.corPrincipal,
    required this.corClara,
  });

  final List<double> pattern;
  final int digitCount;
  final int maxDigits;
  final _EstadoBarcode estado;
  final Color corPrincipal;
  final Color corClara;

  @override
  State<_CrystalBarcode> createState() => _CrystalBarcodeState();
}

class _CrystalBarcodeState extends State<_CrystalBarcode>
    with TickerProviderStateMixin {
  static const double _altura = 44;
  static const double _escalaLargura = 1.4;
  static const double _margemBarra = 1.0;

  // Mola ligeiramente sub-amortecida: o progresso "assenta" de forma orgânica.
  static const SpringDescription _mola = SpringDescription(
    mass: 1,
    stiffness: 120,
    damping: 15.5,
  );

  late final AnimationController _clock; // tempo contínuo (respiração do ruído)
  late final AnimationController _progress; // proporção n/max, movida por mola
  late final AnimationController _impulse; // onda a cada dígito/apagar/limpar
  late final AnimationController _valid; // intensidade do modo "a validar"
  late final AnimationController _beam; // feixe de leitura (ping-pong suave)
  late final AnimationController _success; // onda final de sucesso
  late final AnimationController _error; // estilhaçar em vermelho

  late _BarcodeLayout _layout;

  double _impCenter = 0.5;
  double _impSpan = 0.3;
  bool _impOut = true;

  double _alvo() => _c01(widget.digitCount / widget.maxDigits);

  _BarcodeLayout _novoLayout() => _BarcodeLayout.from(
        widget.pattern,
        widget.maxDigits,
        _escalaLargura,
        _margemBarra,
      );

  @override
  void initState() {
    super.initState();
    _layout = _novoLayout();
    _clock = AnimationController(vsync: this, duration: const Duration(hours: 1))
      ..repeat();
    _progress = AnimationController.unbounded(vsync: this, value: _alvo());
    _impulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1,
    );
    _valid = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _beam = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _success = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _error = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _CrystalBarcode old) {
    super.didUpdateWidget(old);

    if (!identical(old.pattern, widget.pattern) ||
        old.maxDigits != widget.maxDigits) {
      _layout = _novoLayout();
    }

    if (old.digitCount != widget.digitCount ||
        old.maxDigits != widget.maxDigits) {
      _onDigitosAlterados(old.digitCount);
    }

    if (old.estado != widget.estado) {
      _onEstadoAlterado();
    }
  }

  void _onDigitosAlterados(int antes) {
    final depois = widget.digitCount;
    if (depois > antes) {
      // Nova semente: a onda expande-se a partir dela.
      _impCenter = _layout.seedCenters[(depois - 1).clamp(0, widget.maxDigits - 1).toInt()];
      _impSpan = 0.38;
      _impOut = true;
    } else if (depois == 0) {
      // Limpar tudo: implosão a partir do centro.
      _impCenter = 0.5;
      _impSpan = 0.7;
      _impOut = false;
    } else {
      // Apagar um dígito: implosão na zona que se desfaz.
      _impCenter = _layout.seedCenters[(antes - 1).clamp(0, widget.maxDigits - 1).toInt()];
      _impSpan = 0.28;
      _impOut = false;
    }
    _impulse.forward(from: 0);

    _progress.animateWith(
      SpringSimulation(_mola, _progress.value, _alvo(), _progress.velocity),
    );
  }

  void _onEstadoAlterado() {
    switch (widget.estado) {
      case _EstadoBarcode.validando:
        _valid.forward();
        _beam.repeat();
        break;
      case _EstadoBarcode.sucesso:
        _valid.reverse();
        _beam.stop();
        _success.forward(from: 0);
        break;
      case _EstadoBarcode.erro:
        _valid.reverse();
        _beam.stop();
        _error.forward(from: 0);
        break;
      case _EstadoBarcode.idle:
        _valid.reverse();
        _beam.stop();
        _success.value = 0;
        break;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _progress.dispose();
    _impulse.dispose();
    _valid.dispose();
    _beam.dispose();
    _success.dispose();
    _error.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool calm = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      label:
          'Código de barras de progresso: ${widget.digitCount} de ${widget.maxDigits} dígitos',
      child: RepaintBoundary(
        child: SizedBox(
          width: _layout.larguraTotal,
          height: _altura,
          child: CustomPaint(
            painter: _CrystalBarcodePainter(
              layout: _layout,
              maxDigits: widget.maxDigits,
              calm: calm,
              corPrincipal: widget.corPrincipal,
              corClara: widget.corClara,
              impCenter: _impCenter,
              impSpan: _impSpan,
              impOut: _impOut,
              clock: _clock,
              progress: _progress,
              impulse: _impulse,
              valid: _valid,
              beam: _beam,
              success: _success,
              error: _error,
            ),
          ),
        ),
      ),
    );
  }
}

class _CrystalBarcodePainter extends CustomPainter {
  _CrystalBarcodePainter({
    required this.layout,
    required this.maxDigits,
    required this.calm,
    required this.corPrincipal,
    required this.corClara,
    required this.impCenter,
    required this.impSpan,
    required this.impOut,
    required this.clock,
    required this.progress,
    required this.impulse,
    required this.valid,
    required this.beam,
    required this.success,
    required this.error,
  }) : super(
          repaint: Listenable.merge(
            [clock, progress, impulse, valid, beam, success, error],
          ),
        );

  final _BarcodeLayout layout;
  final int maxDigits;
  final bool calm;
  final Color corPrincipal;
  final Color corClara;
  final double impCenter;
  final double impSpan;
  final bool impOut;
  final Animation<double> clock;
  final Animation<double> progress;
  final Animation<double> impulse;
  final Animation<double> valid;
  final Animation<double> beam;
  final Animation<double> success;
  final Animation<double> error;

  static const Color _corRuido = Color(0xFFD3DCE4);
  static final Color _corErro = Colors.redAccent.shade400;

  @override
  void paint(Canvas canvas, Size size) {
    final double h = size.height;
    final double t = calm ? 0.0 : clock.value * 3600.0;
    final double prog = _c01(progress.value);
    final int n = maxDigits;
    final double segW = 1.0 / n;
    final double soft = segW * 0.16;
    final double radius = segW * 0.62;

    // Ativação de cada semente: 0 → 1 à medida que o seu dígito é introduzido.
    final List<double> acts = List<double>.generate(
      n,
      (k) => Curves.easeOutCubic.transform(_c01(prog * n - k)),
    );

    // Onda de impulso (novo dígito / apagar / limpar).
    final double iv = calm ? 1.0 : impulse.value;
    final double ivE = Curves.easeOut.transform(_c01(iv));
    final double impEnv = 1.0 - _c01(iv);
    final double ondaR = impOut ? ivE * impSpan : (1.0 - ivE) * impSpan;

    // Validação (feixe de leitura).
    final double vm = Curves.easeInOut.transform(_c01(valid.value));
    final double beamNorm =
        -0.06 + 1.12 * (0.5 - 0.5 * math.cos(2 * math.pi * beam.value));

    // Sucesso (onda que cristaliza tudo).
    final double sv = Curves.easeOutCubic.transform(_c01(success.value));

    // Erro (estilhaçar): sobe depressa, desvanece devagar.
    final double ev = error.value;
    final double e = ev < 0.12
        ? ev / 0.12
        : Curves.easeOut.transform(_c01(1.0 - (ev - 0.12) / 0.88));

    final Paint paint = Paint()..isAntiAlias = true;

    for (var i = 0; i < layout.xs.length; i++) {
      final double xn = layout.xn[i];
      final double p1 = layout.ph1[i];
      final double p2 = layout.ph2[i];

      // 1) Cristalização: a melhor das sementes ativas.
      double c = 0;
      for (var k = 0; k < n; k++) {
        final double a = acts[k];
        if (a <= 0) continue;
        final double d = (xn - layout.seedCenters[k]).abs();
        final double u = _c01((a * (radius + soft) - d) / soft);
        final double v = _smooth(u);
        if (v > c) c = v;
      }

      // 2) Sucesso: onda que força a cristalização total.
      double sparkS = 0;
      if (sv > 0) {
        final double cs = _c01((sv * 1.5 - xn) / 0.5);
        c = math.max(c, _smooth(cs));
        sparkS = 4 * cs * (1 - cs);
      }

      // 3) Erro: a estrutura desfaz-se um pouco.
      if (e > 0) c *= (1 - 0.55 * e);

      // 4) Altura: ruído que respira ↔ cristal estável.
      final double nz = 0.5 * (0.5 + 0.5 * math.sin(t * 1.15 + p1)) +
          0.5 * (0.5 + 0.5 * math.sin(t * 0.62 + p2 * 1.7));
      final double ruidoFrac = 0.16 + 0.34 * nz * (1 - 0.55 * vm);
      final double cristalFrac =
          0.92 + 0.08 * math.sin(t * (1.8 + 2.4 * vm) + i * 0.38);
      double frac = ruidoFrac + (cristalFrac - ruidoFrac) * c;

      // Frente do cristal: pequeno "brilho" de crescimento.
      final double frente = 4 * c * (1 - c);
      frac += 0.10 * frente;

      // 5) Onda de impulso.
      double bump = 0;
      if (impEnv > 0.001) {
        final double dd = ((xn - impCenter).abs() - ondaR) / 0.07;
        bump = math.exp(-dd * dd) * impEnv;
      }
      if (impOut) {
        frac += (1 - frac) * 0.55 * bump;
      } else {
        frac -= frac * 0.40 * bump;
      }

      // 6) Feixe de leitura durante a validação.
      double bb = 0;
      if (vm > 0.001) {
        final double db = (xn - beamNorm) / 0.075;
        bb = math.exp(-db * db) * vm;
        frac += (1 - frac) * 0.5 * bb;
      }

      // 7) Erro: tremor e encolher.
      double dy = 0;
      double encolher = 1.0;
      if (e > 0) {
        if (!calm) dy = math.sin(t * 36 + p1 * 5) * 3.2 * e;
        encolher = 1 - 0.28 * e * (0.5 + 0.5 * math.sin(p2 * 3 + t * 20));
      }

      // 8) Cor.
      final double shimmer = 0.5 + 0.5 * math.sin(xn * 5.0 - t * 0.9);
      final Color corCristal =
          _mix(corClara, corPrincipal, 0.35 + 0.65 * shimmer);
      Color cor = _mix(_corRuido, corCristal, c);
      final double luz = (0.85 * (impOut ? bump : 0.0) +
              0.9 * bb +
              0.7 * sparkS +
              0.25 * frente)
          .clamp(0.0, 1.0)
          .toDouble();
      cor = _mix(cor, corClara, luz);
      if (e > 0) cor = _mix(cor, _corErro, 0.75 * e);

      // 9) Desenho (cantos suaves, centrado na vertical).
      final double bh = (h * frac * encolher).clamp(2.0, h).toDouble();
      final double top = (h - bh) / 2 + dy;
      paint.color = cor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(layout.xs[i], top, layout.ws[i], bh),
          Radius.circular(math.min(layout.ws[i] / 2, 1.8)),
        ),
        paint,
      );
    }

    // Linha do feixe de leitura (brilho + núcleo).
    if (vm > 0.01) {
      final double x = beamNorm * size.width;
      final Paint brilho = Paint()
        ..color = corClara.withValues(alpha: 0.55 * vm)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 2, -2, 4, h + 4),
          const Radius.circular(2),
        ),
        brilho,
      );
      final Paint nucleo = Paint()
        ..color = corPrincipal.withValues(alpha: 0.85 * vm);
      canvas.drawRect(Rect.fromLTWH(x - 0.7, 0, 1.4, h), nucleo);
    }
  }

  @override
  bool shouldRepaint(covariant _CrystalBarcodePainter old) => true;
}