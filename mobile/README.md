# NADR Mobile

NADR Mobile is the Android Flutter client for the existing NADR navigation
system. It lives alongside the React web client and will consume the same
FastAPI services in later implementation prompts.

The application currently includes its Material 3 map-first shell, a real
interactive MapLibre map, foreground Android location, a geographic location
marker, camera follow/recenter, manual GPS/experimental IMU modes, and a
shared typed REST client with debug-only backend diagnostics. Destination
selection and explicit requests to the existing backend `/route` endpoint are
implemented; route map rendering, OTP login UI, risk UI, simulation, and
WebSocket integration remain unimplemented. See the [mobile development history](../docs/NADR_MOBILE_DEVELOPMENT_HISTORY.md)
for completed prompts, device findings, guardrails, and the current roadmap.

## Backend protection

The existing backend is immutable during mobile development.

**Do not modify `/backend` while implementing mobile prompts.**

Before completing any mobile prompt, run:

```sh
./tool/verify_backend_unchanged.sh
```

The script reports any staged, unstaged, or untracked backend change and exits
with a non-zero status. It never modifies or reverts files.

## Structure

```text
lib/
  app/          Application root, bootstrap, routing, and theme
  core/         Cross-cutting errors, geo, networking, and utilities
  data/         Future API and WebSocket data sources
  features/     Isolated NADR feature modules
  shared/       Shared models and widgets
test/           Unit and widget tests
tool/           Repository-safety tooling
```

## Requirements

- Flutter 3.47.5 or a compatible stable release
- Dart 3.13.4 or a compatible version
- Android SDK/toolchain accepted by `flutter doctor`

## Run

From this directory:

```sh
flutter pub get
flutter run
```

There is no hardcoded backend host. Provide a URL reachable from the Android
device using a Dart define. A phone's `localhost` is the phone itself, not the
development computer. For direct FastAPI development, use its HTTP(S) origin;
for the repository's Nginx proxy, use the site origin plus `/api` because
Nginx strips that prefix before forwarding. The client appends endpoint paths
once, so do not put `/health`, `/route`, or a repeated `/api/api` in the base.
An Android emulator can reach a backend on the development machine through
the emulator-reserved alias `http://10.0.2.2:8000`; a physical phone cannot.
For example, replacing the example hosts with your reachable host:

```sh
flutter run \
  --dart-define=NADR_API_BASE_URL=http://devbox.example.test:8000 \
  --dart-define=NADR_MAP_STYLE_URL=https://tiles.openfreemap.org/styles/liberty

# Or through the repository's Nginx /api proxy:
flutter run \
  --dart-define=NADR_API_BASE_URL=https://nadr.example.test/api \
  --dart-define=NADR_MAP_STYLE_URL=https://tiles.openfreemap.org/styles/liberty
```

Debug builds permit cleartext HTTP for direct development. Production should
use HTTPS; the existing backend sets `session_id` with `Secure`, `HttpOnly`,
and `SameSite=Lax`, so an HTTP development origin cannot round-trip the secure
login cookie. The client persists cookies in app-private support storage and
never logs cookie or OTP values. OTP UI is not present yet. `NADR_WS_BASE_URL`
can be set separately for future WebSocket work but is unused in Prompt 8.
If the REST URL is omitted, the app starts normally and the debug panel reports
“not configured.” The debug-only server icon on the map opens diagnostics for
`GET /` and `GET /health`, with manual retry; an offline backend never blocks
GPS, IMU, or map use.

After a current position and destination are available, the navigation sheet's
“Get route” action snapshots both coordinates and sends one `POST /route`
request through the shared client. GPS/IMU updates do not automatically request
routes. Prompt 10 stores the decoded normal, safe, drifted, and IMU alternatives
for later rendering and shows only compact request status; polylines intentionally
remain a later stage.

`NADR_MAP_STYLE_URL` intentionally has no default because the repository does
not choose a map provider or hold provider credentials. It must point to an
absolute HTTP(S) MapLibre style document. When it is missing, malformed, or
cannot load, the map layer shows a controlled error while the rest of the UI
remains usable. Do not place secrets or private API keys in source control.

The map starts at the web app's Bengaluru demo coordinate, which is only an
initial camera target and is never published as a real GPS fix. Accepted real
GPS or IMU estimates drive the native geographic MapLibre marker through
`displayedPosition`; camera follow, user exploration, and recenter are active.
Map attribution comes from the configured style and remains visible.

## Foreground location

Android declares coarse and fine foreground location permissions. No
background or always-on permission is requested. When the map screen starts,
the app checks location services, requests permission once when appropriate,
obtains an initial position, and then listens for moderate navigation updates.
Tracking is stopped while the app is paused and restarted when it resumes.

The compact map status reports acquisition, active tracking, disabled services,
denied or permanently blocked permission, and location errors. The GPS source
rejects invalid fixes and quarantines substantial unknown-accuracy jumps until
subsequent fixes confirm them. IMU navigation uses the existing website
heuristic only when Android supplies a trustworthy heading source; otherwise
it keeps a neutral marker and suspends directional propagation.

## Quality checks

```sh
flutter analyze
flutter test
flutter build apk --debug
./tool/verify_backend_unchanged.sh
```

Later prompts can add unit, widget, and integration suites without changing the
foundation layout.
