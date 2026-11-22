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
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do Firestore: $e');
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
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'xp': 0,
      }, SetOptions(merge: true));
    }
  }
}
