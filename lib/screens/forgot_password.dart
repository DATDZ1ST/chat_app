import 'package:chat_app/services/remembered_accounts_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _newPasswordController = TextEditingController();
  bool _isSending = false;
  bool _isLoggingIn = false;
  bool _emailSent = false;
  bool _readyToSignInWithNewPassword = false;
  bool _leftAppAfterSendingEmail = false;
  bool _obscureNewPassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_emailSent || _readyToSignInWithNewPassword) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _leftAppAfterSendingEmail = true;
      return;
    }

    if (state == AppLifecycleState.resumed && _leftAppAfterSendingEmail) {
      if (!mounted) {
        return;
      }

      setState(() {
        _readyToSignInWithNewPassword = true;
      });
    }
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    final email = _emailController.text.trim();

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã gửi email đặt lại mật khẩu tới $email. Bấm vào link để đặt lại mật khẩu mới.',
          ),
        ),
      );
      setState(() {
        _emailSent = true;
        _readyToSignInWithNewPassword = false;
        _leftAppAfterSendingEmail = false;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ?? 'Không gửi được email đặt lại mật khẩu.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _signInWithNewPassword() async {
    final email = _emailController.text.trim();
    final password = _newPasswordController.text;

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập email hợp lệ.')),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập mật khẩu mới.')),
      );
      return;
    }

    setState(() {
      _isLoggingIn = true;
    });

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final rememberedAccount = await RememberedAccountsService.instance
          .getAccount(email);
      if (rememberedAccount != null) {
        await RememberedAccountsService.instance.saveAccount(
          email: rememberedAccount.email,
          username: rememberedAccount.username,
          imageUrl: rememberedAccount.imageUrl,
          savePassword: rememberedAccount.hasSavedPassword,
          password: rememberedAccount.hasSavedPassword ? password : null,
        );
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đăng nhập thành công với ${userCredential.user?.email ?? email}.',
          ),
        ),
      );

      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ?? 'Không đăng nhập được với mật khẩu mới.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quên mật khẩu.')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_emailSent) ...[
                      Text(
                        'Nhập email để đổi mật khẩu.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                      ),
                      validator: (value) {
                        if (value == null ||
                            value.trim().isEmpty ||
                            !value.contains('@')) {
                          return 'Vui lòng nhập địa chỉ email hợp lệ.';
                        }
                        return null;
                      },
                    ),
                    if (!_emailSent) ...[
                      const SizedBox(height: 16),
                      if (_isSending)
                        const Center(child: CircularProgressIndicator())
                      else
                        ElevatedButton(
                          onPressed: _submit,
                          child: const Text('Đặt lại mật khẩu mới'),
                        ),
                    ],
                    if (_emailSent) ...[
                      const SizedBox(height: 12),
                      if (!_readyToSignInWithNewPassword)
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _readyToSignInWithNewPassword = true;
                            });
                          },
                          child: const Text(
                            'Tôi đã đổi mật khẩu mới',
                          ),
                        ),
                      if (_readyToSignInWithNewPassword) ...[
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: _obscureNewPassword,
                          decoration: InputDecoration(
                            labelText: 'Mật khẩu mới',
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscureNewPassword = !_obscureNewPassword;
                                });
                              },
                              icon: Icon(
                                _obscureNewPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_isLoggingIn)
                          const Center(child: CircularProgressIndicator())
                        else
                          ElevatedButton(
                            onPressed: _signInWithNewPassword,
                            child: const Text('Đăng nhập với mật khẩu mới'),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
