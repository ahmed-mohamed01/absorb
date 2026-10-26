// Fork-owned: the one HTTP client every ApiService shares (bookorbit_perf.dart).
// On a phone it is an IOClient whose idle connections are closed before the
// server's reverse proxy closes them, since a request on a connection the
// other side has already dropped stalled for half a second to a second.

import 'package:http/http.dart' as http;

import 'shared_http_client_stub.dart' if (dart.library.io) 'shared_http_client_io.dart' as impl;

http.Client newSharedHttpClient() => impl.newClient();
