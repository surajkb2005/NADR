import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:nadr_mobile/features/location/infrastructure/gps_accuracy.dart';

final class GpsFixDecision {
  const GpsFixDecision.accept() : reason = null;
  const GpsFixDecision.reject(this.reason);

  final String? reason;
  bool get accepted => reason == null;
}

/// Conservative guard against stale, imprecise, and physically impossible fixes.
final class GpsFixQualityGate {
  static const maxAge = Duration(minutes: 2);
  static const maxFutureSkew = Duration(seconds: 30);
  static const maxAccuracyMeters = 150.0;
  static const maxReportedSpeedMetersPerSecond = 100.0;
  static const maxImpliedSpeedMetersPerSecond = 100.0;
  static const earthRadiusMeters = 6371000.0;

  const GpsFixQualityGate();

  GpsFixDecision evaluate(
    Position position, {
    required DateTime receivedAt,
    Position? previousAccepted,
  }) {
    final latitude = position.latitude;
    final longitude = position.longitude;
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return const GpsFixDecision.reject('invalid_coordinate');
    }
    final age = receivedAt.difference(position.timestamp);
    if (age > maxAge) return const GpsFixDecision.reject('stale_timestamp');
    if (age < -maxFutureSkew) {
      return const GpsFixDecision.reject('future_timestamp');
    }
    if (GpsAccuracy.isReported(position) &&
        (!position.accuracy.isFinite ||
            position.accuracy <= 0 ||
            position.accuracy > maxAccuracyMeters)) {
      return const GpsFixDecision.reject('poor_accuracy');
    }
    if (position.speed.isFinite &&
        position.speed > maxReportedSpeedMetersPerSecond) {
      return const GpsFixDecision.reject('implausible_reported_speed');
    }
    if (previousAccepted != null) {
      final elapsed = position.timestamp.difference(previousAccepted.timestamp);
      if (elapsed <= Duration.zero) {
        return const GpsFixDecision.reject('out_of_order_timestamp');
      }
      final seconds = elapsed.inMicroseconds / 1000000;
      if (seconds <= maxAge.inSeconds &&
          distanceMeters(position, previousAccepted) / seconds >
              maxImpliedSpeedMetersPerSecond) {
        return const GpsFixDecision.reject('implausible_displacement');
      }
    }
    return const GpsFixDecision.accept();
  }

  static double distanceMeters(Position a, Position b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = lat2 - lat1;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final haversine =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    return 2 * earthRadiusMeters * math.asin(math.sqrt(haversine.clamp(0, 1)));
  }
}

enum GpsOutlierAction { accepted, quarantined, confirmed, rejected }

final class GpsOutlierDecision {
  const GpsOutlierDecision(
    this.action,
    this.reason, {
    required this.displacementMeters,
    required this.elapsedSeconds,
    this.rejectedCandidate,
    this.supportCount = 0,
  });

  final GpsOutlierAction action;
  final String reason;
  final double displacementMeters;
  final double elapsedSeconds;
  final Position? rejectedCandidate;
  final int supportCount;

  bool get accepted =>
      action == GpsOutlierAction.accepted ||
      action == GpsOutlierAction.confirmed;
}

final class _PendingGpsCandidate {
  _PendingGpsCandidate(this.first, this.latest, this.supportCount);

  final Position first;
  Position latest;
  int supportCount;
}

/// Holds large unknown-accuracy jumps until independent fixes agree.
/// Small moves and fixes with measured usable accuracy remain immediate.
final class GpsOutlierQuarantine {
  static const suspiciousJumpMeters = 60.0;
  static const candidateAgreementMeters = 40.0;
  static const confirmationFixCount = 3;
  static const maxCandidateAge = Duration(seconds: 90);
  static const maxSuspiciousElapsed = Duration(minutes: 2);

  _PendingGpsCandidate? _pending;

  Position? get pendingCandidate => _pending?.first;

  void reset() => _pending = null;

  GpsOutlierDecision consider(
    Position position, {
    required Position? previousAccepted,
  }) {
    if (previousAccepted == null) {
      reset();
      return const GpsOutlierDecision(
        GpsOutlierAction.accepted,
        'first_fix',
        displacementMeters: 0,
        elapsedSeconds: 0,
      );
    }
    final elapsed = position.timestamp.difference(previousAccepted.timestamp);
    final seconds = elapsed.inMicroseconds / 1000000;
    final displacement = GpsFixQualityGate.distanceMeters(
      position,
      previousAccepted,
    );
    final pending = _pending;
    if (pending != null &&
        !position.timestamp.isAfter(pending.latest.timestamp)) {
      return GpsOutlierDecision(
        GpsOutlierAction.rejected,
        'out_of_order_candidate',
        displacementMeters: displacement,
        elapsedSeconds: seconds,
      );
    }
    if (pending != null &&
        position.timestamp.difference(pending.first.timestamp) >
            maxCandidateAge) {
      reset();
    }

    // A measured, baseline-approved accuracy is stronger evidence than an
    // earlier unknown-accuracy candidate. Do not delay ordinary measured GPS.
    if (position.hasAccuracy ||
        displacement < suspiciousJumpMeters ||
        elapsed > maxSuspiciousElapsed) {
      final rejectedCandidate = _pending?.first;
      reset();
      return GpsOutlierDecision(
        GpsOutlierAction.accepted,
        rejectedCandidate == null
            ? 'ordinary_fix'
            : 'candidate_disagreed_with_accepted_area',
        displacementMeters: displacement,
        elapsedSeconds: seconds,
        rejectedCandidate: rejectedCandidate,
      );
    }

    final currentPending = _pending;
    if (currentPending != null &&
        GpsFixQualityGate.distanceMeters(position, currentPending.latest) <=
            candidateAgreementMeters) {
      currentPending.latest = position;
      currentPending.supportCount++;
      if (currentPending.supportCount >= confirmationFixCount) {
        final confirmed = GpsOutlierDecision(
          GpsOutlierAction.confirmed,
          'consistent_unknown_accuracy_fixes',
          displacementMeters: displacement,
          elapsedSeconds: seconds,
          supportCount: currentPending.supportCount,
        );
        reset();
        return confirmed;
      }
      return GpsOutlierDecision(
        GpsOutlierAction.quarantined,
        'awaiting_consistent_fix',
        displacementMeters: displacement,
        elapsedSeconds: seconds,
        supportCount: currentPending.supportCount,
      );
    }

    final rejectedCandidate = currentPending?.first;
    _pending = _PendingGpsCandidate(position, position, 1);
    return GpsOutlierDecision(
      GpsOutlierAction.quarantined,
      rejectedCandidate == null
          ? 'unknown_accuracy_large_jump'
          : 'inconsistent_candidate_replaced',
      displacementMeters: displacement,
      elapsedSeconds: seconds,
      rejectedCandidate: rejectedCandidate,
      supportCount: 1,
    );
  }
}
