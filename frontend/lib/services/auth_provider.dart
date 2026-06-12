import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';
import 'api_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    ApiService? apiService,
    fb_auth.FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _apiService = apiService ?? ApiService(),
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final ApiService _apiService;
  final fb_auth.FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  User? currentUser;

  bool get isLoggedIn => currentUser != null;

  bool get isDriver => currentUser?.role == 'driver';

  // ── Login / register / logout ──────────────────────────────────────────────

  Future<void> login(String email, String password) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final fbUser = credential.user;
      if (fbUser == null) {
        throw Exception('Failed to sign in. User is null.');
      }

      // Fetch user profile from Firestore
      final doc = await _firestore
          .collection('users')
          .doc(fbUser.uid)
          .get()
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception(
          'Firestore read timed out. Please check if Cloud Firestore is '
          'enabled in your Firebase Console and the user database is initialized.',
        ),
      );
      if (!doc.exists) {
        throw Exception('User profile not found in Firestore.');
      }

      final data = doc.data()!;
      final String name = data['name'] ?? '';
      final String role = data['role'] ?? 'shipper';

      final token = await fbUser.getIdToken() ?? '';
      await _apiService.saveToken(token);

      await _apiService.syncUser(
        name: name,
        email: email,
        role: role,
      );

      currentUser = User(
        id: fbUser.uid,
        email: email,
        role: role,
        name: name,
        token: token,
      );
      notifyListeners();
    } on fb_auth.FirebaseAuthException catch (e) {
      String msg = e.message ?? 'An error occurred during login.';
      if (e.code == 'user-not-found') {
        msg = 'No user found for that email.';
      } else if (e.code == 'wrong-password') {
        msg = 'Wrong password provided for that user.';
      } else if (e.code == 'invalid-credential') {
        msg = 'Invalid credentials provided.';
      }
      throw Exception(msg);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final fbUser = credential.user;
      if (fbUser == null) {
        throw Exception('Failed to create user. User is null.');
      }

      // Normalize role: customer -> shipper
      final normalizedRole = (role == 'customer') ? 'shipper' : role;

      // Save user profile to Firestore
      await _firestore.collection('users').doc(fbUser.uid).set({
        'uid': fbUser.uid,
        'name': name,
        'email': email,
        'role': normalizedRole,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception(
          'Firestore write timed out. Please check if Cloud Firestore is '
          'enabled in your Firebase Console and security rules allow writes.',
        ),
      );

      final token = await fbUser.getIdToken() ?? '';
      await _apiService.saveToken(token);

      await _apiService.syncUser(
        name: name,
        email: email,
        role: normalizedRole,
      );

      currentUser = User(
        id: fbUser.uid,
        email: email,
        role: normalizedRole,
        name: name,
        token: token,
      );
      notifyListeners();
    } on fb_auth.FirebaseAuthException catch (e) {
      String msg = e.message ?? 'An error occurred during registration.';
      if (e.code == 'email-already-in-use') {
        msg = 'The email address is already in use by another account.';
      } else if (e.code == 'weak-password') {
        msg = 'The password provided is too weak.';
      }
      throw Exception(msg);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> logout() async {
    try {
      await _firebaseAuth.signOut();
    } catch (e) {
      debugPrint('[AuthProvider] Firebase signOut failed: $e');
    }
    await _apiService.clearToken();
    currentUser = null;
    notifyListeners();
  }

  // ── Session restoration on app start ──────────────────────────────────────

  /// Called once on app launch by [_AuthGate].
  Future<void> tryAutoLogin() async {
    debugPrint('[AuthProvider] tryAutoLogin — checking Firebase current user');
    final fbUser = _firebaseAuth.currentUser;
    if (fbUser == null) {
      debugPrint('[AuthProvider] tryAutoLogin — no active session in Firebase');
      await _apiService.clearToken();
      currentUser = null;
      notifyListeners();
      return;
    }

    debugPrint('[AuthProvider] tryAutoLogin — session found: ${fbUser.uid}');
    try {
      final token = await fbUser.getIdToken() ?? '';
      await _apiService.saveToken(token);

      final doc = await _firestore
          .collection('users')
          .doc(fbUser.uid)
          .get()
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Firestore read timed out.'),
      );
      if (!doc.exists) {
        throw Exception('User profile not found in Firestore.');
      }

      final data = doc.data()!;
      final String name = data['name'] ?? '';
      final String role = data['role'] ?? 'shipper';

      await _apiService.syncUser(
        name: name,
        email: fbUser.email ?? '',
        role: role,
      );

      currentUser = User(
        id: fbUser.uid,
        email: fbUser.email ?? '',
        role: role,
        name: name,
        token: token,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthProvider] tryAutoLogin — failed to restore session: $e');
      await _apiService.clearToken();
      currentUser = null;
      notifyListeners();
    }
  }
}
