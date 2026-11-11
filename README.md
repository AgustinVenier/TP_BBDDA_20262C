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
| [`datos/fuentes/`](datos/fuentes) | Los archivos que se importan y una carpeta por fuente o API, con su README: qué trae, cómo se importa y sus límites de uso. |
| [`datos/pruebas/`](datos/pruebas) | Archivos con errores deliberados que usan los tests de importación. |
| [`scraping/`](scraping) | Los scripts de Python que obtienen los jugadores y el equipo arbitral de Wikipedia, y la documentación de la técnica usada. |
| [`bi/`](bi) | El reporte de Power BI (Entrega 9), conectado a las vistas del esquema `Reportes`. |
| [`app_abm/`](app_abm) | La aplicación de escritorio para el ABM de sedes (Entrega 9). |
| [`doc/`](doc) | El DER y el documento de seguridad y respaldo (Entrega 8). |

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
| `Importar_` | Importa desde archivos o APIs externas. | 30–32, 35 |
| `Mostrar_` | Solo muestra resultados (reportes y consultas); no modifica nada. | 36, 48 |
| `Ejecutar_` | Corre otros scripts en orden (modo SQLCMD). | 00, 40 |
| `Cifrado_` | Aplica el cifrado a las tablas (un script por tabla, 42–44) y adapta los SP y las vistas existentes (45–47). | 42–47 |
| `Test_` | Prueba un script. | 54–97 |

Dentro de la base, los SP `usp_Importar<X>` leen una fuente externa (JSON, CSV, API) y arman una tabla de staging; los `usp_Cargar<X>` (`16_SP_CargaMasiva.sql`) hacen el upsert desde esa tabla con las mismas validaciones que los SP de ABM. La norma de nomenclatura completa (tablas, restricciones, SP, funciones, vistas, parámetros y variables) está en el encabezado de [`03_CrearTablas.sql`](src/03_CrearTablas.sql).

## Orden de ejecución

| Script | Qué hace |
|---|---|
| `00_Ejecutar_PrepararBase.sql` | Recrea la base desde cero y ejecuta 01 a 28: estructura (01 a 04), stored procedures (05 a 27) y datos iniciales (28). No importa nada. |
| `30_Importar_Indicadores.sql` | PBI per cápita (API del Banco Mundial). |
| `31_Importar_APIs.sql` | Campañas publicitarias, cotizaciones y feriados (APIs). |
| Scraping (en una terminal, desde la carpeta del repositorio) | `python scraping/Scraping_Jugadores.py` y `python scraping/Scraping_Arbitros.py` generan los CSV de `scraping/datos/` que lee el 32. |
| `32_Importar_Mundial2026.sql` | El torneo real (openfootball y los CSV del scraping). |
| `33_Cargar_DatosComplementarios.sql` | Lo que las fuentes no traen. |
| `34_Cargar_SedesAdicionales.sql` | Las 8 sedes propias del juego de datos. |
| `35_Importar_ImagenesSedes.sql` | La foto de cada sede. |
| `36_Mostrar_Reportes.sql` | Los reportes de la Entrega 7. |
| `40_Ejecutar_Cifrado.sql` | Entrega 8: ejecuta 41 a 47 y cifra los datos personales. |
| `48_Mostrar_ConsultasToBe.sql` | Entrega 9: consultas del alcance, sobre las vistas descifradas. |

Los tests (54 a 97) no siguen ese orden. Cada uno lleva el número de su script más 50; el de roles (27) tiene uno por usuario, del 77 al 80. Los 54 a 76 se ejecutan antes del cifrado (40), porque después los que buscan personas por nombre no las encuentran; los 77 a 80 (permisos por rol) y 91 a 97 (cifrado), después.
