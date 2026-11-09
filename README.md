# TP_BBDDA_20262C
Sistema de registro y gestión del mundial de fútbol. Aplicando conceptos avanzados de bases de datos. 

## Orden de ejecución

Los scripts de `src/` se ejecutan en el orden de su número. Los `Ejecutar_` que corren otros scripts (en modo SQLCMD) llevan el número anterior al de los scripts que corren:

| Script | Qué hace |
|---|---|
| `00_Ejecutar_PrepararBase.sql` | Recrea la base desde cero y ejecuta 01 a 28: base, esquemas, tablas, funciones y vistas (01 a 04), SP de ABM, negocio, carga, importación, consultas, reportes y roles (05 a 27) y datos iniciales (28). No importa nada. |
| `30_Importar_Indicadores.sql` | PBI per cápita (API del Banco Mundial). |
| `31_Importar_APIs.sql` | Campañas publicitarias, cotizaciones y feriados (APIs). |
| Scraping (en una terminal, desde la carpeta del repositorio) | `python scraping/Scraping_Jugadores.py` y `python scraping/Scraping_Arbitros.py` generan los CSV de `scraping/datos/` que lee el 32. |
| `32_Importar_Mundial2026.sql` | El torneo real (openfootball y los CSV del scraping). |
| `33_Cargar_DatosComplementarios.sql` | Lo que las fuentes no traen. |
| `34_Cargar_SedesAdicionales.sql` | Las 8 sedes propias del juego de datos. |
| `35_Importar_ImagenesSedes.sql` | La foto de cada sede. |
| `36_Mostrar_Reportes.sql` | Los reportes de la Entrega 7. |
| `40_Ejecutar_Cifrado.sql` | Entrega 8: ejecuta 41 a 45 y cifra los datos personales. |
| `46_Mostrar_ConsultasToBe.sql` | Entrega 9: consultas del alcance, sobre las vistas descifradas. |

Los tests (54 a 95) no siguen ese orden. Cada uno lleva el número de su script más 50; el de roles (27) tiene uno por usuario, del 77 al 80. Los 54 a 76 se ejecutan antes del cifrado (40), porque después los que buscan personas por nombre no las encuentran; los 77 a 80 (permisos por rol) y 91 a 95 (cifrado), después.
