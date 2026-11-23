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
  static const Color kProfiteclaBlue = Color(0xFF008AD8); // cor por omissão
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

  // Cor de cada curso (usada no padrão de fundo do ecrã de resolução)
  static const Map<int, Color> _coresCursos = {
    1: Color(0xFF1A365D), // Gestão e Administração
    2: Color(0xFF1E5631), // Desenvolvimento de Software
    3: Color(0xFFC84B31), // Comunicação e Marketing
    4: Color(0xFF4A235A), // Multimédia
    5: Color(0xFF800000), // Cozinha e Restauração
    6: Color(0xFF005B96), // Turismo
    7: Color(0xFF00695C), // Auxiliar de Saúde
    8: Color(0xFF513E7C), // Auxiliar de Farmácia
    9: Color(0xFF2C3E50), // Secretariado Executivo
    10: Color(0xFF880E4F), // Comunicação e Serviço Digital
    11: Color(0xFF4E342E), // Professores
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
  bool _todosConcluidos = false;
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
      _todosConcluidos = false;
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

      // Sincroniza os casos já jogados antes de sortear (um só jogo por caso).
      await ProgressManager().refreshCasosJogados();
      if (!mounted || token != _loadToken) return;

      final List<int> disponiveis = [
        for (int i = 0; i < casosLimpos.length; i++)
          if (!ProgressManager()
              .jaJogou(_idDoCaso(casosLimpos[i], i, parsedAudience)))
            i,
      ];

      if (disponiveis.isEmpty) {
        setState(() {
          _audienceId = parsedAudience;
          _cursoNome = nomeCurso;
          _casosDoCurso = casosLimpos;
          _todosConcluidos = true;
          _isLoading = false;
        });
        return;
      }

      final int initialIndex = disponiveis[_rng.nextInt(disponiveis.length)];

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

  /// ID estável do caso. Usa o campo "id" do JSON (ex.: caso_gea_001); se não
  /// existir, recorre a curso + posição na lista (frágil se a ordem mudar).
  String _idDoCaso(Map<String, dynamic> caso, int index, int audience) {
    final String id = (caso['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
    return 'curso_${audience}_$index';
  }

  /// Índices dos casos deste curso que o jogador ainda não jogou.
  List<int> _indicesDisponiveis({bool excluirAtual = false}) {
    final int aud = _audienceId ?? 0;
    return [
      for (int i = 0; i < _casosDoCurso.length; i++)
        if (!(excluirAtual && i == _casoIndex) &&
            !ProgressManager().jaJogou(_idDoCaso(_casosDoCurso[i], i, aud)))
          i,
    ];
  }

  void _sortearProximoCaso() {
    final List<int> disponiveis = _indicesDisponiveis(excluirAtual: true);
    if (disponiveis.isEmpty) return;
    _prepararCaso(disponiveis[_rng.nextInt(disponiveis.length)]);
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
                texto.toUpperCase() == respostaCorreta ||
                RegExp('^${RegExp.escape(respostaCorreta)}\\s*[\\)\\.\\-:]')
                    .hasMatch(texto.toUpperCase()));
        opcoesList.add({
          'chaveOriginal': chave,
          'texto': texto,
          'correta': correta,
        });
      }
    }

    // Baralha as opções para evitar que a resposta certa seja adivinhada por posição/extensão
    opcoesList.shuffle(_rng);

    setState(() {
      _casoIndex = safeIndex;
      _opcoesApresentadas = opcoesList;
      _selectedOptionIndex = null;
      _hasAnswered = false;
    });
  }

  /// Cor do curso atual (ou azul Profitecla se o QR ainda não foi interpretado).
  Color get _corCurso =>
      _coresCursos[_audienceId ?? _parseAudienceFromQr(widget.qrData)] ??
      kProfiteclaBlue;

  /// Variante mais escura da cor do curso (títulos de destaque).
  Color get _corCursoEscura =>
      Color.lerp(_corCurso, Colors.black, 0.25) ?? _corCurso;

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
    final String casoId =
        _idDoCaso(_casoAtual!, _casoIndex, _audienceId ?? 0);
    final int mg = _mgRecompensa;

    setState(() {
      _hasAnswered = true;
      _isSavingPoints = true;
    });

    // Regista o caso como jogado (certo ou errado) e credita os mg só à 1.ª vez
    // e só se a resposta estiver certa. O resultado só é revelado depois de o
    // servidor confirmar o registo.
    final RegistoCaso registo = await ProgressManager()
        .registarCasoJogado(casoId, xpGanho: isCorrect ? mg : 0);

    if (!mounted) return;

    if (registo == RegistoCaso.erro) {
      setState(() {
        _hasAnswered = false;
        _isSavingPoints = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Sem ligação ao servidor. A resposta não foi registada: tenta confirmar novamente.',
            ),
            backgroundColor: kKo,
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    setState(() => _isSavingPoints = false);
    _showResultBottomSheet(
      isCorrect,
      primeiraVez: registo == RegistoCaso.primeiraVez,
    );
  }

  void _showResultBottomSheet(bool isCorrect, {bool primeiraVez = true}) {
    final Color accent = isCorrect ? kOk : kKo;
    final String feedback = (_casoAtual?['feedback'] ?? '').toString().trim();
    final bool temMaisCasos = _indicesDisponiveis(excluirAtual: true).isNotEmpty;

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
                if (isCorrect && primeiraVez) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _corCurso.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _corCurso.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.medication_rounded,
                          size: 16,
                          color: _corCurso,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+ $_mgRecompensa MG NA ESCALA',
                          style: TextStyle(
                            color: _corCurso,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!primeiraVez) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Este caso já tinha sido jogado: não conta para a escala.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kTextMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (!temMaisCasos) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Concluíste todos os casos deste curso!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _corCursoEscura,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
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
                        _sortearProximoCaso();
                      },
                      icon: const Icon(Icons.shuffle_rounded, size: 20),
                      label: const Text(
                        'OUTRA SITUAÇÃO DESTE CURSO',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _corCurso,
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
                _corCurso.withValues(alpha: 0.05),
                220,
              ),
            ),
            Positioned(
              bottom: 60,
              left: -70,
              child: _buildMolecule(
                _corCurso.withValues(alpha: 0.08),
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
    final bool podeTrocarCaso = !_isLoading &&
        !_hasAnswered &&
        !_todosConcluidos &&
        _indicesDisponiveis(excluirAtual: true).isNotEmpty;
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
                color: _corCurso.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _corCurso.withValues(alpha: 0.18),
                ),
              ),
              child: Icon(
                Icons.close_rounded,
                color: _corCurso,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _corCurso.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _corCurso.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.school_rounded,
                    size: 16,
                    color: _corCurso,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      badgeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _corCurso,
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
                    _sortearProximoCaso();
                  },
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _corCurso.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _corCurso.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Icon(
                      Icons.shuffle_rounded,
                      color: _corCurso,
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
      return Center(
        key: ValueKey('loading'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _corCurso),
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

    if (_todosConcluidos) {
      return KeyedSubtree(
        key: const ValueKey('concluido'),
        child: _buildConcluido(),
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
                        color: _corCurso.withValues(alpha: 0.08),
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
                              color: _corCurso.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.health_and_safety_rounded,
                              color: _corCurso,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CASO ${_casoIndex + 1} DE ${_casosDoCurso.length}',
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
                          style: TextStyle(
                            color: _corCursoEscura,
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
              ? _corCurso.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? _corCurso : const Color(0xFFE0E0E0),
            width: isSelected ? 2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? _corCurso.withValues(alpha: 0.12)
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
                    ? _corCurso
                    : _corCurso.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  rotulo,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: isSelected ? Colors.white : _corCurso,
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
            _isSavingPoints ? 'A GUARDAR...' : 'CONFIRMAR RESPOSTA',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _corCurso,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            elevation: 6,
            shadowColor: _corCurso.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  Widget _buildConcluido() {
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
                color: kOk.withValues(alpha: 0.1),
                border: Border.all(color: kOk.withValues(alpha: 0.35), width: 1.5),
              ),
              child: const Icon(Icons.emoji_events_rounded, color: kOk, size: 38),
            ),
            const SizedBox(height: 16),
            const Text(
              'CURSO CONCLUÍDO',
              style: TextStyle(
                color: kOk,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Já jogaste todas as situações${_cursoNome.isNotEmpty ? ' de $_cursoNome' : ''}. '
              'Cada caso só pode ser jogado uma vez. Lê o QR code de outro curso para continuar.',
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
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text(
                'VOLTAR À LEITURA DE QR',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _corCurso,
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
                backgroundColor: _corCurso,
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