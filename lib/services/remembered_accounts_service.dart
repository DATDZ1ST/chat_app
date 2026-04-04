import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RememberedAccount {
  const RememberedAccount({
    required this.email,
    required this.username,
    this.imageUrl,
    required this.hasSavedPassword,
    required this.lastUsedAt,
  });

  final String email;
  final String username;
  final String? imageUrl;
  final bool hasSavedPassword;
  final int lastUsedAt;

  factory RememberedAccount.fromJson(Map<String, dynamic> json) {
    return RememberedAccount(
      email: (json['email'] as String? ?? '').trim(),
      username: (json['username'] as String? ?? '').trim(),
      imageUrl: (json['imageUrl'] as String?)?.trim(),
      hasSavedPassword: json['hasSavedPassword'] == true,
      lastUsedAt: json['lastUsedAt'] is int ? json['lastUsedAt'] as int : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'username': username,
      'imageUrl': imageUrl,
      'hasSavedPassword': hasSavedPassword,
      'lastUsedAt': lastUsedAt,
    };
  }
}

class RememberedAccountsService {
  RememberedAccountsService._();

  static final RememberedAccountsService instance =
      RememberedAccountsService._();

  static const _accountsStorageKey = 'remembered_accounts';
  static const _passwordStoragePrefix = 'remembered_account_password_';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  SharedPreferences? _preferences;
  RememberedAccount? _pendingSelection;
  bool _hideRememberedAccountsOnNextAuthScreen = false;
  bool _prefsUnavailable = false;
  bool _secureStorageUnavailable = false;

  Future<SharedPreferences?> _prefs() async {
    if (_prefsUnavailable) {
      return null;
    }

    if (_preferences != null) {
      return _preferences;
    }

    try {
      _preferences = await SharedPreferences.getInstance();
      return _preferences;
    } on MissingPluginException catch (error) {
      _prefsUnavailable = true;
      debugPrint('SharedPreferences plugin unavailable: $error');
      return null;
    } on PlatformException catch (error) {
      _prefsUnavailable = true;
      debugPrint('SharedPreferences channel error: $error');
      return null;
    } catch (error) {
      _prefsUnavailable = true;
      debugPrint('SharedPreferences init failed: $error');
      return null;
    }
  }

  Future<String?> _readStoredPassword(String email) async {
    if (_secureStorageUnavailable) {
      return null;
    }

    try {
      return await _secureStorage.read(key: _passwordStorageKey(email));
    } on MissingPluginException catch (error) {
      _secureStorageUnavailable = true;
      debugPrint('Secure storage plugin unavailable: $error');
      return null;
    } on PlatformException catch (error) {
      _secureStorageUnavailable = true;
      debugPrint('Secure storage channel error: $error');
      return null;
    } catch (error) {
      _secureStorageUnavailable = true;
      debugPrint('Secure storage read failed: $error');
      return null;
    }
  }

  Future<void> _writeStoredPassword(String email, String password) async {
    if (_secureStorageUnavailable) {
      return;
    }

    try {
      await _secureStorage.write(
        key: _passwordStorageKey(email),
        value: password,
      );
    } on MissingPluginException catch (error) {
      _secureStorageUnavailable = true;
      debugPrint('Secure storage plugin unavailable: $error');
    } on PlatformException catch (error) {
      _secureStorageUnavailable = true;
      debugPrint('Secure storage channel error: $error');
    } catch (error) {
      _secureStorageUnavailable = true;
      debugPrint('Secure storage write failed: $error');
    }
  }

  Future<void> _deleteStoredPassword(String email) async {
    if (_secureStorageUnavailable) {
      return;
    }

    try {
      await _secureStorage.delete(key: _passwordStorageKey(email));
    } on MissingPluginException catch (error) {
      _secureStorageUnavailable = true;
      debugPrint('Secure storage plugin unavailable: $error');
    } on PlatformException catch (error) {
      _secureStorageUnavailable = true;
      debugPrint('Secure storage channel error: $error');
    } catch (error) {
      _secureStorageUnavailable = true;
      debugPrint('Secure storage delete failed: $error');
    }
  }

  String _passwordStorageKey(String email) {
    return '$_passwordStoragePrefix${email.trim().toLowerCase()}';
  }

  String _fallbackUsername(String email) {
    final trimmed = email.trim();
    if (!trimmed.contains('@')) {
      return trimmed;
    }

    final localPart = trimmed.split('@').first.trim();
    return localPart.isEmpty ? trimmed : localPart;
  }

  Future<List<RememberedAccount>> getAccounts() async {
    final prefs = await _prefs();
    if (prefs == null) {
      return const [];
    }
    final rawValue = prefs.getString(_accountsStorageKey);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! List) {
        return const [];
      }

      final accounts = decoded
          .whereType<Map>()
          .map(
            (item) =>
                RememberedAccount.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((account) => account.email.isNotEmpty)
          .toList();

      accounts.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      return accounts;
    } catch (_) {
      return const [];
    }
  }

  Future<RememberedAccount?> getAccount(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      return null;
    }

    final accounts = await getAccounts();
    for (final account in accounts) {
      if (account.email.toLowerCase() == normalizedEmail) {
        return account;
      }
    }

    return null;
  }

  Future<void> saveAccount({
    required String email,
    String? username,
    String? imageUrl,
    required bool savePassword,
    String? password,
  }) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      return;
    }

    final accounts = List<RememberedAccount>.from(await getAccounts());
    RememberedAccount? existingAccount;
    accounts.removeWhere((account) {
      final isMatch = account.email.toLowerCase() == trimmedEmail.toLowerCase();
      if (isMatch) {
        existingAccount = account;
      }
      return isMatch;
    });

    final normalizedUsername = username?.trim().isNotEmpty == true
        ? username!.trim()
        : existingAccount?.username.isNotEmpty == true
        ? existingAccount!.username
        : _fallbackUsername(trimmedEmail);
    final normalizedImageUrl = imageUrl?.trim().isNotEmpty == true
        ? imageUrl!.trim()
        : existingAccount?.imageUrl;

    accounts.insert(
      0,
      RememberedAccount(
        email: trimmedEmail,
        username: normalizedUsername,
        imageUrl: normalizedImageUrl,
        hasSavedPassword: savePassword,
        lastUsedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final prefs = await _prefs();
    if (prefs == null) {
      return;
    }
    await prefs.setString(
      _accountsStorageKey,
      jsonEncode(accounts.map((account) => account.toJson()).toList()),
    );

    if (savePassword && password != null && password.isNotEmpty) {
      await _writeStoredPassword(trimmedEmail, password);
    } else if (!savePassword) {
      await _deleteStoredPassword(trimmedEmail);
    }
  }

  Future<String?> getSavedPassword(String email) async {
    return _readStoredPassword(email);
  }

  void setPendingSelection(RememberedAccount? account) {
    _pendingSelection = account;
  }

  RememberedAccount? consumePendingSelection() {
    final selection = _pendingSelection;
    _pendingSelection = null;
    return selection;
  }

  void clearPendingSelection() {
    _pendingSelection = null;
  }

  void hideRememberedAccountsOnNextAuthScreen() {
    _hideRememberedAccountsOnNextAuthScreen = true;
  }

  void showRememberedAccountsOnNextAuthScreen() {
    _hideRememberedAccountsOnNextAuthScreen = false;
  }

  bool consumeHideRememberedAccountsOnNextAuthScreen() {
    final shouldHide = _hideRememberedAccountsOnNextAuthScreen;
    _hideRememberedAccountsOnNextAuthScreen = false;
    return shouldHide;
  }
}
