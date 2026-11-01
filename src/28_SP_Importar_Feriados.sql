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

 Fecha: 31/10/2026
 Archivo: 28_SP_Importar_Feriados.sql
 Objetivo: Crear el proceso de importación de feriados nacionales desde la
           API Nager.Date, para saber si un partido cae en día feriado en un
           mercado de la publicidad (Publicidad.fn_MercadosEnPrimeTime). Los
           SP, en el orden en que se crean (primero el que usa el otro):
             DatosGenerales.usp_ProcesarFeriadosJSON  valida la respuesta de la API y carga sus registros
             DatosGenerales.usp_ImportarFeriadosAPI   consulta la API por un país y año, y procesa la respuesta
           El pedido a la API lo hace DatosGenerales.usp_ConsumirAPI
           (22_SP_ConsumirAPI.sql).
           Requiere haber ejecutado 00 a 22. Su script de testing es
           78_Test_SP_Importar_Feriados.sql.
================================================================================

 Fuente: API Nager.Date v3, sin clave (ver datos/fuentes/nager/README.md). Se
 consulta de a un país y año: no tiene un pedido para varios países. Responde
 en JSON: un arreglo con un objeto por feriado, con la fecha (date), el nombre
 en el idioma del país (localName) y en inglés (name), el país (countryCode,
 ISO alfa-2), si es de todo el país (global), las subdivisiones donde rige si
 no lo es (counties, ej. GB-SCT) y sus tipos (types: Public, Bank, School,
 Authorities, Optional, Observance). Ej.:
   [{"date":"2026-07-09","localName":"Día de la Independencia","name":"Independence Day",
     "countryCode":"AR","global":true,"counties":null,"types":["Public"]}, ...]

 Cómo importa usp_ProcesarFeriadosJSON (los pasos tienen el mismo número en
 el código):
   1. Se controla el documento: que sea JSON, que no sea un mensaje de error
      de la API y que sea un arreglo. Si no, no se importa nada.
   2. OPENJSON pasa los registros, tal como vienen, a la tabla de staging
      #staging_feriados, y ahí se convierten (TRY_CONVERT). Todas las
      transformaciones se hacen acá, en T-SQL.
   3. Antes de cargar, cada registro puede quedar:
        OMITIDO      si es de un país que el sistema no tiene, si no es un
                     feriado público (los bancarios, escolares u optativos no
                     cambian la audiencia) o si es regional (rige solo en
                     algunas provincias o estados). No es un error.
        RECHAZADO    si le falta la fecha o el nombre, si la fecha no es una
                     fecha o si el nombre es demasiado largo.
   4. Cada registro se asigna a los países del sistema que tienen su código
      ISO. Inglaterra y Escocia comparten GB pero tienen feriados distintos:
      a cada una le tocan los de todo el Reino Unido y los de su subdivisión
      (GB-ENG, GB-SCT). Si un país tiene dos feriados el mismo día, se
      registran juntos, con los nombres separados por " / ".
   5. Se cargan todos juntos con el SP de la Entrega 5
      DatosGenerales.usp_ImportarFeriados (16_SP_Importacion.sql), que recibe
      un parámetro de tipo tabla y hace el upsert sin recorrerlos de a uno.
      Como los pasos 3 y 4 aplican las mismas reglas que ese SP, los
      registros válidos se cargan aunque haya otros rechazados.
   6. Se devuelve el resumen, los omitidos por motivo y los rechazados con
      sus motivos.
   La carga es un solo upsert, así que la importación puede correr dentro de
   una transacción (los tests la deshacen con ROLLBACK).

 Criterios del upsert (los de usp_ImportarFeriados):
   - Clave natural: país y fecha.
   - Si la fuente cambia el nombre de un feriado, se actualiza con su
     fecha_actualizacion. Importar dos veces lo mismo no cambia nada. Un
     feriado que deja de venir no se borra: se conserva lo ya registrado.
   - Se guarda el nombre en el idioma del país; si no viene, el nombre en
     inglés.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   PROCESAMIENTO DEL JSON (lo usa el SP de abajo)
   ============================================================================ */

/*
  usp_ProcesarFeriadosJSON
  Importa una respuesta de la API Nager.Date v3 (/api/v3/PublicHolidays).
  La llama usp_ImportarFeriadosAPI. @origen es la URL o el texto que
  identifica de dónde salió, para el resumen. Con @mostrar = 1 devuelve el
  resumen (leídos, insertados, actualizados, sin cambios, omitidos y
  rechazados), los omitidos por motivo y los rechazados con sus motivos. Los
  totales también salen en los parámetros OUTPUT, para quien importa varios
  países y arma un solo resumen. Leídos, omitidos y rechazados cuentan
  registros de la API; insertados, actualizados y sin cambios cuentan
  feriados por país y día (un feriado del Reino Unido puede dar dos, uno de
  Inglaterra y otro de Escocia).
  Si el documento no es JSON, es un mensaje de error de la API o no es un
  arreglo de feriados, no se importa nada (THROW 50002).
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ProcesarFeriadosJSON
    @json          NVARCHAR(MAX),
    @origen        NVARCHAR(1000),
    @mostrar       BIT = 1,
    @leidos        INT = NULL OUTPUT,
    @insertados    INT = NULL OUTPUT,
    @actualizados  INT = NULL OUTPUT,
    @sin_cambios   INT = NULL OUTPUT,
    @omitidos      INT = NULL OUTPUT,
    @rechazados    INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @nl       NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @mensaje  NVARCHAR(2048);
    DECLARE @validos  DatosGenerales.TT_FERIADO;
    -- Países del sistema que en la API son una subdivisión de otro código ISO.
    DECLARE @subdivisiones TABLE (codigo_fifa CHAR(3) PRIMARY KEY, subdivision NVARCHAR(10));

    INSERT INTO @subdivisiones (codigo_fifa, subdivision)
    VALUES ('ENG', N'GB-ENG'), ('SCO', N'GB-SCT');

    SELECT @insertados = 0, @actualizados = 0, @sin_cambios = 0;

    /* 1. El documento.
          Si la API rechaza el pedido responde un objeto con title, status y
          detail en vez del arreglo. */
    IF ISJSON(@json) IS DISTINCT FROM 1
        SET @mensaje = N'el documento no es un JSON válido (puede ser una respuesta incompleta).';
    ELSE IF JSON_VALUE(@json, '$.title') IS NOT NULL OR JSON_VALUE(@json, '$.detail') IS NOT NULL
        SET @mensaje = N'la API Nager.Date devolvió un error: '
                     + ISNULL(JSON_VALUE(@json, '$.detail'), JSON_VALUE(@json, '$.title'))
                     + N' (revisar el código del país y el año).';
    ELSE IF ISJSON(@json, ARRAY) = 0
        SET @mensaje = N'el JSON no es de feriados de la API Nager.Date v3 (tiene que ser un arreglo de '
                     + N'objetos con date, localName, countryCode, global y types).';

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'DatosGenerales.usp_ProcesarFeriadosJSON: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    CREATE TABLE #staging_feriados (
        id_registro       INT IDENTITY(1,1) PRIMARY KEY,
        -- Tal como vienen en el JSON
        fecha_txt         NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
        nombre_local      NVARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
        nombre_ingles     NVARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
        iso2              NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
        global_txt        NVARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
        subdivisiones     NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
        tipos             NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
        -- Convertidos
        fecha             DATE           NULL,
        nombre            NVARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
        errores           NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
        motivo_omision    VARCHAR(60)    COLLATE DATABASE_DEFAULT NULL,
        accion            VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
    );

    -- Feriados de cada registro por país del sistema (paso 4).
    CREATE TABLE #feriados_pais (
        id_registro  INT            NOT NULL,
        id_pais      SMALLINT       NOT NULL,
        fecha        DATE           NOT NULL,
        nombre       NVARCHAR(400)  COLLATE DATABASE_DEFAULT NOT NULL
    );

    /* 2. Los registros, como vienen de la API. */
    INSERT INTO #staging_feriados (fecha_txt, nombre_local, nombre_ingles, iso2, global_txt, subdivisiones, tipos)
    SELECT NULLIF(TRIM(fecha_txt), N''),
           NULLIF(TRIM(nombre_local), N''),
           NULLIF(TRIM(nombre_ingles), N''),
           UPPER(NULLIF(TRIM(iso2), N'')),
           LOWER(NULLIF(TRIM(global_txt), N'')),
           subdivisiones,
           tipos
    FROM OPENJSON(@json)
         WITH (fecha_txt      NVARCHAR(50)  '$.date',
               nombre_local   NVARCHAR(400) '$.localName',
               nombre_ingles  NVARCHAR(400) '$.name',
               iso2           NVARCHAR(50)  '$.countryCode',
               global_txt     NVARCHAR(10)  '$.global',
               subdivisiones  NVARCHAR(MAX) '$.counties' AS JSON,
               tipos          NVARCHAR(MAX) '$.types'    AS JSON);

    /* 3. Omitidos: lo que el sistema no guarda (un registro sin país cuenta
          como de un país no registrado). */
    UPDATE s
    SET accion = 'OMITIDO', motivo_omision = 'País no registrado en el sistema'
    FROM #staging_feriados AS s
    WHERE NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p WHERE p.codigo_iso2 = s.iso2);

    UPDATE s
    SET accion = 'OMITIDO', motivo_omision = 'No es feriado público (bancario, escolar u optativo)'
    FROM #staging_feriados AS s
    WHERE s.accion IS NULL
      AND NOT EXISTS (SELECT 1 FROM OPENJSON(s.tipos) WHERE value = N'Public');

    -- Regional: no es de todo el país ni de una subdivisión que el sistema registra como país.
    UPDATE s
    SET accion = 'OMITIDO', motivo_omision = 'Feriado regional (rige solo en parte del país)'
    FROM #staging_feriados AS s
    WHERE s.accion IS NULL
      AND s.global_txt = N'false'
      AND NOT EXISTS (SELECT 1
                      FROM DatosGenerales.PAIS AS p
                      INNER JOIN @subdivisiones AS sd ON sd.codigo_fifa = p.codigo_fifa
                      WHERE p.codigo_iso2 = s.iso2
                        AND EXISTS (SELECT 1 FROM OPENJSON(s.subdivisiones) WHERE value = sd.subdivision));

    -- Conversión y errores de formato. La fecha viene como AAAA-MM-DD (estilo 23).
    UPDATE #staging_feriados
    SET fecha  = TRY_CONVERT(DATE, fecha_txt, 23),
        nombre = ISNULL(nombre_local, nombre_ingles)
    WHERE accion IS NULL;

    UPDATE #staging_feriados
    SET errores = NULLIF(CONCAT(
            IIF(fecha_txt IS NULL,
                @nl + N'- La fecha es obligatoria.', N''),
            IIF(fecha_txt IS NOT NULL AND fecha IS NULL,
                @nl + N'- La fecha "' + fecha_txt + N'" no es una fecha (AAAA-MM-DD).', N''),
            IIF(nombre IS NULL,
                @nl + N'- El nombre del feriado es obligatorio.', N''),
            IIF(LEN(nombre) > 200,
                @nl + N'- El nombre del feriado no puede superar los 200 caracteres.', N'')), N'')
    WHERE accion IS NULL;

    UPDATE #staging_feriados
    SET accion = 'RECHAZADO'
    WHERE accion IS NULL AND errores IS NOT NULL;

    /* 4. Cada registro, a los países del sistema con su código ISO. Rige en
          el país si es de todo el país (global no es false) o si es de la
          subdivisión que el sistema registra como país (Inglaterra y Escocia
          dentro del Reino Unido). */
    INSERT INTO #feriados_pais (id_registro, id_pais, fecha, nombre)
    SELECT s.id_registro, p.id_pais, s.fecha, s.nombre
    FROM #staging_feriados AS s
    INNER JOIN DatosGenerales.PAIS AS p ON p.codigo_iso2 = s.iso2
    LEFT JOIN @subdivisiones AS sd ON sd.codigo_fifa = p.codigo_fifa
    WHERE s.accion IS NULL
      AND (s.global_txt IS DISTINCT FROM N'false'
           OR EXISTS (SELECT 1 FROM OPENJSON(s.subdivisiones) WHERE value = sd.subdivision));

    /* Dos feriados del mismo país y día van en un solo registro, con los
       nombres juntos. Si juntos superan los 200 caracteres se rechazan. */
    WITH dias AS (
        SELECT fp.id_pais, fp.fecha,
               STRING_AGG(fp.nombre, N' / ') WITHIN GROUP (ORDER BY fp.nombre) AS nombre
        FROM (SELECT DISTINCT id_pais, fecha, nombre FROM #feriados_pais) AS fp
        GROUP BY fp.id_pais, fp.fecha
    )
    UPDATE s
    SET accion = 'RECHAZADO',
        errores = @nl + N'- Con los otros feriados del mismo día, el nombre supera los 200 caracteres.'
    FROM #staging_feriados AS s
    WHERE s.accion IS NULL
      AND EXISTS (SELECT 1 FROM #feriados_pais AS fp
                  INNER JOIN dias AS d ON d.id_pais = fp.id_pais AND d.fecha = fp.fecha
                  WHERE fp.id_registro = s.id_registro AND LEN(d.nombre) > 200);

    /* 5. Carga de los válidos, todos juntos, con el SP de la Entrega 5. */
    INSERT INTO @validos (id_pais, fecha, nombre)
    SELECT fp.id_pais, fp.fecha, STRING_AGG(fp.nombre, N' / ') WITHIN GROUP (ORDER BY fp.nombre)
    FROM (SELECT DISTINCT f.id_pais, f.fecha, f.nombre
          FROM #feriados_pais AS f
          INNER JOIN #staging_feriados AS s ON s.id_registro = f.id_registro
          WHERE s.accion IS NULL) AS fp
    GROUP BY fp.id_pais, fp.fecha;

    IF EXISTS (SELECT 1 FROM @validos)
        EXEC DatosGenerales.usp_ImportarFeriados
            @feriados     = @validos,
            @insertados   = @insertados   OUTPUT,
            @actualizados = @actualizados OUTPUT,
            @sin_cambios  = @sin_cambios  OUTPUT;

    /* 6. Resultado. */
    SELECT @leidos     = COUNT(*),
           @omitidos   = ISNULL(SUM(IIF(accion = 'OMITIDO',   1, 0)), 0),
           @rechazados = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
    FROM #staging_feriados;

    IF @mostrar = 1
    BEGIN
        SELECT @origen AS origen, @leidos AS leidos, @insertados AS insertados, @actualizados AS actualizados,
               @sin_cambios AS sin_cambios, @omitidos AS omitidos, @rechazados AS rechazados;

        SELECT motivo_omision AS omitidos_por, COUNT(*) AS registros
        FROM #staging_feriados
        WHERE accion = 'OMITIDO'
        GROUP BY motivo_omision
        ORDER BY registros DESC;

        SELECT CONCAT(ISNULL(iso2, N'(sin país)'), N' ', ISNULL(fecha_txt, N'(sin fecha)'),
                      IIF(nombre IS NULL, N'', N' - ' + LEFT(nombre, 60))) AS rechazado,
               STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_feriados
        WHERE accion = 'RECHAZADO'
        ORDER BY rechazado;
    END;
END;
GO


/* ============================================================================
   IMPORTACIÓN DESDE LA API
   ============================================================================ */

/*
  usp_ImportarFeriadosAPI
  Consulta la API Nager.Date v3 con usp_ConsumirAPI por los feriados de
  @anio del país con código ISO alfa-2 @codigo_iso2, y procesa la respuesta
  con usp_ProcesarFeriadosJSON (@mostrar y los OUTPUT son los de ese SP).
  Por defecto trae los del año actual. Para varios países se llama una vez
  por país, como hace 29_ImportarCotizacionesYFeriados.sql.
  Valida: código ISO de 2 letras y de algún país del sistema; año entre 1960
  y el siguiente al actual. Si la API no tiene feriados de ese país (responde
  sin contenido, HTTP 204), no responde, responde con otro código HTTP
  distinto de 200 o no devuelve un JSON válido, no se importa nada (THROW
  50002): los feriados de un país que la API no cubre se cargan con
  usp_FERIADO_Alta o usp_ImportarFeriados.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarFeriadosAPI
    @codigo_iso2   VARCHAR(10),
    @anio          SMALLINT = NULL,
    @mostrar       BIT      = 1,
    @leidos        INT      = NULL OUTPUT,
    @insertados    INT      = NULL OUTPUT,
    @actualizados  INT      = NULL OUTPUT,
    @sin_cambios   INT      = NULL OUTPUT,
    @omitidos      INT      = NULL OUTPUT,
    @rechazados    INT      = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @anio_actual  SMALLINT       = YEAR(GETDATE());
    DECLARE @paises       NVARCHAR(400);
    DECLARE @url          NVARCHAR(1000);
    DECLARE @estado_http  SMALLINT;
    DECLARE @respuesta    NVARCHAR(MAX);
    DECLARE @mensaje      NVARCHAR(2048);

    SET @codigo_iso2 = UPPER(NULLIF(TRIM(@codigo_iso2), ''));
    SET @anio        = ISNULL(@anio, @anio_actual);

    SELECT @paises = STRING_AGG(nombre, ' y ') WITHIN GROUP (ORDER BY nombre)
    FROM DatosGenerales.PAIS
    WHERE codigo_iso2 = @codigo_iso2;

    /* El código va dentro de la URL: solo se aceptan dos letras, para que no
       se pueda alterar la consulta. */
    IF @codigo_iso2 IS NULL
        SET @errores += @nl + N'- El código ISO alfa-2 del país es obligatorio (ej. AR).';
    ELSE IF @codigo_iso2 COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z]'
        SET @errores += @nl + N'- El código ISO alfa-2 debe tener 2 letras.';
    ELSE IF @paises IS NULL
        SET @errores += @nl + N'- No hay ningún país del sistema con código ISO alfa-2 "' + @codigo_iso2 + N'".';

    IF @anio NOT BETWEEN 1960 AND @anio_actual + 1
        SET @errores += @nl + N'- El año debe estar entre 1960 y ' + CAST(@anio_actual + 1 AS NVARCHAR(4)) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_ImportarFeriadosAPI: no se pudo consultar la API.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SET @url = CONCAT(N'https://date.nager.at/api/v3/PublicHolidays/', @anio, N'/', @codigo_iso2);

    BEGIN TRY
        EXEC DatosGenerales.usp_ConsumirAPI @url = @url, @estado_http = @estado_http OUTPUT, @respuesta = @respuesta OUTPUT;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'falló la consulta a la API: ' + ERROR_MESSAGE();
    END CATCH;

    /* 204: la API no cubre ese país. Con un pedido inválido responde 4xx y un
       JSON con el motivo en detail. */
    IF @mensaje IS NULL AND @estado_http = 204
        SET @mensaje = N'la API no tiene feriados de ' + @paises + N' (' + @codigo_iso2 + N'): '
                     + N'hay que cargarlos con DatosGenerales.usp_FERIADO_Alta.';
    ELSE IF @mensaje IS NULL AND @estado_http <> 200
        SET @mensaje = N'la API respondió con el código HTTP ' + CAST(@estado_http AS NVARCHAR(5))
                     + ISNULL(N': ' + IIF(ISJSON(@respuesta) = 1, JSON_VALUE(@respuesta, '$.detail'), NULL), N'')
                     + N'.';

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'DatosGenerales.usp_ImportarFeriadosAPI: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    EXEC DatosGenerales.usp_ProcesarFeriadosJSON
        @json         = @respuesta,
        @origen       = @url,
        @mostrar      = @mostrar,
        @leidos       = @leidos       OUTPUT,
        @insertados   = @insertados   OUTPUT,
        @actualizados = @actualizados OUTPUT,
        @sin_cambios  = @sin_cambios  OUTPUT,
        @omitidos     = @omitidos     OUTPUT,
        @rechazados   = @rechazados   OUTPUT;
END;
GO


-- Evidencia: SP de importación de feriados creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'DatosGenerales'
  AND p.name IN (N'usp_ProcesarFeriadosJSON', N'usp_ImportarFeriadosAPI')
ORDER BY p.name;
GO
