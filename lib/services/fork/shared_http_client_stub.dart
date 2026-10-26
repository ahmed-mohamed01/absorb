import 'package:http/http.dart' as http;

/// Without dart:io (web) the platform client has no idle timeout to set.
http.Client newClient() => http.Client();
