import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'auth_screen.dart';
import 'level_selection.dart';
import 'audio_manager.dart';
import 'progress_manager.dart';
import 'rules_screen.dart';
import 'profile_screen.dart';
import 'gabinete_screen.dart';
import 'escala_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dica_balcao_card.dart';
import 'pratica_screen.dart';

// Altura partilhada entre a cápsula de modos e a barra de navegação
const double kBarraAltura = 56;
const double kEspacoVertical = 28; // distância vertical padrão entre blocos do menu

// Cores Oficiais Profitecla e Light Mode
const Color kProfiteclaBlue = Color(0xFF008AD8);
const Color kTextDark = Color(0xFF333333);
const Color kTextMuted = Color(0xFF757575);

// Inicializa o Firebase
Future<void> _initFirebase() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FirebaseInitializer());
}

class FirebaseInitializer extends StatelessWidget {
  const FirebaseInitializer({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFirebase(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'Erro de configuração Firebase:\n${snapshot.error}', 
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kTextDark),
                  ),
                ),
              ),
            ),
          );
        }
        
        if (snapshot.connectionState == ConnectionState.done) {
          return const PharmaIncApp();
        }
        
        return const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator(color: kProfiteclaBlue)),
          ),
        );
      },
    );
  }
}

class PharmaIncApp extends StatelessWidget {
  const PharmaIncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pharma SOS', // Novo nome comunitário
      theme: ThemeData(
        useMaterial3: true,
        // Aplica a cor escura de texto por defeito a todas as fontes Poppins
        textTheme: GoogleFonts.poppinsTextTheme().apply(
          bodyColor: kTextDark,
          displayColor: kTextDark,
        ),
        scaffoldBackgroundColor: Colors.white,
        primaryColor: kProfiteclaBlue,
        
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _opacity = 0.0;
  double _scale = 0.8;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _opacity = 1.0;
        _scale = 1.0;
      });
    });

    _checkSessionAndNavigate();
  }

  Future<void> _checkSessionAndNavigate() async {
    await Future.delayed(const Duration(milliseconds: 3500));
    
    if (!mounted) return;

    User? user;
    try {
      try {
        final redirectCred = await FirebaseAuth.instance.getRedirectResult();
        user = redirectCred?.user;
      } catch (e) {
        debugPrint('getRedirectResult falhou (ignorado): $e');
      }

      user ??= await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => FirebaseAuth.instance.currentUser);

      if (user != null) {
        final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        final doc = await docRef.get();

        if (!doc.exists) {
          await docRef.set({
            'name': user.displayName ?? 'Farmacêutico',
            'audience': 5, 
            'xp': 0,
            'level': 1,
            'careerTitle': 'Estagiário/a',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        await ProgressManager().loadUserData();
      }
    } catch (e) {
      debugPrint('Erro ao verificar sessão no SplashScreen: $e');
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              user != null ? const MenuScreen() : const AuthScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedOpacity(
          duration: const Duration(seconds: 2),
          opacity: _opacity,
          curve: Curves.easeIn,
          child: AnimatedScale(
            duration: const Duration(seconds: 2),
            scale: _scale,
            curve: Curves.easeOutCubic,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  // Sombra subtil azulada para dar relevo ao logo
                  BoxShadow(
                    color: kProfiteclaBlue.withValues(alpha: 0.1),
                    blurRadius: 60,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Image.asset('assets/images/logo_splash.png', width: 300),
            ),
          ),
        ),
      ),
    );
  }
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isBgmStarted = false;

  @override
  void initState() {
    super.initState();
    AudioManager().playCrossfade('bgm.mp3');
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Listener(
        onPointerDown: (_) {
          if (!_isBgmStarted) {
            AudioManager().playCrossfade('bgm.mp3');
            _isBgmStarted = true;
          }
        },
        child: Stack(
          children: [
            // Moléculas em marca de água Azul Profitecla
            Positioned(top: -40, right: -60, child: _buildMolecule(kProfiteclaBlue.withValues(alpha: 0.05), 220)),
            Positioned(bottom: 100, left: -70, child: _buildMolecule(kProfiteclaBlue.withValues(alpha: 0.08), 260)),

            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          children: [
                            const SizedBox(height: 12),

                            // TOP BAR (Perfil e Volume)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [Color(0xFF33B5FF), kProfiteclaBlue],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: kProfiteclaBlue.withValues(alpha: 0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          FirebaseAuth.instance.currentUser?.displayName?.isNotEmpty == true 
                                              ? FirebaseAuth.instance.currentUser!.displayName![0].toUpperCase() 
                                              : 'P',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900, 
                                            fontSize: 18, 
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text.rich(
                                          TextSpan(
                                            children: [
                                              TextSpan(
                                                text: '${FirebaseAuth.instance.currentUser?.displayName?.split(' ')[0] ?? 'Comunidade'} • ',
                                                style: const TextStyle(fontWeight: FontWeight.w900, color: kTextDark, fontSize: 13),
                                              ),
                                              TextSpan(
                                                text: ProgressManager().audienceName,
                                                style: const TextStyle(fontWeight: FontWeight.w900, color: kProfiteclaBlue, fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${ProgressManager().careerTitle} • Nível ${ProgressManager().currentLevel} (${ProgressManager().currentXP} XP)',
                                          style: const TextStyle(fontWeight: FontWeight.w700, color: kTextMuted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                
                                Container(
                                  decoration: BoxDecoration(
                                    color: kProfiteclaBlue.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      AudioManager().isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                      color: kProfiteclaBlue,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        AudioManager().toggleMute();
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: kEspacoVertical),

                            const DicaBalcaoCard(),

                            // LOGO BALANÇANTE
                            Expanded(
                              child: Center(
                                child: AnimatedBuilder(
                                  animation: _animation,
                                  builder: (context, child) {
                                    return Transform.translate(
                                      offset: Offset(0, _animation.value),
                                      child: child,
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: kProfiteclaBlue.withValues(alpha: 0.05), 
                                          blurRadius: 40, 
                                          spreadRadius: 5
                                        ),
                                      ],
                                    ),
                                    child: Image.asset('assets/images/logo_splash.png', height: 210),
                                  ),
                                ),
                              ),
                            ),

                            // ESPAÇAMENTO ENTRE O LOGO E O DOCK
                            const SizedBox(height: 60),

                            // DOCK INFERIOR (Com o botão "Play" integrado)
                            Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                // A BARRA BRANCA
                                Container(
                                  height: kBarraAltura,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(kBarraAltura / 2),
                                    border: Border.all(color: const Color(0xFFE0E0E0)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      // METADE ESQUERDA
                                      Expanded(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            _buildDockIcon(
                                              icon: Icons.menu_book_rounded,
                                              label: 'Bula',
                                              color: kTextDark,
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (context) => const RulesScreen()),
                                                );
                                              },
                                            ),
                                            _buildDockIcon(
                                              icon: Icons.badge_rounded,
                                              label: 'Cédula',
                                              color: kTextDark,
                                              onTap: () async {
                                                await Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                                                );
                                                setState(() {});
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      
                                      // ESPAÇO VAZIO NO CENTRO (Para a meia-lua do botão)
                                      const SizedBox(width: 70),
                                      
                                      // METADE DIREITA
                                      Expanded(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            _buildDockIcon(
                                              icon: Icons.leaderboard_rounded,
                                              label: 'Escala',
                                              color: kTextDark,
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (context) => const EscalaScreen()),
                                                );
                                              },
                                            ),
                                            _buildDockIcon(
                                              icon: Icons.settings_rounded,
                                              label: 'Gabinete',
                                              color: kTextDark,
                                              onTap: () async {
                                                await Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (context) => const GabineteScreen()),
                                                );
                                                setState(() {});
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                // O BOTÃO CENTRAL DE AÇÃO (FAB) FLUTUANTE
                                // (Removemos o Positioned para a Stack o centrar automaticamente!)
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const PraticaScreen()),
                                    );
                                  },
                                  child: Container(
                                    width: 68, // Aumentei ligeiramente (de 65 para 68) para o destaque superior/inferior ser mais notório
                                    height: 68,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: kProfiteclaBlue,
                                      border: Border.all(color: Colors.white, width: 4),
                                      boxShadow: [
                                        BoxShadow(
                                          color: kProfiteclaBlue.withValues(alpha: 0.4),
                                          blurRadius: 15,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.qr_code_scanner_rounded, 
                                        color: Colors.white, 
                                        size: 30,
                                      ),
                                    ),
                                  ),
                                ),
                              ], // <-- Fecho da Stack
                            ),
                            
                            const SizedBox(height: 12),
                            
                            // COPYRIGHT RESTAURADO
                            const Text(
                              'Pharma Inc. ©',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: kTextMuted,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
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
    );
  }

  Widget _buildDockIcon({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color.withValues(alpha: 0.8), size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}