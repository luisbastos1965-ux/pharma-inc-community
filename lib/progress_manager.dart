import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Resultado do registo de um caso clínico jogado.
enum RegistoCaso {
  /// Primeira vez que o caso é jogado: ficou registado (e os mg, se houver, creditados).
  primeiraVez,

  /// O caso já constava como jogado: nada foi alterado.
  jaJogado,

  /// Não foi possível confirmar no servidor: nada foi registado nem creditado.
  erro,
}

class _ResultadoTx {
  final bool primeiraVez;
  final int xp;
  final Set<String> jogados;
  const _ResultadoTx(this.primeiraVez, this.xp, this.jogados);
}

class ProgressManager {
  static final ProgressManager _instance = ProgressManager._internal();
  factory ProgressManager() => _instance;
  ProgressManager._internal();

  int currentXP = 0; // Pontuação em mg para o ranking (Escala)
  int selectedAudience = 11; // 1..10 cursos Profitecla | 11: Professores
  String playerName = 'Utilizador';

  /// ID do documento único da pauta (ex.: "user_1234").
  String? pautaDocId;

  /// UID a que pertence o estado em memória (evita misturar contas no mesmo dispositivo).
  String? _uidAtual;

  /// IDs dos casos clínicos já jogados (um só jogo por caso, por conta).
  /// Persistido em users/{pautaDocId}.casosJogados (array de strings).
  final Set<String> casosJogados = <String>{};

  bool jaJogou(String casoId) => casosJogados.contains(casoId);

  void _resetMemoria() {
    currentXP = 0;
    selectedAudience = 11;
    playerName = 'Utilizador';
    pautaDocId = null;
    casosJogados.clear();
  }

  /// Se mudou o utilizador autenticado, descarta o estado em memória da conta anterior.
  void _sincronizarUtilizador(String uid) {
    if (_uidAtual == uid) return;
    _uidAtual = uid;
    _resetMemoria();
  }

  static Set<String> _lerJogados(Map<String, dynamic>? data) {
    final raw = data?['casosJogados'];
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return <String>{};
  }

  String? _resolverPautaDocId({String? fallbackPautaId}) {
    if (fallbackPautaId != null && fallbackPautaId.trim().isNotEmpty) {
      pautaDocId = fallbackPautaId.trim();
    }
    return pautaDocId;
  }

  String get audienceName {
    switch (selectedAudience) {
      case 1:
        return 'Gestão e Administração';
      case 2:
        return 'Desenvolvimento de Software';
      case 3:
        return 'Comunicação e Marketing';
      case 4:
        return 'Multimédia';
      case 5:
        return 'Cozinha e Restauração';
      case 6:
        return 'Turismo';
      case 7:
        return 'Auxiliar de Saúde';
      case 8:
        return 'Auxiliar de Farmácia';
      case 9:
        return 'Secretariado Executivo';
      case 10:
        return 'Comunicação e Serviço Digital';
      case 11:
      default:
        return 'Professores';
    }
  }

  Future<void> init() async {
    await loadUserData();
  }

  Future<void> loadUserData({String? pautaId}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _sincronizarUtilizador(user.uid);

    final targetId = _resolverPautaDocId(fallbackPautaId: pautaId);
    if (targetId == null || targetId.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(targetId)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        playerName =
            (data['name'] ?? user.displayName ?? 'Utilizador').toString().trim();
        currentXP = ((data['xp'] ?? 0) as num).toInt();
        selectedAudience = ((data['audience'] ?? 11) as num).toInt();
        casosJogados
          ..clear()
          ..addAll(_lerJogados(data));
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados da pauta ($targetId): $e');
    }
  }

  /// Volta a ler do Firestore os casos já jogados na pauta (ex.: jogou noutro dispositivo).
  Future<void> refreshCasosJogados() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _sincronizarUtilizador(user.uid);

    final targetId = _resolverPautaDocId();
    if (targetId == null || targetId.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(targetId)
          .get();
      if (doc.exists && doc.data() != null) {
        currentXP = ((doc.data()!['xp'] ?? currentXP) as num).toInt();
        casosJogados.addAll(_lerJogados(doc.data()));
      }
    } catch (e) {
      debugPrint('Erro ao atualizar casos jogados da pauta: $e');
    }
  }

  /// Regista, de forma atómica (transação no servidor), na PAUTA (`users/{pautaDocId}`)
  /// que o caso foi jogado e credita os mg.
  Future<RegistoCaso> registarCasoJogado(String casoId, {int xpGanho = 0}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return RegistoCaso.erro;
    _sincronizarUtilizador(user.uid);

    final targetId = _resolverPautaDocId();
    if (targetId == null || targetId.isEmpty) return RegistoCaso.erro;

    if (casosJogados.contains(casoId)) return RegistoCaso.jaJogado;

    final int mg = xpGanho < 0 ? 0 : xpGanho;
    final ref = FirebaseFirestore.instance.collection('users').doc(targetId);

    try {
      final _ResultadoTx r =
          await FirebaseFirestore.instance.runTransaction<_ResultadoTx>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists || snap.data() == null) {
          throw StateError('Pauta $targetId inexistente.');
        }

        final data = snap.data()!;
        final jogados = _lerJogados(data);
        final int xpServidor = ((data['xp'] ?? 0) as num).toInt();

        if (jogados.contains(casoId)) {
          return _ResultadoTx(false, xpServidor, jogados);
        }

        final int novoXp = xpServidor + mg;
        final List<String> novaLista = [...jogados, casoId];
        tx.set(ref, {
          'xp': novoXp,
          'casosJogados': novaLista,
        }, SetOptions(merge: true));
        return _ResultadoTx(true, novoXp, jogados);
      });

      casosJogados
        ..addAll(r.jogados)
        ..add(casoId);
      currentXP = r.xp;
      return r.primeiraVez ? RegistoCaso.primeiraVez : RegistoCaso.jaJogado;
    } catch (e) {
      debugPrint('Erro ao registar caso jogado ($casoId) em $targetId: $e');
      return RegistoCaso.erro;
    }
  }

  Future<void> addXP(int amount) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _sincronizarUtilizador(user.uid);

    final targetId = _resolverPautaDocId();
    if (targetId == null || targetId.isEmpty) return;

    currentXP += amount;
    if (currentXP < 0) currentXP = 0;

    await FirebaseFirestore.instance.collection('users').doc(targetId).set({
      'xp': currentXP,
    }, SetOptions(merge: true));
  }

  Future<void> updateOfficialAudience(int newAudience) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _sincronizarUtilizador(user.uid);

    final targetId = _resolverPautaDocId();
    if (targetId == null || targetId.isEmpty) return;

    selectedAudience = newAudience;
    await FirebaseFirestore.instance.collection('users').doc(targetId).set({
      'audience': selectedAudience,
    }, SetOptions(merge: true));
  }

  Future<void> resetProgress() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _sincronizarUtilizador(user.uid);

    final targetId = _resolverPautaDocId();
    if (targetId == null || targetId.isEmpty) return;

    currentXP = 0;
    casosJogados.clear();
    await FirebaseFirestore.instance.collection('users').doc(targetId).set({
      'xp': 0,
      'casosJogados': <String>[],
    }, SetOptions(merge: true));
  }
}