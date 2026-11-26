// Implementação Web (JS interop moderno, sem dart:html).
// Requer Dart >= 3.3 (dart:js_interop + dart:js_interop_unsafe).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

const String _kPromptKey = '__pwaDeferredPrompt';
const String _kInstalledKey = '__pwaInstalled';

JSObject? get _nav {
  try {
    return globalContext.getProperty<JSObject?>('navigator'.toJS);
  } catch (_) {
    return null;
  }
}

/// True quando a app corre instalada (standalone / fullscreen / minimal-ui)
/// ou, no iOS, quando `navigator.standalone` é true.
bool pwaIsStandalone() {
  try {
    for (final mode in const [
      'standalone',
      'fullscreen',
      'minimal-ui',
      'window-controls-overlay',
    ]) {
      final mql = globalContext.callMethod<JSObject>(
        'matchMedia'.toJS,
        '(display-mode: $mode)'.toJS,
      );
      if (mql.getProperty<JSBoolean>('matches'.toJS).toDart) return true;
    }
  } catch (_) {}

  try {
    final s = _nav?.getProperty<JSAny?>('standalone'.toJS);
    if (s.dartify() == true) return true;
  } catch (_) {}

  return false;
}

String pwaUserAgent() {
  try {
    return _nav?.getProperty<JSString>('userAgent'.toJS).toDart ?? '';
  } catch (_) {
    return '';
  }
}

int pwaMaxTouchPoints() {
  try {
    final v = _nav?.getProperty<JSAny?>('maxTouchPoints'.toJS).dartify();
    if (v is num) return v.toInt();
  } catch (_) {}
  return 0;
}

JSObject? _deferredPrompt() {
  try {
    return globalContext.getProperty<JSObject?>(_kPromptKey.toJS);
  } catch (_) {
    return null;
  }
}

/// True se o Chrome já entregou o evento `beforeinstallprompt`.
bool pwaHasInstallPrompt() => _deferredPrompt() != null;

bool pwaWasInstalled() {
  try {
    return globalContext.getProperty<JSAny?>(_kInstalledKey.toJS).dartify() ==
        true;
  } catch (_) {
    return false;
  }
}

/// Abre o diálogo nativo de instalação. Devolve true se o utilizador aceitou.
Future<bool> pwaPromptInstall() async {
  final p = _deferredPrompt();
  if (p == null) return false;
  try {
    p.callMethod<JSAny?>('prompt'.toJS);
    final choice = await p
        .getProperty<JSPromise<JSObject>>('userChoice'.toJS)
        .toDart;
    final outcome = choice.getProperty<JSString>('outcome'.toJS).toDart;
    // O evento só pode ser usado uma vez.
    globalContext.setProperty(_kPromptKey.toJS, null);
    return outcome == 'accepted';
  } catch (_) {
    return false;
  }
}

/// Regista listeners para `beforeinstallprompt` e `appinstalled`.
/// (O ideal é também capturar o evento cedo no index.html, ver instruções.)
void pwaListen(void Function() onChange) {
  try {
    void onBeforeInstall(JSObject e) {
      e.callMethod<JSAny?>('preventDefault'.toJS);
      globalContext.setProperty(_kPromptKey.toJS, e);
      onChange();
    }

    void onInstalled(JSObject e) {
      globalContext.setProperty(_kPromptKey.toJS, null);
      globalContext.setProperty(_kInstalledKey.toJS, true.toJS);
      onChange();
    }

    globalContext.callMethod<JSAny?>(
      'addEventListener'.toJS,
      'beforeinstallprompt'.toJS,
      onBeforeInstall.toJS,
    );
    globalContext.callMethod<JSAny?>(
      'addEventListener'.toJS,
      'appinstalled'.toJS,
      onInstalled.toJS,
    );
  } catch (_) {}
}

Map<String, String> pwaDiagnostics() {
  String mq(String mode) {
    try {
      final mql = globalContext.callMethod<JSObject>(
        'matchMedia'.toJS,
        '(display-mode: $mode)'.toJS,
      );
      return mql.getProperty<JSBoolean>('matches'.toJS).toDart.toString();
    } catch (_) {
      return 'n/d';
    }
  }

  String navStandalone() {
    try {
      return _nav
              ?.getProperty<JSAny?>('standalone'.toJS)
              .dartify()
              ?.toString() ??
          'undefined';
    } catch (_) {
      return 'n/d';
    }
  }

  return {
    'display-mode: standalone': mq('standalone'),
    'display-mode: fullscreen': mq('fullscreen'),
    'display-mode: minimal-ui': mq('minimal-ui'),
    'navigator.standalone': navStandalone(),
    'beforeinstallprompt': pwaHasInstallPrompt().toString(),
    'maxTouchPoints': pwaMaxTouchPoints().toString(),
    'userAgent': pwaUserAgent(),
  };
}
