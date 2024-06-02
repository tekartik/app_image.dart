import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

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

    void complete(XFile? file) {
      onFocusSubscription.cancel();
      if (!completer.isCompleted) {
        completer.complete(file);
      }
    }

    // First one wins
    onFocusSubscription =
        web.EventStreamProviders.focusEvent.forTarget(web.window).listen((e) {
      // If we get the focus back, return null
      // it means no files were selected
      complete(null);
    });
    // ignore: unawaited_futures
    _picker
        .pickImage(source: source, preferredCameraDevice: preferredCameraDevice)
        .then((file) {
      complete(file);
    });

    return await completer.future;
  } finally {
    // ignore: unawaited_futures
    onFocusSubscription.cancel();
  }
}
