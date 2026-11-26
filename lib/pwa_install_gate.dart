import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'pwa_platform.dart';

// Paleta local (evita dependência circular com o main.dart)
const Color _kAzul = Color(0xFF008AD8);
const Color _kAzulClaro = Color(0xFFE1F0FA);
const Color _kTexto = Color(0xFF333333);
const Color _kTextoSuave = Color(0xFF757575);

enum _Alvo { android, ios, outro }

/// Ecrã bloqueante: só deixa passar para [child] quando a app está
/// instalada (modo standalone). Num separador normal de um telemóvel
/// mostra instruções de instalação.
///
/// - [ativo]: desliga o gate por completo (ex.: build de testes).
/// - [ativoEmDebug]: por defeito o gate NÃO bloqueia em `flutter run`.
/// - [bloquearDesktop]: por defeito só bloqueia Android/iOS; em computador
///   a app abre normalmente (útil para professores/desenvolvimento).
class PwaInstallGate extends StatefulWidget {
  final Widget child;
  final bool ativo;
  final bool ativoEmDebug;
  final bool bloquearDesktop;

  const PwaInstallGate({
    super.key,
    required this.child,
    this.ativo = true,
    this.ativoEmDebug = false,
    this.bloquearDesktop = false,
  });

  @override
  State<PwaInstallGate> createState() => _PwaInstallGateState();
}

class _PwaInstallGateState extends State<PwaInstallGate> {
  late final bool _passa;
  late final _Alvo _alvoDetetado;
  late _Alvo _alvo;
  late final bool _ios;
  late final bool _emAppEmbutida; // Instagram, Facebook, TikTok, etc.
  late final bool _iosSafari;
  late final bool _androidChrome;
  bool _instalando = false;
  bool _instaladaAgora = false;

  @override
  void initState() {
    super.initState();
    final ua = pwaUserAgent();
    final toques = pwaMaxTouchPoints();

    final iphoneIpod = RegExp(r'iPhone|iPod').hasMatch(ua);
    final ipad =
        ua.contains('iPad') || (ua.contains('Macintosh') && toques > 1);
    _ios = iphoneIpod || ipad;
    final android = ua.contains('Android');

    _emAppEmbutida = RegExp(
      r'FBAN|FBAV|Instagram|Line/|MicroMessenger|TikTok|Snapchat|; wv\)',
    ).hasMatch(ua);
    _iosSafari =
        _ios &&
        !RegExp(r'CriOS|FxiOS|EdgiOS|OPiOS|GSA/').hasMatch(ua) &&
        !_emAppEmbutida;
    _androidChrome =
        android &&
        ua.contains('Chrome') &&
        !RegExp(r'SamsungBrowser|OPR/|Edg|Firefox|Brave').hasMatch(ua) &&
        !_emAppEmbutida;

    _alvoDetetado = _ios
        ? _Alvo.ios
        : (android ? _Alvo.android : _Alvo.outro);
    _alvo = _alvoDetetado;

    _passa = _devePassar();
    if (!_passa) {
      pwaListen(() {
        if (mounted) setState(() {});
      });
    }
  }

  bool _devePassar() {
    if (!kIsWeb) return true;
    if (!widget.ativo) return true;
    if (kDebugMode && !widget.ativoEmDebug) return true;
    if (pwaIsStandalone()) return true;
    if (_alvoDetetado == _Alvo.outro && !widget.bloquearDesktop) return true;
    return false;
  }

  Future<void> _instalar() async {
    setState(() => _instalando = true);
    final ok = await pwaPromptInstall();
    if (!mounted) return;
    setState(() {
      _instalando = false;
      _instaladaAgora = ok;
    });
  }

  void _mostrarDiagnostico() {
    final diag = pwaDiagnostics();
    final linhas = <String>[
      'alvo detetado: ${_alvoDetetado.name}',
      'iOS Safari: $_iosSafari',
      'Android Chrome: $_androidChrome',
      'browser embutido: $_emAppEmbutida',
      ...diag.entries.map((e) => '${e.key}: ${e.value}'),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Diagnóstico',
          style: TextStyle(fontWeight: FontWeight.w800, color: _kTexto),
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            linhas.join('\n'),
            style: const TextStyle(fontSize: 12, color: _kTexto, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar', style: TextStyle(color: _kAzul)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    if (_passa) return widget.child;

    final instalada = _instaladaAgora || pwaWasInstalled();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(
            top: -50,
            right: -70,
            child: _molecula(_kAzul.withValues(alpha: 0.05), 230),
          ),
          Positioned(
            bottom: -60,
            left: -80,
            child: _molecula(_kAzul.withValues(alpha: 0.07), 270),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                  child: Column(
                    children: [
                      Image.asset('assets/images/logo_splash.png', height: 110),
                      const SizedBox(height: 16),
                      const Text(
                        'Instala a Pharma SOS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _kTexto,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Para manteres a imersão do jogo, a app tem de ser '
                        'aberta a partir do ícone no ecrã principal do teu '
                        'telemóvel.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: _kTextoSuave,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _seletorPlataforma(),
                      const SizedBox(height: 16),
                      if (instalada)
                        _painelInstalada()
                      else ...[
                        ..._avisos(),
                        if (_alvo == _Alvo.android) _botaoInstalarAndroid(),
                        _passos(_passosPara(_alvo)),
                      ],
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: _mostrarDiagnostico,
                        child: Text(
                          'Diagnóstico (professor)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _kTextoSuave.withValues(alpha: 0.8),
                          ),
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

  // ------------------------------------------------------------ COMPONENTES

  Widget _molecula(Color cor, double tamanho) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: tamanho,
        height: tamanho,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tamanho / 3),
          border: Border.all(color: cor, width: 4),
        ),
        child: Center(
          child: Container(
            width: tamanho / 2,
            height: tamanho / 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cor, width: 4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _seletorPlataforma() {
    Widget pilula(_Alvo alvo, IconData icone, String texto) {
      final sel = _alvo == alvo;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _alvo = alvo),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? _kAzul : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icone, size: 16, color: sel ? Colors.white : _kAzul),
                const SizedBox(width: 6),
                Text(
                  texto,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: sel ? Colors.white : _kAzul,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _kAzulClaro,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          pilula(_Alvo.android, Icons.android_rounded, 'Android'),
          pilula(_Alvo.ios, Icons.phone_iphone_rounded, 'iPhone'),
          pilula(_Alvo.outro, Icons.more_horiz_rounded, 'Outro'),
        ],
      ),
    );
  }

  List<Widget> _avisos() {
    final avisos = <String>[];
    if (_emAppEmbutida) {
      avisos.add(
        'Estás a usar o browser de outra app (Instagram, Facebook, etc.). '
        'Abre esta ligação no ${_ios ? 'Safari' : 'Chrome'} para poderes instalar.',
      );
    } else if (_alvo == _Alvo.ios && _ios && !_iosSafari) {
      avisos.add(
        'No iPhone/iPad a instalação funciona melhor no Safari. '
        'Abre esta ligação no Safari e segue os passos abaixo.',
      );
    } else if (_alvo == _Alvo.android &&
        _alvoDetetado == _Alvo.android &&
        !_androidChrome) {
      avisos.add(
        'Recomendamos o Chrome. Noutros browsers o nome da opção pode '
        'variar (ver passos abaixo).',
      );
    }
    return avisos
        .map(
          (t) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFD58A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Color(0xFFB26A00),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Color(0xFF7A4B00),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  Widget _botaoInstalarAndroid() {
    final disponivel = pwaHasInstallPrompt();
    if (!disponivel) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _instalando ? null : _instalar,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kAzul,
            foregroundColor: Colors.white,
            elevation: 4,
            shadowColor: _kAzul.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
          ),
          icon: _instalando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.install_mobile_rounded),
          label: const Text(
            'Instalar agora',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
      ),
    );
  }

  Widget _painelInstalada() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kAzulClaro,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        children: [
          Icon(Icons.check_circle_rounded, size: 48, color: _kAzul),
          SizedBox(height: 12),
          Text(
            'App instalada!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _kTexto,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Fecha este separador e abre a Pharma SOS a partir do ícone no '
            'ecrã principal do teu telemóvel.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: _kTextoSuave,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<_Passo> _passosPara(_Alvo alvo) {
    switch (alvo) {
      case _Alvo.android:
        return const [
          _Passo(
            Icons.more_vert_rounded,
            'Abre o menu do Chrome',
            'Toca nos três pontos (⋮) no canto superior direito.',
          ),
          _Passo(
            Icons.add_to_home_screen_rounded,
            'Instalar app',
            'Escolhe "Instalar app" ou "Adicionar ao ecrã principal".',
          ),
          _Passo(
            Icons.touch_app_rounded,
            'Confirma',
            'Toca em "Instalar" na janela que aparecer.',
          ),
          _Passo(
            Icons.rocket_launch_rounded,
            'Abre pelo ícone',
            'Fecha este separador e abre a Pharma SOS no ecrã principal.',
          ),
        ];
      case _Alvo.ios:
        return const [
          _Passo(
            Icons.ios_share_rounded,
            'Toca em Partilhar',
            'No Safari, usa o botão de partilha (quadrado com seta) na barra '
                'inferior. No iPad fica no topo.',
          ),
          _Passo(
            Icons.add_box_outlined,
            'Adicionar ao ecrã principal',
            'Desliza a lista para baixo e escolhe "Adicionar ao ecrã principal".',
          ),
          _Passo(
            Icons.touch_app_rounded,
            'Confirma',
            'Toca em "Adicionar" no canto superior direito.',
          ),
          _Passo(
            Icons.rocket_launch_rounded,
            'Abre pelo ícone',
            'Fecha o Safari e abre a Pharma SOS no ecrã principal.',
          ),
        ];
      case _Alvo.outro:
        return const [
          _Passo(
            Icons.smartphone_rounded,
            'Usa o telemóvel',
            'O jogo foi pensado para telemóvel: Chrome (Android) ou Safari '
                '(iPhone/iPad).',
          ),
          _Passo(
            Icons.menu_rounded,
            'Abre o menu do browser',
            'Samsung Internet: menu ≡ → "Adicionar página a" → '
                '"Ecrã inicial". Firefox: menu ⋮ → "Instalar".',
          ),
          _Passo(
            Icons.computer_rounded,
            'Chrome / Edge no computador',
            'Procura o ícone de instalar na barra de endereço ou no menu → '
                '"Instalar Pharma SOS".',
          ),
          _Passo(
            Icons.rocket_launch_rounded,
            'Abre pelo ícone',
            'Depois de instalada, abre sempre a app a partir do ícone, '
                'não pelo browser.',
          ),
        ];
    }
  }

  Widget _passos(List<_Passo> passos) {
    return Column(
      children: [
        for (var i = 0; i < passos.length; i++)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE0E0E0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: _kAzulClaro,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(passos[i].icone, color: _kAzul, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i + 1}. ${passos[i].titulo}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: _kTexto,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        passos[i].texto,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: _kTextoSuave,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Passo {
  final IconData icone;
  final String titulo;
  final String texto;
  const _Passo(this.icone, this.titulo, this.texto);
}
