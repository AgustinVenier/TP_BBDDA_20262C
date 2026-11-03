# Indicadores económicos del Banco Mundial

El sistema usa el PBI per cápita en dólares corrientes (indicador `NY.GDP.PCAP.CD`) para estimar el poder adquisitivo de cada mercado al proponer las piezas publicitarias de un partido (`Publicidad.fn_PrioridadPiezas`, que toma el último año cargado de cada país). Se guarda en `DatosGenerales.INDICADOR_ECONOMICO`: una fila por país, indicador y año.

La fuente es la API de indicadores del Banco Mundial (v2). Responde en XML.

## Consumo desde SQL Server

`DatosGenerales.usp_ImportarIndicadoresAPI` (`src/25_SP_Importar_Indicadores.sql`) hace un pedido GET con `DatosGenerales.usp_ConsumirAPI` (`src/22_SP_ConsumirAPI.sql`) y procesa la respuesta con `DatosGenerales.usp_ProcesarIndicadoresXML`. Por defecto trae el PBI per cápita de todos los países en los últimos 10 años. Se puede pedir otro indicador anual del Banco Mundial, otro rango de años o solo algunos países (`@paises = 'ARG;BRA'`). `src/26_Ejecutar_ImportarIndicadores.sql` importa el PBI per cápita con los valores por defecto.

Ejemplo de pedido, sin clave:

```text
https://api.worldbank.org/v2/country/all/indicator/NY.GDP.PCAP.CD?date=2017:2026&per_page=20000&format=xml
```

- `country/all`: todos los países y los agregados (regiones, niveles de ingreso). Se pide todo, porque si en la URL va un código de país que la API no conoce, rechaza el pedido completo. Lo que el sistema no usa se omite al importar.
- `date=2017:2026`: el rango de años.
- `per_page=20000`: la API pagina de a 50 registros si no se indica otra cosa. Con 20000 entran todos los países desde 1960 en una sola página. Si la respuesta es una página de varias, la importación la rechaza.
- `format=xml`: es el formato por defecto. Se indica igual para que quede explícito.

Para verlo desde una consola:

```bat
curl "https://api.worldbank.org/v2/country/all/indicator/NY.GDP.PCAP.CD?date=2017:2026&per_page=20000&format=xml"
```

Los registros se cargan con el SP de la Entrega 5 `DatosGenerales.usp_ImportarIndicadoresEconomicos` (`src/16_SP_Importacion.sql`). Lee la tabla de staging que arma el proceso, valida cada registro con las reglas de los indicadores y hace el upsert de los válidos de una vez. Los rechazados quedan en `DatosGenerales.ERRORES_INDICADOR_ECONOMICO`, con el número de la importación (`DatosGenerales.IMPORTACION`).

SQL Server 2022 no trae un procedimiento para llamar a una API REST (`sp_invoke_external_rest_endpoint` recién está en SQL Server 2025), así que el pedido se hace con OLE Automation (`MSXML2.ServerXMLHTTP`) en `DatosGenerales.usp_ConsumirAPI` (`src/22_SP_ConsumirAPI.sql`), que sirve para cualquier API REST sin clave. Hace falta la opción de instancia `Ole Automation Procedures`, que viene deshabilitada. `src/26_Ejecutar_ImportarIndicadores.sql` la habilita solo mientras consulta la API y después la deja como estaba.

## Formato

```xml
<wb:data page="1" pages="1" per_page="20000" total="2926" sourceid="2" lastupdated="2026-10-08" xmlns:wb="http://www.worldbank.org">
  <wb:data>
    <wb:indicator id="NY.GDP.PCAP.CD">GDP per capita (current US$)</wb:indicator>
    <wb:country id="AR">Argentina</wb:country>
    <wb:countryiso3code>ARG</wb:countryiso3code>
    <wb:date>2024</wb:date>
    <wb:value>13969.7836603737</wb:value>
    ...
  </wb:data>
  ...
</wb:data>
```

Si el pedido es inválido (indicador o país que no existen), la API responde con un XML de error:

```xml
<wb:error xmlns:wb="http://www.worldbank.org"><wb:message id="120" key="Invalid value">The provided parameter value is not valid</wb:message></wb:error>
```

## Transformaciones

Se hacen todas en T-SQL, al importar:

- El país se identifica por `wb:countryiso3code` (ISO alfa-3). Inglaterra y Escocia comparten `GBR` y reciben el mismo valor.
- Se omiten los registros de países que el sistema no tiene registrados, los agregados (que traen un código que no es de un país, o ninguno) y los años sin valor publicado (`<wb:value />`).
- El valor se convierte a `DECIMAL(18,4)`, redondeado a 4 decimales.
- El año tiene que ser un año (`AAAA`). Los indicadores trimestrales o mensuales (`2023Q1`, `2023M01`) se rechazan.

## Límites de uso

- No hace falta clave ni registro. La [documentación oficial](https://datahelpdesk.worldbank.org/knowledgebase/articles/889392-about-the-indicators-api) dice que las claves de API ya no son necesarias.
- La documentación no publica un límite de pedidos. Igual conviene no repetir pedidos: cada importación es uno solo, y la API responde con `Cache-Control: max-age=86400`.
- Los datos se actualizan periódicamente. El atributo `lastupdated` del XML indica la fecha de la última actualización. Al reimportar, los años que el Banco Mundial haya revisado quedan como ACTUALIZADO.
