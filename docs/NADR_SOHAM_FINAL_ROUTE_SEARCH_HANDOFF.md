# NADR route and search: Soham code handoff

## Purpose and ownership

Soham's assigned mobile code implementation is complete at the code level. Darshan/Raj own the MapTiler account and credential, runtime configuration, APK build, and live emulator/device/backend checks. No live service, emulator, or device result is claimed in this handoff.

## Implemented flow

The rounded destination search uses a debounced `PlaceSearchController` and a concrete MapTiler Geocoding `PlaceSearchRepository`. Search results retain the provider label, optional subtitle and ID, and a validated coordinate. Selecting a result calls `PlaceSearchResult.toDestination()`, then updates the single `NavigationSessionState.destination`. The existing manual coordinate and map long-press flows remain fallbacks. The selected destination drives the existing destination marker.

Changing the destination clears the old selected route and alternatives. `RouteRequestController` automatically requests a route once a valid `currentRouteStart` is available, waits without sending a malformed request when it is absent, and uses a request generation to ignore late successes and failures from older destinations. Normal position updates and GPS/IMU mode changes do not start continuous route requests. Retry is available after a route failure.

The NADR route decoder validates coordinates and rejects unusable geometry. A route needs at least two distinct, finite, in-range points. Alternatives with `optimization == "fallback"` cannot become ordinary road routes. Accepted `selectedRoute.path` becomes one ordered GeoJSON `LineString` in the MapLibre route source, below the current-position and destination marker layers. Route replacement, clearing, and style reload restore the latest state. Selecting a returned alternative changes the canonical `selectedRoute` and map line.

A new selected route gets a camera fit over the full path, valid start, and destination. Padding reserves space for search, the compact draggable navigation sheet, controls, and system insets. Ordinary location updates, rebuilds, mode switches, and style reloads do not repeatedly fit. Recenter restores normal camera follow. The sheet presents canonical destination and route information, only supplied metrics, returned alternatives, retry, GPS accuracy, IMU heading/status, and one primary issue surface. The normal flow has no **Get route** button or duplicate lower-left status chips.

## Coordinate and request contracts

| Boundary | Coordinate order |
| --- | --- |
| MapTiler GeoJSON Point/center | `[longitude, latitude]` |
| NADR `GeoCoordinate` | named `latitude`, `longitude` |
| NADR `POST /route` `start` and `end` arrays | `[latitude, longitude]` |
| MapLibre GeoJSON route `LineString` | `[longitude, latitude]` |

MapTiler search uses `GET {NADR_PLACE_SEARCH_BASE_URL}/geocoding/{encodedQuery}.json` with `key`, `autocomplete=true`, and `limit=5`. The default base is `https://api.maptiler.com`. Query text is encoded as a URL path segment. The MapTiler repository converts result coordinates explicitly and skips malformed individual features. Search results show linked MapTiler and OpenStreetMap attribution. The map's own style attribution remains separate. MapTiler feature IDs are preserved when supplied, but MapTiler documents that they can change after database reindexing.

The automatic route request snapshots `currentRouteStart` and the selected destination coordinate. `RestRouteRepository` sends those as `[latitude, longitude]` to NADR `POST /route`, requests normal mode, parses the backend alternatives, rejects invalid/fallback geometry, and publishes accepted alternatives and the selected route through the canonical navigation session. Search never calls the route backend directly.

## Runtime configuration

The current `AppEnvironment` reads these Dart defines:

| Define | Use |
| --- | --- |
| `NADR_API_BASE_URL` | Reachable NADR REST origin or Nginx origin with `/api`; needed for live routing. |
| `NADR_MAP_STYLE_URL` | Reachable HTTP(S) MapLibre style document; needed for a visible map. No default is embedded. |
| `NADR_MAPTILER_API_KEY` | Normal public-facing MapTiler API key; needed for live place search. |
| `NADR_PLACE_SEARCH_BASE_URL` | Optional MapTiler-compatible HTTP(S) base; defaults to `https://api.maptiler.com`. |
| `NADR_WS_BASE_URL` | Optional WebSocket base reserved for other mobile work; not required for this route/search flow. |

Placeholder command from `mobile/`:

```sh
flutter run \
  --dart-define=NADR_API_BASE_URL=https://your-reachable-nadr.example/api \
  --dart-define=NADR_MAP_STYLE_URL=https://your-map-style.example/style.json \
  --dart-define=NADR_MAPTILER_API_KEY=<your-public-maptiler-api-key>
```

The REST origin must be reachable from the chosen emulator or phone; a phone's `localhost` is the phone itself. Do not commit a real key or use a MapTiler service token in the app. Darshan/Raj should create and own the MapTiler account, apply appropriate key restrictions for their deployment, and confirm the displayed search and map attribution satisfies their plan and current provider terms. A mobile API key is extractable from an APK, so it must be treated as public-facing.

## Ordered live verification for Darshan/Raj

1. Obtain a normal MapTiler API key, configure the reachable NADR REST URL and MapLibre style URL, then build a debug APK with placeholder-free local Dart defines.
2. Launch the APK on an emulator or physical device and verify the map loads with its style attribution.
3. Search for **MS Ramaiah**, **Cubbon Park**, **Bangalore Palace**, and **Kempegowda Airport**. Check genuine suggestions, labels, coordinates, and linked search attribution.
4. Select a suggestion. Confirm the label and destination marker, and confirm an automatic `POST /route` starts when a valid current location exists.
5. Confirm the accepted line follows roads, the camera fits the route once, the sheet shows actual returned metrics and alternatives, and selecting another returned alternative updates the line.
6. Switch GPS → IMU → GPS. Confirm destination, selected alternative, route line, and sheet information persist without another route request or fit caused solely by switching.
7. Explore the map, use recenter, and confirm follow resumes.
8. Inspect application and backend logs for request failures or credential leakage. Do not publish logs containing keys or user location without redaction.

## Expected failure conditions

- Missing `NADR_MAPTILER_API_KEY`: search reports a controlled unavailable state; app startup, map, and other navigation functions remain available.
- Missing valid current location: selected destination stays visible and routing waits for the first valid start coordinate; no malformed request is sent.
- NADR backend route failure: the route card shows a recoverable failure and retry; no fabricated route is shown.
- Fallback-only or invalid route geometry: no normal road route is selected or rendered.
- Missing or invalid map style: the map layer reports a controlled style error; this does not create a fake location or route.

## Code-level verification and scope

At handoff, `flutter analyze` passed, `flutter test` passed with **301 tests**, `git diff --check` passed, and `git diff -- backend/` was empty. Focused tests cover MapTiler request/response/errors, search races, exact destination mapping, automatic route waiting and races, route validation and fallback rejection, MapLibre geometry/layers/reload, one-time camera fit and recenter, compact UI states, responsive search, and GPS/IMU route persistence. These are automated tests with fake dependencies; they are not live service or native visual verification.

This work intentionally did not change the backend, estimator algorithms, Walking/Vehicle detection or selector behavior, AUTO/default/waiting estimator behavior, or IMU/ESKF/dead-reckoning and sensor-fusion math.

## Explicitly not verified

- A real MapTiler request or real MapTiler credential.
- Physical-device or emulator behavior.
- Live NADR backend connectivity and road route quality.
- Native MapLibre appearance, marker and camera behavior on a device.
- A final debug APK build or execution.

## Git state and final handoff status

- Branch: `feature/integration`.
- HEAD at audit: `41a3f59157756f6d300e46ec1f4635efa80e5710` (`Implement MapTiler Geocoding`).
- Implementation files were committed at that HEAD and the working tree was clean before this handoff document was created. This handoff document is an uncommitted addition; no commit or push was performed in the final audit.

**SOHAM CODE-LEVEL IMPLEMENTATION: COMPLETE**

**LIVE INTEGRATION VERIFICATION: PENDING DARSHAN/RAJ**
