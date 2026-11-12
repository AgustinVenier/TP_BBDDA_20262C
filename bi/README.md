# Reporte de Power BI

`MundialFutbol.pbip` es el reporte de Power BI (sección J del enunciado), guardado como proyecto de Power BI (PBIP): el modelo en `MundialFutbol.SemanticModel` (formato TMDL) y el reporte en `MundialFutbol.Report` (formato PBIR). Son archivos de texto, así que los cambios se ven en git como cualquier script.

Los datos salen directo de la base SQL: el modelo importa las vistas del esquema `Reportes` (`src/05_Consultas_Reportes/26_SP_Reportes.sql`), y **Actualizar** las vuelve a leer.

## Cómo abrirlo

1. Tener la base con las vistas al día. Correr `src/05_Consultas_Reportes/26_SP_Reportes.sql` después de cada cambio en las vistas: el reporte usa columnas que agregó la última versión (`jugador`, `persona`, `partido` y la vista `vw_Sedes`). Si la base ya tiene el cifrado (`40_Ejecutar_Cifrado.sql`), correr después `src/08_Cifrado/47_Cifrado_Reportes.sql`: el 26 vuelve a crear las vistas leyendo los nombres de las tablas, donde están cifrados, y el reporte los mostraría como bytes.
2. Abrir `MundialFutbol.pbip` con Power BI Desktop (doble clic).
3. **Inicio → Actualizar**. La primera vez pide las credenciales de `localhost;MundialFutbol`: elegir **Windows → Usar mis credenciales actuales**. Si avisa que el certificado del servidor no es de confianza, aceptar la conexión sin cifrado (es una instancia local).

## Otra base u otro servidor

El servidor y la base son parámetros del modelo (`Servidor` = `localhost`, `BaseDeDatos` = `MundialFutbol`). Para cambiarlos: **Transformar datos → Editar parámetros**, y después **Actualizar**.

## Mapa de sedes

La página **Sedes** usa el objeto visual de mapa, que Power BI trae deshabilitado. Para verlo: **Archivo → Opciones y configuración → Opciones → Global → Seguridad →** marcar el uso de los objetos visuales de mapa y de mapa coroplético, y volver a abrir el reporte.

## Páginas

| Página | Qué muestra | Vistas |
|---|---|---|
| Plantillas | Selecciones con sus convocados anidados (dorsal, nombre, posición y club), por puesto y dorsal como `Reportes.usp_SeleccionesYPlantillasXML`. El segmentador **Estado** arranca en los convocados; sin elegir, suma los dados de baja con su motivo | `vw_Plantillas` |
| Goleadores | Goleadores del torneo, goles por selección y por fase | `vw_Goles`, `vw_Resultados` |
| Tarjetas | Amarillas y rojas por selección y por jugador | `vw_Tarjetas` |
| Suspensiones | Jugadores suspendidos por acumulación de amarillas, doble amarilla o roja directa, antes del partido que se elige en el segmentador **Momento** (sin elegir, las de todo el torneo): motivo, partido de la sanción, fechas cumplidas y pendientes, y el partido que no juega | `vw_SuspensionesActivas` |
| Árbitros | Partidos dirigidos por cada árbitro (como principal), sus designaciones en todos los roles, las amarillas y rojas que señaló y el detalle de cada tarjeta (partido, minuto, a quién y por qué), con segmentadores de árbitro y de rol. Las tarjetas se atribuyen al árbitro principal del partido, porque la base no guarda quién mostró cada una. El segmentador de árbitro usa la vista `vw_Arbitros`, relacionada con las designaciones y con las tarjetas | `vw_Arbitros`, `vw_DesignacionesArbitrales`, `vw_Tarjetas` |
| Publicidad | Ingresos en dólares, espacios ocupados y anunciantes; ocupación por sede (cuántos de sus espacios tuvo cada anunciante, apilado); ingresos por sede, por anunciante y por espacio. No se muestra un porcentaje de ocupación: el sistema asigna siempre las cuatro piezas de cada partido (sección H), así que daría 100 % | `vw_OcupacionPublicitaria` |
| Publicidad por partido | Matriz sede → partido con el anunciante exhibido en cada uno de los cuatro espacios ("(libre)" si no tiene), los espacios ocupados y los ingresos en dólares, con subtotales por sede y total; segmentadores de fase y de sede. Las medidas `Espacio 1` a `Espacio 4` (tabla `Reportes.vw_OcupacionPublicitaria`) arman las columnas, igual que `espacio_1` a `espacio_4` de `Reportes.usp_OcupacionPublicitaria` | `vw_OcupacionPublicitaria` |
| Monedas | Ingresos convertidos a la moneda elegida, con la cotización del día del partido (API Frankfurter) | `vw_IngresosPublicitariosPorMoneda` |
| Prime time | Matriz partido × mercado (prime time y feriados, API Nager.Date) e ingresos por partido frente a mercados en prime time. Los ingresos llevan el recargo sobre la tarifa por ronda eliminatoria y por mercados de la pieza en prime time (`Publicidad.fn_RecargosPublicidad`), y las tarifas de cada sede son proporcionales a su capacidad (script 33), así que las columnas acompañan la línea | `vw_PrimeTimePorMercado` |
| Resultados de grupos | Posiciones separadas por grupo y los partidos de la fase de grupos, con un segmentador de grupo que filtra las dos | `vw_TablaPosiciones`, `vw_Resultados` |
| Resultados de eliminación | Podio (campeón, segundo y tercer puesto), el cuadro de eliminación directa y los partidos con sus goles | `vw_Resultados`, `vw_CuadroEliminacion` |
| Sedes | Mapa de las sedes (tamaño: partidos) e ingresos por sede | `vw_Sedes` |

El segmentador **Fase** filtra todas las tablas relacionadas con el partido. En **Resultados de grupos**, el segmentador **Grupo** filtra las posiciones y, con las medidas `Resultado de grupo`, los partidos de ese grupo.

## Cuadro de eliminación

Power BI no trae un objeto visual de cuadro de eliminación, así que se dibuja: la medida `Cuadro de eliminación` (tabla `Reportes.vw_CuadroEliminacion`) arma una imagen SVG con los cruces, los resultados (con los penales entre paréntesis), las líneas que unen cada ronda y el tercer puesto aparte, y un objeto visual de imagen la muestra.

El cuadro va en espejo, como los oficiales: la mitad de cada ronda a la izquierda, la otra mitad a la derecha y la final en el centro, con el campeón arriba y el tercer puesto abajo. Así la imagen es más ancha que alta y aprovecha la franja del visual: un cuadro de una sola dirección, con las cinco rondas, es casi tan alto como ancho y se achicaba demasiado. Los colores siguen el tema del reporte: los nombres de las rondas en azul oscuro, el ganador de cada cruce en negrita, con la fila celeste y el marcador en azul, y las líneas que lo llevan al cruce siguiente en azul; la final en dorado y el tercer puesto en bronce. Los nombres de más de 17 letras se angostan para entrar al lado del marcador, y los de más de 22 se cortan con "…".

La vista `Reportes.vw_CuadroEliminacion` ubica cada partido en el cuadro. Como la base no guarda qué partido alimenta a cuál, lo reconstruye con los resultados, desde la final hacia atrás. Mientras falte jugar algún cruce, esa ronda se ordena por número de partido.

## Al guardar

Power BI Desktop guarda los cambios en estos mismos archivos. `.gitignore` deja afuera la caché de datos (`.pbi/cache.abf`) y la configuración local (`.pbi/localSettings.json`).

## Imágenes

El trofeo de la esquina superior derecha de cada página es una ilustración que aportó el grupo (`MundialFutbol.Report/StaticResources/RegisteredResources/trofeo.png`). Está registrada una sola vez en el reporte y cada página la muestra con un objeto visual de imagen.
