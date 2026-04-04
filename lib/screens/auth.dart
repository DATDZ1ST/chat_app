import 'dart:io';

import 'package:chat_app/services/cloudinary_service.dart';
import 'package:chat_app/services/remembered_accounts_service.dart';
import 'package:chat_app/screens/forgot_password.dart';
import 'package:chat_app/widgets/user_image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

final _firebase = FirebaseAuth.instance;

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() {
    return _AuthScreenState();
  }
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  var _isLogin = true;
  var _enteredEmail = '';
  var _enteredPassword = '';
  var _enteredUsername = '';
  var _isAuthenticating = false;

  File? _selectedImage;
  RememberedAccount? _selectedRememberedAccount;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_handleEmailChanged);
    _loadRememberedAccounts();
  }

  @override
  void dispose() {
    _emailController.removeListener(_handleEmailChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _handleEmailChanged() {
    final selectedAccount = _selectedRememberedAccount;
    if (selectedAccount == null) {
      return;
    }

    if (_emailController.text.trim() == selectedAccount.email) {
      return;
    }

    setState(() {
      _selectedRememberedAccount = null;
    });
  }

  String? _emailLocalPart(String? email) {
    if (email == null || email.trim().isEmpty || !email.contains('@')) {
      return null;
    }

    final localPart = email.split('@').first.trim();
    return localPart.isEmpty ? null : localPart;
  }

  String? _readString(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) {
      return null;
    }

    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  Future<void> _loadRememberedAccounts() async {
    final pendingSelection = RememberedAccountsService.instance
        .consumePendingSelection();
    RememberedAccountsService.instance
        .consumeHideRememberedAccountsOnNextAuthScreen();

    if (!mounted) {
      return;
    }

    if (pendingSelection != null) {
      if (pendingSelection.hasSavedPassword) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }

          _handleRememberedAccountTap(pendingSelection);
        });
      } else {
        _prefillRememberedAccount(pendingSelection);
      }
    }
  }

  void _prefillRememberedAccount(RememberedAccount account) {
    _emailController.text = account.email;
    _passwordController.clear();

    setState(() {
      _selectedRememberedAccount = account;
      _isLogin = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _passwordFocusNode.requestFocus();
    });
  }

  Future<bool?> _askToSavePassword() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Lưu mật khẩu?'),
          content: const Text(
            'Bạn có muốn lưu mật khẩu?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Khong luu'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Luu'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _rememberAuthenticatedAccount(
    User user, {
    required bool savePassword,
    String? fallbackUsername,
    String? fallbackImageUrl,
  }) async {
    final userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userSnapshot.data();

    final username = fallbackUsername?.trim().isNotEmpty == true
        ? fallbackUsername!.trim()
        : _readString(userData, const ['username']) ??
              (user.displayName?.trim().isNotEmpty ?? false
                  ? user.displayName!.trim()
                  : _emailLocalPart(user.email)) ??
              'User';
    final imageUrl = fallbackImageUrl?.trim().isNotEmpty == true
        ? fallbackImageUrl!.trim()
        : _readString(userData, const ['image_url', 'imageUrl', 'userImage']) ??
              (user.photoURL?.trim().isNotEmpty ?? false
                  ? user.photoURL!.trim()
                  : null);

    await RememberedAccountsService.instance.saveAccount(
      email: user.email ?? _enteredEmail,
      username: username,
      imageUrl: imageUrl,
      savePassword: savePassword,
      password: savePassword ? _enteredPassword : null,
    );

    final rememberedAccounts = await RememberedAccountsService.instance
        .getAccounts();
    if (!mounted) {
      return;
    }

    RememberedAccount? selectedAccount;
    for (final account in rememberedAccounts) {
      if (account.email == (user.email ?? _enteredEmail)) {
        selectedAccount = account;
        break;
      }
    }

    setState(() {
      _selectedRememberedAccount = selectedAccount;
    });
  }

  Future<void> _handleRememberedAccountTap(RememberedAccount account) async {
    String? password;

    if (account.hasSavedPassword) {
      password = await RememberedAccountsService.instance.getSavedPassword(
        account.email,
      );
    }

    if (password == null || password.isEmpty) {
      password = await _askPasswordForRememberedAccount(account);
      if (password == null || password.isEmpty || !mounted) {
        return;
      }
    }

    await _signInRememberedAccount(
      account: account,
      password: password,
      savePassword: account.hasSavedPassword,
    );
  }

  Future<String?> _askPasswordForRememberedAccount(
    RememberedAccount account,
  ) async {
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscurePassword = true;

    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Đăng nhập ${account.username}'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: passwordController,
                  autofocus: true,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setDialogState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Nhập mật khẩu.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(dialogContext).pop(passwordController.text);
                    }
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(dialogContext).pop(passwordController.text);
                    }
                  },
                  child: const Text('Đăng nhập'),
                ),
              ],
            );
          },
        );
      },
    );

    passwordController.dispose();
    return password;
  }

  Future<void> _signInRememberedAccount({
    required RememberedAccount account,
    required String password,
    required bool savePassword,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isAuthenticating = true;
    });

    try {
      final userCredentials = await _firebase.signInWithEmailAndPassword(
        email: account.email,
        password: password,
      );
      await _syncUserProfile(
        userCredentials.user!,
        fallbackUsername: account.username,
        fallbackImageUrl: account.imageUrl,
      );
      await _rememberAuthenticatedAccount(
        userCredentials.user!,
        savePassword: savePassword,
        fallbackUsername: account.username,
        fallbackImageUrl: account.imageUrl,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Xác thực không thành công.')),
      );

      setState(() {
        _isAuthenticating = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));

      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  Future<void> _syncUserProfile(
    User user, {
    String? fallbackUsername,
    String? fallbackImageUrl,
  }) async {
    final userDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final userSnapshot = await userDocRef.get();
    final userData = userSnapshot.data();

    final username = fallbackUsername?.trim().isNotEmpty == true
        ? fallbackUsername!.trim()
        : _readString(userData, const ['username']) ??
              (user.displayName?.trim().isNotEmpty ?? false
                  ? user.displayName!.trim()
                  : _emailLocalPart(user.email)) ??
              'User';
    final imageUrl = fallbackImageUrl?.trim().isNotEmpty == true
        ? fallbackImageUrl!.trim()
        : _readString(userData, const ['image_url', 'imageUrl', 'userImage']) ??
              (user.photoURL?.trim().isNotEmpty ?? false
                  ? user.photoURL!.trim()
                  : null);

    await userDocRef.set({
      'email': user.email,
      'username': username,
      if (imageUrl != null) 'image_url': imageUrl,
    }, SetOptions(merge: true));

    if (username != user.displayName) {
      await user.updateDisplayName(username);
    }
    if (imageUrl != null && imageUrl != user.photoURL) {
      await user.updatePhotoURL(imageUrl);
    }
  }

  void _openForgotPasswordScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ForgotPasswordScreen(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  Future<void> _submit({
    bool skipSavePasswordPrompt = false,
    bool? savePasswordOverride,
  }) async {
    final isValid = _form.currentState!.validate();
    if (!isValid || (!_isLogin && _selectedImage == null)) {
      return;
    }

    _enteredEmail = _emailController.text.trim();
    _enteredPassword = _passwordController.text;
    _enteredUsername = _usernameController.text.trim();

    final existingAccount = await RememberedAccountsService.instance.getAccount(
      _enteredEmail,
    );
    bool? savePasswordPreference = savePasswordOverride;
    if (savePasswordPreference == null) {
      if (existingAccount != null) {
        savePasswordPreference = existingAccount.hasSavedPassword;
      } else if (!skipSavePasswordPrompt) {
        savePasswordPreference = await _askToSavePassword();
        if (savePasswordPreference == null) {
          return;
        }
      } else {
        savePasswordPreference = false;
      }
    }

    User? createdUser;
    String? imageUrl;

    try {
      setState(() {
        _isAuthenticating = true;
      });

      if (_isLogin) {
        final userCredentials = await _firebase.signInWithEmailAndPassword(
          email: _enteredEmail,
          password: _enteredPassword,
        );
        await _syncUserProfile(userCredentials.user!);
        await _rememberAuthenticatedAccount(
          userCredentials.user!,
          savePassword: savePasswordPreference,
        );
      } else {
        final userCredentials = await _firebase.createUserWithEmailAndPassword(
          email: _enteredEmail,
          password: _enteredPassword,
        );
        createdUser = userCredentials.user;

        imageUrl = await CloudinaryService.uploadImage(
          _selectedImage!,
          publicId: userCredentials.user!.uid,
        );
        await userCredentials.user!.updateDisplayName(_enteredUsername.trim());
        await userCredentials.user!.updatePhotoURL(imageUrl);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredentials.user!.uid)
            .set({
              'username': _enteredUsername.trim(),
              'email': _enteredEmail.trim(),
              'image_url': imageUrl,
            }, SetOptions(merge: true));
        await _syncUserProfile(
          userCredentials.user!,
          fallbackUsername: _enteredUsername,
          fallbackImageUrl: imageUrl,
        );
        await _rememberAuthenticatedAccount(
          userCredentials.user!,
          savePassword: savePasswordPreference,
          fallbackUsername: _enteredUsername,
          fallbackImageUrl: imageUrl,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (!_isLogin && createdUser != null) {
        try {
          await createdUser.delete();
          await _firebase.signOut();
        } catch (_) {}
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Xac thuc khong thanh cong.')),
      );
      setState(() {
        _isAuthenticating = false;
      });
    } catch (error) {
      if (!_isLogin && createdUser != null) {
        try {
          await createdUser.delete();
          await _firebase.signOut();
        } catch (_) {}
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                margin: const EdgeInsets.only(
                  top: 30,
                  left: 20,
                  right: 20,
                  bottom: 20,
                ),
                width: 200,
                child: Image.asset('assets/images/chat.png'),
              ),
              Card(
                margin: const EdgeInsets.all(20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_isLogin)
                          UserImagePicker(
                            onPickImage: (pickedImage) {
                              _selectedImage = pickedImage;
                            },
                          ),
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                          ),
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.none,
                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty ||
                                !value.contains('@')) {
                              return 'Vui lòng nhập địa chỉ email hợp lệ.';
                            }
                            return null;
                          },
                        ),
                        if (!_isLogin)
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                            ),
                            enableSuggestions: false,
                            validator: (value) {
                              if (value == null ||
                                  value.isEmpty ||
                                  value.trim().length < 4) {
                                return 'Vui lòng nhập ít nhất 4 ký tự.';
                              }
                              return null;
                            },
                          ),
                        TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.trim().length < 6) {
                              return 'Mật khẩu phải dài ít nhất 6 ký tự.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        if (_selectedRememberedAccount != null && _isLogin)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Đăng nhập vào: ${_selectedRememberedAccount!.email}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        if (_isAuthenticating)
                          const CircularProgressIndicator(),
                        if (!_isAuthenticating)
                          ElevatedButton(
                            onPressed: _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                            ),
                            child: Text(_isLogin ? 'Đăng nhập' : 'Đăng ký'),
                          ),
                        if (!_isAuthenticating && _isLogin)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isLogin = false;
                                    _selectedRememberedAccount = null;
                                    _emailController.clear();
                                    _passwordController.clear();
                                    _usernameController.clear();
                                  });
                                },
                                child: const Text('Tạo tài khoản?'),
                              ),
                              TextButton(
                                onPressed: _openForgotPasswordScreen,
                                child: const Text('Bạn quên mật khẩu?'),
                              ),
                            ],
                          ),
                        if (!_isAuthenticating && !_isLogin)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isLogin = true;
                                if (_selectedRememberedAccount != null) {
                                  _emailController.text =
                                      _selectedRememberedAccount!.email;
                                  _passwordController.clear();
                                }
                              });
                            },
                            child: const Text(
                              'Bạn đã có tài khoản? Đăng nhập.',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
