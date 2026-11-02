# Cotizaciones de monedas de Frankfurter

Las tarifas de los espacios publicitarios están en dólares. Con estas cotizaciones el sistema convierte la pauta a la moneda de cada mercado, y a dólares una exhibición facturada en otra moneda (`DatosGenerales.fn_CotizacionVigente`). Se guardan en `DatosGenerales.COTIZACION`: una fila por moneda y día, con cuántas unidades de esa moneda vale un dólar.

La fuente es la API [Frankfurter](https://frankfurter.dev/) v2. Junta las cotizaciones de 106 bancos centrales y fuentes oficiales, y cubre todas las monedas de los países del sistema.

## Consumo desde SQL Server

`DatosGenerales.usp_ImportarCotizacionesAPI` (`src/27_SP_Importar_Cotizaciones.sql`) hace un pedido GET con `DatosGenerales.usp_ConsumirAPI` (`src/22_SP_ConsumirAPI.sql`) y procesa la respuesta con `DatosGenerales.usp_ProcesarCotizacionesJSON`. Por defecto trae las monedas de todos los países del sistema, sin el dólar, de los últimos 30 días. `src/29_ImportarCotizacionesYFeriados.sql` importa junio y julio de 2026, el período del torneo y de las campañas.

Ejemplo de pedido, sin clave:

```text
https://api.frankfurter.dev/v2/rates?base=USD&quotes=ARS,EUR&from=2026-06-11&to=2026-06-12
```

- `base=USD`: las cotizaciones son contra el dólar, la moneda de las tarifas.
- `quotes`: las monedas a cotizar, separadas por coma.
- `from` y `to`: el rango de fechas. El SP lo limita a un año para que la respuesta no sea demasiado grande.

Para verlo desde una consola:

```bat
curl "https://api.frankfurter.dev/v2/rates?base=USD&quotes=ARS,EUR&from=2026-06-11&to=2026-06-12"
```

Cada registro se carga con el SP de la Entrega 5 `DatosGenerales.usp_ImportarCotizaciones` (`src/16_SP_Importacion.sql`). Lee la tabla de staging que arma el proceso, valida cada registro con las reglas de las cotizaciones y hace el upsert de los válidos de una vez. Los rechazados quedan en `DatosGenerales.ERRORES_COTIZACION`, con el número de la importación (`DatosGenerales.IMPORTACION`).

## Por qué la v2 y no la v1

La v1 (`api.frankfurter.app` o `api.frankfurter.dev/v1`) sigue funcionando, pero responde con un encabezado `Deprecation` que apunta a la v2. Además solo publica las cotizaciones del Banco Central Europeo: 30 monedas, sin ARS, UYU, COP, CLP, PEN ni las de varios países del sistema.

## Formato

```json
[
  {"date":"2026-06-11","base":"USD","quote":"ARS","rate":1436.11},
  {"date":"2026-06-11","base":"USD","quote":"EUR","rate":0.86627}
]
```

- No hay registros de los días sin cotización (fines de semana y feriados bancarios). Al pedir un rango que empieza un día sin cotización, el primer registro puede traer la fecha anterior: es la cotización vigente de ese día.
- Algunas cotizaciones muy chicas, como las de criptomonedas, vienen en notación científica (`1.5957e-05`).

Si el pedido es inválido, la API responde con un código HTTP 4xx y un objeto con el motivo:

```json
{"status":422,"message":"invalid currency: XYZ"}
```

## Transformaciones

Se hacen todas en T-SQL, al importar:

- La fecha se convierte desde `AAAA-MM-DD` y el valor a `DECIMAL(19,6)`. Si viene en notación científica, se convierte pasando por `FLOAT`.
- Se omite el dólar contra el dólar, que vale siempre 1 y no se guarda.
- Se rechazan las cotizaciones que no son contra el dólar, las de moneda que no es un código de 3 letras, las de fecha futura o inválida y las de valor que no es un número mayor que cero.
- Si llega dos veces la misma moneda y fecha con el mismo valor, se importa una vez. Con valores distintos se rechazan las dos.

## Límites de uso

- No hace falta clave ni registro.
- La documentación dice que no hay cuotas ni topes diarios o mensuales. Sí limita la cantidad de pedidos para evitar abusos, sin publicar el número. Cada importación es un solo pedido.
- La API responde con `Cache-Control: max-age=86400`: las cotizaciones de un día no cambian.
- Las cotizaciones de cada banco central se publican en días hábiles, con el horario de cada país.
