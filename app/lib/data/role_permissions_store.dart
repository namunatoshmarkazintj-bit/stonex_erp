import 'package:flutter/foundation.dart';
import '../domain/models.dart';
import 'api_client.dart';

class RolePermissionsStore extends ChangeNotifier {
  static final RolePermissionsStore instance = RolePermissionsStore._();
  RolePermissionsStore._();

  Map<String, Map<String, bool>> _permissions = _defaultPermissions();

  Map<String, Map<String, bool>> get all => _permissions;

  bool can(Role role, String key) {
    if (role == Role.master) return true; // Master always has all permissions
    final roleCode = role.code;
    final roleMap = _permissions[roleCode];
    if (roleMap == null) return true;
    return roleMap[key] ?? true;
  }

  Future<void> load(ApiClient api) async {
    try {
      final res = await api.get('/settings/permissions');
      if (res is Map) {
        final Map<String, Map<String, bool>> parsed = {};
        res.forEach((rKey, rVal) {
          if (rVal is Map) {
            final Map<String, bool> pMap = {};
            rVal.forEach((pKey, pVal) {
              pMap[pKey.toString()] = pVal == true;
            });
            parsed[rKey.toString()] = pMap;
          }
        });
        if (parsed.isNotEmpty) {
          _permissions = parsed;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('RolePermissions yuklashda xatolik: $e');
    }
  }

  Future<bool> save(ApiClient api, Map<String, Map<String, bool>> updated) async {
    try {
      await api.post('/settings/permissions', body: {'permissions': updated});
      _permissions = updated;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('RolePermissions saqlashda xatolik: $e');
      return false;
    }
  }

  static Map<String, Map<String, bool>> _defaultPermissions() => {
        'admin': {
          'dashboard': true,
          'pos': true,
          'orders': true,
          'deliveries': true,
          'sales': true,
          'customers': true,
          'debts': true,
          'purchases': true,
          'finance': true,
          'products': true,
          'stock': true,
          'production': true,
          'users': true,
          'view_cost_price': true,
          'delete_products': true,
          'give_discount': true,
        },
        'kassir': {
          'dashboard': false,
          'pos': true,
          'orders': true,
          'deliveries': true,
          'sales': true,
          'customers': true,
          'debts': true,
          'purchases': true,
          'finance': true,
          'products': true,
          'stock': false,
          'production': false,
          'users': false,
          'view_cost_price': false,
          'delete_products': false,
          'give_discount': true,
        },
        'ish_boshqaruvchi': {
          'dashboard': false,
          'pos': false,
          'orders': false,
          'deliveries': false,
          'sales': false,
          'customers': false,
          'debts': false,
          'purchases': false,
          'finance': false,
          'products': false,
          'stock': true,
          'production': true,
          'users': false,
          'view_cost_price': false,
          'delete_products': false,
          'give_discount': false,
        },
        'haydovchi': {
          'dashboard': false,
          'pos': false,
          'orders': true,
          'deliveries': true,
          'sales': false,
          'customers': false,
          'debts': false,
          'purchases': false,
          'finance': false,
          'products': false,
          'stock': false,
          'production': false,
          'users': false,
          'view_cost_price': false,
          'delete_products': false,
          'give_discount': false,
        },
        'ishchi': {
          'dashboard': false,
          'pos': false,
          'orders': false,
          'deliveries': false,
          'sales': false,
          'customers': false,
          'debts': false,
          'purchases': false,
          'finance': false,
          'products': false,
          'stock': false,
          'production': true,
          'users': false,
          'view_cost_price': false,
          'delete_products': false,
          'give_discount': false,
        },
      };
}
