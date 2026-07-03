import 'connectivity_probe_stub.dart'
    if (dart.library.io) 'connectivity_probe_io.dart'
    if (dart.library.html) 'connectivity_probe_web.dart';

Future<bool> hasInternetConnection() => probeInternetConnection();
