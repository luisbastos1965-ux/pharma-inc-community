import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pratica_ui_components.dart';
import 'caso_clinico_screen.dart';

class PraticaScreen extends StatefulWidget {
  const PraticaScreen({super.key});

  @override
  State<PraticaScreen> createState() => _PraticaScreenState();
}

class _PraticaScreenState extends State<PraticaScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Color _profiteclaBlue = Color(0xFF008AD8);
  static const Color _lightBlueTint = Color(0xFFE1F0FA);
  static const Duration _startTimeout = Duration(seconds: 15);

  late final AnimationController _pulseController;
  late final MobileScannerController _scannerController;

  bool _isScanning = true;
  Timer? _resumeTimer;
  Timer? _startWatchdog;
  bool _busy = false;
  String? _localError;
  String _diagnosticLog = '';

  /// true enquanto o CasoClinicoScreen está aberto por cima deste ecrã.
  bool _navigating = false;

  /// true se a câmara foi parada porque a app saiu de primeiro plano.
  bool _stoppedByLifecycle = false;

  /// Fila: todas as operações de start/stop da câmara correm uma a uma, por ordem.
  Future<void> _cameraQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scannerController = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: const [BarcodeFormat.qrCode],
    );

    _scannerController.addListener(_onScannerStateChanged);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startCamera());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    _startWatchdog?.cancel();
    _scannerController.removeListener(_onScannerStateChanged);
    _pulseController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  bool get _isSecureContext {
    if (!kIsWeb) return true;
    final base = Uri.base;
    return base.scheme == 'https' ||
        base.host == 'localhost' ||
        base.host == '127.0.0.1';
  }

  String _describeState(MobileScannerState s) =>
      'Init=${s.isInitialized} | Run=${s.isRunning} | Err=${s.error?.errorCode.name ?? 'None'}';

  void _onScannerStateChanged() {
    final s = _scannerController.value;
    if (s.isInitialized || s.error != null) {
      _startWatchdog?.cancel();
    }
  }

  void _armWatchdog() {
    _startWatchdog?.cancel();
    _startWatchdog = Timer(_startTimeout, () {
      if (!mounted) return;
      final s = _scannerController.value;
      if (!s.isInitialized && s.error == null) {
        setState(() {
          _localError =
              'Timeout interno. O browser não emitiu o feed de vídeo.';
          _diagnosticLog +=
              '[Falha] Watchdog detetou timeout após ${_startTimeout.inSeconds}s.\n';
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // CICLO DE VIDA DA APP (Android / Flutter Web)
  // ---------------------------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      // Com o CasoClinicoScreen aberto, a câmara reinicia quando se regressar.
      if (_navigating) return;
      if (_stoppedByLifecycle) {
        unawaited(_startCamera(hardRestart: true));
      }
      return;
    }

    // inactive / hidden / paused: liberta a câmara.
    if (_navigating) return; // já está parada
    _stoppedByLifecycle = true;
    _isScanning = false;
    _resumeTimer?.cancel();
    unawaited(_stopCamera());
  }

  // ---------------------------------------------------------------------------
  // CÂMARA: operações serializadas
  // ---------------------------------------------------------------------------
  Future<void> _enqueueCamera(Future<void> Function() op) {
    final Future<void> next = _cameraQueue.then((_) => op());
    _cameraQueue = next.catchError((Object e) {
      debugPrint('Fila da câmara: $e');
    });
    return next;
  }

  Future<void> _stopCamera() => _enqueueCamera(() async {
        try {
          await _scannerController.stop();
        } catch (e) {
          debugPrint('Erro ao parar câmara: $e');
        }
      });

  Future<void> _startCamera({bool hardRestart = false}) =>
      _enqueueCamera(() => _startCameraNow(hardRestart: hardRestart));

  void _appendLog(String message) {
    if (!mounted) return;
    setState(() => _diagnosticLog += message);
  }

  Future<bool> _waitUntilInitialized({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    while (sw.elapsed < timeout) {
      if (!mounted) return false;
      final s = _scannerController.value;
      if (s.error != null) return false;
      if (s.isInitialized) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  /// Arranca (ou rearma) a câmara. Se a primeira tentativa não deixar o scanner
  /// inicializado, repete uma vez com paragem completa + pausa (reinício a frio).
  Future<void> _startCameraNow({required bool hardRestart}) async {
    if (!mounted) return;
    final c = _scannerController;

    // Já está a funcionar: só repõe a leitura.
    if (!hardRestart &&
        c.value.isInitialized &&
        c.value.isRunning &&
        c.value.error == null) {
      _stoppedByLifecycle = false;
      _localError = null;
      _isScanning = true;
      return;
    }

    setState(() {
      _busy = true;
      _localError = null;
      _diagnosticLog = '[Fase] Início do pedido de câmara.\n';
    });

    try {
      if (kIsWeb && !_isSecureContext) {
        setState(() => _localError = 'Contexto inseguro. A câmara requer HTTPS.');
        return;
      }

      bool ok = false;
      for (int attempt = 0; attempt < 2 && !ok && mounted; attempt++) {
        if (hardRestart || attempt > 0) {
          try {
            await c.stop();
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (!mounted) return;
        }

        _armWatchdog();
        try {
          await c.start().timeout(_startTimeout);
        } on TimeoutException {
          _appendLog('[Aviso] Tentativa ${attempt + 1}: start() expirou.\n');
        } on MobileScannerException catch (e) {
          _appendLog(
            '[Aviso] Tentativa ${attempt + 1}: ${e.errorCode.name}.\n',
          );
        } catch (e) {
          _appendLog('[Aviso] Tentativa ${attempt + 1}: $e\n');
        }

        if (!mounted) return;
        // Permissão negada / não suportado: não insistir.
        if (c.value.error != null) break;
        ok = await _waitUntilInitialized();
      }

      if (!mounted) return;

      if (ok) {
        _startWatchdog?.cancel();
        _stoppedByLifecycle = false;
        _localError = null;
        _isScanning = true;
      } else if (c.value.error == null) {
        setState(() {
          _localError = 'Não foi possível (re)iniciar a câmara. Tenta novamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onQRDetected(BarcodeCapture capture) async {
    if (!_isScanning) return;

    String? code;
    for (final barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        code = raw;
        break;
      }
    }
    if (code == null) return;
    final String scanned = code;

    // Bloqueia novas leituras de imediato (antes de qualquer await).
    _isScanning = false;
    _resumeTimer?.cancel();
    await _stopCamera();
    if (!mounted) return;

    final Uri? uri = Uri.tryParse(scanned);
    final bool isHttpUrl =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    if (isHttpUrl) {
      await _openUrl(uri);

      // Se a app foi para segundo plano, o ciclo de vida reinicia a câmara ao
      // regressar; este temporizador cobre o caso em que isso não acontece.
      _resumeTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted || _stoppedByLifecycle || _navigating) return;
        unawaited(_startCamera());
      });
      return;
    }

    _navigating = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CasoClinicoScreen(qrData: scanned),
        ),
      );
    } finally {
      _navigating = false;
    }

    if (!mounted) return;
    // Regresso (botão voltar, X ou "Voltar à leitura de QR"): rearma o scanner.
    await _startCamera(hardRestart: _stoppedByLifecycle);
  }

  Future<void> _openUrl(Uri url) async {
    bool opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Erro: $e');
    }

    if (!opened && mounted) {
      _showSnack(
        'Não foi possível abrir o link automaticamente.',
        background: Colors.red,
        duration: const Duration(seconds: 6),
      );
    }
  }

  void _showSnack(
    String message, {
    required Color background,
    Color textColor = Colors.white,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: textColor)),
          backgroundColor: background,
          behavior: SnackBarBehavior.floating,
          duration: duration,
        ),
      );
  }

  ({IconData icon, String title, String message}) _describeError(
    MobileScannerException error,
  ) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return (
          icon: Icons.no_photography_outlined,
          title: 'Acesso à câmara negado',
          message:
              'Autoriza a câmara nas definições e tenta novamente.',
        );
      case MobileScannerErrorCode.unsupported:
        return (
          icon: Icons.videocam_off_outlined,
          title: 'Câmara não suportada',
          message: 'Este dispositivo não suporta o acesso à câmara.',
        );
      default:
        return (
          icon: Icons.videocam_off_outlined,
          title: 'Não foi possível iniciar',
          message: 'Verifica se a câmara não está a ser usada.',
        );
    }
  }

  Widget _buildCenter(MobileScannerState state) {
    final error = state.error;

    if (error != null || _localError != null) {
      final info = error != null
          ? _describeError(error)
          : (
              icon: Icons.warning_amber_rounded,
              title: 'Erro ao iniciar câmara',
              message: _localError!,
            );
      final footer =
          '$_diagnosticLog${_describeState(state)}\nAmbiente: ${kIsWeb ? 'Web' : 'Nativo'}';

      return ScannerErrorCard(
        icon: info.icon,
        title: info.title,
        message: info.message,
        buttonLabel: 'TENTAR NOVAMENTE',
        footer: footer,
        onRetry: () => _startCamera(hardRestart: true),
      );
    }

    if (!state.isInitialized) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _profiteclaBlue.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: _profiteclaBlue.withValues(alpha: 0.15),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _profiteclaBlue),
              const SizedBox(height: 16),
              const Text(
                'A inicializar sistema ótico...',
                style: TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Aguarde um momento',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF757575), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return IgnorePointer(
      child: ScannerReticle(pulseController: _pulseController),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightBlueTint,
      body: ValueListenableBuilder<MobileScannerState>(
        valueListenable: _scannerController,
        builder: (context, state, _) {
          return Stack(
            children: [
              Positioned.fill(
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: _onQRDetected,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error) => const SizedBox.shrink(),
                  placeholderBuilder: (context) => const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _profiteclaBlue.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    ScannerTopBar(onBackPressed: () => Navigator.pop(context)),
                    const Spacer(),
                    _buildCenter(state),
                    const Spacer(),
                    const ScannerInstructionBox(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}