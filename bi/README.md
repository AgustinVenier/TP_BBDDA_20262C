# Reporte de Power BI

`MundialFutbol.pbip` es el reporte de la Entrega 9 (sección J del enunciado), guardado como proyecto de Power BI (PBIP): el modelo en `MundialFutbol.SemanticModel` (formato TMDL) y el reporte en `MundialFutbol.Report` (formato PBIR). Son archivos de texto, así que los cambios se ven en git como cualquier script.

Los datos salen directo de la base SQL: el modelo importa las vistas del esquema `Reportes` (`src/30_SP_Reportes.sql`), y **Actualizar** las vuelve a leer.

## Cómo abrirlo

1. Tener la base con las vistas al día. Correr `src/30_SP_Reportes.sql` después de cada cambio en las vistas: el reporte usa columnas que agregó la última versión (`jugador`, `persona`, `partido` y la vista `vw_Sedes`).
2. Abrir `MundialFutbol.pbip` con Power BI Desktop (doble clic).
3. **Inicio → Actualizar**. La primera vez pide las credenciales de `localhost;MundialFutbol`: elegir **Windows → Usar mis credenciales actuales**. Si avisa que el certificado del servidor no es de confianza, aceptar la conexión sin cifrado (es una instancia local).

## Otra base u otro servidor

El servidor y la base son parámetros del modelo (`Servidor` = `localhost`, `BaseDeDatos` = `MundialFutbol`). Para cambiarlos: **Transformar datos → Editar parámetros**, y después **Actualizar**.

## Mapa de sedes

La página **Sedes** usa el objeto visual de mapa, que Power BI trae deshabilitado. Para verlo: **Archivo → Opciones y configuración → Opciones → Global → Seguridad →** marcar el uso de los objetos visuales de mapa y de mapa coroplético, y volver a abrir el reporte.

## Páginas

| Página | Qué muestra | Vistas |
|---|---|---|
| Goleadores | Goleadores del torneo, goles por selección y por fase | `vw_Goles`, `vw_Resultados` |
| Tarjetas | Amarillas y rojas por selección y por jugador | `vw_Tarjetas` |
| Publicidad | Ingresos y ocupación de los 4 espacios por sede, anunciante y partido | `vw_OcupacionPublicitaria` |
| Monedas | Ingresos convertidos a la moneda elegida, con la cotización del día del partido (API Frankfurter) | `vw_IngresosPublicitariosPorMoneda` |
| Prime time | Matriz partido × mercado (prime time y feriados, API Nager.Date) e ingresos por partido frente a mercados en prime time | `vw_PrimeTimePorMercado` |
| Resultados de grupos | Posiciones separadas por grupo y los partidos de la fase de grupos, con un segmentador de grupo que filtra las dos | `vw_TablaPosiciones`, `vw_Resultados` |
| Resultados de eliminación | Podio (campeón, segundo y tercer puesto), el cuadro de eliminación directa y los partidos con sus goles | `vw_Resultados`, `vw_CuadroEliminacion` |
| Sedes | Mapa de las sedes (tamaño: partidos) e ingresos por sede | `vw_Sedes` |

El segmentador **Fase** filtra todas las tablas relacionadas con el partido. En **Resultados de grupos**, el segmentador **Grupo** filtra las posiciones y, con las medidas `Resultado de grupo`, los partidos de ese grupo.

## Cuadro de eliminación

Power BI no trae un objeto visual de cuadro de eliminación, así que se dibuja: la medida `Cuadro de eliminación` (tabla `Cuadro`) arma una imagen SVG con los cruces, los resultados (con los penales entre paréntesis), las líneas que unen cada ronda y el tercer puesto aparte, y un objeto visual de imagen la muestra. El ganador de cada partido va en negrita y el campeón, con fondo dorado.

La vista `Reportes.vw_CuadroEliminacion` ubica cada partido en el cuadro. Como la base no guarda qué partido alimenta a cuál, lo reconstruye con los resultados, desde la final hacia atrás. Mientras falte jugar algún cruce, esa ronda se ordena por número de partido.

## Al guardar

Power BI Desktop guarda los cambios en estos mismos archivos. `.gitignore` deja afuera la caché de datos (`.pbi/cache.abf`) y la configuración local (`.pbi/localSettings.json`).

## Imágenes

El trofeo de la esquina superior derecha de cada página es una ilustración que aportó el grupo (`MundialFutbol.Report/StaticResources/RegisteredResources/trofeo.png`). Está registrada una sola vez en el reporte y cada página la muestra con un objeto visual de imagen.
