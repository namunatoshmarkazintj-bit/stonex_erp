import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../domain/models.dart';
import '../state/app_lock_controller.dart';
import '../state/auth_controller.dart';
import 'common.dart';

/// Ilova qulfi ekrani (PIN kod so'rash)
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key, required this.user});
  final AppUser user;

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> with SingleTickerProviderStateMixin {
  String _enteredPin = '';
  String? _errorMessage;
  late AnimationController _shakeCtrl;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final char = event.character;
    if (char != null && RegExp(r'^[0-9]$').hasMatch(char)) {
      _onDigit(char);
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.digit0 || event.logicalKey == LogicalKeyboardKey.numpad0) {
      _onDigit('0');
    } else if (event.logicalKey == LogicalKeyboardKey.digit1 || event.logicalKey == LogicalKeyboardKey.numpad1) {
      _onDigit('1');
    } else if (event.logicalKey == LogicalKeyboardKey.digit2 || event.logicalKey == LogicalKeyboardKey.numpad2) {
      _onDigit('2');
    } else if (event.logicalKey == LogicalKeyboardKey.digit3 || event.logicalKey == LogicalKeyboardKey.numpad3) {
      _onDigit('3');
    } else if (event.logicalKey == LogicalKeyboardKey.digit4 || event.logicalKey == LogicalKeyboardKey.numpad4) {
      _onDigit('4');
    } else if (event.logicalKey == LogicalKeyboardKey.digit5 || event.logicalKey == LogicalKeyboardKey.numpad5) {
      _onDigit('5');
    } else if (event.logicalKey == LogicalKeyboardKey.digit6 || event.logicalKey == LogicalKeyboardKey.numpad6) {
      _onDigit('6');
    } else if (event.logicalKey == LogicalKeyboardKey.digit7 || event.logicalKey == LogicalKeyboardKey.numpad7) {
      _onDigit('7');
    } else if (event.logicalKey == LogicalKeyboardKey.digit8 || event.logicalKey == LogicalKeyboardKey.numpad8) {
      _onDigit('8');
    } else if (event.logicalKey == LogicalKeyboardKey.digit9 || event.logicalKey == LogicalKeyboardKey.numpad9) {
      _onDigit('9');
    } else if (event.logicalKey == LogicalKeyboardKey.backspace || event.logicalKey == LogicalKeyboardKey.delete) {
      _onBackspace();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      _onClear();
    }
  }

  void _onDigit(String d) {
    if (_enteredPin.length >= 4) return;
    setState(() {
      _enteredPin += d;
      _errorMessage = null;
    });

    if (_enteredPin.length == 4) {
      _verifyPin();
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = null;
      });
    }
  }

  void _onClear() {
    setState(() {
      _enteredPin = '';
      _errorMessage = null;
    });
  }

  void _verifyPin() {
    final appLock = context.read<AppLockController>();
    final ok = appLock.unlock(_enteredPin);
    if (!ok) {
      _shakeCtrl.forward(from: 0.0);
      setState(() {
        _errorMessage = 'PIN kod noto‘g‘ri';
        _enteredPin = '';
      });
    }
  }

  void _showForgotPinDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_reset_rounded, color: AppColors.neonLime, size: 24),
            SizedBox(width: 10),
            Text('PIN kodni unutdingizmi?', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Text(
          'PIN kodni unutgan bo‘lsangiz, joriy hisobdan chiqib, asosiy login va parolingiz orqali qayta kirishingiz mumkin. Shundan so‘ng yangi PIN kod o‘rnatib olasiz.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor qilish'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Hisobdan chiqish'),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthController>().logout();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _focusNode.requestFocus(),
        child: Scaffold(
          backgroundColor: const Color(0xFF070A0F),
          body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logotip
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/app_icon.png',
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.neonLime,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.lock_rounded, color: Color(0xFF090D14), size: 30),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text(
                    'Ilova Qulfi',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Foydalanuvchi ismi
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_rounded, size: 14, color: AppColors.neonLime),
                        const SizedBox(width: 6),
                        Text(
                          widget.user.fullName,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(${widget.user.role.label})',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'Davom etish uchun PIN kodni kiriting',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // 4 ta PIN indikator nuqtasi (Animatsiyali)
                  AnimatedBuilder(
                    animation: _shakeCtrl,
                    builder: (context, child) {
                      final dx = 12 * (1 - _shakeCtrl.value) * ((_shakeCtrl.value * 4).round().isEven ? 1 : -1);
                      return Transform.translate(
                        offset: Offset(_errorMessage != null ? dx : 0, 0),
                        child: child,
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        final filled = index < _enteredPin.length;
                        final isError = _errorMessage != null;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isError
                                ? AppColors.danger
                                : (filled ? AppColors.neonLime : Colors.white.withValues(alpha: 0.15)),
                            border: Border.all(
                              color: isError
                                  ? AppColors.danger
                                  : (filled ? AppColors.neonLime : Colors.white.withValues(alpha: 0.3)),
                              width: 2,
                            ),
                            boxShadow: filled && !isError
                                ? [
                                    BoxShadow(
                                      color: AppColors.neonLime.withValues(alpha: 0.5),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Xatolik xabari
                  SizedBox(
                    height: 22,
                    child: _errorMessage != null
                        ? Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),

                  // Klaviatura (1-9, C, 0, ⌫)
                  _buildKeypad(),
                  const SizedBox(height: 16),

                  // Unutdim va Chiqish
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF94A3B8)),
                        icon: const Icon(Icons.help_outline_rounded, size: 15),
                        label: const Text('PIN kodni unutdim', style: TextStyle(fontSize: 11.5)),
                        onPressed: _showForgotPinDialog,
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
                        icon: const Icon(Icons.logout_rounded, size: 15),
                        label: const Text('Hisobdan chiqish', style: TextStyle(fontSize: 11.5)),
                        onPressed: () => context.read<AuthController>().logout(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var col = 1; col <= 3; col++)
                  _buildKey('${row * 3 + col}'),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildSpecialKey(
              icon: Icons.clear_rounded,
              label: 'Tozalash',
              onTap: _onClear,
            ),
            _buildKey('0'),
            _buildSpecialKey(
              icon: Icons.backspace_outlined,
              label: 'O‘chirish',
              onTap: _onBackspace,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(String digit) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onDigit(digit),
        borderRadius: BorderRadius.circular(100),
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: const Color(0xFF131B27),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          alignment: Alignment.center,
          child: Text(
            digit,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialKey({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: const Color(0xFF94A3B8), size: 22),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PIN kod o'rnatish va tahrirlash dialogi
// ---------------------------------------------------------------------------

class PinSetupDialog extends StatefulWidget {
  const PinSetupDialog({super.key, required this.user});
  final AppUser user;

  static Future<void> show(BuildContext context, AppUser user) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinSetupDialog(user: user),
    );
  }

  @override
  State<PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<PinSetupDialog> {
  final _oldPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _oldPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final appLock = context.read<AppLockController>();
    final hasOldPin = appLock.hasPin;

    if (hasOldPin) {
      final currentPin = _oldPinCtrl.text.trim();
      if (currentPin.isEmpty) {
        setState(() => _error = 'Amaldagi PIN kodni kiriting');
        return;
      }
      if (!appLock.unlock(currentPin)) {
        setState(() => _error = 'Amaldagi PIN kod noto‘g‘ri');
        return;
      }
    }

    final newPin = _newPinCtrl.text.trim();
    final confirmPin = _confirmPinCtrl.text.trim();

    if (newPin.length != 4 || int.tryParse(newPin) == null) {
      setState(() => _error = 'Yangi PIN kod 4 ta raqamdan iborat bo‘lishi shart');
      return;
    }

    if (newPin != confirmPin) {
      setState(() => _error = 'PIN kodlar bir-biriga mos kelmadi');
      return;
    }

    appLock.setPin(newPin);
    Navigator.pop(context);
    showMessage(context, 'Ilova qulfi (PIN kod) muvaffaqiyatli saqlandi!');
  }

  void _removePin() {
    final appLock = context.read<AppLockController>();
    if (appLock.hasPin) {
      final currentPin = _oldPinCtrl.text.trim();
      if (currentPin.isEmpty || !appLock.unlock(currentPin)) {
        setState(() => _error = 'PINni o‘chirish uchun amaldagi PIN kodni kiriting');
        return;
      }
    }

    appLock.removePin();
    Navigator.pop(context);
    showMessage(context, 'Ilova qulfi olib tashlandi');
  }

  @override
  Widget build(BuildContext context) {
    final appLock = context.watch<AppLockController>();
    final isChanging = appLock.hasPin;

    return Dialog(
      backgroundColor: context.dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.neonLime.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.security_rounded, color: AppColors.neonLime, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isChanging ? 'PIN kodni o‘zgartirish' : 'Ilova qulfi (PIN) o‘rnatish',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.inkColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 20),

            Text(
              'Har gal ilovaga kirganingizda yoki fonga o‘tkazib qaytganingizda 4 xonali PIN kod so‘raladi.',
              style: TextStyle(fontSize: 12, color: context.mutedColor, height: 1.35),
            ),
            const SizedBox(height: 14),

            if (isChanging) ...[
              TextField(
                controller: _oldPinCtrl,
                obscureText: _obscureOld,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: 'Amaldagi PIN kod',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  isDense: true,
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureOld ? Icons.visibility_off : Icons.visibility, size: 18),
                    onPressed: () => setState(() => _obscureOld = !_obscureOld),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            TextField(
              controller: _newPinCtrl,
              obscureText: _obscureNew,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                labelText: isChanging ? 'Yangi 4 xonali PIN kod' : '4 xonali PIN kod kiriting',
                prefixIcon: const Icon(Icons.pin_rounded, size: 18),
                isDense: true,
                counterText: '',
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _confirmPinCtrl,
              obscureText: _obscureConfirm,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                labelText: 'PIN kodni tasdiqlang',
                prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                isDense: true,
                counterText: '',
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],

            const SizedBox(height: 18),

            Row(
              children: [
                if (isChanging)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    onPressed: _removePin,
                    child: const Text('O‘chirish', style: TextStyle(fontSize: 12.5)),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Bekor qilish'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                    foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _save,
                  child: const Text('Saqlash', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
