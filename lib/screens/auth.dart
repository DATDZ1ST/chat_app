import 'dart:io';

import 'package:chat_app/services/cloudinary_service.dart';
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

  var _isLogin = true;
  var _enteredEmail = '';
  var _enteredPassword = '';
  File? _selectedImage;
  var _isAuthenticating = false;

  var _enteredUsername = '';

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

  Future<void> _submit() async {
    final isValid = _form.currentState!.validate();
    if (!isValid || !_isLogin && _selectedImage == null) {
      return;
    }

    _form.currentState!.save();
    User? createdUser;

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
      } else {
        final userCredentials = await _firebase.createUserWithEmailAndPassword(
          email: _enteredEmail,
          password: _enteredPassword,
        );
        createdUser = userCredentials.user;

        final imageUrl = await CloudinaryService.uploadImage(
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
        SnackBar(content: Text(error.message ?? 'Authentication failed.')),
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
                              return 'Please enter a valid email address.';
                            }
                            return null;
                          },
                          onSaved: (value) {
                            _enteredEmail = value!.trim();
                          },
                        ),
                        if (!_isLogin)
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Username',
                            ),
                            enableSuggestions: false,
                            validator: (value) {
                              if (value == null ||
                                  value.isEmpty ||
                                  value.trim().length < 4) {
                                return 'Please enter at laest 4 characters.';
                              }
                              return null;
                            },
                            onSaved: (value) {
                              _enteredUsername = value!.trim();
                            },
                          ),
                        TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.trim().length < 6) {
                              return 'Password must be at least 6 characters long.';
                            }
                            return null;
                          },
                          onSaved: (value) {
                            _enteredPassword = value!;
                          },
                        ),
                        const SizedBox(height: 12),
                        if (_isAuthenticating) CircularProgressIndicator(),
                        if (!_isAuthenticating)
                          ElevatedButton(
                            onPressed: _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                            ),
                            child: Text(_isLogin ? 'Login' : 'Signup'),
                          ),

                        if (!_isAuthenticating)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isLogin = !_isLogin;
                              });
                            },
                            child: Text(
                              _isLogin
                                  ? 'Create an account'
                                  : 'I already have an account. Login.',
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
