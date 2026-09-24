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
and the unconfigured and healthy/retry panel states. All **147 Flutter tests**
passed, including the previous 133 navigation tests; Flutter analysis was
clean. An initial
local probe found no backend at loopback, and no backend was started or
modified. The user then supplied a live direct FastAPI development URL. From
the development machine, its `/` endpoint returned HTTP 200 with
`status=operational`, while `/health` returned HTTP 200 with `status=healthy`
and cache, Redis, and NOAA all true. The supplied Nginx alternative also
returned those responses at `/api/` and `/api/health`, confirming that its
proxy strips `/api` as inspected in `nginx.conf`.

The final OpenFreeMap debug APK was built with that direct URL supplied only
through `--dart-define=NADR_API_BASE_URL=...` and installed on the Motorola
without clearing app data. The debug panel independently reached the backend
from the physical phone and displayed `healthy`, “Backend reachable and
healthy,” plus `cache=true, redis=true, noaa=true`. Manual “Check again” also
returned healthy with a new timestamp. The map and GPS marker remained active
behind the panel. This is a verified physical-device backend connection, not a
mock result. The developer-specific LAN address is intentionally omitted from
shared history and is not present in Flutter source.
The Prompt 7 GPS/IMU/marker/recenter implementation was untouched. See
`mobile/README.md` for phone-reachable URL and build instructions.

## Prompt 9 — Android destination selection

Destination selection now uses the existing `NavigationSessionState.destination`
and `NavigationSessionController`; the map widget does not own a second confirmed
destination. The map-top surface opens a Material 3 bottom sheet that accurately
offers two methods: select a point on the map or enter latitude/longitude. It
shows the confirmed coordinate when one exists and supports replacement and
clearing. The sheet is scrollable on compact phones and width-constrained on
larger devices. No place-name search is claimed.

Map selection is an explicit temporary mode. After choosing “Select a point on
the map,” a stationary MapLibre long-press supplies the native geographic
coordinate and opens a confirmation sheet. Cancel leaves the existing
destination unchanged; confirm updates the session. Ordinary camera gestures
only change camera-follow state and cannot select a destination. Selection mode
ends after a proposal or explicit cancel, while panning, zooming, and recentering
remain available. Manual entry accepts finite numeric latitude in `[-90, 90]`
and longitude in `[-180, 180]`; empty, malformed, NaN, infinity, and out-of-range
values receive field-level errors. Valid numeric input is parsed without display
rounding or coordinate snapping.

The confirmed destination is rendered by one independent native MapLibre source,
symbol layer, and orange pin image. It does not reuse the blue GPS or purple IMU
sources. Replacement rewrites that single source; clearing writes an empty
feature collection. The layer retains the latest session destination while a
style is unavailable and restores it after style reload, avoiding duplicate
layers and stale features. GPS fixes, IMU propagation, mode changes, map gestures,
recenter, and backend diagnostics do not clear destination state.

For Prompt 10, `NavigationSessionState.currentRouteStart` exposes the active
displayed coordinate (latest accepted GPS fix in GPS mode or displayed IMU
position in IMU mode), and `hasRouteEndpoints` reports whether both that start
and a confirmed destination exist. A missing current position stays null and
does not prevent safe destination selection. Prompt 9 sends no `/route` request,
renders no route geometry, and fabricates no duration, risk, or route result.
Known limitations are intentional at this stage: there is no place-name search,
route calculation, route rendering, or destination persistence across a fresh
app process. The confirmed destination persists for the active navigation
session and through GPS/IMU updates and mode changes.

Implementation files added or changed for Prompt 9:

- `mobile/lib/features/destination/presentation/destination_selection_panel.dart`
- `mobile/lib/features/map/infrastructure/maplibre_destination_layer.dart`
- `mobile/lib/features/map/domain/nadr_map_controller.dart`
- `mobile/lib/features/map/infrastructure/maplibre_nadr_map_controller.dart`
- `mobile/lib/features/map/presentation/map_screen.dart`
- `mobile/lib/features/map/presentation/widgets/destination_surface.dart`
- `mobile/lib/features/map/presentation/widgets/interactive_map_layer.dart`
- `mobile/lib/features/map/presentation/widgets/maplibre_map_surface.dart`
- `mobile/lib/features/map/presentation/widgets/navigation_info_sheet.dart`
- `mobile/lib/features/navigation/domain/navigation_session_state.dart`
- destination, map-surface, map-screen, camera-controller, and navigation-session
  tests under `mobile/test/`

All **164 Flutter tests passed**. Coverage includes panel opening, long-press
gating versus normal pan, map review confirm/cancel, exact manual entry, every
invalid-input class, replace/clear, marker create/update/remove, style reload,
GPS/IMU and position-update persistence, route-start selection, no-position
safety, recenter persistence, and zero REST calls during selection. Flutter
analysis reported no issues. The OpenFreeMap debug APK built successfully at
`mobile/build/app/outputs/flutter-apk/app-debug.apk`; the backend URL remained a
build-time `NADR_API_BASE_URL` value rather than Flutter source.

That exact final APK was installed on the connected Motorola. Physical-device
checks opened the destination sheet, showed a field-level manual-entry error,
confirmed a valid manual coordinate, replaced it through a stationary native
MapLibre long-press and review sheet, displayed the distinct orange pin alongside
the blue current-location marker, cleared the destination and removed the pin,
panned and recentered the map, and retained the destination through
GPS→IMU→GPS. The device's actual coordinates are intentionally not recorded.
No backend or React frontend file was modified.

## Prompt 10 — Existing `/route` backend integration

Flutter now integrates the backend's existing `POST /route` contract without
changing or bypassing FastAPI. The exact JSON body is `start`, `end`, and `mode`;
both coordinate pairs use `[latitude, longitude]`, and the explicit mobile action
currently requests `mode: "normal"`. The backend remains the routing authority
and continues to call OSRM internally. Flutter contains no OSRM URL and adds no
routing algorithm.

The request path is UI → `RouteRequestController` → `RouteRepository` →
`RestRouteRepository` → the shared `NadrRestClient` → `/route`. Pressing “Get
route” snapshots the active displayed start and confirmed destination before any
asynchronous work. GPS mode therefore uses the latest accepted/displayed GPS
coordinate; IMU mode uses the displayed IMU coordinate. Later sensor fixes,
heading events, camera changes, and mode changes cannot mutate that in-flight
snapshot and never trigger a route request themselves. The action is disabled
until both endpoints exist. An in-flight guard coalesces rapid repeated taps.

The decoder preserves the backend's normal, safe, drifted, and IMU alternatives,
their latitude/longitude path geometry, distance in meters, estimated time in
seconds, total and average risk, maximum risk zone, risk-segment counts,
optimization, risk weight, description, and the start/end/source/Kp metadata.
Unknown alternatives and response fields are ignored for forward compatibility;
missing optional metadata remains absent. Empty alternatives, malformed shapes,
and invalid coordinates are treated as invalid responses. A successful result is
stored in `NavigationSessionState.routeAlternatives`, with the normal alternative
selected when available, so Prompt 11 can render it.

The navigation sheet uses a non-blocking button spinner and compact success
status. Prompt 10 deliberately creates no MapLibre route source or layer, performs
no fit-bounds operation, and shows no fabricated ETA or directions. Validation,
rate-limit, timeout, unavailable-backend, server, HTTP, authentication, and
invalid-response failures map to short recoverable messages. Cancellation is
quiet. Failures preserve the current position, navigation mode, destination, and
any previously valid route data.

Implementation files added or changed specifically for Prompt 10:

- `mobile/lib/features/routing/application/route_request_controller.dart`
- `mobile/lib/features/routing/infrastructure/rest_route_repository.dart`
- `mobile/lib/features/map/presentation/map_screen.dart`
- `mobile/lib/features/map/presentation/widgets/navigation_info_sheet.dart`
- route client, repository, controller, and map-screen tests under `mobile/test/`
- `mobile/README.md`

All **180 Flutter tests passed** and Flutter analysis reported no issues. Tests
cover the exact method/path/body and coordinate order, all current alternatives,
optional and unknown response data, empty/malformed responses, route-specific
422/429/timeout/offline failures, GPS and IMU start authority, immutable endpoint
snapshots, duplicate-tap coalescing, quiet cancellation, prior-state retention,
explicit UI initiation, and the absence of sensor-triggered route calls.

The final OpenFreeMap debug APK built at
`mobile/build/app/outputs/flutter-apk/app-debug.apk` with the local backend URL
supplied only through `NADR_API_BASE_URL`, then installed successfully on the
connected Motorola. On-device checks confirmed a live current position, confirmed
destination, enabled explicit route action, retained destination/action through
GPS→IMU, and showed the expected recoverable unavailable-backend message without
blocking the map. The exact device location is intentionally not recorded.

Both previously configured LAN backend forms refused connections during final
verification. Consequently, workstation live-response decoding and physical
route-success verification are **pending**, not passed; mock decoding and physical
touch behavior are reported separately. No backend was started or changed in
response to that external connectivity state.

Known limitation: route data is fetched and retained but not drawn. Route
polylines, alternative styling/selection visuals, and route camera fitting belong
to Prompt 11.

**PUBLIC HOSTING: DEFERRED.** No deployment, tunnel, keep-alive service, or public
infrastructure was created.

## Android IMU tracking improvement and React source audit

The actual website live-sensor implementation is in `frontend/src/App.jsx`.
Its `requestSensorPermissions` handler reads gravity-free
`DeviceMotionEvent.acceleration`, calculates the three-axis magnitude, and adds
`magnitude * 0.6` to speed for every event above `1.0`, capped at 20 km/h. A
separate 200 ms interval multiplies speed by `0.90`, subtracts 1 km/h, snaps
values below 2 km/h to zero, and propagates the coordinate on a spherical Earth
using speed, elapsed time, and heading. The first propagation interval is 0.1 s;
negative or greater-than-2-second gaps do not move. GPS initializes the last
position when browser live mode is off.

`App.jsx` obtains heading from `webkitCompassHeading` or `360 - alpha`, then
applies a fixed `-90°` offset. That comment is the only heading “calibration” in
the React live implementation. There is no measured compass bias calibration,
accelerometer calibration, step detector, stationary classifier, sensor fusion,
or walking-direction inference in `App.jsx` or its imported helpers.
`frontend/public/imu.html` is a separate standalone diagnostic: it reports raw
alpha and acceleration including gravity, while its speed buttons are manual;
it is not imported by `App.jsx` and adds no calibration. The simulator and
vehicle animator in `frontend/src/utils/simulation.js` create deliberate route
simulation, not live inertial calibration. `MapComponent.jsx` presents the
result but does not estimate movement. The team-lead-suggested additional
calibration was therefore not present anywhere in the inspected frontend.

Flutter previously reproduced the React event-rate heuristic in
`WebsiteImuPositionEstimator`, including every constant and the separate 200 ms
decay tick. Code inspection and existing OnePlus logs showed why that parity is
not accuracy: at approximately 50 accelerometer events/second, ordinary motion
can repeatedly reach the 20 km/h cap and remain near 17 km/h after decay. The
calculation depends on sampling rate, integrates oscillatory magnitude as
one-way speed, and keeps residual speed after motion. Both React and the former
Flutter production path also assume that the device/display heading is the
user's travel direction. A turn therefore bends any residual travel even when
only the device rotates.

The Android coordinate handling is intentionally different from the browser.
`sensors_plus` user acceleration is gravity-free, matching the React acceleration
quantity, but the native `flutter_compass` plugin already builds a rotation
matrix and remaps axes for Android display rotation and steep device tilt. It
returns clockwise-from-north azimuth and a diagnostic accuracy estimate. The
browser's arbitrary `-90°` offset was not copied. Zero remains valid north;
missing or invalid heading remains null and cannot create northbound travel.
Android compass accuracy is logged as high/medium/low/unknown but is not
misrepresented as a measured guarantee. The heading still represents the top
of the display, so the user must align that edge with travel; true pedestrian
course is unavailable from these inputs alone.

Production Android movement now uses `StepBasedImuPositionEstimator`; the exact
website estimator remains in the tree and retains deterministic parity tests as
a reference. Android's `TYPE_STEP_DETECTOR` is bridged through an EventChannel
with the runtime Physical activity permission. Because the OnePlus detector
registered successfully but emitted no events during a real carried-tablet
walk, the estimator also has a conservative software cadence fallback. Raw
acceleration no longer adds speed per event. A magnitude peak must cross
0.80 m/s², fall to at most 0.30 m/s² to re-arm, and repeat 250–1500 ms later
before it proves walking. Gyroscope magnitude at or above 0.80 rad/s suppresses
device-rotation peaks and resets pending cadence. An isolated handling impulse
cannot move the coordinate. After two seconds without an accepted step, reported
cadence speed becomes zero; no residual distance is integrated.

The constants are traceable rather than demo-oriented. The old React values
(1.0 threshold, 0.6 gain per event, 20 km/h cap, 0.90/−1 decay, 2 km/h cutoff)
remain unchanged only in the reference estimator. A 30-second OnePlus stationary
trace observed sampled gravity-free magnitude from 0.0021 to 0.1098 m/s², while
the user's multi-turn carried-tablet trace reached 1.9167 m/s². This supports the
0.30/0.80 hysteresis separation. The 250–1500 ms cadence window admits roughly
0.67–4 steps/second while rejecting duplicates and requiring re-confirmation
after a stop. The 0.80 rad/s rotation gate corresponds to about 46°/s and
prevents a deliberate device turn from acting as a walking peak. Each accepted
step advances a configurable `NADR_IMU_STEP_LENGTH_METERS`, default 0.65 m and
validated within 0.30–1.50 m. This default is an explicit conservative adult
walking estimate refined by the user's visual over-movement report and a
post-reset trace where 37 accepted steps represented an approximately 24 m
indoor path (`37 × 0.65 m = 24.05 m`). It is not a claim about an individual
stride; physical distance calibration can override it at build time. Android's
explicit low heading quality (45° reported deviation) now pauses directional
propagation; high/medium quality up to 30° and unknown quality remain usable and
diagnosed.

Sensor acquisition remains in `AndroidImuSensorSource`, session/timer handling
in `ImuNavigationCoordinator`, movement and spherical propagation in the new
estimator, authoritative positions in `NavigationSessionController`, and marker
rendering in the existing MapLibre layer. Concise debug diagnostics now include
heading and Android-reported quality, acceleration cadence/magnitude, angular
rate, hardware/software step source, accepted/rejected reason, cadence speed,
cumulative distance, estimated position, displayed position, and marker
position. Per-event acceleration logging remains throttled. Physical logs are
saved under the git-ignored `device_logs/` directory; exact device coordinates
are not copied into this history.

Automated coverage retains React-to-Dart formula parity and adds deterministic
tests for north-clockwise cardinal propagation, valid 0°, unavailable heading,
event-rate independence, stationary noise, walking cadence, straight travel,
turning, rotation-only suppression, isolated impulses, duplicate peaks,
stop/resume, exact step-length calibration, compass accuracy diagnostics, and
hardware step mapping. Existing GPS/IMU switching, neutral no-heading Motorola
behavior, destination/route retention, native marker updates, and camera-follow
tests remain unchanged. All **197 Flutter tests passed** and Flutter analysis
reported no issues.

Physical evidence is kept distinct:

- ADB confirmed the connected primary device as OnePlus Pad OPD2203, serial
  `QCJFFYBAOJN7HUXS`. Its sensor inventory exposes linear acceleration,
  gyroscope, north-referenced rotation vector, and Android step detector.
- The stationary run logged zero accepted steps, zero speed, zero cumulative
  displacement, roughly 0.05° heading variation, and sampled acceleration no
  higher than 0.1098 m/s². This is log evidence; automated tests alone did not
  establish it.
- The user described the available indoor path as approximately 2 m, a 90°
  left turn, 10 m, a 180° turn, 10 m, and additional short turns/roughly 2 m.
  The first run proved that the advertised hardware step detector emitted zero
  steps while the tablet was carried.
- With the software cadence fallback, the same class of multi-turn run accepted
  32 steps and estimated 22.4 m with the former 0.70 m default, rejected four high-angular-rate peaks, followed
  multiple heading changes, and returned speed to zero after stopping. A later
  trace review found and fixed a close-peak pending-candidate edge case, with a
  deterministic regression test. These numbers show estimator behavior and do
  not by themselves prove marker appearance or meter-level path accuracy.
- The user's separate visual judgment was that tracking was better than the
  previous React-parity estimator but still over-moved/drifted. That observation,
  the 25.9 m post-reset estimate for an approximately 24 m path, the duplicate
  trace, and low-quality ±45° headings led to the 0.65 m calibration, duplicate
  fix, and low-heading-quality pause above. A final exact-APK post-fix walk
  remains to be recorded. Motorola physical regression is pending
  because that phone was not connected; automated coverage still verifies a
  neutral purple IMU marker, “IMU heading unavailable,” no fabricated heading
  or directional movement, and immediate GPS restoration.

Files changed for this IMU pass are
`mobile/android/app/src/main/AndroidManifest.xml`,
`mobile/android/app/src/main/kotlin/com/nadr/mobile/MainActivity.kt`,
`mobile/lib/features/imu/application/imu_navigation_coordinator.dart`,
`mobile/lib/features/imu/domain/imu_sensor_sample.dart`,
`mobile/lib/features/imu/infrastructure/android_imu_sensor_source.dart`,
`mobile/lib/features/navigation/infrastructure/step_based_imu_position_estimator.dart`,
and focused tests under `mobile/test/features/imu/` and
`mobile/test/features/navigation/infrastructure/`. No React or backend file was
modified. Destination selection, route state/request integration, GPS quality
filtering, jump quarantine, map following/recenter behavior, and marker color
architecture remain intact. Route rendering is still deferred to Prompt 11.

Remaining limitations are explicit: stride length requires per-user calibration;
compass distortion can still rotate the path; display heading is not independent
walking course; software peak detection can miss unusual gait or handling; and
inertial error accumulates without absolute corrections. Advanced orientation
fusion, pedestrian-heading inference, bias estimation, and GPS/map constraints
remain a separate future sensor-fusion stage. Calibration cannot eliminate IMU
drift.

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
GPS/IMU control, experimental IMU port, the Prompt 7.2 guards, shared REST
client/connectivity diagnostics, and usable destination selection.

**Partial:** location and IMU navigation reliability (hardware-dependent and
not production-grade), route retrieval/state without map rendering, map styling,
and on-device visual validation.

**Not yet implemented:** route display and route-comparison/risk presentation,
plus remaining website-parity features
(including auth, simulation, and live data where applicable). Later production
possibilities, not current prototype features, include automatic GPS/IMU
switching, advanced sensor fusion/drift handling, offline maps/routing, and
persistent navigation sessions. Route rendering begins in Prompt 11.
