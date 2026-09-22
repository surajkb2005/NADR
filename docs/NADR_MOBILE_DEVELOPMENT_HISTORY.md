# NADR mobile development history (through Prompt 7.2A)

This is a handoff record for the Flutter Android prototype in `mobile/`, not a
claim that website parity is complete. The React frontend is the reference for
current behavior; the existing FastAPI backend has not been changed by mobile
development. Read this alongside `mobile/README.md` and the source/tests before
continuing. The paths and tool versions below describe the current development
machine, not requirements for every contributor.

## Non-negotiable boundaries

- Do not change `backend/` unless a future task explicitly authorizes it. Run
  `mobile/tool/verify_backend_unchanged.sh` after mobile work. Do not change the
  React frontend merely to make the mobile prototype easier.
- Map presentation consumes `NavigationSessionState.displayedPosition`. The
  session controller selects the accepted GPS or IMU estimate according to the
  **manual** mode; map widgets do not choose a location source themselves.
- Keep Android location/sensor adapters separate from the estimator and UI.
  `DeviceLocationSource`, `ImuSensorSource`, `PositionEstimator`, map controller,
  route repository, and other interfaces are intended to remain replaceable.
- Never publish a demo coordinate or an unconfirmed GPS candidate as real GPS.
  IMU estimation starts from a real, accepted GPS fix. Destination and route
  state must survive manual GPS/IMU switching.
- Supply map style URLs and any future credentials through configuration, not
  hard-coded presentation widgets. Do not treat the experimental website IMU
  heuristic as production-grade inertial navigation.

## Implementation chronology

| Prompt | What and why | Main implementation and verification | Remaining limit |
| --- | --- | --- | --- |
| 1 — foundation | Added an Android Flutter project with bootstrap, router, Material 3 theme, Dart-define configuration, and a read-only backend-integrity guard so mobile work remains isolated. | `mobile/lib/app/`, `mobile/lib/main.dart`, `mobile/tool/verify_backend_unchanged.sh`; Flutter analysis/tests/build and guard. | API/WebSocket data sources are placeholders. |
| 2 — domain/state | Added geo, destination, route, and navigation models plus `NavigationSessionState`, `displayedPosition`, GPS/IMU mode, and replaceable interfaces. This keeps source selection out of map widgets. | `mobile/lib/core/geo/`, `mobile/lib/features/navigation/domain/`, `destination/domain/`, `routing/domain/`; model/controller tests. | Destination and route models are not wired to live services. |
| 3 — UI | Built the map-first Material 3 shell, destination surface, manual mode control, information bottom sheet, and reusable status/widgets. | `mobile/lib/features/map/presentation/`, `mobile/lib/shared/widgets/`; widget tests. | Destination surface is not functional search/routing. |
| 4 — real map | Replaced the placeholder with interactive MapLibre, isolated camera/controller APIs, and Dart-define style loading. The OpenFreeMap liberty style is used for testing, not embedded as a secret/default. | `mobile/lib/features/map/infrastructure/`, `presentation/widgets/maplibre_map_surface.dart`, `mobile/lib/app/bootstrap/environment.dart`; automated map/widget checks and debug APK. | Internet/style availability is required; offline maps are not present. |
| 5 — GPS | Added Android foreground coarse/fine location permission handling, initial fix plus stream, location coordinator, statuses, and pause/resume lifecycle management. | `mobile/lib/features/location/`, `mobile/android/app/src/main/AndroidManifest.xml`; coordinator/source tests. | No background tracking. |
| 6 — pointer/camera | Added real current-location presentation, camera follow/explore/recenter behavior, and `displayedPosition`-driven updates so manual map exploration is respected. | `mobile/lib/features/map/presentation/map_camera_follow_controller.dart`, map widgets/controller; camera and marker tests. | Human judgment of visual smoothness is still needed. |
| 7 — IMU/pointer | Moved the GPS/IMU marker to a native geographic MapLibre symbol to eliminate screen-overlay drift. Added Android user-accelerometer/compass adapters, a Dart port of the website's experimental IMU heuristic, and manual GPS/IMU mode. | `mobile/lib/features/map/infrastructure/maplibre_current_location_layer.dart`, `features/imu/`, `features/navigation/infrastructure/website_imu_position_estimator.dart`; automated tests and device investigation. | IMU cannot provide dependable directional navigation without trustworthy north heading and is subject to drift. |
| 7.1 — stability/diagnostics | Added baseline GPS quality checks, stage-tagged diagnostics, 200 ms estimator cadence despite faster sensor events, and reduced redundant marker/camera work. Physical testing localized the GPS jump to Android raw location and exposed false compass-zero behavior. | `gps_fix_quality_gate.dart`, `geolocator_device_location_source.dart`, `nadr_diagnostics.dart`, IMU coordinator, map modules; automated tests plus Motorola Android 12 logs. | Baseline gate still accepted plausible-speed large jumps when accuracy was unavailable. |
| 7.2 — confirmed fixes | Added temporary quarantine/confirmation for substantial unknown-accuracy GPS jumps and an Android north-heading capability check. Missing/invalid heading now clears directional state and suspends IMU coordinate propagation. | GPS gate/source, Android `MainActivity.kt`, `android_heading_capability.dart`, IMU source/coordinator/estimator; automated regressions and physical verification status below. | Sustained bad fixes can eventually confirm; unsupported-heading devices cannot directionally navigate in IMU mode. |
| 7.2A — physical-device fix pass | Split GPS/IMU native marker sources so a same-coordinate mode change activates a different symbol layer; preserved useful zoom on recenter; kept the strongest acceleration within each 200 ms window; preserved measured horizontal accuracy metadata. Added stage diagnostics and regressions. | Map layer/follow controller, IMU coordinator/estimator diagnostics, location conversion/domain, related tests; verification below. | Physical behavior on each device still needs fresh, separate logs/visual checks. |

## GPS jump: evidence, fix, and limits

The marker repeatedly jumped roughly 120 m away and returned. An early
hypothesis was overlay/camera instability, so Prompt 7 used a native MapLibre
geographic symbol. Prompt 7.1 then logged raw Android fixes, quality decisions,
navigation state, and map marker updates. On the Motorola Android 12 device the
incorrect coordinate appeared **first in the raw Android location stream**,
passed the baseline gate, and was faithfully rendered by MapLibre. This was
not a MapLibre-originated coordinate bug. The outlying fix had
`Position.hasAccuracy == false`, a zero reported speed, and plausible time and
implied speed. Geolocator's numeric accuracy (which can be zero) is **not**
trusted when `hasAccuracy` is false; zero speed does not prove stationarity.
No exact personal coordinates or device serial are recorded here.

`GpsFixQualityGate` still rejects invalid coordinates, fixes older than two
minutes or over 30 seconds in the future, reported accuracy over 150 m when
available (or invalid numeric accuracy), reported or implied speed over
100 m/s, and out-of-order timestamps. It does not blindly lower the speed
limit. After this baseline, `GpsOutlierQuarantine` holds a jump of at least
60 m from the last accepted fix when accuracy is unavailable and the elapsed
time is at most two minutes. The new point needs three consecutive fixes in
the same area (each within 40 m of the preceding candidate) to confirm.
A fix near the accepted area or a useful-accuracy fix rejects the pending
candidate and updates normally; ordinary unknown-accuracy movement under
60 m also updates normally. Candidates expire after 90 seconds. Source
start/stop/dispose reset pending state, and stream generations reject late
old-session events. A zero stream distance filter with a two-second interval
allows confirmation readings even when the device is stationary at a genuinely
new location; downstream map updates remain deduplicated. Battery/performance
on diverse phones should continue to be watched.

Debug-only `NADR_GPS_*` diagnostics now include raw `hasAccuracy` and numeric
accuracy and distinguish accepted, rejected, quarantined, and confirmed fixes,
including candidate/accepted coordinates, displacement, elapsed time, support
count, and reason. The accepted position alone enters navigation state and the
map marker. This is a pragmatic two-cluster filter, not proof that a sustained
cluster is correct: three consistently erroneous fixes can be confirmed.
The 60 m / 40 m / three-fix / 90-second thresholds are starting values based
on the observed isolated ~120 m outlier and should be evaluated on more devices.

## IMU heading: evidence, fix, and limits

The website IMU formula is an experimental acceleration/decay heuristic, now
ported to Dart. Android user-accelerometer samples arrive faster than the
website's intended 200 ms estimator tick; since 7.2A, the coordinator consumes
the strongest acceleration observed per tick and the latest heading, adding
speed only once per window. Android compass heading is clockwise from north, unlike the
browser DeviceOrientation convention, so the browser orientation offset is not
copied blindly. The Motorola supplied repeated 0° values from
`flutter_compass`, while device capability checks found neither a magnetic-field
sensor nor a north-referenced rotation-vector sensor. A zero value **can** be
genuine north on a supported device, so it is not globally rejected.

Prompt 7.2 adds the isolated `nadr/heading_capability` Android method channel.
It reports north-reference support for `TYPE_ROTATION_VECTOR`, or for both
accelerometer and magnetic-field sensors, matching `flutter_compass`'s paths;
`TYPE_GAME_ROTATION_VECTOR` alone is not north-referenced. The Flutter source
does not subscribe to compass or accept its constant zero on unsupported
hardware. Supported finite 0° is valid. Invalid, missing, or >4-second-stale
heading reports `headingUnavailable` separately from motion absence or stream
error, and a later valid heading can resume operation. While heading is
unavailable, the coordinator clears heading and speed but preserves the last
coordinate, ignores acceleration for position updates, and uses the neutral
purple IMU marker plus compact status. Switching manually back to GPS still
shows the latest accepted fix. This avoids fabricated northward travel; it
does not create a substitute heading or a new sensor-fusion algorithm.

## Verification status

- Automated: Prompt 7.2 full Flutter test suite: **118 passed**; GPS/IMU
  regression coverage includes A→B→A rejection, sustained relocation,
  unknown/known accuracy, inconsistent candidates, ordering/expiry/reset,
  pending candidate during mode switching, valid 0°, unsupported constant 0°,
  invalid/missing heading, recovery, neutral/directional markers, no invented
  propagation, and manual return to GPS. `dart format`, `flutter analyze`,
  both debug APK builds (plain and OpenFreeMap-configured), `git diff --check`,
  `git diff -- backend/`, and the backend guard all passed.
- Physical Motorola log verification in this task's original Prompt 7.2 run:
  **pending**; `adb devices -l` listed no connected device then. A later
  Prompt 7.2 Motorola capture is reported in the 7.2A handoff: only small
  ordinary GPS changes were seen; the earlier large raw outlier did not recur.
  Thus that capture does **not** physically prove the large-outlier filter.
- Human visual verification: pending. Automated state/log correctness is not
  a substitute for judging marker smoothness, pan/zoom, and recenter on-device.

## Prompt 7.2A — focused fix and investigation

### Evidence by device and method

| Device | Before 7.2A | During this 7.2A run | What is *not* established |
| --- | --- | --- | --- |
| A — Motorola moto g 60, Android 12 | Earlier **ADB logs** proved the ~120 m bad coordinate originated in raw Android location and the old heading source was untrustworthy. The user's later 7.2 capture reported only small GPS changes, not a recurrence of the large outlier. The blue-after-IMU and recenter zoom symptoms were **human visual observations**. | The device connected late in this run. ADB installed the first 7.2A APK; fresh GPS logs showed small accepted changes and the flag/value discrepancy. Screenshots showed blue GPS → neutral purple IMU → blue GPS without recenter. The device disconnected before pan/recenter and before the final accuracy-corrected APK could be installed. | Recenter visual behavior, final APK's physical accuracy handling, and the exact large-outlier regression remain unverified. |
| B — working-heading device (reported as Oneplus pad 1) | **Human visual observation only:** heading/directional purple pointer looks correct and “IMU estimation active” appears, but geographic motion was not visible while walking. There were no prior Device B diagnostic logs. | Not connected; no fresh acceleration, speed, coordinate, navigation, or map logs. | The first failed stage of Device B's physical motion pipeline. Do not attribute Motorola logs to B. |
| C — indoor tablet observation | **Human visual observation only:** initial GPS was inaccurate indoors and improved over time; another near-building walk showed roughly 10–15 m discrepancy. | Not connected; no fresh GPS log. | Whether any specific fix was accepted/rejected on this tablet. Ordinary GNSS uncertainty is not evidence of a code defect. |

### Marker and camera

The session mapper and screen listener already included `navigationMode`, so
coordinate equality in those components was **not** the missing mode signal.
The prior native layer used one GeoJSON feature/source and changed its `icon`
property at the same geometry. That is a concrete same-point visual-refresh
fragility, consistent with the user's observation that moving the camera via
recenter made the color update; without a fresh device capture, the native
renderer behavior itself is not proven. `MapLibreCurrentLocationLayer` now
keeps separate GPS and IMU sources/layers. Switching mode empties the old source
and populates the new one even at identical coordinates. IMU heading/coordinate
changes also alter GeoJSON feature identity; style reload reinstalls both
sources and restores current marker state. Automated tests verify blue GPS,
neutral/directional purple IMU, same-point mode/heading changes, coordinate
changes, and style reload. No map widget or camera move is needed for refresh.

The recenter zoom-out had a definite code cause: `MapCameraFollowController`
always passed zoom 16.5, including when the user was already zoomed closer.
Recenter now targets `displayedPosition`, restores FOLLOWING, preserves any
finite current zoom at or above 15.5, and uses 16.5 only when zoom is lower or
unknown. It does not select a navigation mode or change the marker. Manual
pan/zoom still enters USER_EXPLORE. Tests cover both zoom branches and mode
preservation; on-device visual verification remains pending.

### IMU movement and diagnostics

The current React implementation uses magnitude `sqrt(x²+y²+z²)`, strict
threshold 1, gain 0.6, cap 20 km/h, then on each ~200 ms tick applies
`speed = speed * 0.90 - 1`, snaps values below 2 to zero, divides by 3.6,
uses initial `dt=0.1` (later actual elapsed time, rejecting gaps over 2 s),
and propagates on a sphere of radius 6,371,000 m. Dart matches these constants,
order, and geographic calculation, without applying the browser's -90°
orientation offset to Android. There is **no identified formula/order parity
bug**. Prompt 7.1 intentionally changed event-rate speed accumulation to one
contribution per estimator window. A deterministic 7.2A test exposed that the
last quiet event in a window could erase an earlier strong movement sample.
The coordinator now retains the strongest finite acceleration in that window
but still contributes speed only once, using the latest valid heading. This
addresses a real sampling loss without reverting to event-rate accumulation.

The existing cutoff can still make mild motion invisible: one magnitude-2
sample adds 1.2 km/h, then immediately decays below 2 and produces zero
distance. This is a tested consequence of the current heuristic, not evidence
that Device B produced such samples. `NADR_IMU_SENSOR`, `NADR_IMU_ESTIMATOR`,
`NADR_IMU_TICK`, `NADR_NAV_IMU`, and `NADR_MAP_MARKER` now expose raw gravity-free
values, magnitude/threshold, pre/post contribution and decay speed, heading,
sample age, `dt`, distance, generated coordinate, publication, session
coordinate, and native marker coordinate. Only Device B's fresh logs can locate
its actual first failing stage. Supported 0° north and directional heading
remain valid; the Motorola no-heading path stays neutral/no propagation.

### GPS accuracy and convergence

Inspected the pinned Geolocator Android 5.0.3 mapper and platform interface
4.3.0, then confirmed the discrepancy in fresh **Motorola ADB logs**:
`hasAccuracy=false` accompanied positive numeric radii around 10–20 m.
Android's `Location.hasAccuracy()` controls whether the native channel includes
`accuracy` (horizontal accuracy radius in meters). `Position.fromMap` correctly
sets `hasAccuracy` from key presence. However, `AndroidPosition.fromMap` then
reconstructs a subclass using the number but **fails to forward any `has*`
flags** to its superclass, whose defaults are false. That wrapper is the exact
cause of the contradictory device log. Absent native values receive numeric
zero; zero must not mean perfect measurement. `GpsAccuracy` recognizes a
positive/nonzero AndroidPosition radius as reported by this pinned native
mapper, allowing the baseline gate to reject measured >150 m errors and
preserving positive finite values in `PositionSample.horizontalAccuracyMeters`.
Because the observed Motorola outlier could still carry a misleading radius,
the large-jump quarantine **continues to treat the lost flag conservatively**;
it does not let this inferred radius bypass confirmation. Quarantine decisions
remain internal until confirmed. No 60 m/40 m/three-fix/90-second threshold
was retuned. Tests cover the wrapper loss, 10 m/20 m measurements, absent and
explicit-false accuracy, poor accuracy rejection, continued Android large-jump
quarantine, ordinary jitter and ~15 m convergence, A→B→A, and session reset.

Prompt 7.2A final automated results: **127 Flutter tests passed**;
`flutter analyze` reported no issues; plain and OpenFreeMap debug APK builds
succeeded. The first 7.2A APK was visually checked for immediate marker mode
color on Motorola, but the final accuracy-corrected APK was built after that
phone disconnected and could not be installed. Recenter behavior still needs
physical verification. The fresh GPS log excerpt spanned ordinary small fixes,
not a recurrence of the earlier large outlier; it was not a continuous
60-second archived trace. Backend guard and diff checks are in the handoff.

## Prompt 7.2B — recenter concurrency and React IMU event-rate parity

### Recenter finding and fix

On Motorola, repeated Recenter taps produced delayed “Unable to recenter on
location” messages despite the map remaining usable. Each tap previously
started a new MapLibre `animateCamera` operation. The pinned MapLibre Android
implementation completes a superseded camera Future with `Exception: Map
camera movement cancelled.`; the screen caught every exception as a location
failure and queued one snackbar per cancellation. The follow controller now
coalesces taps while a recenter animation is in flight, treats an already
centered camera as a successful no-op, defers GPS follow-camera moves during
the recenter, and recognizes MapLibre's camera-cancellation exception as a
non-error outcome. The screen shows no error for coalesced/already-centered/
cancelled outcomes and allows at most one visible snackbar for a genuine
recenter failure. A deterministic 15-request test confirms one effective
camera operation. The final OpenFreeMap APK was installed on the Motorola and
an ADB-injected pan plus 15 rapid Recenter taps produced 15 requests, one
animation start and success, 11 coalesced requests, and three already-centered
no-ops. The targeted `device_a_recenter_final.log` recorded no recenter
failure or camera-cancellation error. A subsequent screen capture showed the
blue GPS marker centered and no queued snackbar. On the same APK, GPS→IMU
showed the neutral purple marker and “IMU heading unavailable”; IMU→GPS
immediately restored blue. There was no crash in this run.

### IMU parity finding and Device B evidence

Re-reading `frontend/src/App.jsx` confirmed two independent loops: its
`devicemotion` listener adds `magnitude * 0.6` for **every** real event above
1.0 m/s² (cap 20 km/h), while a ~200 ms interval performs `speed * 0.90 - 1`,
the <2 km/h cutoff, and geographic propagation. The Prompt 7.1/7.2A Flutter
coordinator instead retained only the strongest acceleration event per
200 ms window and contributed speed once. That sampling policy, not a
constant mismatch, made ordinary walking too easy to erase at decay. Flutter
now feeds each sensor event to the estimator and leaves decay/position updates
on the 200 ms timer. Heading remains north-referenced and independent; no
threshold, gain, cap, decay, or GPS-quality constants changed. One motion
subscription remains active per IMU session, with stop/cancel on mode change.

Device B is the **OnePlus Pad 1 / OPD2203**. ADB logs are now available (unlike
the original 7.2A handoff). The pre-fix Pad logs supplied with this prompt
showed valid changing heading, acceleration and threshold crossings, but many
moderate impulses decayed below cutoff and generated zero distance. Stronger
movement already produced non-zero distance and changed estimator, navigation,
displayed and MapLibre coordinates, so the downstream map path was functional.
The final APK was installed on the Pad; the user confirmed the captured motion
was normal walking, not shaking. Its targeted run was saved as
`device_b_imu_final.log` (local diagnostic, ignored by Git). It reported about
50 accelerometer events/s; 228 decay ticks consumed 2,258 events, 629 above
threshold (maximum 10 above-threshold events in a tick). Speed survived decay
and distance was positive in 161 ticks; the summed estimated distance was
about 95 m. One representative window began at 0 km/h, received 7 qualifying
events out of 10, reached 4.94 km/h before decay, retained 3.45 km/h after
decay, and propagated 0.19 m. The log also shows changing north-referenced
heading, `latestImuPosition`, `displayedPosition`, and native MapLibre marker
coordinates. These log observations support event-rate parity and geographic
movement; exact real-world distance accuracy and visual smoothness still
require human assessment. No exact user location coordinates are included in
this shared history.

Automated checks after the final test addition: Flutter analysis clean; all
133 Flutter tests passed, including the 15-tap recenter, mixed walking-event,
and mode-switch/no-duplicate-contribution cases.
Both plain and OpenFreeMap debug APK builds succeeded. Backend verification
reported unchanged. The GPS quality gate and its thresholds were untouched.

## Prompt 8 — shared REST client and backend connectivity foundation

The original plan's REST/cookie work was deferred while Prompt 7 expanded to
complete and physically verify GPS/IMU navigation. Prompt 8 therefore combines
that foundation with typed response models and a developer connectivity check;
it does not implement destination selection, routing UI, risk UI, OTP login UI,
simulation, WebSockets, or automatic navigation-mode switching.

The API contract was read from `frontend/src/services/api.js`, `App.jsx`,
`nginx.conf`, `backend/app/main.py`, `models.py`, and the backend routing,
heatmap and risk services. The website uses Axios at `/api`, a 10-second
timeout, and `withCredentials`. Backend paths are `/`, `/health`,
`/space-weather/current` (GET with latitude/longitude), `/heatmap` (POST with
`bbox` in lon/lat order and `resolution`), `/route` (POST with lat/lon `start`
and `end`, plus `mode`), and existing `/auth/*` methods. Nginx's `/api/`
proxy strips that prefix before forwarding to FastAPI. The Flutter Dio client
accepts either a direct FastAPI base origin or a proxy base ending `/api/`,
then appends relative endpoint paths exactly once. It has 10-second connect,
send and receive timeouts and one shared instance for the existing contracts.

`NADR_API_BASE_URL` must now be supplied via `--dart-define`; the previous
hardcoded emulator host was removed. An absent URL is an explicit unconfigured
diagnostic state and does not prevent map/navigation use. Android's debug
manifest permits direct HTTP development; production remains HTTPS-first. The
client's app-private persistent cookie jar accepts the backend's `session_id`
cookie. The backend sets it `Secure`, `HttpOnly`, and `SameSite=Lax`, so a
direct HTTP development URL cannot round-trip that authentication cookie;
use HTTPS for session testing. No cookie or OTP values are logged. No token
scheme or login UI was introduced.

The new DTOs decode root, health, route alternatives/metadata, space weather,
heatmap GeoJSON, and authentication responses. Route path pairs remain
`[latitude, longitude]`; GeoJSON and bbox pairs remain longitude-first.
Unknown optional fields are ignored, optional route/weather fields may be
absent, empty lists are valid, and malformed required fields produce typed
invalid-response errors. Network errors distinguish unavailable transport,
timeout, invalid JSON/schema, 401, 422, 429, 5xx and other HTTP failures.
Only the backend's known fixed public error messages may appear in diagnostics;
arbitrary internal error/validation payloads are suppressed.

`GET /` returns `message` and `status=operational`. `GET /health` returns
`healthy` or `degraded`, a timestamp and boolean cache/Redis/NOAA service
flags; it can return 503 when a service check raises. The debug-build-only
server icon opens a small panel on the map with the configured base URL,
status, last result, safe error text, service flags, and a manual retry. A 503
is reported as reachable-but-degraded, unlike a connection failure. The panel
does not load or block the map when the backend is offline and cancels its
request when closed.

Mock fixtures mirror the current backend response construction and cover
success, optional/missing/unknown fields, empty lists, malformed fields,
HTTP failures, path prefixing, health states, cookie retention and persistence,
and the unconfigured panel. The full suite passed **146 tests**; Flutter
analysis was clean. A local live smoke check found neither direct FastAPI at
port 8000 nor the repository Nginx proxy at port 5173 running. No backend was
started or modified. Physical Android connectivity remains pending a real
backend URL reachable from the device; mock success is not physical proof.
The OpenFreeMap debug APK was installed on the Motorola without clearing app
data. A screen capture confirmed the map remained active and the new panel
opened with “Base URL: Not configured,” “Status: unconfigured,” and a retry
button. This is a physical UI smoke check, **not** a backend connection.
The Prompt 7 GPS/IMU/marker/recenter implementation was untouched. See
`mobile/README.md` for phone-reachable URL and build instructions.

## Development setup on this machine

Repository: `/home/darshan/NADR/`; mobile project: `/home/darshan/NADR/mobile/`.
Flutter: `/home/darshan/.cache/nadr-tooling/flutter/bin/flutter`.
Android SDK: `/home/darshan/.cache/nadr-tooling/android-sdk`.
JDK: `/home/darshan/.cache/nadr-tooling/jdk-21`.
Adapt these absolute paths on another machine.

From `mobile/`, with the SDK/JDK on your environment's normal paths, build the
phone-ready test APK with the map style supplied explicitly:

```sh
flutter build apk --debug \
  --dart-define=NADR_MAP_STYLE_URL=https://tiles.openfreemap.org/styles/liberty
adb devices -l
adb -s <authorized-device-serial> install -r build/app/outputs/flutter-apk/app-debug.apk
```

`NADR_MAP_STYLE_URL` has no default; without a valid style, the map shows a
controlled error instead of a street map. Before any uninstall, check for
`INSTALL_FAILED_UPDATE_INCOMPATIBLE`/debug-signature mismatch. Uninstalling or
clearing app data can destroy local device data; obtain the user's approval
first. Verify with `dart format lib test`, `flutter analyze`, `flutter test`,
`flutter build apk --debug`, `git diff --check`, `git diff -- backend/`, and
`mobile/tool/verify_backend_unchanged.sh`.

## Roadmap, not completed work

**Completed prototype foundations:** Flutter shell, models/session, map-first
UI and real interactive map, foreground GPS, marker/camera handling, manual
GPS/IMU control, experimental IMU port, and the Prompt 7.2 guards above.

**Partial:** location and IMU navigation reliability (hardware-dependent and
not production-grade), destination/route domain and UI shells, map styling
and on-device visual validation.

**Not yet implemented:** backend REST client/integration, usable destination
selection, existing `/route` API integration, route display, route information
and risk metadata, and remaining website-parity features (including auth,
simulation, and live data where applicable). Later production possibilities,
not current prototype features, include automatic GPS/IMU switching, advanced
sensor fusion/drift handling, offline maps/routing, and persistent navigation
sessions. Do not begin these as part of Prompt 7.2.
