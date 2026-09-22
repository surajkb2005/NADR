import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/navigation/domain/connection_status.dart';

abstract interface class ImuSyncChannel {
  WebSocketStatus get status;

  Stream<WebSocketStatus> get statusChanges;

  Future<void> connect({required String clientId});

  Future<void> sendPosition(
    PositionSample position, {
    required double speedKilometersPerHour,
  });

  Future<void> disconnect();
}
