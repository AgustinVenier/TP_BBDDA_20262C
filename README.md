# Sistema de registro y gestión del Mundial de Fútbol

**Universidad Nacional de La Matanza**
3641 – Bases de Datos Aplicada · 2026, segundo cuatrimestre
Comisión 01 · Grupo 2

| Integrante | GitHub |
|---|---|
| Caruso Dellisanti, Carolina Belen | [CarolinaCaruso](https://github.com/CarolinaCaruso) |
| D'Ambrosio, Rodrigo | [rodrigoDambrosio](https://github.com/rodrigoDambrosio) |
| Tavella, Tomás | [TomasTavella](https://github.com/TomasTavella) |
| Venier, Agustin | [AgustinVenier](https://github.com/AgustinVenier) |

Base de datos en SQL Server para gestionar los partidos del Mundial 2026: sedes, selecciones y convocatorias, formaciones, cambios, goles y tarjetas, árbitros, publicidad, importación de datos externos, reportes, seguridad y una plataforma de BI.

## Contenido del repositorio

| Carpeta | Qué hay |
|---|---|
| [`src/`](src) | Los scripts T-SQL, en una solución de SSMS (`MundialFutbol.slnx`). |
| [`datos/fuentes/`](datos/fuentes) | Los archivos que se importan: los JSON de openfootball y las fotos de las sedes. Las fuentes y APIs, con sus límites de uso, están en `doc/Fuentes_de_Datos_y_APIs.docx`. |
| [`datos/pruebas/`](datos/pruebas) | Archivos con errores deliberados que usan los tests de importación. |
| [`scraping/`](scraping) | Los scripts de Python que obtienen los jugadores y el equipo arbitral de Wikipedia, y los CSV que generan. La técnica y las páginas de origen están en `doc/Tecnica_de_Scraping.docx`. |
| [`bi/`](bi) | El reporte de Power BI, conectado a las vistas del esquema `Reportes`. |
| [`app_abm/`](app_abm) | La aplicación de escritorio para el ABM de sedes y los reportes XML. |
| [`doc/`](doc) | El DER y los documentos: carátula, instalación y configuración, fuentes de datos y APIs, técnica de scraping, roles de seguridad y permisos, y política de respaldo. |

## Antes de ejecutar

Los dos scripts `Ejecutar_` (00 y 40) corren otros scripts con `:r`, así que:

1. En SSMS, activar el modo SQLCMD: menú **Query > SQLCMD Mode**.
2. En cada uno, cambiar `:setvar src` por la ruta de la carpeta `src\` del repositorio en la máquina donde se ejecuta, terminada en `\`. El valor del repositorio es la ruta de un integrante: en otra máquina falla al primer `:r`.
3. En `40_Ejecutar_Cifrado.sql`, cambiar `:setvar ClaveMaestra` por una contraseña propia.

## Nombres de los scripts

Cada script empieza con dos dígitos que indican su orden de ejecución. Después, el prefijo dice qué hace:

| Prefijo | Qué hace | Scripts |
|---|---|---|
| `Crear` | Crea la base, los esquemas, las tablas, las funciones y las vistas. | 01–04 |
| `SP_` | Crea stored procedures, sin tocar datos: ABM, negocio, carga masiva, utilidades, importación, consultas, reportes, roles y cifrado. | 05–27, 41 |
| `Cargar_` | Carga datos propios del grupo, que no vienen de ninguna fuente externa. | 28, 33, 34 |
| `Importar_` | Importa desde archivos o APIs externas. | 31, 32, 35 |
| `Mostrar_` | Solo muestra resultados (reportes y consultas); no modifica nada. | 36, 48 |
| `Ejecutar_` | Corre otros scripts en orden (modo SQLCMD). | 00, 40 |
| `Cifrado_` | Aplica el cifrado a las tablas (un script por tabla, 42–44) y adapta los SP y las vistas existentes (45–47). | 42–47 |
| `Test_` | Prueba un script. | 54–97 |

Dentro de la base, los SP `usp_Importar<X>` leen una fuente externa (JSON, CSV, API) y arman una tabla de staging; los `usp_Cargar<X>` hacen el upsert desde esa tabla con las mismas validaciones que los SP de ABM. Cada `usp_Cargar<X>` está en el mismo archivo que el `usp_Importar<X>` que lo usa, justo antes (ver el mapa de abajo); la forma de trabajo común está en el encabezado de [`17_SP_Utilidades_Importacion.sql`](src/04_Importacion/17_SP_Utilidades_Importacion.sql). La norma de nomenclatura completa (tablas, restricciones, SP, funciones, vistas, parámetros y variables) está en el encabezado de [`03_CrearTablas.sql`](src/01_Estructura/03_CrearTablas.sql).

## Mapa de la importación

Cada fila es un dataset: de dónde sale, en qué archivo de `src/04_Importacion/` están sus SP (el de carga masiva y el que lee la fuente), dónde quedan los registros rechazados, qué script lo ejecuta y cuál lo prueba.

| Dataset | Fuente | Archivo y SP | Rechazados en | Lo ejecuta | Test |
|---|---|---|---|---|---|
| Sedes | openfootball, `worldcup.stadiums.json` | 18: `usp_CargarSedes`, `usp_ImportarSedesJSON` | `Torneo.ERRORES_SEDE` | 32 | 68 |
| Selecciones | openfootball, `worldcup.teams.json` | 18: `usp_CargarSelecciones`, `usp_ImportarSeleccionesJSON` | `Torneo.ERRORES_SELECCION` | 32 | 68 |
| Partidos, formaciones, cambios, goles y tarjetas | openfootball, `worldcup-full.json` | 18: `usp_CargarPartidos`, `usp_CargarDesarrolloPartidos`, `usp_ImportarPartidosJSON` | `Torneo.ERRORES_PARTIDO`, `DesarrolloPartido.ERRORES_EVENTO` | 32 | 68 |
| Árbitros y designaciones | scraping, `designaciones_arbitrales.csv` | 18: `usp_CargarArbitros`, `usp_CargarDesignaciones`, `usp_ImportarDesignacionesCSV` | `Arbitraje.ERRORES_DESIGNACION` | 32 | 68 |
| Jugadores | scraping, `jugadores.csv` | 19: `usp_CargarJugadores`, `usp_ImportarJugadoresCSV` | `Torneo.ERRORES_JUGADOR` | 32 | 69 |
| Directores técnicos | scraping, `cuerpo_tecnico.csv` | 19: `usp_CargarCuerpoTecnico`, `usp_ImportarCuerpoTecnicoCSV` | `Torneo.ERRORES_CUERPO_TECNICO` | 32 | 69 |
| Campañas publicitarias | API de Firestore (Dossier Mundial) | 20: `usp_CargarCampanias`, `usp_ProcesarCampaniasJSON`, `usp_ImportarCampaniasAPI` | `Publicidad.ERRORES_CAMPANIA` | 31 | 70 |
| PBI per cápita | API del Banco Mundial (XML) | 21: `usp_CargarIndicadoresEconomicos`, `usp_ProcesarIndicadoresXML`, `usp_ImportarIndicadoresAPI` | `DatosGenerales.ERRORES_INDICADOR_ECONOMICO` | 31 | 71 |
| Cotizaciones | API Frankfurter | 22: `usp_CargarCotizaciones`, `usp_ProcesarCotizacionesJSON`, `usp_ImportarCotizacionesAPI` | `DatosGenerales.ERRORES_COTIZACION` | 31 | 72 |
| Feriados | API Nager.Date | 23: `usp_CargarFeriados`, `usp_ProcesarFeriadosJSON`, `usp_ImportarFeriadosAPI` | `DatosGenerales.ERRORES_FERIADO` | 31 | 73 |
| Fotos de las sedes | `datos/fuentes/sedes/` | 24: `usp_ImportarImagenesSedes` | no registra importación | 35 | 74 |

Cada importación queda registrada en `DatosGenerales.IMPORTACION` con sus totales (leídos, insertados, actualizados, sin cambios, omitidos y rechazados). El test 66 prueba las reglas de todos los `usp_Cargar<X>` llamándolos directamente.

Los datos que carga el grupo a mano no pasan por la importación: los datos iniciales (28) se dan de alta con los SP de ABM, y los datos complementarios (33) usan los mismos `usp_Cargar<X>` más `Torneo.usp_CargarReemplazos` (11) y `Arbitraje.usp_CargarInformesArbitrales` (14).

## Orden de ejecución

| Script | Qué hace |
|---|---|
| `00_Ejecutar_PrepararBase.sql` | Recrea la base desde cero y ejecuta 01 a 28: estructura (01 a 04), stored procedures (05 a 27) y datos iniciales (28). No importa nada. |
| `31_Importar_APIs.sql` | PBI per cápita, campañas publicitarias, cotizaciones y feriados (APIs). |
| Scraping (en una terminal, desde la carpeta del repositorio) | `python scraping/Scraping_Jugadores.py` y `python scraping/Scraping_Arbitros.py` generan los CSV de `scraping/datos/` que lee el 32. |
| `32_Importar_Mundial2026.sql` | El torneo real (openfootball y los CSV del scraping). |
| `33_Cargar_DatosComplementarios.sql` | Lo que las fuentes no traen. |
| `34_Cargar_SedesAdicionales.sql` | Las 8 sedes propias del juego de datos. |
| `35_Importar_ImagenesSedes.sql` | La foto de cada sede. |
| `36_Mostrar_Reportes.sql` | Los reportes (R1 a R7). |
| `40_Ejecutar_Cifrado.sql` | Ejecuta 41 a 47 y cifra los datos personales. |
| `48_Mostrar_ConsultasToBe.sql` | Las consultas del alcance, sobre las vistas descifradas. |

Los tests (54 a 97) no siguen ese orden. Cada uno lleva el número de su script más 50 (el 66 prueba los SP de carga masiva, que están en 18 a 23); el de roles (27) tiene uno por usuario, del 77 al 80. Los 54 a 76 se ejecutan antes del cifrado (40), porque después los que buscan personas por nombre no las encuentran; los 77 a 80 (permisos por rol) y 91 a 97 (cifrado), después.
