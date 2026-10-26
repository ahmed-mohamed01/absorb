import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Idle keep-alive connections are dropped after this; the proxy in front of
/// the server was seen dropping them between 10 and 15 s, and a request on a
/// dropped one stalls instead of failing.
const sharedClientIdleTimeout = Duration(seconds: 5);

http.Client newClient() => IOClient(HttpClient()
  ..idleTimeout = sharedClientIdleTimeout
  ..connectionTimeout = const Duration(seconds: 15));
