import 'package:dio/dio.dart';

class DioFactory {
  DioFactory._();

  static Dio create({String? baseUrl}) {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl ?? '',
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 18),
        sendTimeout: const Duration(seconds: 6),
      ),
    );
  }

  static Dio createForValidation() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
  }
}
