# Safe360 - Frontend (Flutter)

Plantilla inicial del frontend con las 8 pantallas principales, navegación
funcional y datos de ejemplo (mock). Aún no incluye Mapbox real ni conexión
al backend — eso se integra después.

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
2. Dentro de esta carpeta:
   ```
   flutter pub get
   flutter run
   ```

## Cómo integrarlo al repo `safe360`
1. Copia todo el contenido de esta carpeta dentro de `frontend/` en el repo
2. Desde la raíz del repo:
   ```
   git checkout -b frontend-flutter
   git add frontend/
   git commit -m "Estructura inicial del frontend en Flutter"
   git push origin frontend-flutter
   ```
3. Abre un Pull Request de `frontend-flutter` → `main` para revisión del equipo

## Próximos pasos pendientes
- Reemplazar `lib/widgets/map_placeholder.dart` por la integración real de
  Mapbox (paquete `mapbox_maps_flutter`) usando los datos de heatmap del
  backend (PostGIS)
- Conectar los formularios (login, registro, reportar) a los endpoints reales
- Conectar Chaty a un servicio de voz/NLP real
- Agregar manejo de estado (Provider, Riverpod o Bloc) en vez de datos mock
