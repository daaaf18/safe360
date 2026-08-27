# Safe360 - Frontend (Flutter)

<<<<<<< HEAD
Pantallas rediseñadas para coincidir con las mockups aprobadas
(Login, Home/Mapa, Reportar, Ruta segura, Chaty), adaptadas a layout
móvil vertical. SOS, Contactos y Perfil mantienen el diseño base anterior.

## Cómo correrlo
```
flutter pub get
flutter run -d edge      # o: flutter run -d windows
```

## Pendiente
- Reemplazar `lib/widgets/map_view.dart` por Mapbox real
  (`mapbox_maps_flutter`), usando los datos de heatmap del backend
- Conectar formularios y Chaty a los endpoints/servicios reales
- Agregar manejo de estado (Provider/Riverpod/Bloc)
=======
Frontend con las 9 pantallas principales, navegación funcional, conexión
real al backend (auth, reportes, rutas) y mapa real de Mapbox.

## Pantallas incluidas
1. Login (`lib/screens/login_screen.dart`)
2. Registro (`lib/screens/register_screen.dart`)
3. Home / Mapa (`lib/screens/home_screen.dart`)
4. Reportar incidente (`lib/screens/report_screen.dart`)
5. Ruta segura (`lib/screens/safe_route_screen.dart`)
6. SOS / Emergencia (`lib/screens/sos_screen.dart`)
7. Contactos de confianza (`lib/screens/contacts_screen.dart`)
8. Chaty (`lib/screens/chaty_screen.dart`)
9. Perfil (`lib/screens/profile_screen.dart`)

## Cómo correrlo
1. Necesitas el Flutter SDK instalado (https://docs.flutter.dev/get-started/install)
2. Conseguí un token público de Mapbox (gratis) en
   https://console.mapbox.com/account/access-tokens/
3. Dentro de esta carpeta (`frontend/`), copiá `env.example.json` a
   `env.json` y completá tu token:
   ```
   cp env.example.json env.json
   ```
4. Instalá dependencias y corré la app:
   ```
   flutter pub get
   flutter run --dart-define-from-file=env.json
   ```
   `env.json` está en `.gitignore`, nunca se sube al repo — cada dev usa
   el suyo.

## Próximos pasos pendientes
- Conectar el mapa a los datos reales de heatmap/luminarias del backend
  (`GET /luminarias`), no solo a `reportes`.
- Reemplazar la línea recta de "Ruta segura" por geometría real de ruta
  cuando el backend la exponga (ver `TODO(Jorge)` en
  `lib/widgets/safe360_map.dart`).
- Conectar Chaty (ya tiene backend real en `POST /chaty`) a la UI y
  agregar speech-to-text al botón del micro.
- Agregar manejo de estado (Provider, Riverpod o Bloc) en vez de datos mock
  donde todavía queden.
>>>>>>> origin/jorge
