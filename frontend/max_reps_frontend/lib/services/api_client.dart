import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:max_reps_frontend/config/api_config.dart';

// Represents an unsuccessful API response.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  // Controls how the exception appears when converted to text.
  @override
  String toString() => 'ApiException ($statusCode): $message';
}

class ApiClient {
  // Reuse this HTTP client for requests.
  // The leading underscore makes it private to this Dart library.
  final http.Client _client;

  // Accept a supplied client, or create one when none is provided.
  // Supplying a client will also make testing easier later.
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  // JSON responses can contain an object, list, or other JSON value.
  // Future means the result will become available asynchronously.
  Future<dynamic> get(
    String path, {
    String? token,
    Map<String, String>? queryParameters,
  }) async {
    // Combine the server address with a path such as /exercises/.
    // Uri handles encoding query parameters correctly.
    final uri = Uri.parse(
      ApiConfig.baseUrl,
    ).resolve(path).replace(queryParameters: queryParameters);

    final response = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',

            // Include authentication only when a token was supplied.
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(ApiConfig.requestTimeout);

    return _handleResponse(response);
  }

  // Send a POST request
  // Send a POST request whose body contains JSON.
  Future<dynamic> postJson(
    String path, {
    required Map<String, dynamic> body,
    String? token,
  }) async {
    final uri = Uri.parse(ApiConfig.baseUrl).resolve(path);

    final response = await _client
        .post(
          uri,
          headers: {
            // Tell the server which response format we accept.
            'Accept': 'application/json',

            // Tell the server how our request body is encoded.
            'Content-Type': 'application/json',

            if (token != null) 'Authorization': 'Bearer $token',
          },

          // Convert the Dart map into JSON text before sending it.
          body: jsonEncode(body),
        )
        .timeout(ApiConfig.requestTimeout);

    // Reuse the same response handling as GET requests.
    return _handleResponse(response);
  }

  // Send a POST request for form fields
  Future<dynamic> postForm(
    String path, {
    required Map<String, String> body,
    String? token,
  }) async {
    final uri = Uri.parse(ApiConfig.baseUrl).resolve(path);

    final response = await _client
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: body,
        )
        .timeout(ApiConfig.requestTimeout);

    return _handleResponse(response);
  }

  // DELETE endpoints may accept JSON, such as password confirmation or a
  // previewed cleanup cutoff. A successful 204 response is handled as null.
  Future<dynamic> delete(
    String path, {
    required String token,
    Map<String, dynamic>? body,
  }) async {
    final response = await _client
        .delete(
          Uri.parse(ApiConfig.baseUrl).resolve(path),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            if (body != null) 'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(ApiConfig.requestTimeout);
    return _handleResponse(response);
  }

  // Decode responses and handle HTTP failures in one shared place.
  dynamic _handleResponse(http.Response response) {
    final isSuccessful =
        response.statusCode >= 200 && response.statusCode < 300;

    dynamic data;

    try {
      // An empty response has no JSON to decode.
      // Decode bytes as UTF-8 so non-ASCII text is preserved.
      data = response.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      // A server or proxy might return HTML or another non-JSON body.
      throw ApiException(
        statusCode: response.statusCode,
        message: isSuccessful
            ? 'The server returned invalid JSON.'
            : 'Request failed (${response.statusCode}).',
      );
    }

    if (!isSuccessful) {
      // FastAPI returns errors as {"detail": "message"}.
      // Validation errors can contain a list instead of a string.
      final detail = data is Map<String, dynamic> ? data['detail'] : null;

      throw ApiException(
        statusCode: response.statusCode,
        message: detail is String
            ? detail
            : 'Request failed (${response.statusCode}).',
      );
    }

    return data;
  }

  // Release resources when the owner is finished using this client.
  // Keep it open while the app still needs to make requests.
  void close() {
    _client.close();
  }
}
