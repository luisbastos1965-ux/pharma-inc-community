import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'progress_manager.dart';

// Cores Oficiais Light Mode
const Color kProfiteclaBlue = Color(0xFF008AD8);
const Color kTextDark = Color(0xFF333333);
const Color kTextMuted = Color(0xFF757575);

/// Mapa central dos públicos/cursos (o número é o que fica guardado na base de dados).
const Map<int, String> kAudienceNames = {
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

/// Converte o valor de `audience` (int ou String) no nome do curso.
String audienceLabel(dynamic raw) {
  final id = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  return kAudienceNames[id] ?? 'Sem Curso';
}

class EscalaScreen extends StatefulWidget {
  const EscalaScreen({super.key});

  @override
  State<EscalaScreen> createState() => _EscalaScreenState();
}

class _EscalaScreenState extends State<EscalaScreen>
    with SingleTickerProviderStateMixin {
  String _selectedCategory = 'Global';
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  final List<String> _categories = ['Global', ...kAudienceNames.values];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  final GlobalKey _filterButtonKey = GlobalKey();

  IconData _iconForCategory(String cat) {
    if (cat == 'Global') return Icons.public_rounded;
    if (cat == 'Gestão e Administração') return Icons.business_center_rounded;
    if (cat == 'Desenvolvimento de Software') return Icons.computer_rounded;
    if (cat == 'Comunicação e Marketing') return Icons.campaign_rounded;
    if (cat == 'Multimédia') return Icons.movie_creation_rounded;
    if (cat == 'Cozinha e Restauração') return Icons.restaurant_rounded;
    if (cat == 'Turismo') return Icons.flight_takeoff_rounded;
    if (cat == 'Auxiliar de Saúde') return Icons.health_and_safety_rounded;
    if (cat == 'Auxiliar de Farmácia') return Icons.medical_information_rounded;
    if (cat == 'Secretariado Executivo') return Icons.assignment_ind_rounded;
    if (cat == 'Comunicação e Serviço Digital') return Icons.devices_rounded;
    if (cat == 'Professores') return Icons.school_rounded;
    return Icons.group_rounded;
  }

  Widget _buildFilterButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kProfiteclaBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kProfiteclaBlue.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(color: kProfiteclaBlue.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_alt_rounded, color: kProfiteclaBlue, size: 16),
          const SizedBox(width: 6),
          Text(
            _selectedCategory == 'Global' ? 'FILTRAR' : 'FILTRADO',
            style: const TextStyle(
              color: kProfiteclaBlue,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterCascade(BuildContext context) {
    final RenderBox? box = _filterButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    const double circleSize = 48;

    final Offset origin = box.localToGlobal(Offset.zero);
    final Size buttonSize = box.size;
    final Size screen = MediaQuery.of(context).size;
    final double rightInset = screen.width - (origin.dx + buttonSize.width);
    final double listTop = origin.dy + buttonSize.height + 14;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar filtro',
      barrierColor: Colors.black.withValues(alpha: 0.3), // Fundo escurecido mais leve no light mode
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              Widget buildItem(int i) {
                final String category = _categories[i];
                final bool isSelected = _selectedCategory == category;

                // O Interval exige end <= 1.0, por isso o atraso é distribuído pelas categorias
                final double start = i * (0.5 / _categories.length);
                final double t = Interval(start, start + 0.5, curve: Curves.easeOutBack)
                    .transform(animation.value);

                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * -24),
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * t,
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedCategory = category);
                            Navigator.pop(dialogContext);
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: isSelected ? kProfiteclaBlue : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected ? kProfiteclaBlue : const Color(0xFFE0E0E0),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      )
                                    ],
                                  ),
                                  child: Text(
                                    category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : kTextDark,
                                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: circleSize,
                                height: circleSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? kProfiteclaBlue : Colors.white,
                                  border: Border.all(
                                    color: isSelected ? kProfiteclaBlue : const Color(0xFFE0E0E0),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSelected
                                          ? kProfiteclaBlue.withValues(alpha: 0.3)
                                          : Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _iconForCategory(category),
                                  size: 22,
                                  color: isSelected ? Colors.white : kTextMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Stack(
                children: [
                  Positioned(
                    left: origin.dx,
                    top: origin.dy,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(dialogContext),
                      child: _buildFilterButton(),
                    ),
                  ),
                  Positioned(
                    right: rightInset,
                    top: listTop,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: screen.height - listTop - 16,
                        maxWidth: screen.width - rightInset - 16,
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (int i = 0; i < _categories.length; i++) buildItem(i),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final int userXP = ProgressManager().currentXP;
    const String userRole = 'Sem Curso';

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(
            top: -60,
            right: -60,
            child: _buildMolecule(kProfiteclaBlue.withValues(alpha: 0.05), 220),
          ),
          Positioned(
            bottom: 50,
            left: -70,
            child: _buildMolecule(kProfiteclaBlue.withValues(alpha: 0.08), 260),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: kProfiteclaBlue.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                            border: Border.all(color: kProfiteclaBlue.withValues(alpha: 0.15)),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: kProfiteclaBlue,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Ranking Profitecla',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: kTextDark,
                          letterSpacing: -0.5,
                        ),
                      ),
                      GestureDetector(
                        key: _filterButtonKey,
                        onTap: () => _showFilterCascade(context),
                        child: _buildFilterButton(),
                      ),
                    ],
                  ),
                ),

                if (_selectedCategory != 'Global')
                  Padding(
                    padding: const EdgeInsets.only(left: 24.0, top: 12.0, bottom: 4.0),
                    child: Row(
                      children: [
                        const Icon(Icons.subdirectory_arrow_right_rounded, color: kTextMuted, size: 14),
                        const SizedBox(width: 8),
                        Text(
                          _selectedCategory.toUpperCase(),
                          style: const TextStyle(
                            color: kTextMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 16),

                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: kProfiteclaBlue),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Erro ao carregar escala: ${snapshot.error}',
                            style: const TextStyle(color: kTextMuted),
                          ),
                        );
                      }

                      List<Map<String, dynamic>> list = [];

                      if (snapshot.hasData) {
                        for (var doc in snapshot.data!.docs) {
                          Map<String, dynamic> data = {};
                          try {
                            data = doc.data() as Map<String, dynamic>;
                          } catch (_) {}

                          String docId = doc.id;
                          String name = data['name']?.toString() ?? 'Aluno/a';

                          int xp = 0;
                          var rawXp = data['xp'];
                          if (rawXp is int) {
                            xp = rawXp;
                          } else if (rawXp != null) {
                            xp = int.tryParse(rawXp.toString()) ?? (docId == currentUserId ? userXP : 0);
                          } else if (docId == currentUserId) {
                            xp = userXP;
                          }

                          String role = data['audience'] != null
                              ? audienceLabel(data['audience'])
                              : (data['role']?.toString() ?? 'Sem Curso');

                          list.add({
                            'uid': docId,
                            'name': docId == currentUserId ? '$name (Tu)' : name,
                            'xp': xp,
                            'role': role,
                            'isUser': docId == currentUserId,
                            'capsuleTop': data['capsuleTop'],
                            'capsuleBottom': data['capsuleBottom'],
                          });
                        }
                      }

                      bool hasUser = false;
                      for (int i = 0; i < list.length; i++) {
                        if (list[i]['isUser'] == true) {
                          hasUser = true;
                          break;
                        }
                      }

                      if (!hasUser) {
                        list.add({
                          'uid': currentUserId ?? 'local_user',
                          'name': 'Aluno/a (Tu)',
                          'xp': userXP,
                          'role': userRole,
                          'isUser': true,
                        });
                      }

                      list.sort((a, b) {
                        int valA = a['xp'] as int;
                        int valB = b['xp'] as int;
                        return valB.compareTo(valA);
                      });

                      List<Map<String, dynamic>> filtered = [];
                      if (_selectedCategory == 'Global') {
                        filtered = list;
                      } else {
                        for (int i = 0; i < list.length; i++) {
                          if (list[i]['role'] == _selectedCategory) {
                            filtered.add(list[i]);
                          }
                        }
                      }

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text(
                            'Ainda não há pontuações nesta categoria.',
                            style: TextStyle(
                              color: kTextMuted,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }

                      return FadeTransition(
                        opacity: _fadeAnim,
                        child: ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 8.0,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            var player = filtered[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: _buildRankCard(
                                rank: index + 1,
                                name: player['name'].toString(),
                                xp: player['xp'] as int,
                                role: player['role'].toString(),
                                isUser: player['isUser'] as bool,
                                capsuleTop: player['capsuleTop'] as int?,
                                capsuleBottom: player['capsuleBottom'] as int?,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),

                // BARRA INFERIOR (A TUA POSIÇÃO)
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: const Border(
                      top: BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'A TUA POSIÇÃO NO RANKING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: kProfiteclaBlue,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .snapshots(),
                        builder: (context, snapshot) {
                          int userRank = 99;
                          if (snapshot.hasData) {
                            List<Map<String, dynamic>> checkList = [];
                            for (var doc in snapshot.data!.docs) {
                              Map<String, dynamic> data = {};
                              try {
                                data = doc.data() as Map<String, dynamic>;
                              } catch (_) {}

                              int xp = 0;
                              var rawXp = data['xp'];
                              if (rawXp is int) {
                                xp = rawXp;
                              } else if (rawXp != null) {
                                xp = int.tryParse(rawXp.toString()) ?? 0;
                              }

                              checkList.add({
                                'uid': doc.id,
                                'xp': xp,
                                'isUser': doc.id == currentUserId,
                              });
                            }

                            checkList.sort((a, b) {
                              int valA = a['xp'] as int;
                              int valB = b['xp'] as int;
                              return valB.compareTo(valA);
                            });

                            for (int i = 0; i < checkList.length; i++) {
                              if (checkList[i]['isUser'] == true) {
                                userRank = i + 1;
                                break;
                              }
                            }
                          }

                          return StreamBuilder<DocumentSnapshot>(
                            stream: currentUserId != null
                                ? FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(currentUserId)
                                    .snapshots()
                                : null,
                            builder: (context, userDocSnapshot) {
                              String dynamicName = 'Aluno/a';
                              String dynamicRole = userRole;
                              Map<String, dynamic>? userData;

                              if (userDocSnapshot.hasData &&
                                  userDocSnapshot.data != null &&
                                  userDocSnapshot.data!.exists) {
                                userData = userDocSnapshot.data!.data()
                                    as Map<String, dynamic>?;
                                if (userData != null) {
                                  if (userData['name'] != null) {
                                    dynamicName = userData['name'].toString();
                                  }
                                  
                                  if (userData['audience'] != null) {
                                    dynamicRole = audienceLabel(userData['audience']);
                                  } else if (userData['role'] != null) {
                                    dynamicRole = userData['role'].toString();
                                  }
                                }
                              }

                              return _buildRankCard(
                                rank: userRank,
                                name: '$dynamicName (Tu)',
                                xp: userXP,
                                role: dynamicRole,
                                isUser: true,
                                capsuleTop: userData?['capsuleTop'] as int?,
                                capsuleBottom: userData?['capsuleBottom'] as int?,
                              );
                            },
                          );
                        },
                      ),
                    ],
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

  Widget _buildRankCard({
    required int rank,
    required String name,
    required int xp,
    required String role,
    bool isUser = false,
    int? capsuleTop,
    int? capsuleBottom,
  }) {
    Color getRankColor(int r) {
      if (r == 1) return const Color(0xFFFFD700); // Ouro
      if (r == 2) return const Color(0xFF9E9E9E); // Prata (escurecido para destacar no branco)
      if (r == 3) return const Color(0xFFCD7F32); // Bronze
      return kProfiteclaBlue; // Restantes a azul em vez de cyan
    }

    final Color rankColor = getRankColor(rank);
    
    // Cores da cápsula (Agora o padrão é o Azul Profitecla para combinar com a nova identidade)
    final Color topColor = capsuleTop != null ? Color(capsuleTop) : kProfiteclaBlue;
    final Color bottomColor = capsuleBottom != null ? Color(capsuleBottom) : const Color(0xFF005C9E);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isUser
            ? kProfiteclaBlue.withValues(alpha: 0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUser
              ? kProfiteclaBlue.withValues(alpha: 0.3)
              : const Color(0xFFE0E0E0),
          width: isUser ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isUser
                ? kProfiteclaBlue.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // DESIGN DA CÁPSULA COM O NÚMERO DO RANK
          Container(
            width: 42,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [topColor, bottomColor],
                stops: const [0.5, 0.5],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: bottomColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: isUser ? FontWeight.w900 : FontWeight.w800,
                    fontSize: 15,
                    color: isUser ? kProfiteclaBlue : kTextDark,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  role.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: kTextMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$xp mg',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: rankColor,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}