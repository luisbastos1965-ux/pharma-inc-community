import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'progress_manager.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  String _firestoreUserName = '';
  String _playerLicenseId = 'PI-0000';
  bool _isLoadingName = true;

  // Cores Oficiais Light Mode
  static const Color kProfiteclaBlue = Color(0xFF008AD8);
  static const Color kTextDark = Color(0xFF333333);
  static const Color kTextMuted = Color(0xFF757575);

  // Cores da cápsula (agora com o Azul Profitecla como base)
  static const Color _defaultCapsuleTop = kProfiteclaBlue;
  static const Color _defaultCapsuleBottom = Color(0xFF005C9E);
  Color _capsuleTop = _defaultCapsuleTop;
  Color _capsuleBottom = _defaultCapsuleBottom;

  static const List<Color> _capsulePalette = [
    kProfiteclaBlue,
    Color(0xFF005C9E),
    Color(0xFF9575CD),
    Color(0xFF512DA8),
    Color(0xFF42A5F5),
    Color(0xFF1565C0),
    Color(0xFF00BCD4),
    Color(0xFF0097A7),
    Color(0xFF26A69A),
    Color(0xFF00796B),
    Color(0xFF66BB6A),
    Color(0xFF388E3C),
    Color(0xFFFFA726),
    Color(0xFFEF6C00),
    Color(0xFFEF5350),
    Color(0xFFC62828),
    Color(0xFFEC407A),
    Color(0xFFAD1457),
    Color(0xFF8D6E63),
    Color(0xFF455A64),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCirc));
    _animController.forward();

    _fetchUserDataFromFirestore();
  }

  String _firstNameInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final firstWord = trimmed.split(RegExp(r'\s+')).first;
    final match = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').firstMatch(firstWord);
    return (match?.group(0) ?? firstWord[0]).toUpperCase();
  }

  Future<void> _fetchUserDataFromFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final shortUid = user.uid.length >= 6 ? user.uid.substring(0, 6).toUpperCase() : '8492PI';

        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          if (!mounted) return;
          final data = doc.data()!;
          final loadedName = (data['name'] ?? user.displayName ?? 'Utilizador').toString().trim();
          ProgressManager().playerName = loadedName;
          if (data['audience'] is num) {
            ProgressManager().selectedAudience = (data['audience'] as num).toInt();
          }
          setState(() {
            _firestoreUserName = loadedName;
            _playerLicenseId = 'REG. Nº #$shortUid';
            _capsuleTop = _colorFromData(data['capsuleTop']) ?? _defaultCapsuleTop;
            _capsuleBottom = _colorFromData(data['capsuleBottom']) ?? _defaultCapsuleBottom;
            _isLoadingName = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do Firestore: $e');
    }

    if (mounted) {
      final user = FirebaseAuth.instance.currentUser;
      final fallbackName = (user?.displayName ?? ProgressManager().playerName).trim();
      setState(() {
        _firestoreUserName = fallbackName.isEmpty ? 'Utilizador' : fallbackName;
        _playerLicenseId = 'REG. Nº #PI-2027';
        _isLoadingName = false;
      });
    }
  }

  Color? _colorFromData(dynamic raw) {
    if (raw is num) return Color(raw.toInt());
    return null;
  }

  Future<void> _saveCapsuleColors(Color top, Color bottom) async {
    setState(() {
      _capsuleTop = top;
      _capsuleBottom = bottom;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'capsuleTop': top.toARGB32(),
        'capsuleBottom': bottom.toARGB32(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao guardar cores da cápsula: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível guardar as cores. Tenta de novo.')),
      );
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthScreen()),
      (Route<dynamic> route) => false,
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Fim de Sessão', style: TextStyle(fontWeight: FontWeight.w900, color: kTextDark, fontSize: 18)),
          ],
        ),
        content: const Text('Vais desvincular o teu perfil do sistema. Confirmas?', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('MANTER SESSÃO', style: TextStyle(color: kTextMuted, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _signOut(context);
            },
            child: const Text('SAIR DA APP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = _isLoadingName ? 'A carregar...' : _firestoreUserName;
    final String capsuleLetter = _isLoadingName ? '' : _firstNameInitial(_firestoreUserName);
    final String audienceName = ProgressManager().audienceName;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(top: -50, right: -50, child: _buildMolecule(kProfiteclaBlue.withValues(alpha: 0.05), 200)),
          Positioned(bottom: 100, left: -80, child: _buildMolecule(kProfiteclaBlue.withValues(alpha: 0.08), 250)),

          SafeArea(
            child: Column(
              children: [
                // CABEÇALHO (Botão Voltar e Botão Sair)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: kProfiteclaBlue.withValues(alpha: 0.08), shape: BoxShape.circle),
                          child: const Icon(Icons.arrow_back_rounded, color: kProfiteclaBlue, size: 20),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showLogoutDialog(context),
                        icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 24),
                      ),
                    ],
                  ),
                ),

                // CONTEÚDO CENTRADO VERTICALMENTE
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: FadeTransition(
                        opacity: _fadeAnim,
                        child: SlideTransition(
                          position: _slideAnim,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 500),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // AVATAR CÁPSULA
                                  GestureDetector(
                                    onTap: _isLoadingName ? null : () => _showCapsuleEditor(_firestoreUserName),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        _buildCapsuleAvatar(
                                          letter: capsuleLetter,
                                          top: _capsuleTop,
                                          bottom: _capsuleBottom,
                                          width: 130,
                                          height: 180,
                                          fontSize: 64,
                                        ),
                                        Positioned(
                                          right: -4,
                                          bottom: 12,
                                          child: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: kProfiteclaBlue.withValues(alpha: 0.3), width: 1.5),
                                              boxShadow: [
                                                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
                                              ],
                                            ),
                                            child: const Icon(Icons.palette_rounded, size: 18, color: kProfiteclaBlue),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 32),

                                  // NOME
                                  Text(
                                    displayName,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: kTextDark, letterSpacing: -0.5),
                                  ),

                                  const SizedBox(height: 12),

                                  // NÚMERO DE CÉDULA OFICIAL
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.verified_rounded, size: 16, color: kProfiteclaBlue),
                                      const SizedBox(width: 6),
                                      Text(
                                        _playerLicenseId,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: kProfiteclaBlue,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 36),

                                  // TAG EXCLUSIVA DO CURSO COM ÍCONE DINÂMICO
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(color: const Color(0xFFE0E0E0)),
                                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 6))],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(_getIconForAudience(audienceName), size: 18, color: kProfiteclaBlue),
                                        const SizedBox(width: 8),
                                        Text(
                                          audienceName.toUpperCase(),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kTextDark, letterSpacing: 0.5),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 20),
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

  Widget _buildCapsuleAvatar({
    required String letter,
    required Color top,
    required Color bottom,
    double width = 110,
    double height = 150,
    double fontSize = 56,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 60 / 110),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            top,
            bottom,
          ],
          stops: const [0.5, 0.5],
        ),
        boxShadow: [
          BoxShadow(
            color: bottom.withValues(alpha: 0.3),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.8),
          width: 3.5,
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            shadows: const [
              Shadow(
                color: Colors.black45,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorRow(String label, Color selected, ValueChanged<Color> onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2.0, color: kTextMuted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _capsulePalette.map((c) {
            final bool isSelected = c == selected;
            return GestureDetector(
              onTap: () => onSelect(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? kTextDark : Colors.transparent,
                    width: isSelected ? 3 : 0,
                  ),
                  boxShadow: [
                    if (!isSelected)
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))
                  ],
                ),
                child: isSelected ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showCapsuleEditor(String displayName) {
    final String letter = _firstNameInitial(displayName);
    Color tempTop = _capsuleTop;
    Color tempBottom = _capsuleBottom;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'PERSONALIZAR CÁPSULA',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2.0, color: kTextDark),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: _buildCapsuleAvatar(
                        letter: letter,
                        top: tempTop,
                        bottom: tempBottom,
                        width: 66,
                        height: 90,
                        fontSize: 34,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildColorRow('PARTE SUPERIOR', tempTop, (c) => setSheetState(() => tempTop = c)),
                    const SizedBox(height: 20),
                    _buildColorRow('PARTE INFERIOR', tempBottom, (c) => setSheetState(() => tempBottom = c)),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kProfiteclaBlue,
                              side: BorderSide(color: kProfiteclaBlue.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            onPressed: () {
                              final rnd = math.Random();
                              Color pick() => _capsulePalette[rnd.nextInt(_capsulePalette.length)];
                              final Color newTop = pick();
                              Color newBottom = pick();
                              while (newBottom == newTop) {
                                newBottom = pick();
                              }
                              setSheetState(() {
                                tempTop = newTop;
                                tempBottom = newBottom;
                              });
                            },
                            icon: const Icon(Icons.casino_rounded, size: 18),
                            label: const Text('ALEATÓRIO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kProfiteclaBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            onPressed: () {
                              _saveCapsuleColors(tempTop, tempBottom);
                              Navigator.pop(sheetContext);
                            },
                            child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _getIconForAudience(String audience) {
    if (audience == 'Gestão e Administração') return Icons.business_center_rounded;
    if (audience == 'Desenvolvimento de Software') return Icons.computer_rounded;
    if (audience == 'Comunicação e Marketing') return Icons.campaign_rounded;
    if (audience == 'Multimédia') return Icons.movie_creation_rounded;
    if (audience == 'Cozinha e Restauração') return Icons.restaurant_rounded;
    if (audience == 'Turismo') return Icons.flight_takeoff_rounded;
    if (audience == 'Auxiliar de Saúde') return Icons.health_and_safety_rounded;
    if (audience == 'Auxiliar de Farmácia') return Icons.medical_information_rounded;
    if (audience == 'Secretariado Executivo') return Icons.assignment_ind_rounded;
    if (audience == 'Comunicação e Serviço Digital') return Icons.devices_rounded;
    if (audience == 'Professores') return Icons.school_rounded;
    return Icons.group_rounded;
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
}