part of 'transport_web.dart';

@JS('Object.keys')
external JSArray<JSString> _objectKeys(JSObject object);

Future<JSAny?> _encodeJs(Object? raw, WorkerTransferBudget budget) async {
  final pause = budget.checkpoint();
  if (pause != null) await pause;
  final value = workerWireValue(raw);
  if (value is Iterable<Object?>) {
    final array = JSArray<JSAny?>();
    final items = array.toDart;
    for (final item in value) {
      items.add(await _encodeJs(item, budget));
    }
    return array;
  }
  if (value is Map<Object?, Object?>) {
    final object = JSObject();
    for (final entry in value.entries) {
      final key = workerWireValue(entry.key).toString().toJS;
      object.setProperty(key, await _encodeJs(entry.value, budget));
    }
    return object;
  }
  // Primitive conversion is bounded; large graphs never enter jsify().
  return value.jsify();
}

// Copy only a bounded traversal slice before admitting a browser task. The
// returned Dart graph is private to this read, not a view into the JS payload.
Future<Object?> _decodeJs(
  JSAny? value,
  WorkerTransferBudget budget, [
  int depth = 0,
]) async {
  final pause = budget.checkpoint();
  if (pause != null) await pause;
  if (depth > 16)
    throw const FormatException('Worker response nesting is invalid.');
  if (value == null) return null;
  if (value.isA<JSString>() ||
      value.isA<JSNumber>() ||
      value.isA<JSBoolean>()) {
    return value.dartify();
  }
  if (value.isA<JSArray<JSAny?>>()) {
    final source = (value as JSArray<JSAny?>).toDart;
    final result = <Object?>[];
    for (var i = 0; i < source.length; i++) {
      result.add(await _decodeJs(source[i], budget, depth + 1));
    }
    return result;
  }
  if (value.isA<JSObject>()) {
    final object = value as JSObject;
    final result = <String, Object?>{};
    for (final key in _objectKeys(object).toDart) {
      result[key.toDart] = await _decodeJs(
        object.getProperty<JSAny?>(key),
        budget,
        depth + 1,
      );
    }
    return result;
  }
  throw const FormatException('Unexpected worker response value.');
}
