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
 Archivo: 27_SP_Importar_Cotizaciones.sql
 Objetivo: Crear el proceso de importación de cotizaciones de monedas desde
           la API Frankfurter, con las que se factura la publicidad en otra
           moneda (las tarifas de los espacios están en dólares). Los SP, en
           el orden en que se crean (primero el que usa el otro):
             DatosGenerales.usp_ProcesarCotizacionesJSON  valida la respuesta de la API y carga sus registros
             DatosGenerales.usp_ImportarCotizacionesAPI   consulta la API y procesa la respuesta
           El pedido a la API lo hace DatosGenerales.usp_ConsumirAPI
           (22_SP_ConsumirAPI.sql).
           Requiere haber ejecutado 00 a 22. Su script de testing es
           77_Test_SP_Importar_Cotizaciones.sql.
================================================================================

 Fuente: API Frankfurter v2, sin clave (ver datos/fuentes/frankfurter/README.md).
 Responde en JSON: un arreglo con un objeto por moneda y fecha, con la fecha
 (date), la moneda base (base, siempre USD porque se pide así), la moneda
 cotizada (quote, ISO 4217) y cuántas unidades de esa moneda vale un dólar
 (rate). Ej.:
   [{"date":"2026-06-11","base":"USD","quote":"ARS","rate":1436.11}, ...]

 Cómo importa usp_ProcesarCotizacionesJSON (los pasos tienen el mismo número
 en el código):
   1. Se controla el documento: que sea JSON, que no sea un mensaje de error
      de la API y que sea un arreglo. Si no, no se importa nada.
   2. OPENJSON pasa los registros, tal como vienen, a la tabla de staging
      #staging_cotizaciones, y ahí se convierten (TRY_CONVERT). Todas las
      transformaciones se hacen acá, en T-SQL.
   3. Antes de cargar, cada registro puede quedar:
        OMITIDO      si es el dólar contra sí mismo (vale siempre 1) o si
                     repite otro registro con el mismo valor. No es un error.
        RECHAZADO    si no es una cotización contra el dólar, si la moneda no
                     es un código de 3 letras, si la fecha no es una fecha o
                     es futura, si el valor no es un número mayor que cero, o
                     si viene la misma moneda y fecha con valores distintos
                     (no se sabe cuál es el correcto).
   4. Los demás se cargan todos juntos con el SP de la Entrega 5
      DatosGenerales.usp_ImportarCotizaciones (16_SP_Importacion.sql), que
      recibe un parámetro de tipo tabla y hace el upsert sin recorrerlos de a
      uno. Como el paso 3 aplica las mismas reglas que ese SP, los registros
      válidos se cargan aunque haya otros rechazados.
   5. Se devuelve el resumen, los omitidos por motivo y los rechazados con
      sus motivos.
   La carga es un solo upsert, así que la importación puede correr dentro de
   una transacción (los tests la deshacen con ROLLBACK).

 Criterios del upsert (los de usp_ImportarCotizaciones):
   - Clave natural: moneda y fecha. Cada día es un registro, así que se
     conserva la serie histórica.
   - Si la fuente corrige el valor de un día, se actualiza ese día y su
     fecha_actualizacion. Importar dos veces lo mismo no cambia nada.
   - Los días sin cotización (fines de semana, feriados bancarios) no se
     inventan: DatosGenerales.fn_CotizacionVigente usa la última anterior.
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
  usp_ProcesarCotizacionesJSON
  Importa una respuesta de la API Frankfurter v2 (/v2/rates con base=USD).
  La llama usp_ImportarCotizacionesAPI. @origen es la URL o el texto que
  identifica de dónde salió, para el resumen. Devuelve el resumen (leídos,
  insertados, actualizados, sin cambios, omitidos y rechazados), los
  omitidos por motivo y los rechazados con sus motivos.
  Si el documento no es JSON, es un mensaje de error de la API o no es un
  arreglo de cotizaciones, no se importa nada (THROW 50002).
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ProcesarCotizacionesJSON
    @json    NVARCHAR(MAX),
    @origen  NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @nl            NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @hoy           DATE     = CONVERT(DATE, GETDATE());
    DECLARE @mensaje       NVARCHAR(2048);
    DECLARE @validas       DatosGenerales.TT_COTIZACION;
    DECLARE @insertados    INT = 0;
    DECLARE @actualizados  INT = 0;
    DECLARE @sin_cambios   INT = 0;

    /* 1. El documento.
          Si la API rechaza el pedido responde un objeto con status y message
          en vez del arreglo. */
    IF ISJSON(@json) IS DISTINCT FROM 1
        SET @mensaje = N'el documento no es un JSON válido (puede ser una respuesta incompleta).';
    ELSE IF JSON_VALUE(@json, '$.message') IS NOT NULL
        SET @mensaje = N'la API Frankfurter devolvió un error: ' + JSON_VALUE(@json, '$.message')
                     + N' (revisar las monedas y las fechas).';
    ELSE IF ISJSON(@json, ARRAY) = 0
        SET @mensaje = N'el JSON no es de cotizaciones de la API Frankfurter v2 (tiene que ser un arreglo '
                     + N'de objetos con date, base, quote y rate).';

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'DatosGenerales.usp_ProcesarCotizacionesJSON: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    CREATE TABLE #staging_cotizaciones (
        id_registro       INT IDENTITY(1,1) PRIMARY KEY,
        -- Tal como vienen en el JSON
        fecha_txt         NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
        base_txt          NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
        moneda            NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
        valor_txt         NVARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        -- Convertidos
        fecha             DATE           NULL,
        valor             DECIMAL(19,6)  NULL,
        errores           NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
        motivo_omision    VARCHAR(60)    COLLATE DATABASE_DEFAULT NULL,
        accion            VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
    );

    /* 2. Los registros, como vienen de la API. */
    INSERT INTO #staging_cotizaciones (fecha_txt, base_txt, moneda, valor_txt)
    SELECT NULLIF(TRIM(fecha_txt), N''),
           UPPER(NULLIF(TRIM(base_txt), N'')),
           UPPER(NULLIF(TRIM(moneda), N'')),
           NULLIF(TRIM(valor_txt), N'')
    FROM OPENJSON(@json)
         WITH (fecha_txt  NVARCHAR(50)  '$.date',
               base_txt   NVARCHAR(50)  '$.base',
               moneda     NVARCHAR(50)  '$.quote',
               valor_txt  NVARCHAR(100) '$.rate');

    /* 3. Omitidos: el dólar contra sí mismo. */
    UPDATE #staging_cotizaciones
    SET accion = 'OMITIDO', motivo_omision = 'Dólar contra dólar (vale siempre 1)'
    WHERE base_txt = N'USD' AND moneda = N'USD';

    /* Conversión y errores de formato. La fecha viene como AAAA-MM-DD (estilo
       23). El valor puede venir en notación científica (1.5e-05), que
       DECIMAL no acepta: en ese caso se convierte pasando por FLOAT. */
    UPDATE #staging_cotizaciones
    SET fecha = TRY_CONVERT(DATE, fecha_txt, 23),
        valor = ISNULL(TRY_CONVERT(DECIMAL(19,6), valor_txt),
                       TRY_CONVERT(DECIMAL(19,6), TRY_CONVERT(FLOAT, valor_txt)))
    WHERE accion IS NULL;

    UPDATE #staging_cotizaciones
    SET errores = NULLIF(CONCAT(
            IIF(base_txt IS DISTINCT FROM N'USD',
                @nl + N'- La cotización es contra ' + ISNULL(base_txt, N'(sin moneda base)')
                + N' y no contra el dólar (la URL tiene que pedir base=USD).', N''),
            IIF(moneda IS NULL,
                @nl + N'- La moneda es obligatoria.', N''),
            IIF(moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]',
                @nl + N'- La moneda "' + moneda + N'" no es un código de 3 letras (ISO 4217).', N''),
            IIF(fecha_txt IS NULL,
                @nl + N'- La fecha es obligatoria.', N''),
            IIF(fecha_txt IS NOT NULL AND fecha IS NULL,
                @nl + N'- La fecha "' + fecha_txt + N'" no es una fecha (AAAA-MM-DD).', N''),
            IIF(fecha > @hoy,
                @nl + N'- La fecha ' + CONVERT(NVARCHAR(10), fecha, 103) + N' es futura.', N''),
            IIF(valor_txt IS NULL,
                @nl + N'- El valor es obligatorio.', N''),
            IIF(valor_txt IS NOT NULL AND valor IS NULL,
                @nl + N'- El valor "' + valor_txt + N'" no es un número (o tiene más de 13 dígitos enteros).', N''),
            IIF(valor <= 0,
                @nl + N'- El valor tiene que ser mayor que cero.', N'')), N'')
    WHERE accion IS NULL;

    /* Misma moneda y fecha más de una vez: con el mismo valor se importa una
       vez y las copias se omiten; con valores distintos no se sabe cuál es el
       correcto y se rechazan todas. */
    WITH repetidos AS (
        SELECT accion, motivo_omision, errores,
               COUNT(*)   OVER (PARTITION BY moneda, fecha) AS veces,
               MIN(valor) OVER (PARTITION BY moneda, fecha) AS valor_minimo,
               MAX(valor) OVER (PARTITION BY moneda, fecha) AS valor_maximo,
               ROW_NUMBER() OVER (PARTITION BY moneda, fecha ORDER BY id_registro) AS copia
        FROM #staging_cotizaciones
        WHERE accion IS NULL AND errores IS NULL
    )
    UPDATE repetidos
    SET errores        = IIF(valor_minimo <> valor_maximo,
                             @nl + N'- La respuesta trae ' + CAST(veces AS NVARCHAR(10))
                             + N' veces esta moneda y fecha, con valores distintos: no se sabe cuál es el correcto.',
                             NULL),
        accion         = IIF(valor_minimo = valor_maximo AND copia > 1, 'OMITIDO', NULL),
        motivo_omision = IIF(valor_minimo = valor_maximo AND copia > 1, 'Repetido con el mismo valor', NULL)
    WHERE veces > 1;

    UPDATE #staging_cotizaciones
    SET accion = 'RECHAZADO'
    WHERE accion IS NULL AND errores IS NOT NULL;

    /* 4. Carga de los válidos, todos juntos, con el SP de la Entrega 5. */
    INSERT INTO @validas (codigo_moneda, fecha, unidades_por_usd)
    SELECT moneda, fecha, valor
    FROM #staging_cotizaciones
    WHERE accion IS NULL;

    IF EXISTS (SELECT 1 FROM @validas)
        EXEC DatosGenerales.usp_ImportarCotizaciones
            @cotizaciones = @validas,
            @insertados   = @insertados   OUTPUT,
            @actualizados = @actualizados OUTPUT,
            @sin_cambios  = @sin_cambios  OUTPUT;

    /* 5. Resultado. */
    SELECT @origen AS origen,
           COUNT(*)                                          AS leidos,
           @insertados                                       AS insertados,
           @actualizados                                     AS actualizados,
           @sin_cambios                                      AS sin_cambios,
           ISNULL(SUM(IIF(accion = 'OMITIDO',   1, 0)), 0)   AS omitidos,
           ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)   AS rechazados
    FROM #staging_cotizaciones;

    SELECT motivo_omision AS omitidos_por, COUNT(*) AS registros
    FROM #staging_cotizaciones
    WHERE accion = 'OMITIDO'
    GROUP BY motivo_omision
    ORDER BY registros DESC;

    SELECT CONCAT(ISNULL(moneda, N'(sin moneda)'), N' ', ISNULL(fecha_txt, N'(sin fecha)')) AS rechazado,
           STUFF(errores, 1, 2, N'') AS motivos
    FROM #staging_cotizaciones
    WHERE accion = 'RECHAZADO'
    ORDER BY rechazado;
END;
GO


/* ============================================================================
   IMPORTACIÓN DESDE LA API
   ============================================================================ */

/*
  usp_ImportarCotizacionesAPI
  Consulta la API Frankfurter v2 con usp_ConsumirAPI por las cotizaciones
  contra el dólar de @monedas entre @fecha_desde y @fecha_hasta, y procesa la
  respuesta con usp_ProcesarCotizacionesJSON.
  Por defecto trae las monedas de todos los países del sistema (menos el
  dólar) de los últimos 30 días. @monedas va con los códigos ISO 4217
  separados por punto y coma (ej. 'ARS;EUR'); la API rechaza el pedido
  completo si alguno no existe.
  Valida: monedas solo con letras y punto y coma; que haya alguna moneda para
  consultar; fecha hasta no futura; fecha desde no mayor que la fecha hasta y
  a no más de un año (366 días), para que la respuesta no sea demasiado
  grande. Si la API no responde, responde con un código HTTP distinto de 200
  o no devuelve un JSON válido, no se importa nada (THROW 50002).
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarCotizacionesAPI
    @fecha_desde  DATE         = NULL,
    @fecha_hasta  DATE         = NULL,
    @monedas      VARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @hoy          DATE           = CONVERT(DATE, GETDATE());
    DECLARE @url          NVARCHAR(1000);
    DECLARE @estado_http  SMALLINT;
    DECLARE @respuesta    NVARCHAR(MAX);
    DECLARE @mensaje      NVARCHAR(2048);

    SET @monedas     = UPPER(NULLIF(REPLACE(@monedas, ' ', ''), ''));
    SET @fecha_hasta = ISNULL(@fecha_hasta, @hoy);
    SET @fecha_desde = ISNULL(@fecha_desde, DATEADD(DAY, -30, @fecha_hasta));

    -- Sin monedas indicadas, las de los países del sistema.
    IF @monedas IS NULL
        SELECT @monedas = STRING_AGG(m.codigo_moneda, ';') WITHIN GROUP (ORDER BY m.codigo_moneda)
        FROM (SELECT DISTINCT codigo_moneda FROM DatosGenerales.PAIS
              WHERE codigo_moneda IS NOT NULL AND codigo_moneda <> 'USD') AS m;

    /* Las monedas van dentro de la URL: solo se aceptan letras y punto y
       coma, para que no se pueda alterar la consulta. Las reglas de cada
       registro las aplica la importación. */
    IF @monedas IS NULL
        SET @errores += @nl + N'- No hay monedas para consultar: ningún país del sistema tiene moneda distinta del dólar.';
    ELSE IF @monedas COLLATE Latin1_General_BIN LIKE '%[^A-Z;]%'
        SET @errores += @nl + N'- Las monedas van con su código ISO 4217, separadas por punto y coma (ej. ARS;EUR).';

    IF @fecha_hasta > @hoy
        SET @errores += @nl + N'- La fecha hasta no puede ser futura.';
    IF @fecha_desde > @fecha_hasta
        SET @errores += @nl + N'- La fecha desde no puede ser mayor que la fecha hasta.';
    ELSE IF DATEDIFF(DAY, @fecha_desde, @fecha_hasta) > 366
        SET @errores += @nl + N'- El rango no puede superar un año (366 días): para más, importarlo en partes.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_ImportarCotizacionesAPI: no se pudo consultar la API.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SET @url = CONCAT(N'https://api.frankfurter.dev/v2/rates?base=USD&quotes=', REPLACE(@monedas, ';', ','),
                      N'&from=', CONVERT(CHAR(10), @fecha_desde, 23),
                      N'&to=', CONVERT(CHAR(10), @fecha_hasta, 23));

    BEGIN TRY
        EXEC DatosGenerales.usp_ConsumirAPI @url = @url, @estado_http = @estado_http OUTPUT, @respuesta = @respuesta OUTPUT;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'falló la consulta a la API: ' + ERROR_MESSAGE();
    END CATCH;

    -- Con un pedido inválido la API responde 4xx y un JSON con el motivo en message.
    IF @mensaje IS NULL AND @estado_http <> 200
        SET @mensaje = N'la API respondió con el código HTTP ' + CAST(@estado_http AS NVARCHAR(5))
                     + ISNULL(N': ' + IIF(ISJSON(@respuesta) = 1, JSON_VALUE(@respuesta, '$.message'), NULL), N'')
                     + N'.';

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'DatosGenerales.usp_ImportarCotizacionesAPI: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    EXEC DatosGenerales.usp_ProcesarCotizacionesJSON @json = @respuesta, @origen = @url;
END;
GO


-- Evidencia: SP de importación de cotizaciones creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'DatosGenerales'
  AND p.name IN (N'usp_ProcesarCotizacionesJSON', N'usp_ImportarCotizacionesAPI')
ORDER BY p.name;
GO
