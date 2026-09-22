import 'package:flutter/services.dart';

abstract interface class HeadingCapabilitySource {
  Future<bool> hasNorthReferencedHeading();
}

/// Mirrors the sensors actually used by flutter_compass on Android.
final class AndroidHeadingCapabilitySource implements HeadingCapabilitySource {
  const AndroidHeadingCapabilitySource();

  static const channel = MethodChannel('nadr/heading_capability');

  @override
  Future<bool> hasNorthReferencedHeading() async {
    return await channel.invokeMethod<bool>('hasNorthReferencedHeading') ??
        false;
  }
}
