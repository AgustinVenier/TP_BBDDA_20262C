# Feriados de Nager.Date

El sistema usa los feriados nacionales de cada país para saber si un partido cae en día feriado en un mercado de la publicidad. `Publicidad.fn_MercadosEnPrimeTime` muestra, para cada mercado, si la fecha local del partido es feriado y cuál. Se guardan en `DatosGenerales.FERIADO`: una fila por país y fecha.

La fuente es la API [Nager.Date](https://date.nager.at/) v3.

## Consumo desde SQL Server

`DatosGenerales.usp_ImportarFeriadosAPI` (`src/28_SP_Importar_Feriados.sql`) pide los feriados de un país y un año con `DatosGenerales.usp_ConsumirAPI` (`src/22_SP_ConsumirAPI.sql`), y procesa la respuesta con `DatosGenerales.usp_ProcesarFeriadosJSON`. La API no tiene un pedido para varios países, así que `src/29_ImportarCotizacionesYFeriados.sql` hace un pedido por cada código ISO de los países del sistema, para 2026.

Ejemplo de pedido, sin clave (año y código ISO alfa-2):

```text
https://date.nager.at/api/v3/PublicHolidays/2026/AR
```

Para verlo desde una consola:

```bat
curl "https://date.nager.at/api/v3/PublicHolidays/2026/AR"
```

Cada respuesta se carga con el SP de la Entrega 5 `DatosGenerales.usp_ImportarFeriados` (`src/16_SP_Importacion.sql`). Recibe todos los feriados válidos en un parámetro de tipo tabla y hace el upsert de una vez.

## Formato

```json
[
  {"date":"2026-07-09","localName":"Día de la Independencia","name":"Independence Day",
   "countryCode":"AR","fixed":false,"global":true,"counties":null,"launchYear":null,"types":["Public"]},
  {"date":"2026-06-15","localName":"World Cup Bank Holiday","name":"World Cup Bank Holiday",
   "countryCode":"GB","fixed":false,"global":false,"counties":["GB-SCT"],"launchYear":null,"types":["Public"]}
]
```

- `global` es `false` en los feriados que rigen solo en algunas subdivisiones, listadas en `counties` (provincias, estados o, en el Reino Unido, sus cuatro naciones).
- `types` puede ser `Public`, `Bank`, `School`, `Authorities`, `Optional` u `Observance`.

Respuestas de error:

- País que la API no cubre: HTTP 204, sin contenido.
- Código de país que no existe: HTTP 404 y un objeto con el motivo:

```json
{"title":"Unknown country code","status":404,"detail":"The country code provided is invalid or not recognized."}
```

## Transformaciones

Se hacen todas en T-SQL, al importar:

- El país se identifica por `countryCode` (ISO alfa-2). Inglaterra y Escocia comparten `GB` pero tienen feriados distintos: a cada una le tocan los de todo el Reino Unido y los de su subdivisión (`GB-ENG`, `GB-SCT`).
- Se omiten los feriados que no son públicos (`types` sin `Public`) y los regionales (`global` en `false` y sin una subdivisión que el sistema registre como país).
- Se guarda el nombre en el idioma del país (`localName`) y, si no viene, el nombre en inglés.
- Si un país tiene dos feriados el mismo día (Ecuador, el 02/11/2026), se registran juntos, con los nombres separados por " / ".
- Se rechazan los registros sin fecha o con fecha inválida, sin nombre o con un nombre de más de 200 caracteres.

## Países sin datos

Nager.Date no tiene feriados de Irán, Arabia Saudita, Catar, Uzbekistán, Jordania, India ni Emiratos Árabes Unidos (responde 204). `src/29_ImportarCotizacionesYFeriados.sql` carga a mano los del período del torneo (11/06 al 19/07/2026):

| País | Fecha | Feriado |
|---|---|---|
| Irán | 24/06/2026 | Tasua |
| Irán | 25/06/2026 | Ashura |
| India | 26/06/2026 | Muharram (Ashura) |
| Emiratos Árabes Unidos | 16/06/2026 | Año Nuevo Islámico |
| Jordania | 16/06/2026 | Año Nuevo Islámico |

Arabia Saudita, Catar y Uzbekistán no tienen feriados nacionales en ese período. Los de la tabla son del calendario lunar islámico: cada país confirma la fecha con la observación de la luna, y puede correrse un día. Hay que verificarlos con el calendario oficial de cada país.

## Límites de uso

- No hace falta clave ni registro.
- No publica un límite de pedidos. Cada importación de un país es un pedido, y el script 29 hace uno por código ISO: 50, de los que 43 traen datos.
- La API responde con `Cache-Control: max-age=604800` (una semana).
- Los datos son de un proyecto de código abierto mantenido por la comunidad. La cobertura de los feriados del calendario lunar es parcial: por ejemplo, no trae el Eid al-Adha de 2026 de Marruecos, Argelia ni Túnez.
- El proyecto publica una v4 en `nagerholidays.com`. Se usa la v3 porque sigue activa y trae el nombre en el idioma del país (`localName`), que la v4 no tiene.
