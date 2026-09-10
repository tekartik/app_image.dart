/// Integer helpers whose implementation depends on the platform.
///
/// When compiled to JavaScript, bit operations produce unsigned 32-bit
/// results, so an arithmetic right shift of a negative value must be
/// emulated; on the VM the native `>>` is used.
library;

export 'int_utils_vm.dart' if (dart.library.js_interop) 'int_utils_js.dart';
