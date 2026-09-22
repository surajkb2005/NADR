import 'package:nadr_mobile/core/geo/navigation_mode.dart';

abstract interface class NavigationModeController {
  NavigationMode get currentMode;

  Stream<NavigationMode> get modeChanges;

  void setMode(NavigationMode mode);
}
