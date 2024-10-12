import 'package:dev_build/shell.dart';

Future<void> main() async {
  await run('flutter run -d web-server --web-port 8060 --web-hostname 0.0.0.0');
}
