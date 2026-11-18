import 'dart:ffi' as ffi;

typedef WindowsNetworkCallback = ffi.Void Function(
  ffi.Uint64,
  ffi.Int32,
  ffi.Uint32,
);

@ffi.Native<
  ffi.Uint64 Function(ffi.Pointer<ffi.NativeFunction<WindowsNetworkCallback>>)
>(
  symbol: 'readout_network_callback_create',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external int createNetworkCallback(
  ffi.Pointer<ffi.NativeFunction<WindowsNetworkCallback>> listener,
);
@ffi.Native<ffi.Pointer<ffi.Void> Function()>(
  symbol: 'readout_network_callback_function',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external ffi.Pointer<ffi.Void> networkCallbackFunction();
@ffi.Native<ffi.Void Function(ffi.Uint64)>(
  symbol: 'readout_network_callback_ack',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external void acknowledgeNetworkCallback(int token);
@ffi.Native<ffi.Void Function(ffi.Uint64)>(
  symbol: 'readout_network_callback_remove',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external void removeNetworkCallback(int token);

// Ordinals correspond to the internal C ABI; never exposed as entity options.
enum WindowsCall {
  firstVolume,
  nextVolume,
  freeSpace,
  openFile,
  volumeInformation,
  processorTopology,
  processAffinity,
  processCpuSets,
  systemCpuSets,
}

final class WindowsCallResult extends ffi.Struct {
  @ffi.IntPtr()
  external int value;
  @ffi.Uint32()
  external int error;
}

@ffi.Native<
  ffi.Void Function(
    ffi.Int32,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.UintPtr>,
    ffi.Pointer<WindowsCallResult>,
  )
>(
  symbol: 'readout_win32_call',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external void _call(
  int kind,
  ffi.Pointer<ffi.Void> function,
  ffi.Pointer<ffi.UintPtr> arguments,
  ffi.Pointer<WindowsCallResult> result,
);

/// Buffer lifetime belongs to the enclosing collection operation.
final class WindowsCalls {
  final ffi.Pointer<ffi.UintPtr> _arguments;
  final ffi.Pointer<WindowsCallResult> _result;
  WindowsCalls(ffi.Pointer<ffi.Void> Function(int) reserve)
    : _arguments = reserve(8 * ffi.sizeOf<ffi.UintPtr>()).cast(),
      _result = reserve(ffi.sizeOf<WindowsCallResult>()).cast();

  int get error => _result.ref.error;
  int invoke(
    WindowsCall kind,
    ffi.Pointer<ffi.Void> function,
    List<int> arguments,
  ) {
    for (var i = 0; i < arguments.length; i++) {
      _arguments[i] = arguments[i];
    }
    _call(kind.index, function, _arguments, _result);
    return _result.ref.value;
  }
}
