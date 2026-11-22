import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'progress_manager.dart';

class CasoClinicoScreen extends StatefulWidget {
  final String qrData;

  const CasoClinicoScreen({super.key, required this.qrData});

  @override
  State<CasoClinicoScreen> createState() => _CasoClinicoScreenState();
}

class _CasoClinicoScreenState extends State<CasoClinicoScreen> {
  // Identidade visual oficial Light Mode
  static const Color kProfiteclaBlue = Color(0xFF008AD8);
  static const Color kProfiteclaDarkBlue = Color(0xFF005C9E);
  static const Color kTextDark = Color(0xFF333333);
  static const Color kTextMuted = Color(0xFF757575);
  static const Color kOk = Color(0xFF00A86B);
  static const Color kKo = Color(0xFFD9383A);

  static const Map<int, String> _nomesCursos = {
    1: 'Gestão e Administração',
    2: 'Desenvolvimento de Software',
    3: 'Comunicação e Marketing',
    4: 'Multimédia',
    5: 'Cozinha e Restauração',
    6: 'Turismo',
    7: 'Auxiliar de Saúde',
    8: 'Auxiliar de Farmácia',
    9: 'Secretariado Executivo',
    10: 'Comunicação e Serviço Digital',
    11: 'Professores',
  };

  // Cache em memória por curso (1..11) para evitar leituras repetidas no Firestore
  static final Map<int, Map<String, dynamic>> _courseCache = {};

  final math.Random _rng = math.Random();

  int? _audienceId;
  String _cursoNome = '';
  List<Map<String, dynamic>> _casosDoCurso = [];
  int _casoIndex = 0;

  List<Map<String, dynamic>> _opcoesApresentadas = [];
  int? _selectedOptionIndex;
  bool _hasAnswered = false;
  bool _isSavingPoints = false;

  bool _isLoading = true;
  String _errorMessage = '';
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _carregarCurso();
  }

  /// Extrai o número do curso (1..11) a partir de formatos como "CURSO_1", "curso_1" ou "1".
  int? _parseAudienceFromQr(String raw) {
    final cleaned = raw.trim().toUpperCase();
    final match = RegExp(r'(?:CURSO[_\-\s]*)?(\d{1,2})$').firstMatch(cleaned);
    if (match == null) return null;
    final num = int.tryParse(match.group(1)!);
    if (num == null || num < 1 || num > 11) return null;
    return num;
  }

  Future<void> _carregarCurso({bool forceRefresh = false}) async {
    final int token = ++_loadToken;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _selectedOptionIndex = null;
      _hasAnswered = false;
    });

    final int? parsedAudience = _parseAudienceFromQr(widget.qrData);
    if (parsedAudience == null) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _errorMessage =
            'Código QR (${widget.qrData.trim()}) inválido para a seleção de cursos.';
        _isLoading = false;
      });
      return;
    }

    try {
      Map<String, dynamic>? courseData =
          forceRefresh ? null : _courseCache[parsedAudience];

      if (courseData == null) {
        final DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('cursos_casos')
            .doc('curso_$parsedAudience')
            .get();

        if (!mounted || token != _loadToken) return;

        if (!doc.exists || doc.data() == null) {
          setState(() {
            _errorMessage =
                'O curso $parsedAudience (${_nomesCursos[parsedAudience] ?? ''}) ainda não está disponível na base de dados.';
            _isLoading = false;
          });
          return;
        }

        courseData = Map<String, dynamic>.from(doc.data() as Map);
        _courseCache[parsedAudience] = courseData;
      }

      final List<dynamic> rawCasos = (courseData['casos'] as List?) ?? const [];
      final List<Map<String, dynamic>> casosLimpos = rawCasos
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (casosLimpos.isEmpty) {
        if (!mounted || token != _loadToken) return;
        setState(() {
          _errorMessage =
              'Este curso ainda não tem situações de saúde configuradas.';
          _isLoading = false;
        });
        return;
      }

      final String nomeCurso = (courseData['curso'] ??
              _nomesCursos[parsedAudience] ??
              'Curso $parsedAudience')
          .toString()
          .trim();

      final int initialIndex = _rng.nextInt(casosLimpos.length);

      if (!mounted || token != _loadToken) return;
      setState(() {
        _audienceId = parsedAudience;
        _cursoNome = nomeCurso;
        _casosDoCurso = casosLimpos;
        _isLoading = false;
      });
      _prepararCaso(initialIndex);
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _errorMessage = 'Erro ao carregar os dados do curso: $e';
        _isLoading = false;
      });
    }
  }

  void _prepararCaso(int index) {
    if (_casosDoCurso.isEmpty) return;
    final int safeIndex = index % _casosDoCurso.length;
    final Map<String, dynamic> caso = _casosDoCurso[safeIndex];

    final String respostaCorreta =
        (caso['resposta_correta'] ?? '').toString().trim().toUpperCase();

    final List<Map<String, dynamic>> opcoesList = [];
    final dynamic rawOpcoes = caso['opcoes'];

    if (rawOpcoes is Map) {
      final entries = rawOpcoes.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        final String chave = entry.key.toString().trim().toUpperCase();
        final String texto = entry.value.toString().trim();
        opcoesList.add({
          'chaveOriginal': chave,
          'texto': texto,
          'correta': respostaCorreta.isNotEmpty && chave == respostaCorreta,
        });
      }
    } else if (rawOpcoes is List) {
      const letras = ['A', 'B', 'C', 'D', 'E'];
      for (int i = 0; i < rawOpcoes.length; i++) {
        final String chave = i < letras.length ? letras[i] : '${i + 1}';
        final String texto = rawOpcoes[i].toString().trim();
        final bool correta = respostaCorreta.isNotEmpty &&
            (chave == respostaCorreta ||
                texto.toUpperCase().startsWith(respostaCorreta));
        opcoesList.add({
          'chaveOriginal': chave,
          'texto': texto,
          'correta': correta,
        });
      }
    }

    // Baralha as opções para evitar que a resposta certa seja sempre adivinhada por posição/extensão
    opcoesList.shuffle(_rng);

    setState(() {
      _casoIndex = safeIndex;
      _opcoesApresentadas = opcoesList;
      _selectedOptionIndex = null;
      _hasAnswered = false;
    });
  }

  Map<String, dynamic>? get _casoAtual {
    if (_casosDoCurso.isEmpty) return null;
    return _casosDoCurso[_casoIndex];
  }

  int get _mgRecompensa {
    final dynamic raw = _casoAtual?['mg_recompensa'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 100;
  }

  void _select(int index) {
    if (_hasAnswered || _isSavingPoints) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedOptionIndex = index);
  }

  Future<void> _confirmAnswer() async {
    if (_selectedOptionIndex == null || _hasAnswered || _isSavingPoints) return;
    HapticFeedback.mediumImpact();

    final bool isCorrect =
        _opcoesApresentadas[_selectedOptionIndex!]['correta'] == true;

    setState(() {
      _hasAnswered = true;
      _isSavingPoints = isCorrect;
    });

    if (isCorrect && _mgRecompensa > 0) {
      try {
        await ProgressManager().addXP(_mgRecompensa);
      } catch (e) {
        debugPrint('Erro ao guardar mg no ProgressManager: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isSavingPoints = false);
    _showResultBottomSheet(isCorrect);
  }

  void _showResultBottomSheet(bool isCorrect) {
    final Color accent = isCorrect ? kOk : kKo;
    final String feedback = (_casoAtual?['feedback'] ?? '').toString().trim();
    final bool temMaisCasos = _casosDoCurso.length > 1;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: accent.withValues(alpha: 0.35), width: 1.5),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.12),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    isCorrect ? Icons.check_rounded : Icons.warning_amber_rounded,
                    color: accent,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isCorrect ? 'ABORDAGEM ADEQUADA' : 'ATENÇÃO À CONDUTA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                if (feedback.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    feedback,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kTextDark,
                      fontSize: 14.5,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (isCorrect) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: kProfiteclaBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: kProfiteclaBlue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.medication_rounded,
                          size: 16,
                          color: kProfiteclaBlue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+ $_mgRecompensa MG NA ESCALA',
                          style: const TextStyle(
                            color: kProfiteclaBlue,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (temMaisCasos) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        final nextIndex = (_casoIndex + 1) % _casosDoCurso.length;
                        _prepararCaso(nextIndex);
                      },
                      icon: const Icon(Icons.skip_next_rounded, size: 20),
                      label: const Text(
                        'OUTRA SITUAÇÃO DESTE CURSO',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kProfiteclaBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kTextDark,
                      side: const BorderSide(color: Color(0xFFD0D7DE)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'VOLTAR À LEITURA DE QR',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
            width: size / 2,
            height: size / 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 4),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Positioned(
              top: -60,
              right: -60,
              child: _buildMolecule(
                kProfiteclaBlue.withValues(alpha: 0.05),
                220,
              ),
            ),
            Positioned(
              bottom: 60,
              left: -70,
              child: _buildMolecule(
                kProfiteclaBlue.withValues(alpha: 0.08),
                260,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _buildBody(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final bool podeTrocarCaso =
        !_isLoading && !_hasAnswered && _casosDoCurso.length > 1;
    final String badgeText = _cursoNome.isNotEmpty
        ? _cursoNome.toUpperCase()
        : widget.qrData.trim().replaceAll('_', ' ').toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(50),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kProfiteclaBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: kProfiteclaBlue.withValues(alpha: 0.18),
                ),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: kProfiteclaBlue,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: kProfiteclaBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: kProfiteclaBlue.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.school_rounded,
                    size: 16,
                    color: kProfiteclaBlue,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      badgeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kProfiteclaBlue,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          podeTrocarCaso
              ? InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _prepararCaso((_casoIndex + 1) % _casosDoCurso.length);
                  },
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kProfiteclaBlue.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kProfiteclaBlue.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Icon(
                      Icons.shuffle_rounded,
                      color: kProfiteclaBlue,
                      size: 20,
                    ),
                  ),
                )
              : const SizedBox(width: 42, height: 42),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        key: ValueKey('loading'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kProfiteclaBlue),
            SizedBox(height: 16),
            Text(
              'A carregar situações do curso...',
              style: TextStyle(
                color: kTextMuted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty || _casoAtual == null) {
      return KeyedSubtree(
        key: const ValueKey('erro'),
        child: _buildError(),
      );
    }

    final String titulo = (_casoAtual!['titulo'] ?? 'Situação Clínica').toString();
    final String cenario = (_casoAtual!['cenario'] ?? '').toString();
    final String pergunta = (_casoAtual!['pergunta'] ?? '').toString();
    final String idCaso = (_casoAtual!['id'] ?? '').toString();

    return KeyedSubtree(
      key: ValueKey('caso_${_audienceId}_$_casoIndex'),
      child: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0xFFE0E0E0),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kProfiteclaBlue.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: kProfiteclaBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.health_and_safety_rounded,
                              color: kProfiteclaBlue,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CASO ${_casoIndex + 1} DE ${_casosDoCurso.length}${idCaso.isNotEmpty ? ' · ${idCaso.toUpperCase()}' : ''}',
                                  style: const TextStyle(
                                    color: kTextMuted,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  titulo,
                                  style: const TextStyle(
                                    color: kTextDark,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (cenario.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          cenario,
                          style: const TextStyle(
                            color: kTextDark,
                            fontSize: 14.5,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (pergunta.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Divider(color: Color(0xFFECEFF1), height: 1),
                        ),
                        Text(
                          pergunta,
                          style: const TextStyle(
                            color: kProfiteclaDarkBlue,
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'ESCOLHE UMA OPÇÃO',
                  style: TextStyle(
                    color: kTextMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                for (int i = 0; i < _opcoesApresentadas.length; i++) ...[
                  _buildOptionTile(i),
                  if (i < _opcoesApresentadas.length - 1)
                    const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          Positioned(
            bottom: 18,
            left: 20,
            right: 20,
            child: Center(child: _buildConfirmPill()),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile(int index) {
    final bool isSelected = _selectedOptionIndex == index;
    final String texto = (_opcoesApresentadas[index]['texto'] ?? '').toString();
    final String rotulo = String.fromCharCode(65 + index); // A, B, C, D...

    return GestureDetector(
      onTap: () => _select(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? kProfiteclaBlue.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? kProfiteclaBlue : const Color(0xFFE0E0E0),
            width: isSelected ? 2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? kProfiteclaBlue.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected
                    ? kProfiteclaBlue
                    : kProfiteclaBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  rotulo,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: isSelected ? Colors.white : kProfiteclaBlue,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: kTextDark,
                  height: 1.38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmPill() {
    final bool visible =
        _selectedOptionIndex != null && !_hasAnswered && !_isSavingPoints;

    return IgnorePointer(
      ignoring: !visible && !_isSavingPoints,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: (visible || _isSavingPoints) ? 1 : 0,
        child: ElevatedButton.icon(
          onPressed: _isSavingPoints ? null : _confirmAnswer,
          icon: _isSavingPoints
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 20),
          label: Text(
            _isSavingPoints ? 'A GUARDAR MG...' : 'CONFIRMAR RESPOSTA',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: kProfiteclaBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            elevation: 6,
            shadowColor: kProfiteclaBlue.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kKo.withValues(alpha: 0.1),
                border: Border.all(color: kKo.withValues(alpha: 0.35), width: 1.5),
              ),
              child: const Icon(Icons.error_outline_rounded, color: kKo, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kTextDark,
                fontSize: 14.5,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: () => _carregarCurso(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'TENTAR NOVAMENTE',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kProfiteclaBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}