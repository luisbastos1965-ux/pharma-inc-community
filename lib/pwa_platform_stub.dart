// Implementação neutra (fora do browser). Nunca bloqueia nada.

bool pwaIsStandalone() => true;

String pwaUserAgent() => '';

int pwaMaxTouchPoints() => 0;

bool pwaHasInstallPrompt() => false;

bool pwaWasInstalled() => false;

Future<bool> pwaPromptInstall() async => false;

void pwaListen(void Function() onChange) {}

Map<String, String> pwaDiagnostics() => const {'plataforma': 'não-web'};
