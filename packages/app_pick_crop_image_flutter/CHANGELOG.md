## 0.3.0

* `file_picker` is no longer used directly: picking goes through
  `tekaly_file_picker_flutter` (which handles the linux `file_selector`
  fallback and the last directory) and `saveImageFile()` through
  `tekaly_file_download` (browser download on the web, save dialog elsewhere),
  so it is no longer platform specific.
* `TkPickedFilePlatform` now holds a `TekalyPickedFile` (`pickedFile`) instead
  of a `file_picker` `PlatformFile`.

## 0.0.1

* TODO: Describe initial release.
