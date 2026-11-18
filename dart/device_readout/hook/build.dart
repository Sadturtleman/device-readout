import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets ||
        input.config.code.targetOS != OS.windows) {
      return;
    }
    await CBuilder.library(
      name: 'device_readout_win32',
      assetName: 'src/windows_calls.dart',
      sources: [
        'src/windows_calls.c',
        'src/windows_network_events.c',
        'src/windows_connectivity.c',
        'src/windows_wifi.c',
        'src/windows_battery.c',
        'src/windows_battery_packs.c',
      ],
    ).run(input: input, output: output);
  });
}
