import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tekartik_pick_crop_image_demo/page/main_page.dart';

/// Shared preferences.
late SharedPreferences prefs;

/// How webp is encoded (displayed in the options).
var webpEncoderLabel = '';

/// Runs the demo, [webpEncoder] telling how webp is encoded.
Future<void> runPickCropDemo({required String webpEncoder}) async {
  WidgetsFlutterBinding.ensureInitialized();
  webpEncoderLabel = webpEncoder;
  prefs = await SharedPreferences.getInstance();
  runApp(const PickCropDemoApp());
}

/// Pick crop demo app.
class PickCropDemoApp extends StatelessWidget {
  /// Pick crop demo app constructor.
  const PickCropDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pick Crop Image Demo',
      theme: ThemeData(),
      home: const MainPage(),
    );
  }
}
