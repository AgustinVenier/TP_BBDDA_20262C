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
           poder adquisitivo de cada mercado. Se importa consultando la API,
           que responde en XML. Los SP, en el orden en que se crean (primero
           el que usa el otro):
             DatosGenerales.usp_ProcesarIndicadoresXML  valida el XML de la API y carga sus registros
             DatosGenerales.usp_ImportarIndicadoresAPI  consulta la API y procesa la respuesta
           El pedido a la API lo hace DatosGenerales.usp_ConsumirAPI
           (22_SP_ConsumirAPI.sql).
           Requiere haber ejecutado 01 a 22. Su script de testing es
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
      #staging_indicadores, y ahí se convierten (TRY_CONVERT). La respuesta
      se importa tal como la entrega la API: todas las transformaciones se
      hacen acá, en T-SQL.
   3. Antes de cargar, cada registro puede quedar:
        OMITIDO      si es de un país que el sistema no tiene registrado (la
                     API trae todos los países y también agregados como
                     "World" o "High income"), si no tiene valor (el Banco
                     Mundial todavía no lo publicó) o si repite otro registro
                     de la respuesta con el mismo valor (si ese registro se
                     rechaza en el paso 4, la copia también). No es un error.
        RECHAZADO    si el año o el valor no son números.
      Cada regla es un UPDATE sobre toda la tabla de staging, que anota el
      motivo en los registros que no la cumplen.
   4. El SP de la Entrega 5 DatosGenerales.usp_ImportarIndicadoresEconomicos
      (16_SP_Importacion.sql) lee #staging_indicadores, valida los demás con
      las reglas de los indicadores y rechaza los que no las cumplen (sin
      año o código de indicador, año fuera de 1960 al actual, código de
      indicador de más de 30 caracteres o con caracteres no admitidos, o el
      mismo país, indicador y año con valores distintos), y hace el upsert
      de los válidos, todos juntos. En la misma transacción se registra la
      importación (DatosGenerales.IMPORTACION, su número queda en
      @id_importacion) y los rechazados, en
      DatosGenerales.ERRORES_INDICADOR_ECONOMICO.
   5. Se devuelve el resumen, los omitidos por motivo y los rechazados con
      sus motivos.
   La importación puede correr dentro de una transacción del que la llama
   (los tests la deshacen con ROLLBACK).

 Criterios del upsert (los de usp_ImportarIndicadoresEconomicos):
   - Clave natural: país (ISO alfa-3), indicador y año.
   - Inglaterra y Escocia comparten el código GBR: el valor se registra para
     las dos.
   - Cada año es un registro, así que la serie histórica se conserva. Si el
     Banco Mundial revisa el valor de un año, se actualiza ese año y su
     fecha_actualizacion. Un valor que no viene no borra el guardado.
   - Importar dos veces la misma respuesta no cambia nada.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   PROCESAMIENTO DEL XML (lo usa el SP de abajo)
   ============================================================================ */

/*
  usp_ProcesarIndicadoresXML
  Importa un documento de la API de indicadores del Banco Mundial. Lo
  llama usp_ImportarIndicadoresAPI. @origen es la URL o el texto que
  identifica de dónde salió y @proceso, el SP que importa (el
  que lo llama; si no viene, este). Registra la importación (su número
  queda en @id_importacion) y los rechazados en
  DatosGenerales.ERRORES_INDICADOR_ECONOMICO, y devuelve el resumen (leídos,
  insertados, actualizados, sin cambios, omitidos y rechazados), los
  omitidos por motivo y los rechazados con sus motivos.
  Si el documento no es de datos del Banco Mundial, es un mensaje de error
  de la API o le faltan páginas, no se importa nada (THROW 50002).
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ProcesarIndicadoresXML
    @xml             XML,
    @origen          NVARCHAR(2000),
    @proceso         VARCHAR(100) = NULL,
    @id_importacion  INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @nl            NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @mensaje       NVARCHAR(2048);
    DECLARE @raices        INT;
    DECLARE @es_error_api  BIT;
    DECLARE @error_api     NVARCHAR(400);
    DECLARE @pagina        INT;
    DECLARE @paginas       INT;
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
          Raíz wb:data con page y pages; si la API rechaza el pedido, la raíz
          es wb:error con el motivo en wb:message. */
    WITH XMLNAMESPACES ('http://www.worldbank.org' AS wb)
    SELECT @raices       = @xml.value('count(/*)', 'INT'),
           @es_error_api = @xml.exist('/wb:error'),
           @error_api    = @xml.value('(/wb:error/wb:message)[1]', 'NVARCHAR(400)'),
           @pagina       = @xml.value('(/wb:data/@page)[1]', 'INT'),
           @paginas      = @xml.value('(/wb:data/@pages)[1]', 'INT');

    IF @es_error_api = 1
        SET @mensaje = N'la API del Banco Mundial devolvió un error: ' + ISNULL(@error_api, N'(sin mensaje)')
                     + N' (revisar el código del indicador, los países y los años).';
    ELSE IF ISNULL(@raices, 0) <> 1 OR @paginas IS NULL
        SET @mensaje = N'el XML no es de datos de la API del Banco Mundial (tiene que tener un solo '
                     + N'elemento raíz wb:data, del espacio de nombres http://www.worldbank.org).';
    ELSE IF @paginas > 1
        SET @mensaje = N'el XML es la página ' + CAST(@pagina AS NVARCHAR(10)) + N' de '
                     + CAST(@paginas AS NVARCHAR(10)) + N' del resultado y le faltan registros. '
                     + N'Hay que descargarlo completo, con per_page=20000 en la URL.';

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'DatosGenerales.usp_ProcesarIndicadoresXML: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    -- usp_ImportarIndicadoresEconomicos lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_indicadores (
        id_registro       INT IDENTITY(1,1) PRIMARY KEY,
        -- Tal como vienen en el XML
        pais_txt          NVARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,
        anio_txt          NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
        valor_txt         NVARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        -- Lo que lee usp_ImportarIndicadoresEconomicos, ya convertido
        codigo_iso3       NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
        codigo_indicador  NVARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        anio              SMALLINT       NULL,
        valor             DECIMAL(18,4)  NULL,
        -- Lo que le pasa a cada registro: lo completan este SP y usp_ImportarIndicadoresEconomicos
        errores           NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
        motivo_omision    VARCHAR(60)    COLLATE DATABASE_DEFAULT NULL,
        copia_de          INT            NULL,      -- un repetido con el mismo valor: el registro que se importa en su lugar
        accion            VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
    );

    /* 2. Los registros, como vienen de la api. */
    WITH XMLNAMESPACES ('http://www.worldbank.org' AS wb)
    INSERT INTO #staging_indicadores (codigo_indicador, pais_txt, codigo_iso3, anio_txt, valor_txt)
    SELECT UPPER(NULLIF(TRIM(d.value('(wb:indicator/@id)[1]', 'NVARCHAR(100)')), N'')),
           NULLIF(TRIM(d.value('(wb:country)[1]', 'NVARCHAR(200)')), N''),
           UPPER(NULLIF(TRIM(d.value('(wb:countryiso3code)[1]', 'NVARCHAR(50)')), N'')),
           NULLIF(TRIM(d.value('(wb:date)[1]', 'NVARCHAR(50)')), N''),
           NULLIF(TRIM(d.value('(wb:value)[1]', 'NVARCHAR(100)')), N'')
    FROM @xml.nodes('/wb:data/wb:data') AS t(d);

    /* 3. Omitidos: lo que el sistema no guarda. */
    UPDATE i
    SET accion = 'OMITIDO', motivo_omision = 'País no registrado en el sistema o agregado regional'
    FROM #staging_indicadores AS i
    WHERE NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p WHERE p.codigo_iso3 = i.codigo_iso3);

    UPDATE #staging_indicadores
    SET accion = 'OMITIDO', motivo_omision = 'Sin valor publicado para ese año'
    WHERE accion IS NULL AND valor_txt IS NULL;

    -- Conversión y lo que no se pudo convertir. Las reglas de los indicadores las aplica
    -- usp_ImportarIndicadoresEconomicos.
    UPDATE #staging_indicadores
    SET anio  = TRY_CONVERT(SMALLINT, anio_txt),
        valor = TRY_CONVERT(DECIMAL(18,4), valor_txt)
    WHERE accion IS NULL;

    UPDATE #staging_indicadores
    SET errores = NULLIF(CONCAT(
            IIF(anio_txt IS NOT NULL AND anio IS NULL,
                @nl + N'- El año "' + anio_txt + N'" no es un año (AAAA): el sistema guarda indicadores anuales.', NULL),
            IIF(valor IS NULL,
                @nl + N'- El valor "' + valor_txt + N'" no es un número (o tiene más de 14 dígitos enteros).', NULL)), N'')
    WHERE accion IS NULL;

    UPDATE #staging_indicadores
    SET accion = 'RECHAZADO'
    WHERE accion IS NULL AND errores IS NOT NULL;

    -- Mismo país, indicador y año más de una vez con el mismo valor: se importa una vez y las
    -- copias se omiten (si ese registro se rechaza, las copias también, en el paso 4). Con
    -- valores distintos los rechaza usp_ImportarIndicadoresEconomicos.
    WITH repetidos AS (
        SELECT accion, motivo_omision, copia_de,
               MIN(valor) OVER (PARTITION BY codigo_iso3, codigo_indicador, anio) AS valor_minimo,
               MAX(valor) OVER (PARTITION BY codigo_iso3, codigo_indicador, anio) AS valor_maximo,
               MIN(id_registro) OVER (PARTITION BY codigo_iso3, codigo_indicador, anio) AS primero,
               ROW_NUMBER() OVER (PARTITION BY codigo_iso3, codigo_indicador, anio ORDER BY id_registro) AS copia
        FROM #staging_indicadores
        WHERE accion IS NULL AND codigo_indicador IS NOT NULL AND anio IS NOT NULL
    )
    UPDATE repetidos
    SET accion = 'OMITIDO', motivo_omision = 'Repetido en la respuesta con el mismo valor', copia_de = primero
    WHERE copia > 1 AND valor_minimo = valor_maximo;

    /* 4. El SP de la Entrega 5 valida los demás y carga los válidos, todos juntos; después se
          registran la importación y sus rechazados, en la misma transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC DatosGenerales.usp_ImportarIndicadoresEconomicos;

        -- Las copias de un registro que se rechazó también se rechazan, con sus mismos motivos.
        UPDATE c
        SET accion = 'RECHAZADO', motivo_omision = NULL, errores = r.errores
        FROM #staging_indicadores AS c
        INNER JOIN #staging_indicadores AS r ON r.id_registro = c.copia_de
        WHERE c.accion = 'OMITIDO' AND r.accion = 'RECHAZADO';

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @omitidos     = ISNULL(SUM(IIF(accion = 'OMITIDO', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_indicadores;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @origen, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @omitidos = @omitidos,
            @rechazados = @rechazados, @id_importacion = @id_importacion OUTPUT;

        INSERT INTO DatosGenerales.ERRORES_INDICADOR_ECONOMICO (id_importacion, registro, codigo_indicador, pais,
                                                                codigo_iso3, anio, valor, motivos)
        SELECT @id_importacion, id_registro, codigo_indicador, pais_txt, codigo_iso3, anio_txt, valor_txt,
               STUFF(errores, 1, 2, N'')
        FROM #staging_indicadores
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
    FROM #staging_indicadores
    WHERE accion = 'OMITIDO'
    GROUP BY motivo_omision
    ORDER BY registros DESC;

    SELECT CONCAT(ISNULL(codigo_iso3, N'(sin país)'), N' ', ISNULL(anio, N'(sin año)'), N' ',
                  ISNULL(codigo_indicador, N'(sin indicador)'), IIF(pais IS NULL, N'', N' - ' + pais)) AS rechazado,
           motivos
    FROM DatosGenerales.ERRORES_INDICADOR_ECONOMICO
    WHERE id_importacion = @id_importacion
    ORDER BY rechazado;
END;
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
  nada (THROW 50002). El número de la importación queda en @id_importacion.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarIndicadoresAPI
    @codigo_indicador  VARCHAR(60)  = 'NY.GDP.PCAP.CD',
    @anio_desde        SMALLINT     = NULL,
    @anio_hasta        SMALLINT     = NULL,
    @paises            VARCHAR(400) = NULL,
    @id_importacion    INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @anio_actual  SMALLINT       = YEAR(GETDATE());
    DECLARE @url          NVARCHAR(2000);
    DECLARE @estado_http  SMALLINT;
    DECLARE @respuesta    NVARCHAR(MAX);
    DECLARE @xml          XML;
    DECLARE @mensaje      NVARCHAR(2048);
    DECLARE @proceso      VARCHAR(100)   = CONCAT(OBJECT_SCHEMA_NAME(@@PROCID), '.', OBJECT_NAME(@@PROCID));

    SET @codigo_indicador = UPPER(NULLIF(TRIM(@codigo_indicador), ''));
    SET @paises           = UPPER(NULLIF(REPLACE(@paises, ' ', ''), ''));
    SET @anio_hasta       = ISNULL(@anio_hasta, @anio_actual);
    SET @anio_desde       = ISNULL(@anio_desde, @anio_hasta - 9);

    /* El código y los países van dentro de la URL: solo se aceptan sus
       caracteres, para que no se pueda alterar la consulta. Las reglas de
       cada registro las aplica la importación. */
    IF @codigo_indicador IS NULL
        SET @errores += @nl + N'- El código del indicador es obligatorio (ej. NY.GDP.PCAP.CD).';
    ELSE IF @codigo_indicador COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9._]%'
        SET @errores += @nl + N'- El código del indicador solo admite letras sin acentos, números, puntos y guiones bajos.';

    IF @paises COLLATE Latin1_General_BIN LIKE '%[^A-Z;]%'
        SET @errores += @nl + N'- Los países van con su código ISO alfa-3, separados por punto y coma (ej. ARG;BRA).';

    IF @anio_desde NOT BETWEEN 1960 AND @anio_actual OR @anio_hasta NOT BETWEEN 1960 AND @anio_actual
        SET @errores += @nl + N'- Los años deben estar entre 1960 y ' + CAST(@anio_actual AS NVARCHAR(4)) + N'.';
    ELSE IF @anio_desde > @anio_hasta
        SET @errores += @nl + N'- El año desde no puede ser mayor que el año hasta.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_ImportarIndicadoresAPI: no se pudo consultar la API.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SET @url = CONCAT(N'https://api.worldbank.org/v2/country/', ISNULL(@paises, 'all'),
                      N'/indicator/', @codigo_indicador,
                      N'?date=', @anio_desde, N':', @anio_hasta, N'&per_page=20000&format=xml');

    BEGIN TRY
        EXEC DatosGenerales.usp_ConsumirAPI @url = @url, @estado_http = @estado_http OUTPUT, @respuesta = @respuesta OUTPUT;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'falló la consulta a la API: ' + ERROR_MESSAGE();
    END CATCH;

    IF @mensaje IS NULL AND (@estado_http IS NULL OR @estado_http <> 200)
        SET @mensaje = N'la API respondió con el código HTTP ' + CAST(@estado_http AS NVARCHAR(5)) + N'.';

    /* La respuesta llega como texto (UTF-16) y empieza con la declaración
       <?xml ... encoding="utf-8"?>, que SQL Server no acepta en un texto
       NVARCHAR: se le quita antes de convertirla a XML. TRY_CONVERT y no
       CAST: un XML mal formado hace fallar el CAST con un error que deja sin
       poder confirmar la transacción de quien llama, aunque esté dentro de
       TRY ... CATCH. */
    IF @mensaje IS NULL
    BEGIN
        SET @xml = TRY_CONVERT(XML, IIF(LEFT(@respuesta, 5) = N'<?xml',
                                        STUFF(@respuesta, 1, CHARINDEX(N'?>', @respuesta) + 1, N''),
                                        @respuesta));
        IF @xml IS NULL
            SET @mensaje = N'la respuesta no es un XML válido.';
    END;

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'DatosGenerales.usp_ImportarIndicadoresAPI: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    EXEC DatosGenerales.usp_ProcesarIndicadoresXML
        @xml = @xml, @origen = @url, @proceso = @proceso, @id_importacion = @id_importacion OUTPUT;
END;
GO


-- Evidencia: SP de importación de indicadores creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'DatosGenerales'
  AND p.name IN (N'usp_ProcesarIndicadoresXML', N'usp_ImportarIndicadoresAPI')
ORDER BY p.name;
GO
