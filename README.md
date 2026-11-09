# TP_BBDDA_20262C
Sistema de registro y gestión del mundial de fútbol. Aplicando conceptos avanzados de bases de datos. 

## Orden de ejecución

Los scripts de `src/` se ejecutan en el orden de su número. Los `Ejecutar_` que corren otros scripts (en modo SQLCMD) llevan el número anterior al de los scripts que corren:

| Script | Qué hace |
|---|---|
| `00_Ejecutar_PrepararBase.sql` | Recrea la base desde cero y ejecuta 01 a 29: base, esquemas, tablas, funciones y vistas, SP, datos iniciales, reportes y roles. No importa nada. |
| `30_Ejecutar_ImportarIndicadores.sql` | PBI per cápita (API del Banco Mundial). |
| `31_Ejecutar_ImportarAPIs.sql` | Campañas publicitarias, cotizaciones y feriados (APIs). |
| Scraping (en una terminal, desde la carpeta del repositorio) | `python scraping/Scraping_Jugadores.py` y `python scraping/Scraping_Arbitros.py` generan los CSV de `scraping/datos/` que lee el 32. |
| `32_Ejecutar_ImportarMundial2026.sql` | El torneo real (openfootball y los CSV del scraping). |
| `33_Ejecutar_DatosComplementarios.sql` | Lo que las fuentes no traen. |
| `34_Ejecutar_SedesAdicionales.sql` | Las 8 sedes propias del juego de datos. |
| `35_Ejecutar_ImportarImagenesSedes.sql` | La foto de cada sede. |
| `36_Ejecutar_Entrega7_Reportes.sql` | Los reportes de la Entrega 7. |
| `40_Ejecutar_Cifrado.sql` | Entrega 8: ejecuta 41 a 45 y cifra los datos personales. |
| `46_Ejecutar_Entrega9_ConsultasToBe.sql` | Entrega 9: consultas del alcance, sobre las vistas descifradas. |

Los tests (53 a 95) no siguen ese orden: los 53 a 80 se ejecutan antes del cifrado (40), porque después los que buscan personas por nombre no las encuentran; los 81 a 84 (permisos por rol) y 91 a 95 (cifrado, uno por cada script del 41 al 45), después.
