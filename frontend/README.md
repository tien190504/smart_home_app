# Smartify Frontend

Flutter frontend for the Smartify smart-home system. The app supports:

- Email/password sign in
- Account registration through `/api/auth/register`
- Session persistence with refresh tokens
- Realtime dashboard updates through MQTT
- Device control and provisioning flows

## Docker Web Stack

The Docker stack is orchestrated from `../backend/docker-compose.yml`.

It now includes:

- `postgres`
- `mosquitto`
- `backend`
- `frontend`

Start the full stack:

```powershell
cd ..\backend
docker compose up --build
```

After startup:

- Web app: `http://localhost:3000`
- Backend API: `http://localhost:8080`
- MQTT TCP: `localhost:1883`
- MQTT WebSocket: proxied through `http://localhost:3000/mqtt`

`mosquitto` is only the Docker-internal hostname used between containers.
For real phones and ESP devices on the same Wi-Fi, use your computer LAN IP instead, for example `192.168.1.10:1883`.

## Mobile Builds

For Android emulator with the Docker backend running on the host:

```powershell
flutter run -d emulator-5554 `
  --dart-define=REST_BASE_URL=http://10.0.2.2:8080 `
  --dart-define=MQTT_TCP_HOST=10.0.2.2 `
  --dart-define=MQTT_TCP_PORT=1883
```

For a real Android phone on the same Wi-Fi network, use your computer's LAN IP instead of `10.0.2.2`:

```powershell
flutter run -d <device-id> `
  --dart-define=REST_BASE_URL=http://192.168.1.10:8080 `
  --dart-define=MQTT_TCP_HOST=192.168.1.10 `
  --dart-define=MQTT_TCP_PORT=1883
```

`10.0.2.2` only works inside the Android emulator.

For real devices, the app now includes a first-run LAN connection screen.
You can save the REST base URL and MQTT host/port once on the phone, then keep using the app on the same Wi-Fi without rebuilding.
The `dart-define` values above are still useful as optional defaults during development, but they are no longer required for day-to-day LAN testing on a real phone.

For iOS simulator:

```powershell
flutter run -d ios `
  --dart-define=REST_BASE_URL=http://localhost:8080 `
  --dart-define=MQTT_TCP_HOST=localhost `
  --dart-define=MQTT_TCP_PORT=1883
```
