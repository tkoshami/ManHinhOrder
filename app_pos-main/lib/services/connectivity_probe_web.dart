// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> probeInternetConnection() async {
  return html.window.navigator.onLine ?? true;
}
