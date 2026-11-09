# Mundial 2026 de openfootball

Los tres archivos son del proyecto [openfootball/worldcup.json](https://github.com/openfootball/worldcup.json), guardados tal como se descargaron, sin modificaciones. Los datos son de dominio público ([CC0](https://creativecommons.org/publicdomain/zero/1.0/)).

| Archivo | Qué trae | Lo importa |
|---|---|---|
| `worldcup.stadiums.json` | Las 16 sedes: estadio, ciudad, país (ISO alfa-2), desfase UTC, capacidad y coordenadas | `Torneo.usp_ImportarSedesJSON` |
| `worldcup.teams.json` | Las 48 selecciones: nombre en inglés, código FIFA, grupo y confederación | `Torneo.usp_ImportarSeleccionesJSON` |
| `worldcup-full.json` | Los 104 partidos: fecha y hora local, sede, resultado (90 minutos, alargue y penales), asistencia, formaciones, cambios, goles, penales de la definición, tarjetas y árbitro principal | `Torneo.usp_ImportarPartidosJSON` |

Los SP están en `src/18_SP_Importar_Mundial2026.sql`. `src/32_Importar_Mundial2026.sql` carga el torneo completo, junto con los jugadores del CSV del scraping (`scraping/datos/jugadores.csv`).

## Cómo se obtuvieron

Con un pedido GET a cada URL, sin clave:

```bat
curl -o worldcup-full.json     https://raw.githubusercontent.com/openfootball/worldcup.json/master/2026/worldcup-full.json
curl -o worldcup.teams.json    https://raw.githubusercontent.com/openfootball/worldcup.json/master/2026/worldcup.teams.json
curl -o worldcup.stadiums.json https://raw.githubusercontent.com/openfootball/worldcup.json/master/2026/worldcup.stadiums.json
```

La cuenta del servicio de SQL Server tiene que poder leer esta carpeta (ver "Antes de ejecutar" en `src/32_Importar_Mundial2026.sql`).

## Límites de uso

- No hace falta clave ni registro: son archivos estáticos de un repositorio público de GitHub, que los sirve desde `raw.githubusercontent.com`.
- GitHub limita los pedidos sin autenticar a `raw.githubusercontent.com`, igual que los clones por HTTPS y la API REST ([changelog del 8 de mayo de 2025](https://github.blog/changelog/2025-05-08-updated-rate-limits-for-unauthenticated-requests/)). No publica cuántos pedidos admite para descargar archivos; al superarlo responde HTTP 429 (Too Many Requests).
- La importación no consulta la URL: lee los archivos de esta carpeta. Los tres pedidos se hacen solo para actualizar los archivos.

## Lo que los archivos no traen

- El número de partido: el importador los numera por fecha y hora (ver el encabezado de `src/18_SP_Importar_Mundial2026.sql`).
- Las tarifas de los espacios publicitarios: las sedes nuevas reciben las tarifas que se pasan como parámetro.
- El motivo de los cambios y de las tarjetas.
- Los asistentes, el cuarto árbitro y el VAR. El árbitro principal sí viene, pero no se importa de acá: el equipo arbitral completo de cada partido sale del scraping de Wikipedia (`scraping/Scraping_Arbitros.py`).

## Diferencias entre los archivos

- `worldcup-full.json` nombra a tres selecciones distinto que `worldcup.teams.json` ("Bosnia and Herzegovina", "Côte d'Ivoire", "Congo DR").
- Escribe algunos jugadores de otra forma que el CSV del scraping (otra transliteración, el apodo o el nombre completo).
- `src/32_Importar_Mundial2026.sql` registra esos nombres en `Torneo.NOMBRE_ALTERNATIVO` y reprocesa solo los partidos que se habían rechazado (`@reprocesar_importacion`).
