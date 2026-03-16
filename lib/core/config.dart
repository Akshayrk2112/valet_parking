// Centralized API base URL. Override with:
// --dart-define=API_BASE=http://<your-host-ip>:5000
// Default targets the current LAN host for physical devices.
const String apiLanDefault = 'http://10.184.12.85:5000';
// Android emulator host bridge.
const String apiEmulatorFallback = 'http://10.0.2.2:5000';
const String apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: apiLanDefault,
);
