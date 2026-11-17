import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

// Invoked with the pinned Flutter tool's package configuration by the consumer fixture.
void main(List<String> arguments) {
  stdout.write(jsonEncode(loadYaml(File(arguments.single).readAsStringSync())));
}
