import 'package:flutter/widgets.dart';

import '../data/local_security_store.dart';
import '../domain/models.dart';

/// Ilova qulfi (PIN-kod) holatini boshqarish va ilova fon rejimiga o'tganda avtomatik qulflash
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController() {
    WidgetsBinding.instance.addObserver(this);
  }

  AppUser? _currentUser;
  bool _isLocked = false;
  bool _shouldLockOnResume = false;
  bool _initialized = false;

  AppUser? get currentUser => _currentUser;
  bool get isLocked => _isLocked;
  bool get hasPin => _currentUser != null && LocalSecurityStore.hasPin(_currentUser!.id);
  bool get isLockEnabled => _currentUser != null && LocalSecurityStore.isLockEnabled(_currentUser!.id);

  /// Foydalanuvchi ma'lumotlarini sinxronlash (login / logout yoki startda)
  void syncUser(AppUser? user) {
    if (_currentUser?.id == user?.id && _initialized) {
      _currentUser = user;
      return;
    }
    _currentUser = user;
    if (user != null) {
      // Dastur qayta ochilganda agar qulf yoqilgan bo'lsa, qulflaymiz
      if (LocalSecurityStore.isLockEnabled(user.id)) {
        _isLocked = true;
      } else {
        _isLocked = false;
      }
    } else {
      _isLocked = false;
    }
    _initialized = true;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // Ilova fonga o'tdi yoki telefon ekrani o'chdi
      if (isLockEnabled && hasPin) {
        _shouldLockOnResume = true;
      }
    } else if (state == AppLifecycleState.resumed) {
      // Ilova yana faol bo'ldi
      if (_shouldLockOnResume && isLockEnabled && hasPin) {
        _isLocked = true;
        _shouldLockOnResume = false;
        notifyListeners();
      }
    }
  }

  /// PIN kodni tekshirish va qulfni ochish
  bool unlock(String enteredPin) {
    if (_currentUser == null) return false;
    final savedPin = LocalSecurityStore.getPin(_currentUser!.id);
    if (savedPin != null && savedPin == enteredPin.trim()) {
      _isLocked = false;
      _shouldLockOnResume = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Ilovani zudlik bilan qulflash (masalan, foydalanuvchi tugmani bosganda)
  void lockNow() {
    if (hasPin) {
      _isLocked = true;
      notifyListeners();
    }
  }

  /// Yangi PIN kod o'rnatish
  void setPin(String newPin) {
    if (_currentUser == null) return;
    LocalSecurityStore.savePin(userId: _currentUser!.id, pin: newPin, enabled: true);
    _isLocked = false;
    _shouldLockOnResume = false;
    notifyListeners();
  }

  /// Qulfni yoqish yoki o'chirish
  void setLockEnabled(bool enabled) {
    if (_currentUser == null) return;
    LocalSecurityStore.setLockEnabled(userId: _currentUser!.id, enabled: enabled);
    if (!enabled) {
      _isLocked = false;
      _shouldLockOnResume = false;
    }
    notifyListeners();
  }

  /// PIN kodni butunlay o'chirish
  void removePin() {
    if (_currentUser == null) return;
    LocalSecurityStore.removePin(_currentUser!.id);
    _isLocked = false;
    _shouldLockOnResume = false;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
