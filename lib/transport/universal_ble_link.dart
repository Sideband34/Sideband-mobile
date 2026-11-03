import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'ble_transport.dart';

/// [GattLink] on the `universal_ble` plugin (BSD-3, Android/iOS/desktop).
///
/// UNTESTED ON HARDWARE. It compiles and is analysed in CI, but nothing in this
/// repository has run it against a real peripheral. The app does not use it
/// yet: discovery and pairing UX, OS permission prompts and background
/// behaviour still need device testing.
class UniversalBleGattLink implements GattLink {
  UniversalBleGattLink(this.deviceId);

  final String deviceId;

  /// Scans for providers advertising the Sideband service.
  static Stream<BleDevice> scan() async* {
    await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [sidebandServiceUuid]));
    yield* UniversalBle.scanStream;
  }

  static Future<void> stopScan() => UniversalBle.stopScan();

  /// Connects, discovers services and subscribes to provider notifications.
  static Future<UniversalBleGattLink> connect(String deviceId) async {
    await UniversalBle.connect(deviceId);
    await UniversalBle.discoverServices(deviceId);
    await UniversalBle.subscribeNotifications(
        deviceId, sidebandServiceUuid, sidebandTxCharUuid);
    return UniversalBleGattLink(deviceId);
  }

  @override
  Future<int> negotiateMtu(int wanted) =>
      UniversalBle.requestMtu(deviceId, wanted);

  @override
  Future<void> write(Uint8List value) => UniversalBle.write(
      deviceId, sidebandServiceUuid, sidebandRxCharUuid, value);

  @override
  Stream<Uint8List> get notifications =>
      UniversalBle.characteristicValueStream(deviceId, sidebandTxCharUuid);

  @override
  Stream<bool> get connected => UniversalBle.connectionStream(deviceId);

  @override
  Future<void> disconnect() => UniversalBle.disconnect(deviceId);
}
