import 'dart:async';
import 'dart:html' as html; // ignore: avoid_web_libraries_in_flutter

import 'package:image_picker/image_picker.dart';

import 'import.dart';

final _picker = ImagePicker();

/// Handle file picker cancel, listening for onFocus on the window.
///
/// focus is restored on the window when cancelled.
Future<XFile?> pickImageWeb({
  required ImageSource source,
  CameraDevice preferredCameraDevice = CameraDevice.rear,
}) async {
  late StreamSubscription onFocusSubscription;
  try {
    var completer = Completer<XFile?>();

    void _complete(XFile? file) {
      onFocusSubscription.cancel();
      if (!completer.isCompleted) {
        completer.complete(file);
      }
    }

    // First one wins
    onFocusSubscription = html.window.onFocus.listen((e) {
      // If we get the focus back, return null
      // it means no files were selected
      _complete(null);
    });
    // ignore: unawaited_futures
    _picker
        .pickImage(source: source, preferredCameraDevice: preferredCameraDevice)
        .then((file) {
      _complete(file);
    });

    return await completer.future;
  } finally {
    // ignore: unawaited_futures
    onFocusSubscription.cancel();
  }
}
