# Safe360 - Frontend (Flutter)

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
