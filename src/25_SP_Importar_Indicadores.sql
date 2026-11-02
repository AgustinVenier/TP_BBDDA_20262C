/*
================================================================================
 Universidad Nacional de La Matanza
 Materia: 3641 - Bases de Datos Aplicada
 Comisión: 01    Grupo: 2
 Integrantes:
   Caruso Dellisanti, Carolina Belen - CarolinaCaruso
   D'Ambrosio, Rodrigo - rodrigoDambrosio
   Tavella, Tomás - TomasTavella
   Venier, Agustin - AgustinVenier

 Fecha: 29/10/2026
 Archivo: 25_SP_Importar_Indicadores.sql
 Objetivo: Crear el proceso de importación masiva de indicadores económicos
           por país del Banco Mundial, como el PBI per cápita
           (NY.GDP.PCAP.CD) con el que la asignación de publicidad estima el
           poder adquisitivo de cada mercado. Se importa desde un archivo XML
           descargado de la API o consultando la API directamente. Los SP,
           en el orden en que se crean (primero el que usan los otros dos):
             DatosGenerales.usp_ProcesarIndicadoresXML  valida el XML de la API y carga sus registros
             DatosGenerales.usp_ImportarIndicadoresXML  lee un archivo XML y lo procesa con el primero
             DatosGenerales.usp_ImportarIndicadoresAPI  consulta la API y procesa la respuesta igual
           El pedido a la API lo hace DatosGenerales.usp_ConsumirAPI
           (22_SP_ConsumirAPI.sql).
           Requiere haber ejecutado 00 a 22. Su script de testing es
           75_Test_SP_Importar_Indicadores.sql.
================================================================================

 Fuente: API de indicadores del Banco Mundial (v2), sin clave (ver
 datos/fuentes/bancomundial/README.md). Responde en XML: un elemento wb:data
 por país y año, con el código del indicador (wb:indicator/@id), el país
 (wb:countryiso3code, ISO alfa-3), el año (wb:date) y el valor (wb:value).

 Cómo importa usp_ProcesarIndicadoresXML (los pasos tienen el mismo número
 en el código):
   1. Se controla el documento: que sea XML, que sea de datos del Banco
      Mundial y no un mensaje de error de la API, y que traiga todos los
      registros (una sola página). Si no, no se importa nada.
   2. nodes() pasa los registros, tal como vienen, a la tabla de staging
      #staging_indicadores, y ahí se convierten (TRY_CONVERT). El archivo
      se importa tal como lo entrega la API: todas las transformaciones se
      hacen acá, en T-SQL.
   3. Antes de cargar, cada registro puede quedar:
        OMITIDO      si es de un país que el sistema no tiene registrado (la
                     API trae todos los países y también agregados como
                     "World" o "High income"), si no tiene valor (el Banco
                     Mundial todavía no lo publicó) o si repite otro registro
                     del archivo con el mismo valor. No es un error.
        RECHAZADO    si no tiene año o código de indicador, si el año o el
                     valor no son números, si el año no está entre 1960 y el
                     actual, si el código del indicador tiene más de 30
                     caracteres o caracteres no admitidos, o si el archivo
                     trae el mismo país, indicador y año con valores
                     distintos (no se sabe cuál es el correcto).
      Cada regla es un UPDATE sobre toda la tabla de staging, que anota el
      motivo en los registros que no la cumplen.
   4. Los demás se cargan todos juntos con el SP de la Entrega 5
      DatosGenerales.usp_ImportarIndicadoresEconomicos (16_SP_Importacion.sql),
      que recibe un parámetro de tipo tabla y hace el upsert sin recorrerlos
      de a uno. Como el paso 3 aplica las mismas reglas que ese SP, los
      registros válidos se cargan aunque haya otros rechazados.
   5. Se devuelve el resumen, los omitidos por motivo y los rechazados con
      sus motivos.
   La carga es un solo upsert, así que la importación puede correr dentro de
   una transacción (los tests la deshacen con ROLLBACK).

 Criterios del upsert (los de usp_ImportarIndicadoresEconomicos):
   - Clave natural: país (ISO alfa-3), indicador y año.
   - Inglaterra y Escocia comparten el código GBR: el valor se registra para
     las dos.
   - Cada año es un registro, así que la serie histórica se conserva. Si el
     Banco Mundial revisa el valor de un año, se actualiza ese año y su
     fecha_actualizacion. Un valor que no viene no borra el guardado.
   - Importar dos veces el mismo archivo no cambia nada.

 Se usa SQL dinámico solo para leer el archivo porque OPENROWSET(BULK) no acepta
 la ruta en una variable.

*/
USE MundialFutbol;


GO
SET ANSI_NULLS ON;

SET QUOTED_IDENTIFIER ON;


GO
/* ============================================================================
   PROCESAMIENTO DEL XML (lo usan los dos SP de abajo)
   ============================================================================ */
/*
  usp_ProcesarIndicadoresXML
  Importa un documento de la API de indicadores del Banco Mundial. Lo
  llaman usp_ImportarIndicadoresXML y usp_ImportarIndicadoresAPI. @origen
  es el archivo o la URL de donde salió, para el resumen. Devuelve el
  resumen (leídos, insertados, actualizados, sin cambios, omitidos y
  rechazados), los omitidos por motivo y los rechazados con sus motivos.
  Si el documento no es de datos del Banco Mundial, es un mensaje de error
  de la API o le faltan páginas, no se importa nada (THROW 50002).
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ProcesarIndicadoresXML
    @xml XML,
    @origen NVARCHAR (2000)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @nl AS NCHAR (2) = NCHAR(13) + NCHAR(10);
    DECLARE @mensaje AS NVARCHAR (2048);
    DECLARE @raices AS INT;
    DECLARE @es_error_api AS BIT;
    DECLARE @error_api AS NVARCHAR (400);
    DECLARE @pagina AS INT;
    DECLARE @paginas AS INT;
    DECLARE @anio_actual AS SMALLINT = YEAR (
                                           GETDATE()
                                       );
    DECLARE @validos AS DatosGenerales.TT_INDICADOR_ECONOMICO;
    DECLARE @insertados AS INT = 0;
    DECLARE @actualizados AS INT = 0;
    DECLARE @sin_cambios AS INT = 0;
    /* 1. El documento.
          Raíz wb:data con page y pages; si la API rechaza el pedido, la raíz
          es wb:error con el motivo en wb:message. */
    WITH   XMLNAMESPACES ('http://www.worldbank.org' AS wb)
    SELECT @raices = @xml.value('count(/*)', 'INT'),
           @es_error_api = @xml.exist('/wb:error'),
           @error_api = @xml.value('(/wb:error/wb:message)[1]', 'NVARCHAR(400)'),
           @pagina = @xml.value('(/wb:data/@page)[1]', 'INT'),
           @paginas = @xml.value('(/wb:data/@pages)[1]', 'INT');
    IF @es_error_api = 1
        SET @mensaje = N'la API del Banco Mundial devolvió un error: ' + ISNULL(@error_api, N'(sin mensaje)') + N' (revisar el código del indicador, los países y los años).';
    ELSE
        IF ISNULL(@raices, 0) <> 1
           OR @paginas IS NULL
            SET @mensaje = N'el XML no es de datos de la API del Banco Mundial (tiene que tener un solo ' + N'elemento raíz wb:data, del espacio de nombres http://www.worldbank.org).';
        ELSE
            IF @pagina IS NULL
               OR @paginas IS NULL
               OR @pagina <> 1
               OR @paginas <> 1
                SET @mensaje = N'el XML no contiene una única página completa. ' + N'Hay que descargar el resultado completo, con per_page=20000 en la URL.';
    IF @mensaje IS NOT NULL
        BEGIN
            SET @mensaje = N'DatosGenerales.usp_ProcesarIndicadoresXML: no se importó nada, ' + @mensaje;
            THROW 50002, @mensaje, 1;
        END
    CREATE TABLE #staging_indicadores (
        id_registro    INT             IDENTITY (1, 1) PRIMARY KEY,
        -- Tal como vienen en el XML
        indicador_txt  NVARCHAR (100)  COLLATE DATABASE_DEFAULT NULL,
        pais_txt       NVARCHAR (200)  COLLATE DATABASE_DEFAULT NULL,
        iso3           NVARCHAR (50)   COLLATE DATABASE_DEFAULT NULL,
        anio_txt       NVARCHAR (50)   COLLATE DATABASE_DEFAULT NULL,
        valor_txt      NVARCHAR (100)  COLLATE DATABASE_DEFAULT NULL,
        -- Convertidos
        anio           SMALLINT        NULL,
        valor          DECIMAL (18, 4) NULL,
        errores        NVARCHAR (MAX)  COLLATE DATABASE_DEFAULT NULL,
        motivo_omision VARCHAR (60)    COLLATE DATABASE_DEFAULT NULL,
        accion         VARCHAR (15)    COLLATE DATABASE_DEFAULT NULL
    );
    /* 2. Los registros, como vienen de la api. */
    WITH XMLNAMESPACES ('http://www.worldbank.org' AS wb)
    INSERT INTO #staging_indicadores (
        indicador_txt,
        pais_txt,
        iso3,
        anio_txt,
        valor_txt
    )
    SELECT NULLIF (TRIM (
                       d.value (
                           '(wb:indicator/@id)[1]',
                           'NVARCHAR(100)'
                       )
                   ), N''),
           NULLIF (TRIM (
                       d.value (
                           '(wb:country)[1]',
                           'NVARCHAR(200)'
                       )
                   ), N''),
           UPPER (
               NULLIF (TRIM (
                   d.value (
                       '(wb:countryiso3code)[1]',
                       'NVARCHAR(50)'
                   )
               ), N'')
           ),
           NULLIF (TRIM (
                       d.value (
                           '(wb:date)[1]',
                           'NVARCHAR(50)'
                       )
                   ), N''),
           NULLIF (TRIM (
                       d.value (
                           '(wb:value)[1]',
                           'NVARCHAR(100)'
                       )
                   ), N'')
    FROM   @xml.nodes('/wb:data/wb:data') AS t(d);
    /* 3. Omitidos: lo que el sistema no guarda. */
    UPDATE i
    SET    accion         = 'OMITIDO',
           motivo_omision = 'País no registrado en el sistema o agregado regional'
    FROM   #staging_indicadores AS i
    WHERE  NOT EXISTS (SELECT 1
                       FROM   DatosGenerales.PAIS AS p
                       WHERE  p.codigo_iso3 = i.iso3);
    UPDATE #staging_indicadores
    SET    accion         = 'OMITIDO',
           motivo_omision = 'Sin valor publicado para ese año'
    WHERE  accion IS NULL
           AND valor_txt IS NULL;
    -- Conversión, y las reglas de usp_ImportarIndicadoresEconomicos aplicadas a
    -- cada registro: así ese SP recibe solo los válidos y no rechaza la carga.
    UPDATE #staging_indicadores
    SET    anio  = TRY_CONVERT (SMALLINT, anio_txt),
           valor = TRY_CONVERT (DECIMAL (18, 4), valor_txt)
    WHERE  accion IS NULL;
    UPDATE #staging_indicadores
    SET    errores = NULLIF (CONCAT (
                                 CASE WHEN indicador_txt IS NULL THEN @nl + N'- El código del indicador es obligatorio.' WHEN LEN (indicador_txt) > 30 THEN @nl + N'- El código del indicador no puede superar los 30 caracteres.' WHEN UPPER (indicador_txt) COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9._]%' THEN @nl + N'- El código del indicador solo admite letras sin acentos, números, puntos y guiones bajos.' END,
                                 CASE WHEN anio_txt IS NULL THEN @nl + N'- El año es obligatorio.' WHEN anio IS NULL THEN @nl + N'- El año "' + anio_txt + N'" no es un año (AAAA): el sistema guarda indicadores anuales.' WHEN anio NOT BETWEEN 1960 AND @anio_actual THEN @nl + N'- El año debe estar entre 1960 y ' + CAST (@anio_actual AS NVARCHAR (4)) + N'.' END,
                                 IIF (valor IS NULL, @nl + N'- El valor "' + valor_txt + N'" no es un número (o tiene más de 14 dígitos enteros).', N'')
                             ), N'')
    WHERE  accion IS NULL;
    /* Mismo país, indicador y año más de una vez en el archivo:
       con el mismo valor se importa una vez y las copias válidas se omiten;
       con valores distintos se rechazan todos los registros de esa clave.
       Se incluyen registros con otros errores para no perder conflictos. */;
    WITH repetidos
    AS   (SELECT id_registro,
                 COUNT(*) OVER (PARTITION BY iso3,
                                             UPPER(indicador_txt),
                                             anio) AS veces,
                 MIN(valor) OVER (PARTITION BY iso3,
                                               UPPER(indicador_txt),
                                               anio) AS valor_minimo,
                 MAX(valor) OVER (PARTITION BY iso3,
                                               UPPER(indicador_txt),
                                               anio) AS valor_maximo,
                 ROW_NUMBER() OVER (PARTITION BY iso3,
                                                 UPPER(indicador_txt),
                                                 anio ORDER BY CASE WHEN errores IS NULL THEN 0 ELSE 1 END,
                                                               id_registro) AS copia
          FROM   #staging_indicadores
          WHERE  accion IS NULL
                 AND iso3 IS NOT NULL
                 AND indicador_txt IS NOT NULL
                 AND anio IS NOT NULL
                 AND valor IS NOT NULL)
    UPDATE i
    SET    errores        = CASE WHEN r.valor_minimo <> r.valor_maximo THEN CONCAT (
                                                                                ISNULL (
                                                                                    i.errores,
                                                                                    N''
                                                                                ),
                                                                                @nl,
                                                                                N'- El archivo trae ',
                                                                                CAST (r.veces AS NVARCHAR (10)),
                                                                                N' veces este país, indicador y año, con valores distintos: no se sabe cuál es el correcto.'
                                                                            ) ELSE i.errores END,
           accion         = CASE WHEN r.valor_minimo = r.valor_maximo
                                      AND r.copia > 1
                                      AND i.errores IS NULL THEN 'OMITIDO' ELSE NULL END,
           motivo_omision = CASE WHEN r.valor_minimo = r.valor_maximo
                                      AND r.copia > 1
                                      AND i.errores IS NULL THEN 'Repetido en el archivo con el mismo valor' ELSE NULL END
    FROM   #staging_indicadores AS i
           INNER JOIN
           repetidos AS r
           ON r.id_registro = i.id_registro
    WHERE  r.veces > 1;
    UPDATE #staging_indicadores
    SET    accion = 'RECHAZADO'
    WHERE  accion IS NULL
           AND errores IS NOT NULL;
    /* 4. Carga de los válidos, todos juntos, con el SP de la Entrega 5. */
    INSERT INTO @validos (
        codigo_iso3,
        codigo_indicador,
        anio,
        valor
    )
    SELECT iso3,
           indicador_txt,
           anio,
           valor
    FROM   #staging_indicadores
    WHERE  accion IS NULL;
    IF EXISTS (SELECT 1
               FROM   @validos)
        EXECUTE DatosGenerales.usp_ImportarIndicadoresEconomicos @indicadores = @validos, @insertados = @insertados OUTPUT, @actualizados = @actualizados OUTPUT, @sin_cambios = @sin_cambios OUTPUT;
    /* 5. Resultado. */
    SELECT @origen AS origen,
           COUNT(*) AS leidos,
           @insertados AS insertados,
           @actualizados AS actualizados,
           @sin_cambios AS sin_cambios,
           ISNULL (
               SUM (IIF (accion = 'OMITIDO', 1, 0)),
               0
           ) AS omitidos,
           ISNULL (
               SUM (IIF (accion = 'RECHAZADO', 1, 0)),
               0
           ) AS rechazados
    FROM   #staging_indicadores;
    SELECT   motivo_omision AS omitidos_por,
             COUNT(*) AS registros
    FROM     #staging_indicadores
    WHERE    accion = 'OMITIDO'
    GROUP BY motivo_omision
    ORDER BY registros DESC;
    SELECT   CONCAT (
                 ISNULL (
                     iso3,
                     N'(sin país)'
                 ),
                 N' ',
                 ISNULL (
                     anio_txt,
                     N'(sin año)'
                 ),
                 N' ',
                 ISNULL (
                     indicador_txt,
                     N'(sin indicador)'
                 ),
                 IIF (pais_txt IS NULL, N'', N' - ' + pais_txt)
             ) AS rechazado,
             STUFF(errores, 1, 2, N'') AS motivos
    FROM     #staging_indicadores
    WHERE    accion = 'RECHAZADO'
    ORDER BY rechazado;
END


GO
/* ============================================================================
   IMPORTACIÓN DESDE UN ARCHIVO
   ============================================================================ */
/*
  usp_ImportarIndicadoresXML
  Importa el archivo XML @ruta_archivo, descargado de la API de indicadores
  del Banco Mundial sin modificar (ver datos/fuentes/bancomundial/README.md),
  con usp_ProcesarIndicadoresXML.
  Valida: ruta obligatoria y terminada en .xml. Si el archivo no se puede
  leer o no tiene un XML válido, no se importa nada (THROW 50002).
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarIndicadoresXML
    @ruta_archivo NVARCHAR (400)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores AS NVARCHAR (2048) = N'';
    DECLARE @nl AS NCHAR (2) = NCHAR(13) + NCHAR(10);
    DECLARE @sql AS NVARCHAR (MAX);
    DECLARE @contenido AS VARBINARY (MAX);
    DECLARE @xml AS XML;
    DECLARE @mensaje AS NVARCHAR (2048);
    SET @ruta_archivo = NULLIF (TRIM(@ruta_archivo), N'');
    IF @ruta_archivo IS NULL
        SET @errores += @nl + N'- La ruta del archivo es obligatoria.';
    ELSE
        IF @ruta_archivo NOT LIKE N'%.xml'
            SET @errores += @nl + N'- El archivo tiene que ser un .xml (el que devuelve la API del Banco Mundial).';
    IF @errores <> N''
        BEGIN
            SET @errores = N'DatosGenerales.usp_ImportarIndicadoresXML: no se pudo importar el archivo.' + @errores;
            THROW 50001, @errores, 1;
        END
    /* Lectura. OPENROWSET(BULK) no acepta la ruta en una variable: SQL dinámico.
       SINGLE_BLOB trae los bytes tal cual y, al convertirlos a XML, SQL Server
       respeta la codificación que declara el archivo (UTF-8). */
    BEGIN TRY
        SET @sql = N'SELECT @contenido = BulkColumn FROM OPENROWSET(BULK N''' + REPLACE(@ruta_archivo, N'''', N'''''') + N''', SINGLE_BLOB) AS archivo;';
        EXECUTE sp_executesql @sql, N'@contenido VARBINARY(MAX) OUTPUT', @contenido = @contenido OUTPUT;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'no se pudo leer el archivo (' + ERROR_MESSAGE() + N').';
    END CATCH
    /* TRY_CONVERT y no CAST: un XML mal formado hace fallar el CAST con un
       error que deja sin poder confirmar la transacción de quien llama,
       aunque esté dentro de TRY ... CATCH. */
    SET @xml = TRY_CONVERT (XML, @contenido);
    IF @mensaje IS NULL
       AND @xml IS NULL
        SET @mensaje = N'el archivo no tiene un XML válido (puede ser una descarga incompleta).';
    IF @mensaje IS NOT NULL
        BEGIN
            SET @mensaje = N'DatosGenerales.usp_ImportarIndicadoresXML: no se importó nada, ' + @mensaje;
            THROW 50002, @mensaje, 1;
        END
    EXECUTE DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = @ruta_archivo;
END


GO
/* ============================================================================
   IMPORTACIÓN DESDE LA API
   ============================================================================ */
/*
  usp_ImportarIndicadoresAPI
  Consulta la API de indicadores del Banco Mundial con usp_ConsumirAPI por
  el indicador @codigo_indicador entre @anio_desde y @anio_hasta, y procesa
  la respuesta con usp_ProcesarIndicadoresXML.
  Por defecto trae el PBI per cápita (NY.GDP.PCAP.CD) de todos los países en
  los últimos 10 años. @paises limita la consulta a algunos países, con sus
  códigos ISO alfa-3 separados por punto y coma (ej. 'ARG;BRA'); la API
  rechaza el pedido completo si alguno no existe. Pide per_page=20000, que
  alcanza para todos los países desde 1960 en una sola página.
  Valida: código del indicador obligatorio y con caracteres de código;
  países solo con letras y punto y coma; años entre 1960 y el actual, el
  primero no mayor que el segundo. Si la API no responde, responde con un
  código HTTP distinto de 200 o no devuelve un XML válido, no se importa
  nada (THROW 50002).
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarIndicadoresAPI
    @codigo_indicador VARCHAR (60)='NY.GDP.PCAP.CD',
    @anio_desde SMALLINT=NULL,
    @anio_hasta SMALLINT=NULL,
    @paises VARCHAR (400)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores AS NVARCHAR (2048) = N'';
    DECLARE @nl AS NCHAR (2) = NCHAR(13) + NCHAR(10);
    DECLARE @anio_actual AS SMALLINT = YEAR (
                                           GETDATE()
                                       );
    DECLARE @url AS NVARCHAR (2000);
    DECLARE @estado_http AS SMALLINT;
    DECLARE @respuesta AS NVARCHAR (MAX);
    DECLARE @xml AS XML;
    DECLARE @mensaje AS NVARCHAR (2048);
    SET @codigo_indicador = UPPER (
                                NULLIF (TRIM (@codigo_indicador), '')
                            );
    SET @paises = UPPER (
                      NULLIF (REPLACE (
                          @paises,
                          ' ',
                          ''
                      ), '')
                  );
    SET @anio_hasta = ISNULL(@anio_hasta, @anio_actual);
    SET @anio_desde = ISNULL(@anio_desde, @anio_hasta - 9);
    /* El código y los países van dentro de la URL: solo se aceptan sus
       caracteres, para que no se pueda alterar la consulta. Las reglas de
       cada registro las aplica la importación. */
    IF @codigo_indicador IS NULL
        SET @errores += @nl + N'- El código del indicador es obligatorio (ej. NY.GDP.PCAP.CD).';
    ELSE
        IF @codigo_indicador COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9._]%'
            SET @errores += @nl + N'- El código del indicador solo admite letras sin acentos, números, puntos y guiones bajos.';
    IF @paises COLLATE Latin1_General_BIN LIKE '%[^A-Z;]%'
        SET @errores += @nl + N'- Los países van con su código ISO alfa-3, separados por punto y coma (ej. ARG;BRA).';
    IF @anio_desde NOT BETWEEN 1960 AND @anio_actual
       OR @anio_hasta NOT BETWEEN 1960 AND @anio_actual
        SET @errores += @nl + N'- Los años deben estar entre 1960 y ' + CAST (@anio_actual AS NVARCHAR (4)) + N'.';
    ELSE
        IF @anio_desde > @anio_hasta
            SET @errores += @nl + N'- El año desde no puede ser mayor que el año hasta.';
    IF @errores <> N''
        BEGIN
            SET @errores = N'DatosGenerales.usp_ImportarIndicadoresAPI: no se pudo consultar la API.' + @errores;
            THROW 50001, @errores, 1;
        END
    SET @url = CONCAT (
                   N'https://api.worldbank.org/v2/country/',
                   ISNULL (
                       @paises,
                       'all'
                   ),
                   N'/indicator/',
                   @codigo_indicador,
                   N'?date=',
                   @anio_desde,
                   N':',
                   @anio_hasta,
                   N'&per_page=20000&format=xml'
               );
    BEGIN TRY
        EXECUTE DatosGenerales.usp_ConsumirAPI @url = @url, @estado_http = @estado_http OUTPUT, @respuesta = @respuesta OUTPUT;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'falló la consulta a la API: ' + ERROR_MESSAGE();
    END CATCH
    IF @mensaje IS NULL
       AND (@estado_http IS NULL
            OR @estado_http <> 200)
        SET @mensaje = N'la API respondió con el código HTTP ' + CAST (@estado_http AS NVARCHAR (5)) + N'.';
    /* La respuesta llega como texto (UTF-16) y empieza con la declaración
       <?xml ... encoding="utf-8"?>, que SQL Server no acepta en un texto
       NVARCHAR: se le quita antes de convertirla a XML. TRY_CONVERT por lo
       mismo que en usp_ImportarIndicadoresXML. */
    IF @mensaje IS NULL
        BEGIN
            SET @xml = TRY_CONVERT (XML, IIF (LEFT(@respuesta, 5) = N'<?xml', STUFF (
                                                                                  @respuesta,
                                                                                  1,
                                                                                  CHARINDEX (
                                                                                      N'?>',
                                                                                      @respuesta
                                                                                  ) + 1,
                                                                                  N''
                                                                              ), @respuesta));
            IF @xml IS NULL
                SET @mensaje = N'la respuesta no es un XML válido.';
        END
    IF @mensaje IS NOT NULL
        BEGIN
            SET @mensaje = N'DatosGenerales.usp_ImportarIndicadoresAPI: no se importó nada, ' + @mensaje;
            THROW 50002, @mensaje, 1;
        END
    EXECUTE DatosGenerales.usp_ProcesarIndicadoresXML @xml = @xml, @origen = @url;
END


GO
-- Evidencia: SP de importación de indicadores creados.
SELECT   s.name AS esquema,
         p.name AS procedimiento,
         p.modify_date AS ultima_modificacion
FROM     sys.procedures AS p
         INNER JOIN
         sys.schemas AS s
         ON s.schema_id = p.schema_id
WHERE    s.name = N'DatosGenerales'
         AND p.name IN (
             N'usp_ProcesarIndicadoresXML',
             N'usp_ImportarIndicadoresXML',
             N'usp_ImportarIndicadoresAPI'
         )
ORDER BY p.name;


GO
