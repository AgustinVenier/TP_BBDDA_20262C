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
 Archivo: 26_SP_Importar_Cotizaciones.sql
 Objetivo: Crear el proceso de importación de cotizaciones de monedas desde
           la API Frankfurter, con las que se factura la publicidad en otra
           moneda (las tarifas de los espacios están en dólares). Los SP, en
           el orden en que se crean (primero el que usa el otro):
             DatosGenerales.usp_ProcesarCotizacionesJSON  valida la respuesta de la API y carga sus registros
             DatosGenerales.usp_ImportarCotizacionesAPI   consulta la API y procesa la respuesta
           El pedido a la API lo hace DatosGenerales.usp_ConsumirAPI
           (22_SP_ConsumirAPI.sql).
           Requiere haber ejecutado 01 a 22. Su script de testing es
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
                     repite otro registro con el mismo valor (si ese registro
                     se rechaza en el paso 4, la copia también). No es un
                     error.
        RECHAZADO    si no es una cotización contra el dólar o si la fecha o
                     el valor no se pueden convertir.
   4. El SP de la Entrega 5 DatosGenerales.usp_ImportarCotizaciones
      (16_SP_Importacion.sql) lee #staging_cotizaciones, valida los demás con
      las reglas de las cotizaciones y rechaza los que no las cumplen (moneda
      que no es un código de 3 letras, fecha futura, valor que no es mayor
      que cero, o la misma moneda y fecha con valores distintos), y hace el
      upsert de los válidos, todos juntos. En la misma transacción se
      registra la importación (DatosGenerales.IMPORTACION, su número queda en
      @id_importacion) y los rechazados, en DatosGenerales.ERRORES_COTIZACION.
   5. Se devuelve el resumen, los omitidos por motivo y los rechazados con
      sus motivos.
   La importación puede correr dentro de una transacción del que la llama
   (los tests la deshacen con ROLLBACK).

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
  identifica de dónde salió y @proceso, el SP que importa (el que lo llama;
  si no viene, este). Registra la importación (su número queda en
  @id_importacion) y los rechazados en DatosGenerales.ERRORES_COTIZACION, y
  devuelve el resumen (leídos, insertados, actualizados, sin cambios,
  omitidos y rechazados), los omitidos por motivo y los rechazados con sus
  motivos.
  Si el documento no es JSON, es un mensaje de error de la API o no es un
  arreglo de cotizaciones, no se importa nada (THROW 50002).
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ProcesarCotizacionesJSON
    @json            NVARCHAR(MAX),
    @origen          NVARCHAR(1000),
    @proceso         VARCHAR(100) = NULL,
    @id_importacion  INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @nl            NCHAR(2)     = NCHAR(13) + NCHAR(10);
    DECLARE @mensaje       NVARCHAR(2048);
    DECLARE @tran_propia   BIT          = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @leidos        INT;
    DECLARE @insertados    INT;
    DECLARE @actualizados  INT;
    DECLARE @sin_cambios   INT;
    DECLARE @omitidos      INT;
    DECLARE @rechazados    INT;

    SET @proceso = ISNULL(NULLIF(TRIM(@proceso), ''), CONCAT(OBJECT_SCHEMA_NAME(@@PROCID), '.', OBJECT_NAME(@@PROCID)));
    SET @id_importacion = NULL;

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

    -- usp_ImportarCotizaciones lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_cotizaciones (
        id_registro       INT IDENTITY(1,1) PRIMARY KEY,
        -- Tal como vienen en el JSON
        fecha_txt         NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
        base_txt          NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
        valor_txt         NVARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        -- Lo que lee usp_ImportarCotizaciones, ya convertido
        codigo_moneda     NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
        fecha             DATE           NULL,
        unidades_por_usd  DECIMAL(19,6)  NULL,
        -- Lo que le pasa a cada registro: lo completan este SP y usp_ImportarCotizaciones
        errores           NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
        motivo_omision    VARCHAR(60)    COLLATE DATABASE_DEFAULT NULL,
        copia_de          INT            NULL,      -- un repetido con el mismo valor: el registro que se importa en su lugar
        accion            VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
    );

    /* 2. Los registros, como vienen de la API. */
    INSERT INTO #staging_cotizaciones (fecha_txt, base_txt, codigo_moneda, valor_txt)
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
    WHERE base_txt = N'USD' AND codigo_moneda = N'USD';

    /* Conversión y lo que no se pudo convertir. La fecha viene como AAAA-MM-DD
       (estilo 23). El valor puede venir en notación científica (1.5e-05), que
       DECIMAL no acepta: en ese caso se convierte pasando por FLOAT. Las reglas
       de las cotizaciones las aplica usp_ImportarCotizaciones. */
    UPDATE #staging_cotizaciones
    SET fecha            = TRY_CONVERT(DATE, fecha_txt, 23),
        unidades_por_usd = ISNULL(TRY_CONVERT(DECIMAL(19,6), valor_txt),
                                  TRY_CONVERT(DECIMAL(19,6), TRY_CONVERT(FLOAT, valor_txt)))
    WHERE accion IS NULL;

    UPDATE #staging_cotizaciones
    SET errores = NULLIF(CONCAT(
            IIF(base_txt IS DISTINCT FROM N'USD',
                @nl + N'- La cotización es contra ' + ISNULL(base_txt, N'(sin moneda base)')
                + N' y no contra el dólar (la URL tiene que pedir base=USD).', N''),
            IIF(fecha_txt IS NOT NULL AND fecha IS NULL,
                @nl + N'- La fecha "' + fecha_txt + N'" no es una fecha (AAAA-MM-DD).', N''),
            IIF(valor_txt IS NOT NULL AND unidades_por_usd IS NULL,
                @nl + N'- El valor "' + valor_txt + N'" no es un número (o tiene más de 13 dígitos enteros).', N'')), N'')
    WHERE accion IS NULL;

    UPDATE #staging_cotizaciones
    SET accion = 'RECHAZADO'
    WHERE accion IS NULL AND errores IS NOT NULL;

    /* Misma moneda y fecha más de una vez con el mismo valor: se importa una vez y las copias
       se omiten (si ese registro se rechaza, las copias también, en el paso 4). Con valores
       distintos las rechaza usp_ImportarCotizaciones. */
    WITH repetidos AS (
        SELECT accion, motivo_omision, copia_de,
               MIN(unidades_por_usd) OVER (PARTITION BY codigo_moneda, fecha) AS valor_minimo,
               MAX(unidades_por_usd) OVER (PARTITION BY codigo_moneda, fecha) AS valor_maximo,
               MIN(id_registro) OVER (PARTITION BY codigo_moneda, fecha) AS primero,
               ROW_NUMBER() OVER (PARTITION BY codigo_moneda, fecha ORDER BY id_registro) AS copia
        FROM #staging_cotizaciones
        WHERE accion IS NULL AND codigo_moneda IS NOT NULL AND fecha IS NOT NULL AND unidades_por_usd IS NOT NULL
    )
    UPDATE repetidos
    SET accion = 'OMITIDO', motivo_omision = 'Repetido con el mismo valor', copia_de = primero
    WHERE copia > 1 AND valor_minimo = valor_maximo;

    /* 4. El SP de la Entrega 5 valida las demás y carga las válidas, todas juntas; después se
          registran la importación y sus rechazados, en la misma transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC DatosGenerales.usp_ImportarCotizaciones;

        -- Las copias de una cotización que se rechazó también se rechazan, con sus mismos motivos.
        UPDATE c
        SET accion = 'RECHAZADO', motivo_omision = NULL, errores = r.errores
        FROM #staging_cotizaciones AS c
        INNER JOIN #staging_cotizaciones AS r ON r.id_registro = c.copia_de
        WHERE c.accion = 'OMITIDO' AND r.accion = 'RECHAZADO';

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @omitidos     = ISNULL(SUM(IIF(accion = 'OMITIDO', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_cotizaciones;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @origen, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @omitidos = @omitidos,
            @rechazados = @rechazados, @id_importacion = @id_importacion OUTPUT;

        INSERT INTO DatosGenerales.ERRORES_COTIZACION (id_importacion, registro, fecha, moneda_base, codigo_moneda, valor, motivos)
        SELECT @id_importacion, id_registro, fecha_txt, base_txt, codigo_moneda, valor_txt, STUFF(errores, 1, 2, N'')
        FROM #staging_cotizaciones
        WHERE accion = 'RECHAZADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    /* 5. Resultado. */
    SELECT @id_importacion AS id_importacion, @origen AS origen, @leidos AS leidos, @insertados AS insertados,
           @actualizados AS actualizados, @sin_cambios AS sin_cambios, @omitidos AS omitidos, @rechazados AS rechazados;

    SELECT motivo_omision AS omitidos_por, COUNT(*) AS registros
    FROM #staging_cotizaciones
    WHERE accion = 'OMITIDO'
    GROUP BY motivo_omision
    ORDER BY registros DESC;

    SELECT CONCAT(ISNULL(codigo_moneda, N'(sin moneda)'), N' ', ISNULL(fecha, N'(sin fecha)')) AS rechazado, motivos
    FROM DatosGenerales.ERRORES_COTIZACION
    WHERE id_importacion = @id_importacion
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
  o no devuelve un JSON válido, no se importa nada (THROW 50002). El número
  de la importación queda en @id_importacion.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarCotizacionesAPI
    @fecha_desde     DATE         = NULL,
    @fecha_hasta     DATE         = NULL,
    @monedas         VARCHAR(400) = NULL,
    @id_importacion  INT          = NULL OUTPUT
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
    DECLARE @proceso      VARCHAR(100)   = CONCAT(OBJECT_SCHEMA_NAME(@@PROCID), '.', OBJECT_NAME(@@PROCID));

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

    EXEC DatosGenerales.usp_ProcesarCotizacionesJSON
        @json = @respuesta, @origen = @url, @proceso = @proceso, @id_importacion = @id_importacion OUTPUT;
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
