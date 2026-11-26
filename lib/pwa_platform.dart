// Seleção condicional: no browser usa a implementação JS interop,
// noutras plataformas (testes, desktop, mobile nativo) usa o stub inerte.
export 'pwa_platform_stub.dart'
    if (dart.library.js_interop) 'pwa_platform_web.dart';
