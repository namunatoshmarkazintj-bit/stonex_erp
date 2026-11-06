import 'dart:convert';

import 'package:http/http.dart' as http;
import '../core/config.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.baseUrl) : _client = http.Client();
  String baseUrl;
  String? token;
  final http.Client _client;

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, {Object? body}) => _send('POST', path, body: body);
  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<String> getText(String path, {Map<String, String>? query}) async {
    baseUrl = AppConfig.apiBaseUrl;
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final req = http.Request('GET', uri);
    req.headers['Accept'] = '*/*';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';

    http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 15)));
    } on Exception {
      throw ApiException('Serverga ulanib bo‘lmadi. Internet va server manzilini tekshiring.');
    }

    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 400) {
      throw ApiException('Xatolik (${res.statusCode})', res.statusCode);
    }
    return text;
  }

  Future<dynamic> uploadFile(String path, List<int> bytes, String filename, {String fieldName = 'file'}) async {
    baseUrl = AppConfig.apiBaseUrl;
    final uri = Uri.parse('$baseUrl$path');
    final req = http.MultipartRequest('POST', uri);
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes(fieldName, bytes, filename: filename));

    http.Response res;
    try {
      final streamedRes = await _client.send(req).timeout(const Duration(seconds: 30));
      res = await http.Response.fromStream(streamedRes);
    } on Exception {
      throw ApiException('Rasm serverga yuklanmadi. Internet va server holatini tekshiring.');
    }

    final text = utf8.decode(res.bodyBytes);
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = text;
      }
    }
    if (res.statusCode >= 400) {
      final msg = _detail(data);
      if (msg != null && msg.isNotEmpty) {
        throw ApiException(msg, res.statusCode);
      }
      if (res.statusCode == 500) {
        throw ApiException('Serverda ichki xatolik yuz berdi (500). Serverni tekshiring.', res.statusCode);
      }
      throw ApiException(
        text.isNotEmpty && text.length < 100 && !text.contains('<html') ? text : 'Rasm yuklashda xatolik (${res.statusCode})',
        res.statusCode,
      );
    }
    return data;
  }

  static String resolveUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
    final base = AppConfig.apiBaseUrl.endsWith('/')
        ? AppConfig.apiBaseUrl.substring(0, AppConfig.apiBaseUrl.length - 1)
        : AppConfig.apiBaseUrl;
    final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '$base$path';
  }

  Future<dynamic> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    baseUrl = AppConfig.apiBaseUrl;
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);

    http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 15)));
    } on Exception {
      throw ApiException('Serverga ulanib bo‘lmadi. Internet va server manzilini tekshiring.');
    }

    final text = utf8.decode(res.bodyBytes);
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = text;
      }
    }
    if (res.statusCode >= 400) {
      final msg = _detail(data);
      if (msg != null && msg.isNotEmpty) {
        throw ApiException(msg, res.statusCode);
      }
      if (res.statusCode == 500) {
        throw ApiException('Serverda ichki xatolik yuz berdi (500). Serverni tekshiring.', res.statusCode);
      }
      throw ApiException(
        text.isNotEmpty && text.length < 100 && !text.contains('<html') ? text : 'Xatolik (${res.statusCode})',
        res.statusCode,
      );
    }
    return data;
  }

  String? _detail(dynamic data) {
    if (data is Map && data['detail'] != null) {
      final d = data['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty && d.first is Map) return (d.first as Map)['msg']?.toString();
    }
    return null;
  }
}
