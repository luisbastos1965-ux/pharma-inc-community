import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class ProgressManager {
  static final ProgressManager _instance = ProgressManager._internal();
  factory ProgressManager() => _instance;
  ProgressManager._internal();

  int currentXP = 0; // Pontuação em mg para o ranking (Escala)
  int selectedAudience = 11; // 1..10 cursos Profitecla | 11: Professores
  String playerName = 'Utilizador';

  /// IDs dos casos clínicos já jogados (um só jogo por caso, por conta).
  /// Persistido em users/{uid}.casosJogados (array de strings).
  final Set<String> casosJogados = <String>{};

  bool jaJogou(String casoId) => casosJogados.contains(casoId);

  static Set<String> _lerJogados(Map<String, dynamic>? data) {
    final raw = data?['casosJogados'];
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return <String>{};
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

  Future<void> loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
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
      debugPrint('Erro ao carregar dados do Firestore: $e');
    }
  }

  /// Volta a ler do Firestore os casos já jogados (ex.: jogou noutro dispositivo).
  /// Faz união com o que já existe em memória; em caso de erro mantém o local.
  Future<void> refreshCasosJogados() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      casosJogados.addAll(_lerJogados(doc.data()));
    } catch (e) {
      debugPrint('Erro ao atualizar casos jogados: $e');
    }
  }

  /// Regista, de forma atómica (transação), que o caso foi jogado e credita os mg.
  /// Devolve true se este foi o primeiro jogo do caso (os mg foram creditados) e
  /// false se o caso já constava como jogado (não credita nada).
  Future<bool> registarCasoJogado(String casoId, {int xpGanho = 0}) async {
    if (casosJogados.contains(casoId)) return false;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      casosJogados.add(casoId);
      if (xpGanho > 0) currentXP += xpGanho;
      return true;
    }

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    int? xpFinal;
    try {
      final bool primeiraVez =
          await FirebaseFirestore.instance.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data();
        final jogados = _lerJogados(data);
        if (jogados.contains(casoId)) {
          casosJogados.addAll(jogados);
          return false;
        }
        final int xpAtual = ((data?['xp'] ?? currentXP) as num).toInt();
        final int novoXp = xpAtual + xpGanho;
        xpFinal = novoXp;
        tx.set(ref, {
          'xp': novoXp,
          'casosJogados': FieldValue.arrayUnion([casoId]),
        }, SetOptions(merge: true));
        return true;
      });

      casosJogados.add(casoId);
      if (primeiraVez) currentXP = xpFinal ?? (currentXP + xpGanho);
      return primeiraVez;
    } catch (e) {
      // Sem confirmação do servidor: bloqueia o caso nesta sessão para não repetir.
      casosJogados.add(casoId);
      if (xpGanho > 0) currentXP += xpGanho;
      rethrow;
    }
  }

  Future<void> addXP(int amount) async {
    currentXP += amount;
    if (currentXP < 0) currentXP = 0;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'xp': currentXP,
      }, SetOptions(merge: true));
    }
  }

  Future<void> updateOfficialAudience(int newAudience) async {
    selectedAudience = newAudience;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'audience': selectedAudience,
      }, SetOptions(merge: true));
    }
  }

  Future<void> resetProgress() async {
    currentXP = 0;
    casosJogados.clear();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'xp': 0,
        'casosJogados': <String>[],
      }, SetOptions(merge: true));
    }
  }
}