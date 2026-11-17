import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

@JS('document.baseURI')
external String get _documentBaseUri;

Uri packagedWorkerUri() {
  final asset = ui_web.assetManager.getAssetUrl(
    'packages/device_readout_flutter/assets/device-readout-dart-worker.js',
  );
  // Resolve against the document base, including when a router changes location.
  return Uri.parse(_documentBaseUri).resolve(asset);
}
