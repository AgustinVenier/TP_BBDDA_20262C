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

 Fecha: 25/10/2026
 Archivo: 16_SP_Importacion.sql
 Objetivo: Crear los SP de lógica de negocio para la importación de datos
           externos. Cada uno hace el upsert de un dataset (inserta si es
           nuevo, actualiza si existe) desde la tabla de staging que arma el
           proceso de importación de la Entrega 6 que lo llama:
             SP                                                staging               clave natural
             DatosGenerales.usp_ImportarIndicadoresEconomicos  #staging_indicadores  país (ISO alfa-3) + indicador + año
             DatosGenerales.usp_ImportarCotizaciones           #staging_cotizaciones moneda + fecha
             DatosGenerales.usp_ImportarFeriados               #staging_feriados     país + fecha
             Torneo.usp_ImportarSedes                          #staging_sedes        nombre del estadio
             Torneo.usp_ImportarSelecciones                    #staging_selecciones  código FIFA del país
             Torneo.usp_ImportarJugadores                      #staging_jugadores    selección + apellido + nombre
             Torneo.usp_ImportarPartidos                       #staging_partidos     número de partido
             DesarrolloPartido.usp_ImportarDesarrolloPartidos  #staging_eventos      lo que pasó en cada partido
             Arbitraje.usp_ImportarArbitros                    #staging_arbitros     país + apellido + nombre
             Arbitraje.usp_ImportarDesignaciones               #staging_designaciones número de partido + árbitro
             Publicidad.usp_ImportarCampanias                  #staging_campanias    anunciante + nombre de la campaña
                                                               y #staging_piezas     (y título de cada pieza)
           Y los del registro de las importaciones (02_CrearTablas.sql):
             DatosGenerales.usp_RegistrarImportacion  registra una importación y devuelve su número
             DatosGenerales.usp_BorrarImportacion     la borra, con sus registros rechazados
           Siguen las convenciones de 10_SP_Negocio_SedesYPartidos.sql.
           Requiere haber ejecutado 00 a 15. Su script de testing es
           66_Test_SP_Importacion.sql.
================================================================================

 Cómo se usan (así lo hacen los procesos de 23 a 28):
   1. El proceso lee el archivo o la API a una tabla temporal con el nombre
      que espera el SP (#staging_sedes, por ejemplo), convierte los datos y
      marca accion = 'RECHAZADO', con el motivo en errores, los registros que
      no pudo convertir (u 'OMITIDO' los que el sistema no usa).
   2. Llama al SP, que no recibe los datos por parámetro: un SP ve las
      tablas temporales del que lo llama. El SP valida por conjuntos los
      registros con accion NULL, anota en errores los motivos de cada uno y
      los marca RECHAZADO; carga los demás, todos juntos, y los marca
      INSERTADO, ACTUALIZADO o SIN CAMBIOS.
   3. El proceso registra la importación (usp_RegistrarImportacion) y guarda
      los rechazados en la tabla ERRORES_ de lo que importó.
   Las reglas de cada tabla están una sola vez, acá; el proceso solo rechaza
   lo que no puede convertir. Así se importan los registros válidos y se
   informan los errores de los demás. No se usa un parámetro de tipo tabla
   porque es de solo lectura: el SP no podría marcar los registros.

 La tabla de staging:
   - La crea el que llama, con las columnas que usa el SP (las indica el
     comentario de cada uno), más errores NVARCHAR(MAX) y accion
     VARCHAR(15). Puede tener otras columnas, que el SP no toca.
   - Las columnas de texto llevan COLLATE DATABASE_DEFAULT: tempdb puede
     tener otra intercalación que la base.
   - Si no existe, el SP no importa nada (THROW 50001); si le falta una
     columna, falla al ejecutarse.
   - El SP normaliza ahí los datos que valida (códigos en mayúsculas, sin
     espacios de más, fases y posiciones en español) y completa errores y
     accion. Las columnas que traduce tienen que tener lugar para el valor
     en español: hasta 13 caracteres en la posición de un jugador
     (MEDIOCAMPISTA) y en la fase de un partido (DIECISEISAVOS).

 Criterios comunes:
   - Importar dos veces lo mismo no duplica nada: si el registro existe y no
     cambió, no se modifica (SIN CAMBIOS).
   - Un dato que no viene (NULL) no borra el valor guardado, así se conserva
     la información histórica ya registrada.
   - Las traducciones de valores de las fuentes (fases y posiciones en
     inglés, por ejemplo) se hacen acá, en T-SQL.
   - Una regla que depende de todo el conjunto (cupo de un grupo, tamaño de
     una lista de convocados, partidos a menos de 24 horas) se evalúa con
     los registros válidos y rechaza a los que la rompen.
   - La carga es una transacción. Si el que llama ya tiene una abierta, se
     hace dentro de esa.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Los SP de importación de a un registro de la versión anterior, por si la base los tiene.
DROP PROCEDURE IF EXISTS DatosGenerales.usp_ImportarIndicadorEconomico;
DROP PROCEDURE IF EXISTS Torneo.usp_ImportarSede;
DROP PROCEDURE IF EXISTS Torneo.usp_ImportarPartido;
DROP PROCEDURE IF EXISTS Torneo.usp_ImportarJugador;
DROP PROCEDURE IF EXISTS Arbitraje.usp_ImportarArbitro;
GO


/* ============================================================================
   REGISTRO DE LAS IMPORTACIONES
   ============================================================================ */

/*
  usp_RegistrarImportacion
  Registra una importación en DatosGenerales.IMPORTACION y devuelve su número
  en @id_importacion. La llama cada proceso de importación al terminar de
  cargar, en la misma transacción que la carga; después el proceso guarda
  sus registros rechazados en la tabla ERRORES_ que corresponde, con ese
  número. @proceso es el SP que importó y @origen, la ruta del archivo o la
  URL.
  Valida: proceso y origen obligatorios; totales obligatorios y no
  negativos; omitidos más rechazados no mayores que los leídos.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_RegistrarImportacion
    @proceso         VARCHAR(100),
    @origen          NVARCHAR(2000),
    @leidos          INT,
    @insertados      INT,
    @actualizados    INT,
    @sin_cambios     INT,
    @omitidos        INT = 0,
    @rechazados      INT,
    @id_importacion  INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores  NVARCHAR(2048) = N'';
    DECLARE @nl       NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @proceso = NULLIF(TRIM(@proceso), '');
    SET @origen  = NULLIF(TRIM(@origen), N'');

    IF @proceso IS NULL
        SET @errores += @nl + N'- El proceso es obligatorio.';
    IF @origen IS NULL
        SET @errores += @nl + N'- El origen (archivo o URL) es obligatorio.';

    IF @leidos IS NULL OR @insertados IS NULL OR @actualizados IS NULL OR @sin_cambios IS NULL
       OR @omitidos IS NULL OR @rechazados IS NULL
        SET @errores += @nl + N'- Los totales son obligatorios.';
    ELSE IF @leidos < 0 OR @insertados < 0 OR @actualizados < 0 OR @sin_cambios < 0 OR @omitidos < 0 OR @rechazados < 0
        SET @errores += @nl + N'- Los totales no pueden ser negativos.';
    ELSE IF @omitidos + @rechazados > @leidos
        SET @errores += @nl + N'- Los omitidos y los rechazados no pueden ser más que los leídos.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_RegistrarImportacion: no se registró la importación.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO DatosGenerales.IMPORTACION (proceso, origen, leidos, insertados, actualizados, sin_cambios, omitidos, rechazados)
    VALUES (@proceso, @origen, @leidos, @insertados, @actualizados, @sin_cambios, @omitidos, @rechazados);

    SET @id_importacion = SCOPE_IDENTITY();
END;
GO


/*
  usp_BorrarImportacion
  Borra del registro la importación @id_importacion, o todas las del origen
  @origen (la ruta del archivo o la URL, exacta), con sus registros
  rechazados. No toca los datos importados. Sirve para depurar el registro y
  para que los tests no dejen rastro. Si no hay ninguna, no hace nada.
  Valida: uno de los dos parámetros, y no los dos.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_BorrarImportacion
    @id_importacion  INT            = NULL,
    @origen          NVARCHAR(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores       NVARCHAR(2048);
    DECLARE @tran_propia   BIT = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @importaciones TABLE (id_importacion INT PRIMARY KEY);

    SET @origen = NULLIF(TRIM(@origen), N'');

    IF (@id_importacion IS NULL AND @origen IS NULL) OR (@id_importacion IS NOT NULL AND @origen IS NOT NULL)
    BEGIN
        SET @errores = N'DatosGenerales.usp_BorrarImportacion: no se borró nada.' + NCHAR(13) + NCHAR(10)
                     + N'- Hay que indicar la importación o el origen (uno de los dos).';
        THROW 50001, @errores, 1;
    END;

    INSERT INTO @importaciones (id_importacion)
    SELECT id_importacion
    FROM DatosGenerales.IMPORTACION
    WHERE id_importacion = @id_importacion OR origen = @origen;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        DELETE e FROM DatosGenerales.ERRORES_INDICADOR_ECONOMICO AS e
        INNER JOIN @importaciones AS i ON i.id_importacion = e.id_importacion;
        DELETE e FROM DatosGenerales.ERRORES_COTIZACION AS e
        INNER JOIN @importaciones AS i ON i.id_importacion = e.id_importacion;
        DELETE e FROM DatosGenerales.ERRORES_FERIADO AS e
        INNER JOIN @importaciones AS i ON i.id_importacion = e.id_importacion;
        DELETE e FROM Torneo.ERRORES_SEDE AS e
        INNER JOIN @importaciones AS i ON i.id_importacion = e.id_importacion;
        DELETE e FROM Torneo.ERRORES_SELECCION AS e
        INNER JOIN @importaciones AS i ON i.id_importacion = e.id_importacion;
        DELETE e FROM Torneo.ERRORES_JUGADOR AS e
        INNER JOIN @importaciones AS i ON i.id_importacion = e.id_importacion;
        DELETE e FROM Torneo.ERRORES_PARTIDO AS e
        INNER JOIN @importaciones AS i ON i.id_importacion = e.id_importacion;
        DELETE e FROM DesarrolloPartido.ERRORES_EVENTO AS e
        INNER JOIN @importaciones AS i ON i.id_importacion = e.id_importacion;
        DELETE e FROM Arbitraje.ERRORES_DESIGNACION AS e
        INNER JOIN @importaciones AS i ON i.id_importacion = e.id_importacion;
        DELETE e FROM Publicidad.ERRORES_CAMPANIA AS e
        INNER JOIN @importaciones AS i ON i.id_importacion = e.id_importacion;

        DELETE im FROM DatosGenerales.IMPORTACION AS im
        INNER JOIN @importaciones AS i ON i.id_importacion = im.id_importacion;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ============================================================================
   INDICADORES, COTIZACIONES Y FERIADOS
   Llegan de a cientos por archivo o consulta a la API (25, 27 y 28).
   ============================================================================ */

/*
  usp_ImportarIndicadoresEconomicos
  Upsert de indicadores por país, indicador y año (ej. el PBI per cápita de
  la API del Banco Mundial, NY.GDP.PCAP.CD), desde #staging_indicadores.
  Columnas que usa: codigo_iso3, codigo_indicador, anio, valor, errores y
  accion.
  El país se identifica por su código ISO alfa-3: como Inglaterra y Escocia
  comparten GBR, un registro con ese código se carga para las dos.
  Valida cada registro pendiente: país, indicador, año y valor obligatorios;
  código ISO alfa-3 de algún país; código de indicador de hasta 30
  caracteres, solo con letras sin acentos, números, puntos y guiones bajos;
  año entre 1960 y el actual; que no venga dos veces el mismo país,
  indicador y año. Con eso cubre las reglas de usp_INDICADOR_ECONOMICO_Alta
  y _Modificacion. Los valores que cambiaron se actualizan con su
  fecha_actualizacion; los que no existían se insertan. Un registro de GBR
  queda INSERTADO si le falta a alguno de los dos países, ACTUALIZADO si
  cambió en alguno y si no, SIN CAMBIOS.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarIndicadoresEconomicos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @anio_actual  SMALLINT = YEAR(GETDATE());

    IF OBJECT_ID(N'tempdb..#staging_indicadores') IS NULL
        THROW 50001, N'DatosGenerales.usp_ImportarIndicadoresEconomicos: no se importó nada, falta la tabla #staging_indicadores con los indicadores.', 1;

    UPDATE #staging_indicadores
    SET codigo_iso3      = UPPER(NULLIF(TRIM(codigo_iso3), '')),
        codigo_indicador = UPPER(NULLIF(TRIM(codigo_indicador), ''))
    WHERE accion IS NULL;

    /* 1. Cada regla anota su motivo en los registros que no la cumplen. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_iso3 IS NULL
                     THEN @nl + N'- El país (código ISO alfa-3) es obligatorio.'
                 WHEN NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p WHERE p.codigo_iso3 = st.codigo_iso3)
                     THEN @nl + N'- No hay ningún país con el código ISO alfa-3 ' + st.codigo_iso3 + N'.'
            END,
            CASE WHEN st.codigo_indicador IS NULL
                     THEN @nl + N'- El código del indicador es obligatorio.'
                 WHEN LEN(st.codigo_indicador) > 30
                     THEN @nl + N'- El código del indicador no puede superar los 30 caracteres.'
                 WHEN st.codigo_indicador COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9._]%'
                     THEN @nl + N'- El código del indicador solo admite letras sin acentos, números, puntos y guiones bajos.'
            END,
            CASE WHEN st.anio IS NULL
                     THEN @nl + N'- El año es obligatorio.'
                 WHEN st.anio NOT BETWEEN 1960 AND @anio_actual
                     THEN @nl + N'- El año debe estar entre 1960 y ' + CAST(@anio_actual AS NVARCHAR(4)) + N'.'
            END,
            IIF(st.valor IS NULL, @nl + N'- El valor es obligatorio.', NULL)), N'')
    FROM #staging_indicadores AS st
    WHERE st.accion IS NULL;

    -- Mismo país, indicador y año más de una vez: no se sabe cuál cargar y se rechazan todos.
    WITH repetidos AS (
        SELECT errores,
               COUNT(*)   OVER (PARTITION BY codigo_iso3, codigo_indicador, anio) AS veces,
               MIN(valor) OVER (PARTITION BY codigo_iso3, codigo_indicador, anio) AS valor_minimo,
               MAX(valor) OVER (PARTITION BY codigo_iso3, codigo_indicador, anio) AS valor_maximo
        FROM #staging_indicadores
        WHERE accion IS NULL AND codigo_iso3 IS NOT NULL AND codigo_indicador IS NOT NULL AND anio IS NOT NULL
          AND valor IS NOT NULL
    )
    UPDATE repetidos
    SET errores = CONCAT(errores, @nl, N'- Este país, indicador y año vienen ', veces, N' veces',
                         IIF(valor_minimo = valor_maximo, N'.', N', con valores distintos: no se sabe cuál es el correcto.'))
    WHERE veces > 1;

    UPDATE #staging_indicadores SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 2. Lo que le pasa a cada registro válido se calcula antes de cargar: después estarían todos sin cambios. */
    UPDATE st
    SET accion = CASE WHEN EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p
                                   WHERE p.codigo_iso3 = st.codigo_iso3
                                     AND NOT EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
                                                     WHERE ie.id_pais = p.id_pais
                                                       AND ie.codigo_indicador = st.codigo_indicador
                                                       AND ie.anio = st.anio))
                           THEN 'INSERTADO'
                      WHEN EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p
                                   INNER JOIN DatosGenerales.INDICADOR_ECONOMICO AS ie ON ie.id_pais = p.id_pais
                                   WHERE p.codigo_iso3 = st.codigo_iso3
                                     AND ie.codigo_indicador = st.codigo_indicador
                                     AND ie.anio = st.anio
                                     AND ie.valor <> st.valor)
                           THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_indicadores AS st
    WHERE st.accion IS NULL;

    /* 3. Carga, todos juntos. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- Los que ya están cargados con otro valor (un registro de GBR puede ser INSERTADO en un país y cambiar en el otro).
        UPDATE ie
        SET valor = st.valor, fecha_actualizacion = SYSDATETIME()
        FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
        INNER JOIN #staging_indicadores AS st ON st.codigo_iso3 = p.codigo_iso3
                                             AND st.codigo_indicador = ie.codigo_indicador
                                             AND st.anio = ie.anio
        WHERE st.accion IN ('INSERTADO', 'ACTUALIZADO') AND ie.valor <> st.valor;

        -- Los que todavía no están, en cada país con ese código ISO.
        INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
        SELECT p.id_pais, st.codigo_indicador, st.anio, st.valor
        FROM #staging_indicadores AS st
        INNER JOIN DatosGenerales.PAIS AS p ON p.codigo_iso3 = st.codigo_iso3
        WHERE st.accion = 'INSERTADO'
          AND NOT EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
                          WHERE ie.id_pais = p.id_pais
                            AND ie.codigo_indicador = st.codigo_indicador
                            AND ie.anio = st.anio);

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/*
  usp_ImportarCotizaciones
  Upsert de cotizaciones por moneda y fecha (ej. las de la API Frankfurter),
  desde #staging_cotizaciones. Columnas que usa: codigo_moneda, fecha,
  unidades_por_usd, errores y accion.
  Valida cada registro pendiente: moneda, fecha y unidades por dólar
  obligatorias; moneda de 3 letras y distinta del dólar; fecha no futura;
  unidades por dólar mayores que cero; que no venga dos veces la misma
  moneda y fecha. Con eso cubre las reglas de usp_COTIZACION_Alta y
  _Modificacion. Las cotizaciones que cambiaron se actualizan con su
  fecha_actualizacion; las que no existían se insertan.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarCotizaciones
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @hoy          DATE     = CONVERT(DATE, GETDATE());

    IF OBJECT_ID(N'tempdb..#staging_cotizaciones') IS NULL
        THROW 50001, N'DatosGenerales.usp_ImportarCotizaciones: no se importó nada, falta la tabla #staging_cotizaciones con las cotizaciones.', 1;

    UPDATE #staging_cotizaciones
    SET codigo_moneda = UPPER(NULLIF(TRIM(codigo_moneda), ''))
    WHERE accion IS NULL;

    /* 1. Cada regla anota su motivo en los registros que no la cumplen. */
    UPDATE #staging_cotizaciones
    SET errores = NULLIF(CONCAT(errores,
            CASE WHEN codigo_moneda IS NULL
                     THEN @nl + N'- La moneda es obligatoria.'
                 WHEN codigo_moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
                     THEN @nl + N'- La moneda "' + codigo_moneda + N'" no es un código de 3 letras (ISO 4217).'
                 WHEN codigo_moneda = 'USD'
                     THEN @nl + N'- El dólar no lleva cotización: es la base y vale siempre 1.'
            END,
            CASE WHEN fecha IS NULL THEN @nl + N'- La fecha es obligatoria.'
                 WHEN fecha > @hoy  THEN @nl + N'- La fecha ' + CONVERT(NVARCHAR(10), fecha, 103) + N' es futura.'
            END,
            CASE WHEN unidades_por_usd IS NULL THEN @nl + N'- El valor (unidades por dólar) es obligatorio.'
                 WHEN unidades_por_usd <= 0    THEN @nl + N'- El valor (unidades por dólar) tiene que ser mayor que cero.'
            END), N'')
    WHERE accion IS NULL;

    -- Misma moneda y fecha más de una vez: no se sabe cuál cargar y se rechazan todas.
    WITH repetidos AS (
        SELECT errores,
               COUNT(*)              OVER (PARTITION BY codigo_moneda, fecha) AS veces,
               MIN(unidades_por_usd) OVER (PARTITION BY codigo_moneda, fecha) AS valor_minimo,
               MAX(unidades_por_usd) OVER (PARTITION BY codigo_moneda, fecha) AS valor_maximo
        FROM #staging_cotizaciones
        WHERE accion IS NULL AND codigo_moneda IS NOT NULL AND fecha IS NOT NULL AND unidades_por_usd IS NOT NULL
    )
    UPDATE repetidos
    SET errores = CONCAT(errores, @nl, N'- Esta moneda y fecha vienen ', veces, N' veces',
                         IIF(valor_minimo = valor_maximo, N'.', N', con valores distintos: no se sabe cuál es el correcto.'))
    WHERE veces > 1;

    UPDATE #staging_cotizaciones SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 2. Lo que le pasa a cada registro válido, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN c.id_cotizacion IS NULL                      THEN 'INSERTADO'
                      WHEN c.unidades_por_usd <> st.unidades_por_usd    THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_cotizaciones AS st
    LEFT JOIN DatosGenerales.COTIZACION AS c ON c.codigo_moneda = st.codigo_moneda AND c.fecha = st.fecha
    WHERE st.accion IS NULL;

    /* 3. Carga, todas juntas. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE c
        SET unidades_por_usd = st.unidades_por_usd, fecha_actualizacion = SYSDATETIME()
        FROM DatosGenerales.COTIZACION AS c
        INNER JOIN #staging_cotizaciones AS st ON st.codigo_moneda = c.codigo_moneda AND st.fecha = c.fecha
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO DatosGenerales.COTIZACION (codigo_moneda, fecha, unidades_por_usd)
        SELECT codigo_moneda, fecha, unidades_por_usd
        FROM #staging_cotizaciones
        WHERE accion = 'INSERTADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/*
  usp_ImportarFeriados
  Upsert de feriados por país y fecha (ej. los de la API Nager.Date), desde
  #staging_feriados, con un registro por país y día: dos feriados del mismo
  día van juntos en el nombre. Columnas que usa: id_pais, fecha, nombre,
  errores y accion.
  Valida cada registro pendiente: país, fecha y nombre obligatorios; país
  existente; nombre de hasta 200 caracteres; que no venga dos veces el mismo
  país y fecha. Con eso cubre las reglas de usp_FERIADO_Alta y _Modificacion.
  Los feriados que cambiaron de nombre se actualizan con su
  fecha_actualizacion; los que no existían se insertan.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ImportarFeriados
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    IF OBJECT_ID(N'tempdb..#staging_feriados') IS NULL
        THROW 50001, N'DatosGenerales.usp_ImportarFeriados: no se importó nada, falta la tabla #staging_feriados con los feriados.', 1;

    UPDATE #staging_feriados
    SET nombre = NULLIF(TRIM(nombre), N'')
    WHERE accion IS NULL;

    /* 1. Cada regla anota su motivo en los registros que no la cumplen. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.id_pais IS NULL THEN @nl + N'- El país es obligatorio.'
                 WHEN NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p WHERE p.id_pais = st.id_pais)
                     THEN @nl + N'- No existe el país con id ' + CAST(st.id_pais AS NVARCHAR(10)) + N'.'
            END,
            IIF(st.fecha IS NULL, @nl + N'- La fecha es obligatoria.', NULL),
            CASE WHEN st.nombre IS NULL     THEN @nl + N'- El nombre del feriado es obligatorio.'
                 WHEN LEN(st.nombre) > 200  THEN @nl + N'- El nombre del feriado no puede superar los 200 caracteres.'
            END), N'')
    FROM #staging_feriados AS st
    WHERE st.accion IS NULL;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- Este país y fecha vienen ', r.veces, N' veces (dos feriados del mismo día '
                         + N'van en un solo registro, con los nombres juntos).')
    FROM #staging_feriados AS st
    INNER JOIN (SELECT id_pais, fecha, COUNT(*) AS veces FROM #staging_feriados
                WHERE accion IS NULL AND id_pais IS NOT NULL AND fecha IS NOT NULL
                GROUP BY id_pais, fecha HAVING COUNT(*) > 1) AS r
            ON r.id_pais = st.id_pais AND r.fecha = st.fecha
    WHERE st.accion IS NULL;

    UPDATE #staging_feriados SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 2. Lo que le pasa a cada registro válido, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN f.id_feriado IS NULL     THEN 'INSERTADO'
                      WHEN f.nombre <> st.nombre    THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_feriados AS st
    LEFT JOIN DatosGenerales.FERIADO AS f ON f.id_pais = st.id_pais AND f.fecha = st.fecha
    WHERE st.accion IS NULL;

    /* 3. Carga, todos juntos. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE f
        SET nombre = st.nombre, fecha_actualizacion = SYSDATETIME()
        FROM DatosGenerales.FERIADO AS f
        INNER JOIN #staging_feriados AS st ON st.id_pais = f.id_pais AND st.fecha = f.fecha
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO DatosGenerales.FERIADO (id_pais, fecha, nombre)
        SELECT id_pais, fecha, nombre
        FROM #staging_feriados
        WHERE accion = 'INSERTADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ============================================================================
   TORNEO
   Sedes, selecciones, jugadores, partidos y lo que pasó en cada partido
   (formaciones, cambios, goles y tarjetas), para cargar un torneo real desde
   archivos (23_SP_Importar_Mundial2026.sql y 24_SP_Importar_Jugadores.sql).
   Los jugadores de los eventos llegan con su id: identificarlos por el nombre
   que trae el archivo es tarea del proceso de importación.
   ============================================================================ */

/*
  usp_ImportarSedes
  Upsert de sedes por nombre del estadio, desde #staging_sedes. Columnas que
  usa: nombre_estadio, ciudad, codigo_fifa (del país), capacidad,
  huso_horario, latitud, longitud, tarifa_1 a tarifa_4, errores y accion.
  Una sede nueva se registra con sus 4 espacios publicitarios, como en
  usp_RegistrarSede; en una existente, un dato que no viene no se modifica.
  Valida cada sede pendiente: nombre del estadio obligatorio, de hasta 100
  caracteres y sin repetir; ciudad de hasta 80; para las sedes nuevas,
  ciudad, país, capacidad, huso y las 4 tarifas obligatorios; países
  existentes; husos existentes en sys.time_zone_info; capacidad mayor que
  cero y no menor que la asistencia de un partido ya jugado en la sede;
  latitud y longitud juntas y dentro de rango; tarifas no negativas. Con eso
  cubre las reglas de usp_SEDE_Alta, usp_SEDE_Modificacion y
  usp_RegistrarSede. Si cambia el huso de una sede, recalcula la hora local
  de sus partidos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarSedes
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    IF OBJECT_ID(N'tempdb..#staging_sedes') IS NULL
        THROW 50001, N'Torneo.usp_ImportarSedes: no se importó nada, falta la tabla #staging_sedes con las sedes.', 1;

    UPDATE #staging_sedes
    SET nombre_estadio = NULLIF(TRIM(nombre_estadio), ''),
        ciudad         = NULLIF(TRIM(ciudad), ''),
        codigo_fifa    = UPPER(NULLIF(TRIM(codigo_fifa), '')),
        huso_horario   = NULLIF(TRIM(huso_horario), '')
    WHERE accion IS NULL;

    -- El huso se guarda con el nombre exacto de sys.time_zone_info.
    UPDATE st
    SET huso_horario = z.name COLLATE DATABASE_DEFAULT
    FROM #staging_sedes AS st
    INNER JOIN sys.time_zone_info AS z ON z.name COLLATE DATABASE_DEFAULT = st.huso_horario
    WHERE st.accion IS NULL;

    /* 1. Cada regla anota su motivo en las sedes que no la cumplen. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.nombre_estadio IS NULL       THEN @nl + N'- El nombre del estadio es obligatorio.'
                 WHEN LEN(st.nombre_estadio) > 100    THEN @nl + N'- El nombre del estadio no puede superar los 100 caracteres.'
            END,
            IIF(LEN(st.ciudad) > 80, @nl + N'- La ciudad no puede superar los 80 caracteres.', NULL),
            IIF(s.id_sede IS NULL AND st.nombre_estadio IS NOT NULL
                AND (st.ciudad IS NULL OR st.codigo_fifa IS NULL OR st.capacidad IS NULL OR st.huso_horario IS NULL
                     OR st.tarifa_1 IS NULL OR st.tarifa_2 IS NULL OR st.tarifa_3 IS NULL OR st.tarifa_4 IS NULL),
                @nl + N'- Una sede nueva necesita ciudad, país, capacidad, huso horario y las 4 tarifas.', NULL),
            IIF(st.codigo_fifa IS NOT NULL AND p.id_pais IS NULL,
                @nl + N'- No hay ningún país con el código FIFA ' + st.codigo_fifa + N'.', NULL),
            IIF(st.huso_horario IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM sys.time_zone_info AS z
                                WHERE z.name COLLATE DATABASE_DEFAULT = st.huso_horario),
                @nl + N'- El huso horario ' + st.huso_horario + N' no existe en sys.time_zone_info.', NULL),
            IIF(st.capacidad <= 0, @nl + N'- La capacidad tiene que ser mayor que cero.', NULL),
            IIF(st.capacidad > 0 AND EXISTS (SELECT 1 FROM Torneo.PARTIDO AS pa
                                             WHERE pa.id_sede = s.id_sede AND pa.asistencia > st.capacidad),
                @nl + N'- La capacidad es menor que la asistencia de un partido ya jugado en la sede.', NULL),
            IIF((st.latitud IS NULL AND st.longitud IS NOT NULL) OR (st.latitud IS NOT NULL AND st.longitud IS NULL)
                OR st.latitud NOT BETWEEN -90 AND 90 OR st.longitud NOT BETWEEN -180 AND 180,
                @nl + N'- La latitud y la longitud van juntas, entre -90 y 90 y entre -180 y 180.', NULL),
            IIF(st.tarifa_1 < 0 OR st.tarifa_2 < 0 OR st.tarifa_3 < 0 OR st.tarifa_4 < 0,
                @nl + N'- Las tarifas no pueden ser negativas.', NULL)), N'')
    FROM #staging_sedes AS st
    LEFT JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = st.codigo_fifa
    LEFT JOIN Torneo.SEDE AS s ON s.nombre_estadio = st.nombre_estadio
    WHERE st.accion IS NULL;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- Este estadio viene ', r.veces, N' veces.')
    FROM #staging_sedes AS st
    INNER JOIN (SELECT nombre_estadio, COUNT(*) AS veces FROM #staging_sedes
                WHERE nombre_estadio IS NOT NULL
                GROUP BY nombre_estadio HAVING COUNT(*) > 1) AS r
            ON r.nombre_estadio = st.nombre_estadio
    WHERE st.accion IS NULL;

    UPDATE #staging_sedes SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 2. Lo que le pasa a cada sede válida se calcula antes de cargar: después estarían todas sin cambios. */
    UPDATE st
    SET accion = CASE WHEN s.id_sede IS NULL THEN 'INSERTADO'
                      WHEN st.ciudad <> s.ciudad OR p.id_pais <> s.id_pais OR st.capacidad <> s.capacidad
                        OR st.huso_horario <> s.huso_horario
                        OR st.latitud <> ISNULL(s.latitud, 999) OR st.longitud <> ISNULL(s.longitud, 999)
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_sedes AS st
    LEFT JOIN Torneo.SEDE AS s ON s.nombre_estadio = st.nombre_estadio
    LEFT JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = st.codigo_fifa
    WHERE st.accion IS NULL;

    /* 3. Carga, todas juntas. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE s
        SET ciudad       = ISNULL(st.ciudad, s.ciudad),
            id_pais      = ISNULL(p.id_pais, s.id_pais),
            capacidad    = ISNULL(st.capacidad, s.capacidad),
            huso_horario = ISNULL(st.huso_horario, s.huso_horario),
            latitud      = ISNULL(st.latitud, s.latitud),
            longitud     = ISNULL(st.longitud, s.longitud)
        FROM Torneo.SEDE AS s
        INNER JOIN #staging_sedes AS st ON st.nombre_estadio = s.nombre_estadio
        LEFT JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = st.codigo_fifa
        WHERE st.accion = 'ACTUALIZADO';

        -- La hora local de los partidos sale de la UTC y el huso de la sede (si el huso no cambió, queda igual).
        UPDATE pa
        SET fecha_hora_local = CONVERT(DATETIME2(0), (pa.fecha_hora_utc AT TIME ZONE 'UTC') AT TIME ZONE s.huso_horario)
        FROM Torneo.PARTIDO AS pa
        INNER JOIN Torneo.SEDE AS s ON s.id_sede = pa.id_sede
        INNER JOIN #staging_sedes AS st ON st.nombre_estadio = s.nombre_estadio
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario, latitud, longitud)
        SELECT st.nombre_estadio, st.ciudad, p.id_pais, st.capacidad, st.huso_horario, st.latitud, st.longitud
        FROM #staging_sedes AS st
        INNER JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = st.codigo_fifa
        WHERE st.accion = 'INSERTADO';

        INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, descripcion, tarifa_usd)
        SELECT s.id_sede, e.numero, CONCAT('Panel perimetral ', e.numero), e.tarifa
        FROM #staging_sedes AS st
        INNER JOIN Torneo.SEDE AS s ON s.nombre_estadio = st.nombre_estadio
        CROSS APPLY (VALUES (1, st.tarifa_1), (2, st.tarifa_2), (3, st.tarifa_3), (4, st.tarifa_4)) AS e (numero, tarifa)
        WHERE st.accion = 'INSERTADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/*
  usp_ImportarSelecciones
  Upsert de selecciones por el código FIFA de su país, desde
  #staging_selecciones. Columnas que usa: id_registro (distinto en cada
  fila), codigo_fifa, confederacion, grupo, nombre_alternativo, errores y
  accion. Una selección nueva se registra con su lista de convocados
  (todavía vacía), presentada en @fecha_presentacion; el director técnico no
  viene en los archivos y se carga aparte. nombre_alternativo es el nombre
  con el que la fuente escribe la selección (en inglés, por ejemplo): si es
  distinto del nombre del país, se guarda en NOMBRE_ALTERNATIVO para
  reconocerla en otros archivos.
  Valida cada selección pendiente: código FIFA obligatorio, existente y sin
  repetir; confederación válida (obligatoria si la selección es nueva);
  grupo de la A a la L; que no cambie el grupo de una selección con
  partidos de la fase de grupos; nombre alternativo de hasta 120
  caracteres, que no sea de otra selección ni venga para otra. Y con las
  válidas, que ningún grupo quede con más de SELECCIONES_POR_GRUPO
  selecciones: si uno se pasa, se rechazan las suyas. Con eso cubre las
  reglas de usp_SELECCION_Alta, usp_SELECCION_Modificacion,
  usp_LISTA_CONVOCADOS_Alta y usp_NOMBRE_ALTERNATIVO_Alta.
  La fecha de presentación es de la importación y no de cada selección: si
  hay que crear alguna lista y falta o es futura, no se importa nada (THROW
  50001).
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarSelecciones
    @fecha_presentacion  DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048);
    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @cupo_grupo   TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                                      WHERE codigo = 'SELECCIONES_POR_GRUPO');

    -- Lo que ya está registrado de cada selección pendiente.
    DECLARE @registradas TABLE (
        id_registro   INT PRIMARY KEY,
        id_pais       SMALLINT,
        nombre_pais   VARCHAR(60),
        id_seleccion  INT,
        grupo_actual  CHAR(1),
        tiene_lista   BIT
    );

    IF OBJECT_ID(N'tempdb..#staging_selecciones') IS NULL
        THROW 50001, N'Torneo.usp_ImportarSelecciones: no se importó nada, falta la tabla #staging_selecciones con las selecciones.', 1;

    UPDATE #staging_selecciones
    SET codigo_fifa        = UPPER(NULLIF(TRIM(codigo_fifa), '')),
        confederacion      = UPPER(NULLIF(TRIM(confederacion), '')),
        grupo              = UPPER(NULLIF(TRIM(grupo), '')),
        nombre_alternativo = NULLIF(TRIM(nombre_alternativo), N'')
    WHERE accion IS NULL;

    INSERT INTO @registradas (id_registro, id_pais, nombre_pais, id_seleccion, grupo_actual, tiene_lista)
    SELECT st.id_registro, p.id_pais, p.nombre, s.id_seleccion, s.grupo,
           IIF(EXISTS (SELECT 1 FROM Torneo.LISTA_CONVOCADOS AS lc WHERE lc.id_seleccion = s.id_seleccion), 1, 0)
    FROM #staging_selecciones AS st
    LEFT JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = st.codigo_fifa
    LEFT JOIN Torneo.SELECCION AS s ON s.id_pais = p.id_pais
    WHERE st.accion IS NULL;

    /* 1. Cada regla anota su motivo en las selecciones que no la cumplen. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_fifa IS NULL THEN @nl + N'- El código FIFA es obligatorio.'
                 WHEN r.id_pais IS NULL      THEN @nl + N'- No hay un país con código FIFA "' + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.confederacion IS NULL AND r.id_seleccion IS NULL
                     THEN @nl + N'- La confederación es obligatoria.'
                 WHEN st.confederacion NOT IN ('AFC', 'CAF', 'CONCACAF', 'CONMEBOL', 'OFC', 'UEFA')
                     THEN @nl + N'- La confederación "' + st.confederacion + N'" no es AFC, CAF, CONCACAF, CONMEBOL, OFC ni UEFA.'
            END,
            IIF(st.grupo COLLATE Latin1_General_BIN NOT LIKE '[A-L]',
                @nl + N'- El grupo "' + st.grupo + N'" no es una letra de la A a la L.', NULL),
            IIF(st.grupo <> ISNULL(r.grupo_actual, '')
                AND EXISTS (SELECT 1 FROM Torneo.PARTIDO AS p
                            WHERE p.fase = 'GRUPOS' AND r.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)),
                @nl + N'- La selección ya tiene partidos de la fase de grupos: no se le puede cambiar el grupo.', NULL),
            IIF(LEN(st.nombre_alternativo) > 120, @nl + N'- El nombre no puede superar los 120 caracteres.', NULL),
            IIF(EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO AS na
                        WHERE na.id_jugador IS NULL AND na.nombre = st.nombre_alternativo
                          AND na.id_seleccion <> ISNULL(r.id_seleccion, 0)),
                @nl + N'- El nombre "' + st.nombre_alternativo + N'" ya es de otra selección.', NULL)), N'')
    FROM #staging_selecciones AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- Esta selección viene ', r.veces, N' veces.')
    FROM #staging_selecciones AS st
    INNER JOIN (SELECT codigo_fifa, COUNT(*) AS veces FROM #staging_selecciones
                WHERE codigo_fifa IS NOT NULL GROUP BY codigo_fifa HAVING COUNT(*) > 1) AS r
            ON r.codigo_fifa = st.codigo_fifa
    WHERE st.accion IS NULL;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- El nombre "', st.nombre_alternativo, N'" viene para más de una selección.')
    FROM #staging_selecciones AS st
    WHERE st.accion IS NULL
      AND EXISTS (SELECT 1 FROM #staging_selecciones AS o
                  WHERE o.nombre_alternativo = st.nombre_alternativo AND o.codigo_fifa <> st.codigo_fifa);

    -- Grupos como quedarían con las selecciones válidas: si uno se pasa del cupo, se rechazan las suyas.
    WITH validas AS (
        SELECT st.id_registro, ISNULL(st.grupo, r.grupo_actual) AS grupo, r.id_seleccion
        FROM #staging_selecciones AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
        WHERE st.errores IS NULL
    ),
    grupos AS (
        SELECT grupo FROM validas
        UNION ALL
        SELECT s.grupo
        FROM Torneo.SELECCION AS s
        WHERE NOT EXISTS (SELECT 1 FROM validas AS v WHERE v.id_seleccion = s.id_seleccion)
    ),
    excedidos AS (
        SELECT grupo, COUNT(*) AS selecciones FROM grupos
        WHERE grupo IS NOT NULL GROUP BY grupo HAVING COUNT(*) > @cupo_grupo
    )
    UPDATE st
    SET errores = CONCAT(@nl, N'- El grupo ', e.grupo, N' quedaría con ', e.selecciones, N' selecciones y el máximo es ',
                         @cupo_grupo, N' (SELECCIONES_POR_GRUPO).')
    FROM #staging_selecciones AS st
    INNER JOIN validas AS v ON v.id_registro = st.id_registro
    INNER JOIN excedidos AS e ON e.grupo = v.grupo;

    UPDATE #staging_selecciones SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    IF EXISTS (SELECT 1 FROM #staging_selecciones AS st
               INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
               WHERE st.accion IS NULL AND r.tiene_lista = 0)
       AND (@fecha_presentacion IS NULL OR @fecha_presentacion > CONVERT(DATE, GETDATE()))
    BEGIN
        SET @errores = N'Torneo.usp_ImportarSelecciones: no se importó ninguna selección.' + @nl
                     + N'- Hay selecciones sin lista de convocados: la fecha de presentación es obligatoria y no puede ser futura.';
        THROW 50001, @errores, 1;
    END;

    /* 2. Lo que le pasa a cada selección válida, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN r.id_seleccion IS NULL THEN 'INSERTADO'
                      WHEN st.confederacion <> s.confederacion OR st.grupo <> ISNULL(s.grupo, '') OR r.tiene_lista = 0
                        OR (st.nombre_alternativo <> r.nombre_pais
                            AND NOT EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO AS na
                                            WHERE na.id_jugador IS NULL AND na.nombre = st.nombre_alternativo))
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_selecciones AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
    LEFT JOIN Torneo.SELECCION AS s ON s.id_seleccion = r.id_seleccion
    WHERE st.accion IS NULL;

    /* 3. Carga, todas juntas. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE s
        SET confederacion = ISNULL(st.confederacion, s.confederacion),
            grupo         = ISNULL(st.grupo, s.grupo)
        FROM Torneo.SELECCION AS s
        INNER JOIN @registradas AS r ON r.id_seleccion = s.id_seleccion
        INNER JOIN #staging_selecciones AS st ON st.id_registro = r.id_registro
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo)
        SELECT r.id_pais, st.confederacion, st.grupo
        FROM #staging_selecciones AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
        WHERE st.accion = 'INSERTADO';

        UPDATE r SET id_seleccion = s.id_seleccion
        FROM @registradas AS r
        INNER JOIN #staging_selecciones AS st ON st.id_registro = r.id_registro
        INNER JOIN Torneo.SELECCION AS s ON s.id_pais = r.id_pais
        WHERE st.accion = 'INSERTADO';

        INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion)
        SELECT r.id_seleccion, @fecha_presentacion
        FROM #staging_selecciones AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
        WHERE st.accion IN ('INSERTADO', 'ACTUALIZADO') AND r.tiene_lista = 0;

        INSERT INTO Torneo.NOMBRE_ALTERNATIVO (id_seleccion, nombre)
        SELECT r.id_seleccion, st.nombre_alternativo
        FROM #staging_selecciones AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
        WHERE st.accion IN ('INSERTADO', 'ACTUALIZADO')
          AND st.nombre_alternativo <> r.nombre_pais
          AND NOT EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO AS na
                          WHERE na.id_jugador IS NULL AND na.nombre = st.nombre_alternativo);

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/*
  usp_ImportarJugadores
  Upsert de jugadores de las listas de convocados, por selección (código FIFA
  de su país), apellido y nombre, desde #staging_jugadores. Columnas que usa:
  id_registro (distinto en cada fila), codigo_fifa, nombre, apellido,
  posicion, dorsal, fecha_nacimiento, club_origen, errores y accion.
  Acepta las posiciones en español, abreviadas (GK, DF, MF, FW) o en inglés.
  Un jugador nuevo se da de alta en la fecha de presentación de la lista,
  con motivo "Importación"; en uno existente, la fecha de nacimiento y el
  club que no vienen no se borran. Los jugadores de la lista que no vienen
  quedan como están.
  Valida cada jugador pendiente: selección con lista de convocados; nombre,
  apellido, posición y dorsal obligatorios; nombre y apellido de hasta 60
  caracteres y club de hasta 100; posición válida; dorsal entre 1 y 99;
  fecha de nacimiento no futura; que no venga dos veces. Y con los válidos,
  cada lista como quedaría: un dorsal repetido entre los activos rechaza a
  los que lo traen; una lista con más de MAX_CONVOCADOS activos o, si es la
  inicial (estaba vacía), sin entre MIN_CONVOCADOS y MAX_CONVOCADOS
  jugadores con al menos MIN_ARQUEROS_CONVOCADOS arqueros, rechaza a todos
  los de esa selección. Con eso cubre las reglas de usp_JUGADOR_Alta,
  usp_JUGADOR_Modificacion y usp_RegistrarConvocatoria.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarJugadores
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl              NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia     BIT      = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @min_convocados  TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_CONVOCADOS');
    DECLARE @max_convocados  TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS');
    DECLARE @min_arqueros    TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_ARQUEROS_CONVOCADOS');

    -- La lista y el jugador ya registrados de cada fila pendiente.
    DECLARE @registrados TABLE (
        id_registro         INT PRIMARY KEY,
        id_lista            INT,
        fecha_presentacion  DATE,
        lista_vacia         BIT,
        id_jugador          INT,
        activo              BIT
    );

    IF OBJECT_ID(N'tempdb..#staging_jugadores') IS NULL
        THROW 50001, N'Torneo.usp_ImportarJugadores: no se importó nada, falta la tabla #staging_jugadores con los jugadores.', 1;

    UPDATE #staging_jugadores
    SET codigo_fifa = UPPER(NULLIF(TRIM(codigo_fifa), '')),
        nombre      = NULLIF(TRIM(nombre), N''),
        apellido    = NULLIF(TRIM(apellido), N''),
        club_origen = NULLIF(TRIM(club_origen), N''),
        posicion    = CASE UPPER(NULLIF(TRIM(posicion), ''))
                          WHEN 'GK' THEN 'ARQUERO'       WHEN 'GOALKEEPER' THEN 'ARQUERO'
                          WHEN 'DF' THEN 'DEFENSOR'      WHEN 'DEFENDER'   THEN 'DEFENSOR'
                          WHEN 'MF' THEN 'MEDIOCAMPISTA' WHEN 'MIDFIELDER' THEN 'MEDIOCAMPISTA'
                          WHEN 'FW' THEN 'DELANTERO'     WHEN 'FORWARD'    THEN 'DELANTERO'
                          ELSE UPPER(NULLIF(TRIM(posicion), ''))
                      END
    WHERE accion IS NULL;

    INSERT INTO @registrados (id_registro, id_lista, fecha_presentacion, lista_vacia)
    SELECT st.id_registro, lc.id_lista, lc.fecha_presentacion,
           IIF(lc.id_lista IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.JUGADOR AS j WHERE j.id_lista = lc.id_lista), 1, 0)
    FROM #staging_jugadores AS st
    LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = st.codigo_fifa
    LEFT JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_seleccion = s.id_seleccion
    WHERE st.accion IS NULL;

    UPDATE r SET id_jugador = j.id_jugador, activo = IIF(j.fecha_baja IS NULL, 1, 0)
    FROM @registrados AS r
    INNER JOIN #staging_jugadores AS st ON st.id_registro = r.id_registro
    INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = r.id_lista AND j.apellido = st.apellido AND j.nombre = st.nombre;

    /* 1. Las reglas de cada jugador. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_fifa IS NULL THEN @nl + N'- El código FIFA de la selección es obligatorio.'
                 WHEN r.id_lista IS NULL     THEN @nl + N'- No hay una selección con lista de convocados con código FIFA "'
                                                       + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.nombre IS NULL OR st.apellido IS NULL
                     THEN @nl + N'- El nombre y el apellido son obligatorios.'
                 WHEN LEN(st.nombre) > 60 OR LEN(st.apellido) > 60
                     THEN @nl + N'- El nombre y el apellido no pueden superar los 60 caracteres.'
            END,
            CASE WHEN st.posicion IS NULL THEN @nl + N'- La posición es obligatoria.'
                 WHEN st.posicion NOT IN ('ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO')
                     THEN @nl + N'- La posición "' + st.posicion + N'" no es ARQUERO, DEFENSOR, MEDIOCAMPISTA ni DELANTERO '
                              + N'(ni GK, DF, MF o FW).'
            END,
            CASE WHEN st.dorsal IS NULL THEN @nl + N'- El dorsal es obligatorio.'
                 WHEN st.dorsal NOT BETWEEN 1 AND 99
                     THEN @nl + N'- El dorsal ' + CAST(st.dorsal AS NVARCHAR(3)) + N' no está entre 1 y 99.'
            END,
            IIF(st.fecha_nacimiento > CONVERT(DATE, GETDATE()), @nl + N'- La fecha de nacimiento no puede ser futura.', NULL),
            IIF(LEN(st.club_origen) > 100, @nl + N'- El club no puede superar los 100 caracteres.', NULL)), N'')
    FROM #staging_jugadores AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- Este jugador viene ', r.veces, N' veces.')
    FROM #staging_jugadores AS st
    INNER JOIN (SELECT codigo_fifa, nombre, apellido, COUNT(*) AS veces FROM #staging_jugadores
                WHERE codigo_fifa IS NOT NULL AND nombre IS NOT NULL AND apellido IS NOT NULL
                GROUP BY codigo_fifa, nombre, apellido HAVING COUNT(*) > 1) AS r
            ON r.codigo_fifa = st.codigo_fifa AND r.nombre = st.nombre AND r.apellido = st.apellido
    WHERE st.accion IS NULL;

    /* 2. Cada lista como quedaría con los jugadores válidos (los activos que no vienen, más
          los que vienen). Un dorsal repetido entre los activos rechaza a los que lo traen. */
    WITH validos AS (
        SELECT st.id_registro, r.id_lista, r.lista_vacia, r.id_jugador, st.dorsal, st.posicion
        FROM #staging_jugadores AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        WHERE st.errores IS NULL AND ISNULL(r.activo, 1) = 1
    ),
    plantel AS (
        SELECT id_lista, dorsal FROM validos
        UNION ALL
        SELECT j.id_lista, j.dorsal
        FROM Torneo.JUGADOR AS j
        WHERE j.fecha_baja IS NULL
          AND j.id_lista IN (SELECT id_lista FROM @registrados)
          AND NOT EXISTS (SELECT 1 FROM validos AS v WHERE v.id_jugador = j.id_jugador)
    ),
    repetidos AS (
        SELECT id_lista, dorsal, COUNT(*) AS veces FROM plantel GROUP BY id_lista, dorsal HAVING COUNT(*) > 1
    )
    UPDATE st
    SET errores = CONCAT(@nl, N'- El dorsal ', st.dorsal, N' lo tendrían ', rp.veces, N' convocados activos de la selección.')
    FROM #staging_jugadores AS st
    INNER JOIN validos AS v ON v.id_registro = st.id_registro
    INNER JOIN repetidos AS rp ON rp.id_lista = v.id_lista AND rp.dorsal = v.dorsal;

    -- Una lista que no cumple el reglamento rechaza a todos los jugadores de esa selección.
    WITH validos AS (
        SELECT st.id_registro, r.id_lista, r.lista_vacia, r.id_jugador, st.posicion
        FROM #staging_jugadores AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        WHERE st.errores IS NULL AND ISNULL(r.activo, 1) = 1
    ),
    plantel AS (
        SELECT id_lista, lista_vacia, posicion FROM validos
        UNION ALL
        SELECT j.id_lista, 0, j.posicion_habitual
        FROM Torneo.JUGADOR AS j
        WHERE j.fecha_baja IS NULL
          AND j.id_lista IN (SELECT id_lista FROM @registrados)
          AND NOT EXISTS (SELECT 1 FROM validos AS v WHERE v.id_jugador = j.id_jugador)
    ),
    listas AS (
        SELECT id_lista, MAX(CAST(lista_vacia AS TINYINT)) AS vacia, COUNT(*) AS jugadores,
               SUM(IIF(posicion = 'ARQUERO', 1, 0)) AS arqueros
        FROM plantel
        GROUP BY id_lista
    )
    UPDATE st
    SET errores = CONCAT(st.errores, @nl,
                         IIF(l.jugadores > @max_convocados,
                             CONCAT(N'- La lista de la selección quedaría con ', l.jugadores, N' convocados activos y el máximo es ',
                                    @max_convocados, N' (MAX_CONVOCADOS).'),
                             CONCAT(N'- La lista inicial de la selección tendría ', l.jugadores, N' jugadores y ', l.arqueros,
                                    N' arqueros: tienen que ser entre ', @min_convocados, N' y ', @max_convocados,
                                    N', con al menos ', @min_arqueros, N' arqueros.')))
    FROM #staging_jugadores AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
    INNER JOIN listas AS l ON l.id_lista = r.id_lista
    WHERE l.jugadores > @max_convocados
       OR (l.vacia = 1 AND (l.jugadores < @min_convocados OR l.arqueros < @min_arqueros));

    UPDATE #staging_jugadores SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 3. Lo que le pasa a cada jugador válido, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN r.id_jugador IS NULL THEN 'INSERTADO'
                      WHEN st.posicion <> j.posicion_habitual OR st.dorsal <> j.dorsal
                        OR st.fecha_nacimiento <> ISNULL(j.fecha_nacimiento, '19000101')
                        OR st.club_origen <> ISNULL(j.club_origen, N'')
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_jugadores AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
    LEFT JOIN Torneo.JUGADOR AS j ON j.id_jugador = r.id_jugador
    WHERE st.accion IS NULL;

    /* 4. Carga, todos juntos. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE j
        SET posicion_habitual = st.posicion,
            dorsal            = st.dorsal,
            fecha_nacimiento  = ISNULL(st.fecha_nacimiento, j.fecha_nacimiento),
            club_origen       = ISNULL(st.club_origen, j.club_origen)
        FROM Torneo.JUGADOR AS j
        INNER JOIN @registrados AS r ON r.id_jugador = j.id_jugador
        INNER JOIN #staging_jugadores AS st ON st.id_registro = r.id_registro
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO Torneo.JUGADOR
            (id_lista, nombre, apellido, fecha_nacimiento, club_origen, posicion_habitual, dorsal,
             fecha_alta, motivo_alta)
        SELECT r.id_lista, st.nombre, st.apellido, st.fecha_nacimiento, st.club_origen, st.posicion, st.dorsal,
               r.fecha_presentacion, 'Importación'
        FROM #staging_jugadores AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        WHERE st.accion = 'INSERTADO'
        ORDER BY r.id_lista, st.dorsal;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/*
  usp_ImportarPartidos
  Upsert de partidos del fixture por número, desde #staging_partidos.
  Columnas que usa: id_registro (distinto en cada fila), numero_partido,
  nombre_estadio, fase, fecha_hora_utc, codigo_fifa_local,
  codigo_fifa_visitante, goles_local, goles_visitante, penales_local,
  penales_visitante, asistencia, errores y accion.
  La sede se identifica por el nombre del estadio, las selecciones por el
  código FIFA de su país y la fase admite los nombres en inglés (Group A o
  First Stage, Round of 32, Round of 16, Quarter-final, Semi-final, Third
  place o Bronze final, Final). La hora local se calcula con la UTC y el
  huso de la sede. Si trae el resultado, el partido queda FINALIZADO (carga
  histórica). En un partido existente, un dato que no viene queda como está.
  Valida cada partido pendiente, como quedaría: número obligatorio, mayor
  que cero y sin repetir; para los nuevos, estadio, fase y fecha
  obligatorios; sede registrada; fase válida; selecciones registradas y
  distintas; en la fase de grupos, las dos selecciones y del mismo grupo;
  resultado con los goles de las dos selecciones y con las dos selecciones;
  penales de las dos, solo en eliminación directa empatada y sin empate en
  los penales; un empate de eliminación directa con penales; que un partido
  ya empezado o jugado no cambie de selecciones, sede, fase ni fecha; si
  cambia el resultado, que sea igual al de los goles ya cargados (uno que no
  cambia no se valida: los goles pueden estar cargados a medias);
  asistencia entre 0 y la capacidad de la sede. Y con los válidos, el
  fixture como quedaría: ninguna selección juega dos partidos a menos de 24
  horas y ninguna sede tiene dos partidos el mismo día; los partidos que lo
  rompen se rechazan. Con eso cubre las reglas de usp_PARTIDO_Alta y
  usp_PARTIDO_Modificacion.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarPartidos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- Cada partido pendiente como quedaría: lo que trae y, lo que no trae, como está.
    DECLARE @partidos TABLE (
        id_registro            INT PRIMARY KEY,
        id_partido             INT,
        id_sede                INT,
        capacidad              INT,
        fase                   VARCHAR(30),
        fecha_hora_utc         DATETIME2(0),
        fecha_hora_local       DATETIME2(0),
        id_local               INT,
        id_visitante           INT,
        sede_inexistente       BIT,
        local_inexistente      BIT,
        visitante_inexistente  BIT,
        cambia_jugado          BIT    -- cambia selecciones, sede, fase o fecha de un partido ya empezado
    );

    IF OBJECT_ID(N'tempdb..#staging_partidos') IS NULL
        THROW 50001, N'Torneo.usp_ImportarPartidos: no se importó nada, falta la tabla #staging_partidos con los partidos.', 1;

    UPDATE st
    SET nombre_estadio        = NULLIF(TRIM(st.nombre_estadio), ''),
        codigo_fifa_local     = UPPER(NULLIF(TRIM(st.codigo_fifa_local), '')),
        codigo_fifa_visitante = UPPER(NULLIF(TRIM(st.codigo_fifa_visitante), '')),
        fase = CASE WHEN f.fase LIKE '%GROUP%' OR f.fase LIKE 'GRUPO%'                           THEN 'GRUPOS'
                    WHEN f.fase IN ('ROUND OF 32', 'DIECISEISAVOS DE FINAL')                      THEN 'DIECISEISAVOS'
                    WHEN f.fase IN ('ROUND OF 16', 'OCTAVOS DE FINAL')                            THEN 'OCTAVOS'
                    WHEN f.fase LIKE 'QUARTER%' OR f.fase = 'CUARTOS DE FINAL'                    THEN 'CUARTOS'
                    WHEN f.fase LIKE 'SEMI%'                                                      THEN 'SEMIFINAL'
                    WHEN f.fase LIKE '%THIRD%' OR f.fase LIKE 'BRONZE%' OR f.fase LIKE 'TERCER%'  THEN 'TERCER_PUESTO'
                    ELSE f.fase
               END
    FROM #staging_partidos AS st
    CROSS APPLY (SELECT UPPER(NULLIF(TRIM(st.fase), '')) AS fase) AS f
    WHERE st.accion IS NULL;

    INSERT INTO @partidos (id_registro, id_partido, id_sede, fase, fecha_hora_utc, id_local, id_visitante,
                           sede_inexistente, local_inexistente, visitante_inexistente, cambia_jugado)
    SELECT st.id_registro, p.id_partido,
           ISNULL(se.id_sede, p.id_sede), ISNULL(st.fase, p.fase), ISNULL(st.fecha_hora_utc, p.fecha_hora_utc),
           ISNULL(sl.id_seleccion, p.id_seleccion_local), ISNULL(sv.id_seleccion, p.id_seleccion_visitante),
           IIF(st.nombre_estadio IS NOT NULL AND se.id_sede IS NULL, 1, 0),
           IIF(st.codigo_fifa_local IS NOT NULL AND sl.id_seleccion IS NULL, 1, 0),
           IIF(st.codigo_fifa_visitante IS NOT NULL AND sv.id_seleccion IS NULL, 1, 0),
           IIF(p.estado NOT IN ('PROGRAMADO', 'SUSPENDIDO')
               AND (se.id_sede <> p.id_sede OR st.fase <> p.fase OR st.fecha_hora_utc <> p.fecha_hora_utc
                    OR sl.id_seleccion <> ISNULL(p.id_seleccion_local, 0)
                    OR sv.id_seleccion <> ISNULL(p.id_seleccion_visitante, 0)), 1, 0)
    FROM #staging_partidos AS st
    LEFT JOIN Torneo.PARTIDO AS p ON p.numero_partido = st.numero_partido
    LEFT JOIN Torneo.SEDE AS se ON se.nombre_estadio = st.nombre_estadio
    OUTER APPLY (SELECT s.id_seleccion FROM DatosGenerales.PAIS AS pa
                 INNER JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
                 WHERE pa.codigo_fifa = st.codigo_fifa_local) AS sl
    OUTER APPLY (SELECT s.id_seleccion FROM DatosGenerales.PAIS AS pa
                 INNER JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
                 WHERE pa.codigo_fifa = st.codigo_fifa_visitante) AS sv
    WHERE st.accion IS NULL;

    UPDATE pt
    SET capacidad        = s.capacidad,
        fecha_hora_local = CONVERT(DATETIME2(0), (pt.fecha_hora_utc AT TIME ZONE 'UTC') AT TIME ZONE s.huso_horario)
    FROM @partidos AS pt
    INNER JOIN Torneo.SEDE AS s ON s.id_sede = pt.id_sede;

    /* 1. Cada regla anota su motivo en los partidos que no la cumplen. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.numero_partido IS NULL THEN @nl + N'- El número de partido es obligatorio.'
                 WHEN st.numero_partido = 0     THEN @nl + N'- El número de partido tiene que ser mayor que cero.'
            END,
            IIF(pt.id_partido IS NULL AND (st.nombre_estadio IS NULL OR st.fase IS NULL OR st.fecha_hora_utc IS NULL),
                @nl + N'- Un partido nuevo necesita estadio, fase y fecha.', NULL),
            IIF(pt.sede_inexistente = 1, @nl + N'- El estadio "' + st.nombre_estadio + N'" no es una sede registrada.', NULL),
            IIF(st.fase NOT IN ('GRUPOS', 'DIECISEISAVOS', 'OCTAVOS', 'CUARTOS', 'SEMIFINAL', 'TERCER_PUESTO', 'FINAL'),
                @nl + N'- La fase "' + st.fase + N'" no es válida.', NULL),
            IIF(pt.local_inexistente = 1,
                @nl + N'- No hay una selección registrada con código FIFA "' + st.codigo_fifa_local + N'".', NULL),
            IIF(pt.visitante_inexistente = 1,
                @nl + N'- No hay una selección registrada con código FIFA "' + st.codigo_fifa_visitante + N'".', NULL),
            IIF(pt.id_local = pt.id_visitante, @nl + N'- La selección local y la visitante son la misma.', NULL),
            IIF(pt.fase = 'GRUPOS' AND (pt.id_local IS NULL OR pt.id_visitante IS NULL
                                        OR ISNULL(sl.grupo, '') <> ISNULL(sv.grupo, '-')),
                @nl + N'- En la fase de grupos tienen que estar las dos selecciones y ser del mismo grupo.', NULL),
            IIF((st.goles_local IS NULL AND st.goles_visitante IS NOT NULL) OR (st.goles_local IS NOT NULL AND st.goles_visitante IS NULL),
                @nl + N'- El resultado tiene que traer los goles de las dos selecciones.', NULL),
            IIF(st.goles_local IS NOT NULL AND (pt.id_local IS NULL OR pt.id_visitante IS NULL),
                @nl + N'- Un partido con resultado tiene que tener las dos selecciones.', NULL),
            IIF((st.penales_local IS NULL AND st.penales_visitante IS NOT NULL) OR (st.penales_local IS NOT NULL AND st.penales_visitante IS NULL),
                @nl + N'- Los penales tienen que ser de las dos selecciones.', NULL),
            IIF(st.penales_local IS NOT NULL
                AND (pt.fase = 'GRUPOS' OR st.goles_local IS NULL OR st.goles_local <> st.goles_visitante
                     OR st.penales_local = st.penales_visitante),
                @nl + N'- Hay penales solo en eliminación directa, con empate en goles, y no pueden terminar empatados.', NULL),
            IIF(pt.fase <> 'GRUPOS' AND st.goles_local = st.goles_visitante AND st.penales_local IS NULL,
                @nl + N'- Un empate de eliminación directa se define por penales, y no vienen.', NULL),
            IIF(pt.cambia_jugado = 1,
                @nl + N'- El partido ' + CAST(st.numero_partido AS NVARCHAR(3)) + N' ya empezó o se jugó con otras selecciones, '
                    + N'sede, fase o fecha: no se puede cambiar.', NULL),
            IIF(st.asistencia < 0 OR st.asistencia > pt.capacidad,
                CONCAT(@nl, N'- La asistencia ', st.asistencia, N' no está entre 0 y la capacidad de la sede',
                       IIF(pt.capacidad IS NULL, N'', CONCAT(N' (', pt.capacidad, N')')), N'.'), NULL),
            IIF(EXISTS (SELECT 1 FROM DesarrolloPartido.fn_MarcadorSegunGoles(pt.id_partido) AS m
                        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = pt.id_partido
                        WHERE st.goles_local IS NOT NULL AND m.goles_registrados > m.penales_registrados
                          AND (st.goles_local <> ISNULL(p.goles_local, 255) OR st.goles_visitante <> ISNULL(p.goles_visitante, 255))
                          AND (st.goles_local <> m.goles_local OR st.goles_visitante <> m.goles_visitante)),
                @nl + N'- El resultado cambia y no coincide con los goles ya cargados del partido.', NULL)), N'')
    FROM #staging_partidos AS st
    INNER JOIN @partidos AS pt ON pt.id_registro = st.id_registro
    LEFT JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = pt.id_local
    LEFT JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = pt.id_visitante;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- El partido ', st.numero_partido, N' viene ', r.veces, N' veces.')
    FROM #staging_partidos AS st
    INNER JOIN (SELECT numero_partido, COUNT(*) AS veces FROM #staging_partidos
                WHERE numero_partido IS NOT NULL GROUP BY numero_partido HAVING COUNT(*) > 1) AS r
            ON r.numero_partido = st.numero_partido
    WHERE st.accion IS NULL;

    /* 2. El fixture como quedaría con los partidos válidos: ninguna selección juega dos partidos
          a menos de 24 horas y ninguna sede tiene dos partidos el mismo día. */
    WITH fixture AS (
        SELECT st.numero_partido, pt.id_sede, pt.fecha_hora_utc, pt.fecha_hora_local, pt.id_local, pt.id_visitante
        FROM #staging_partidos AS st
        INNER JOIN @partidos AS pt ON pt.id_registro = st.id_registro
        WHERE st.errores IS NULL
        UNION ALL
        SELECT p.numero_partido, p.id_sede, p.fecha_hora_utc, p.fecha_hora_local, p.id_seleccion_local,
               p.id_seleccion_visitante
        FROM Torneo.PARTIDO AS p
        WHERE NOT EXISTS (SELECT 1 FROM #staging_partidos AS st
                          INNER JOIN @partidos AS pt ON pt.id_registro = st.id_registro
                          WHERE st.errores IS NULL AND st.numero_partido = p.numero_partido)
    ),
    jugados AS (
        SELECT f.numero_partido, f.fecha_hora_utc, s.id_seleccion
        FROM fixture AS f
        CROSS APPLY (VALUES (f.id_local), (f.id_visitante)) AS s (id_seleccion)
        WHERE s.id_seleccion IS NOT NULL
    ),
    conflictos AS (
        SELECT a.numero_partido, b.numero_partido AS otro, N'una de sus selecciones juega ese otro partido a menos de 24 horas' AS motivo
        FROM jugados AS a
        INNER JOIN jugados AS b ON b.id_seleccion = a.id_seleccion AND b.numero_partido <> a.numero_partido
        WHERE ABS(DATEDIFF(MINUTE, a.fecha_hora_utc, b.fecha_hora_utc)) < 1440
        UNION
        SELECT a.numero_partido, b.numero_partido, N'la sede tiene ese otro partido el mismo día'
        FROM fixture AS a
        INNER JOIN fixture AS b ON b.id_sede = a.id_sede AND b.numero_partido <> a.numero_partido
        WHERE CAST(a.fecha_hora_local AS DATE) = CAST(b.fecha_hora_local AS DATE)
    )
    UPDATE st
    SET errores = (SELECT STRING_AGG(CONCAT(@nl, N'- Con el partido ', c.otro, N': ', c.motivo, N'.'), N'')
                   FROM conflictos AS c WHERE c.numero_partido = st.numero_partido)
    FROM #staging_partidos AS st
    WHERE st.accion IS NULL AND st.errores IS NULL
      AND EXISTS (SELECT 1 FROM conflictos AS c WHERE c.numero_partido = st.numero_partido);

    UPDATE #staging_partidos SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 3. Lo que le pasa a cada partido válido, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN pt.id_partido IS NULL THEN 'INSERTADO'
                      WHEN pt.id_sede <> p.id_sede OR pt.fase <> p.fase OR pt.fecha_hora_utc <> p.fecha_hora_utc
                        OR ISNULL(pt.id_local, 0) <> ISNULL(p.id_seleccion_local, 0)
                        OR ISNULL(pt.id_visitante, 0) <> ISNULL(p.id_seleccion_visitante, 0)
                        OR st.goles_local <> ISNULL(p.goles_local, 255) OR st.goles_visitante <> ISNULL(p.goles_visitante, 255)
                        OR st.penales_local <> ISNULL(p.penales_local, 255)
                        OR st.penales_visitante <> ISNULL(p.penales_visitante, 255)
                        OR st.asistencia <> ISNULL(p.asistencia, -1)
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_partidos AS st
    INNER JOIN @partidos AS pt ON pt.id_registro = st.id_registro
    LEFT JOIN Torneo.PARTIDO AS p ON p.id_partido = pt.id_partido
    WHERE st.accion IS NULL;

    /* 4. Carga, todos juntos. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE p
        SET id_sede                = pt.id_sede,
            fase                   = pt.fase,
            fecha_hora_utc         = pt.fecha_hora_utc,
            fecha_hora_local       = pt.fecha_hora_local,
            id_seleccion_local     = pt.id_local,
            id_seleccion_visitante = pt.id_visitante,
            goles_local            = ISNULL(st.goles_local, p.goles_local),
            goles_visitante        = ISNULL(st.goles_visitante, p.goles_visitante),
            penales_local          = IIF(st.goles_local IS NULL, p.penales_local, st.penales_local),
            penales_visitante      = IIF(st.goles_local IS NULL, p.penales_visitante, st.penales_visitante),
            asistencia             = ISNULL(st.asistencia, p.asistencia),
            estado                 = IIF(st.goles_local IS NOT NULL, 'FINALIZADO', p.estado)
        FROM Torneo.PARTIDO AS p
        INNER JOIN @partidos AS pt ON pt.id_partido = p.id_partido
        INNER JOIN #staging_partidos AS st ON st.id_registro = pt.id_registro
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO Torneo.PARTIDO
            (numero_partido, id_sede, id_seleccion_local, id_seleccion_visitante, fase, fecha_hora_local,
             fecha_hora_utc, goles_local, goles_visitante, penales_local, penales_visitante, asistencia, estado)
        SELECT st.numero_partido, pt.id_sede, pt.id_local, pt.id_visitante, pt.fase, pt.fecha_hora_local,
               pt.fecha_hora_utc, st.goles_local, st.goles_visitante, st.penales_local, st.penales_visitante, st.asistencia,
               IIF(st.goles_local IS NOT NULL, 'FINALIZADO', 'PROGRAMADO')
        FROM #staging_partidos AS st
        INNER JOIN @partidos AS pt ON pt.id_registro = st.id_registro
        WHERE st.accion = 'INSERTADO'
        ORDER BY st.numero_partido;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/*
  usp_ImportarDesarrolloPartidos
  Upsert de lo que pasó en partidos ya cargados (por número de partido), desde
  #staging_eventos, con un evento por fila según su tipo:
    FORMACION  un jugador de la formación de su selección (es_titular y, si
               es titular, posicion_en_cancha)
    CAMBIO     sale id_jugador y entra id_jugador_entra (minuto,
               minuto_adicional, en_entretiempo, motivo)
    GOL        lo convierte id_jugador (tipo_gol, periodo, minuto,
               minuto_adicional)
    PENAL      un penal convertido en la definición: un gol del período
               PENALES, sin minuto
    TARJETA    la recibe id_jugador (tipo_tarjeta, es_doble_amarilla,
               minuto, minuto_adicional, motivo)
  Columnas que usa: id_evento (distinto en cada fila), tipo, numero_partido,
  id_jugador, id_jugador_entra, es_titular, posicion_en_cancha, minuto,
  minuto_adicional, en_entretiempo, motivo, periodo, tipo_gol,
  tipo_tarjeta, es_doble_amarilla, errores y accion.
  Es una carga histórica: no repite las reglas de los SP que registran el
  partido en vivo (equipo en cancha en ese minuto, ventanas de cambio,
  suspensiones), sino las de las tablas.
  Cada evento se busca entre los ya cargados del partido. De uno cargado se
  actualiza lo que dejan cambiar los SP de modificación de la Entrega 5; lo
  que lo identifica no cambia, y si cambia, es otro evento:
    FORMACION  lo identifica el jugador; se actualiza si es titular y su
               posición
    CAMBIO     los dos jugadores; se actualizan el minuto, el adicional, si
               fue en el entretiempo y el motivo
    GOL/PENAL  el autor, si es de la definición y si es en contra; se
               actualizan el tipo, el período y el minuto
    TARJETA    el jugador, el tipo y si es por doble amarilla; se actualizan
               el minuto y el motivo
  Primero se emparejan los iguales y después, en orden de minuto, los que
  quedan con lo mismo que los identifica, si quedan tantos de un lado como
  del otro: si el archivo corrige un gol del minuto 67 al 68, el gol se
  actualiza y no se repite. Los demás son nuevos. Lo cargado que no viene no
  se borra.
  - La formación de cada selección se arma con sus jugadores del conjunto. El
    esquema táctico de una formación nueva sale de las posiciones habituales
    de los titulares (defensores, mediocampistas y delanteros, ej. 4-3-3); el
    de una ya cargada no se cambia.
  - El motivo de un cambio o una tarjeta puede no venir (NULL): uno nuevo se
    registra como TACTICO o "Sin detalle en la fuente", y uno cargado
    conserva el suyo.
  Valida cada evento pendiente: tipo válido; partido existente; jugadores
  existentes y de una de las dos selecciones del partido; en la formación,
  si es titular y la posición de los titulares; en los cambios, jugadores
  distintos de la misma selección, minuto entre 1 y 120 con hasta 30 de
  adicional, los del entretiempo en el 46, 91 o 106 y motivo TACTICO,
  LESION o PRECAUCION; tipos de gol existentes y minuto de acuerdo con el
  período; tarjetas AMARILLA o ROJA (la doble amarilla, solo roja), minuto
  entre 0 y 120 con hasta 30 de adicional y motivo de hasta 200
  caracteres. Y con los válidos, cada partido como quedaría: un jugador una
  sola vez en la formación; cada formación con 11 titulares (los del
  conjunto más los cargados que no vienen), o se rechazan todos los
  jugadores de esa formación; los jugadores de cambios, goles y tarjetas,
  en la formación del partido (la cargada o la válida del conjunto); cada
  jugador sale y entra una sola vez por partido; y ninguna selección con más
  goles que su resultado, ni con más penales convertidos que los de su
  definición: si pasa, se rechazan sus goles nuevos (un gol que el archivo
  le atribuye a otro jugador es otro gol, y el cargado no se borra).
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_ImportarDesarrolloPartidos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- Lo que ya está registrado de cada evento pendiente.
    DECLARE @eventos TABLE (
        id_evento           INT PRIMARY KEY,
        id_partido          INT,
        id_seleccion        INT,       -- del jugador que forma, sale, convierte o recibe la tarjeta
        de_un_equipo        BIT,       -- ese jugador es de una de las dos selecciones del partido
        id_seleccion_entra  INT,
        entra_de_un_equipo  BIT,
        posicion_habitual   VARCHAR(15),
        id_tipo_gol         TINYINT,
        es_en_contra        BIT,
        formacion_existe    BIT,
        ya_alineado         BIT,
        id_cargado          INT        -- el cambio, gol o tarjeta ya cargado que es este mismo evento
    );

    IF OBJECT_ID(N'tempdb..#staging_eventos') IS NULL
        THROW 50001, N'DesarrolloPartido.usp_ImportarDesarrolloPartidos: no se importó nada, falta la tabla #staging_eventos con los eventos.', 1;

    UPDATE #staging_eventos
    SET tipo               = UPPER(NULLIF(TRIM(tipo), '')),
        posicion_en_cancha = UPPER(NULLIF(TRIM(posicion_en_cancha), '')),
        periodo            = UPPER(NULLIF(TRIM(periodo), '')),
        tipo_gol           = UPPER(NULLIF(TRIM(tipo_gol), '')),
        tipo_tarjeta       = UPPER(NULLIF(TRIM(tipo_tarjeta), '')),
        -- El SET ve el tipo como estaba antes de este UPDATE: se lo compara normalizado.
        motivo             = IIF(UPPER(TRIM(tipo)) = 'CAMBIO', UPPER(NULLIF(TRIM(motivo), '')), NULLIF(TRIM(motivo), ''))
    WHERE accion IS NULL;

    INSERT INTO @eventos (id_evento, id_partido, id_seleccion, de_un_equipo, id_seleccion_entra, entra_de_un_equipo,
                          posicion_habitual, id_tipo_gol, es_en_contra)
    SELECT e.id_evento, p.id_partido,
           lc.id_seleccion, IIF(lc.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante), 1, 0),
           lce.id_seleccion, IIF(lce.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante), 1, 0),
           j.posicion_habitual, tg.id_tipo_gol, tg.es_en_contra
    FROM #staging_eventos AS e
    LEFT JOIN Torneo.PARTIDO AS p ON p.numero_partido = e.numero_partido
    LEFT JOIN Torneo.JUGADOR AS j ON j.id_jugador = e.id_jugador
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
    LEFT JOIN Torneo.JUGADOR AS je ON je.id_jugador = e.id_jugador_entra
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS lce ON lce.id_lista = je.id_lista
    LEFT JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.descripcion = e.tipo_gol
    WHERE e.accion IS NULL;

    UPDATE ev
    SET formacion_existe = IIF(EXISTS (SELECT 1 FROM DesarrolloPartido.FORMACION AS f
                                       WHERE f.id_partido = ev.id_partido AND f.id_seleccion = ev.id_seleccion), 1, 0),
        ya_alineado      = IIF(EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS al
                                       INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = al.id_formacion
                                       WHERE f.id_partido = ev.id_partido AND al.id_jugador = e.id_jugador), 1, 0)
    FROM @eventos AS ev
    INNER JOIN #staging_eventos AS e ON e.id_evento = ev.id_evento
    WHERE e.tipo = 'FORMACION';

    /* 1. Las reglas de cada evento. */
    UPDATE e
    SET errores = NULLIF(CONCAT(e.errores,
            IIF(e.tipo IS NULL OR e.tipo NOT IN ('FORMACION', 'CAMBIO', 'GOL', 'PENAL', 'TARJETA'),
                @nl + N'- El tipo "' + ISNULL(e.tipo, N'') + N'" no es FORMACION, CAMBIO, GOL, PENAL ni TARJETA.', NULL),
            CASE WHEN e.numero_partido IS NULL THEN @nl + N'- El número de partido es obligatorio.'
                 WHEN ev.id_partido IS NULL     THEN @nl + N'- No hay un partido con el número '
                                                         + CAST(e.numero_partido AS NVARCHAR(3)) + N'.'
            END,
            CASE WHEN e.id_jugador IS NULL THEN @nl + N'- El jugador es obligatorio.'
                 WHEN ev.id_partido IS NOT NULL AND ev.de_un_equipo = 0
                     THEN @nl + N'- El jugador no existe o no es de ninguna de las dos selecciones del partido.'
            END,
            -- Formaciones
            IIF(e.tipo = 'FORMACION' AND e.es_titular IS NULL, @nl + N'- Falta si el jugador es titular o suplente.', NULL),
            IIF(e.tipo = 'FORMACION' AND e.es_titular = 1 AND e.posicion_en_cancha IS NULL,
                @nl + N'- Un titular necesita su posición en la cancha.', NULL),
            -- Cambios
            CASE WHEN ISNULL(e.tipo, '') <> 'CAMBIO' THEN NULL
                 WHEN e.id_jugador_entra IS NULL THEN @nl + N'- Falta el jugador que entra.'
                 WHEN ev.id_partido IS NOT NULL AND ev.entra_de_un_equipo = 0
                     THEN @nl + N'- El jugador que entra no existe o no es de ninguna de las dos selecciones del partido.'
                 WHEN e.id_jugador = e.id_jugador_entra THEN @nl + N'- Sale y entra el mismo jugador.'
                 WHEN ev.id_seleccion <> ev.id_seleccion_entra THEN @nl + N'- El que sale y el que entra son de selecciones distintas.'
            END,
            IIF(e.tipo = 'CAMBIO' AND (e.minuto IS NULL OR e.minuto NOT BETWEEN 1 AND 120 OR ISNULL(e.minuto_adicional, 0) > 30),
                @nl + N'- El minuto de un cambio va del 1 al 120, con hasta 30 de adicional.', NULL),
            IIF(e.tipo = 'CAMBIO' AND e.en_entretiempo = 1 AND (e.minuto NOT IN (46, 91, 106) OR ISNULL(e.minuto_adicional, 0) <> 0),
                @nl + N'- Un cambio en el entretiempo va en el minuto 46, 91 o 106.', NULL),
            IIF(e.tipo = 'CAMBIO' AND e.motivo NOT IN ('TACTICO', 'LESION', 'PRECAUCION'),
                @nl + N'- El motivo de un cambio es TACTICO, LESION o PRECAUCION.', NULL),
            -- Goles y penales
            IIF(e.tipo IN ('GOL', 'PENAL') AND ev.id_tipo_gol IS NULL,
                @nl + N'- El tipo de gol "' + ISNULL(e.tipo_gol, N'') + N'" no existe.', NULL),
            IIF(e.tipo = 'PENAL' AND ISNULL(e.periodo, '') <> 'PENALES',
                @nl + N'- Un penal de la definición va en el período PENALES.', NULL),
            IIF(e.tipo IN ('GOL', 'PENAL')
                AND NOT ((e.periodo = 'PENALES'        AND e.minuto IS NULL              AND ISNULL(e.minuto_adicional, 0) = 0)
                      OR (e.periodo = 'PRIMER_TIEMPO'  AND e.minuto BETWEEN 1  AND 45    AND ISNULL(e.minuto_adicional, 0) = 0)
                      OR (e.periodo = 'SEGUNDO_TIEMPO' AND e.minuto BETWEEN 46 AND 90    AND ISNULL(e.minuto_adicional, 0) = 0)
                      OR (e.periodo = 'ALARGUE'        AND e.minuto BETWEEN 91 AND 120   AND ISNULL(e.minuto_adicional, 0) = 0)
                      OR (e.periodo = 'ADICIONALES'    AND e.minuto IN (45, 90, 105, 120) AND e.minuto_adicional BETWEEN 1 AND 30)),
                @nl + N'- El minuto no corresponde al período (PRIMER_TIEMPO del 1 al 45, SEGUNDO_TIEMPO del 46 al 90, '
                    + N'ALARGUE del 91 al 120, ADICIONALES después del 45, 90, 105 o 120, y PENALES sin minuto).', NULL),
            -- Tarjetas
            CASE WHEN ISNULL(e.tipo, '') <> 'TARJETA' THEN NULL
                 WHEN e.tipo_tarjeta IS NULL OR e.tipo_tarjeta NOT IN ('AMARILLA', 'ROJA')
                     THEN @nl + N'- La tarjeta tiene que ser AMARILLA o ROJA.'
                 WHEN e.es_doble_amarilla = 1 AND e.tipo_tarjeta <> 'ROJA'
                     THEN @nl + N'- La doble amarilla se registra como ROJA.'
            END,
            IIF(e.tipo = 'TARJETA' AND (e.minuto IS NULL OR e.minuto > 120 OR ISNULL(e.minuto_adicional, 0) > 30),
                @nl + N'- El minuto de una tarjeta va del 0 al 120, con hasta 30 de adicional.', NULL),
            IIF(e.tipo = 'TARJETA' AND LEN(e.motivo) > 200,
                @nl + N'- El motivo de la tarjeta no puede superar los 200 caracteres.', NULL)), N'')
    FROM #staging_eventos AS e
    INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento;

    /* 2. Las reglas entre eventos. Un jugador figura una sola vez en la formación. */
    UPDATE e
    SET errores = CONCAT(e.errores, @nl, N'- El jugador figura más de una vez en la formación.')
    FROM #staging_eventos AS e
    WHERE e.accion IS NULL AND e.tipo = 'FORMACION' AND e.id_jugador IS NOT NULL
      AND EXISTS (SELECT 1 FROM #staging_eventos AS o
                  WHERE o.tipo = 'FORMACION' AND o.numero_partido = e.numero_partido
                    AND o.id_jugador = e.id_jugador AND o.id_evento <> e.id_evento);

    -- Cada formación tiene que quedar con 11 titulares: los válidos del conjunto, como vienen, y los cargados
    -- que no vienen, como están.
    WITH conjunto AS (
        SELECT ev.id_partido, ev.id_seleccion, e.id_jugador, e.es_titular, e.errores
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo = 'FORMACION' AND ev.id_partido IS NOT NULL AND ev.id_seleccion IS NOT NULL
    ),
    formaciones AS (
        SELECT f.id_partido, f.id_seleccion,
               SUM(IIF(f.es_titular = 1 AND f.errores IS NULL, 1, 0))
             + (SELECT COUNT(*)
                FROM DesarrolloPartido.ALINEACION AS al
                INNER JOIN DesarrolloPartido.FORMACION AS fo ON fo.id_formacion = al.id_formacion
                WHERE fo.id_partido = f.id_partido AND fo.id_seleccion = f.id_seleccion AND al.es_titular = 1
                  AND NOT EXISTS (SELECT 1 FROM conjunto AS c
                                  WHERE c.id_partido = f.id_partido AND c.id_jugador = al.id_jugador AND c.errores IS NULL))
                   AS titulares
        FROM conjunto AS f
        GROUP BY f.id_partido, f.id_seleccion
    )
    UPDATE e
    SET errores = CONCAT(e.errores, @nl, N'- La formación de la selección quedaría con ', f.titulares,
                         N' titulares y tienen que ser 11: no se carga ningún jugador de esa formación.')
    FROM #staging_eventos AS e
    INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
    INNER JOIN formaciones AS f ON f.id_partido = ev.id_partido AND f.id_seleccion = ev.id_seleccion
    WHERE e.tipo = 'FORMACION' AND f.titulares <> 11;

    -- Cambios, goles, penales y tarjetas: los jugadores tienen que estar en la formación del partido.
    UPDATE e
    SET errores = CONCAT(e.errores, @nl, N'- El jugador no está en la formación del partido (o su formación se rechazó).')
    FROM #staging_eventos AS e
    INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
    WHERE e.tipo <> 'FORMACION' AND ev.id_partido IS NOT NULL
      AND EXISTS (SELECT 1 FROM (VALUES (e.id_jugador), (e.id_jugador_entra)) AS j (id_jugador)
                  WHERE j.id_jugador IS NOT NULL
                    AND NOT EXISTS (SELECT 1 FROM #staging_eventos AS f
                                    WHERE f.tipo = 'FORMACION' AND f.accion IS NULL AND f.errores IS NULL
                                      AND f.numero_partido = e.numero_partido AND f.id_jugador = j.id_jugador)
                    AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS a
                                    INNER JOIN DesarrolloPartido.FORMACION AS fo ON fo.id_formacion = a.id_formacion
                                    WHERE fo.id_partido = ev.id_partido AND a.id_jugador = j.id_jugador));

    -- Cada jugador sale y entra una sola vez por partido, contando los cambios ya cargados.
    WITH cambios AS (
        SELECT numero_partido, id_jugador, id_jugador_entra
        FROM #staging_eventos
        WHERE tipo = 'CAMBIO' AND accion IS NULL AND errores IS NULL
        UNION ALL
        SELECT p.numero_partido, ca.id_jugador_sale, ca.id_jugador_entra
        FROM DesarrolloPartido.CAMBIO AS ca
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = ca.id_partido
        WHERE p.numero_partido IN (SELECT numero_partido FROM #staging_eventos WHERE tipo = 'CAMBIO')
          AND NOT EXISTS (SELECT 1 FROM #staging_eventos AS e
                          WHERE e.tipo = 'CAMBIO' AND e.accion IS NULL AND e.errores IS NULL
                            AND e.numero_partido = p.numero_partido
                            AND e.id_jugador = ca.id_jugador_sale AND e.id_jugador_entra = ca.id_jugador_entra)
    ),
    repetidos AS (
        SELECT c.numero_partido, v.tipo, v.id_jugador
        FROM cambios AS c
        CROSS APPLY (VALUES ('S', c.id_jugador), ('E', c.id_jugador_entra)) AS v (tipo, id_jugador)
        GROUP BY c.numero_partido, v.tipo, v.id_jugador
        HAVING COUNT(*) > 1
    )
    UPDATE e
    SET errores = CONCAT(e.errores, @nl, N'- Un jugador de este cambio sale o entra más de una vez en el partido (un cambio '
                         + N'cargado no cambia de jugadores: si el archivo lo corrige, el cargado se da de baja con usp_CAMBIO_Baja).')
    FROM #staging_eventos AS e
    WHERE e.tipo = 'CAMBIO' AND e.accion IS NULL AND e.errores IS NULL
      AND EXISTS (SELECT 1 FROM repetidos AS r
                  WHERE r.numero_partido = e.numero_partido
                    AND ((r.tipo = 'S' AND r.id_jugador = e.id_jugador) OR (r.tipo = 'E' AND r.id_jugador = e.id_jugador_entra)));

    /* 3. Cada evento válido con el ya cargado que es el mismo: un cambio, el de sus dos jugadores; un gol, uno
          de su autor, de la definición o no y en contra o no; una tarjeta, una de su jugador, de su tipo y por
          doble amarilla o no. De los goles y las tarjetas se emparejan primero los iguales y después, en orden
          de minuto, los que quedan sin pareja, si quedan tantos de un lado como del otro (si no, no se sabe
          cuál corrige a cuál y los del conjunto son nuevos). El jugador de una formación ya alineado es el
          mismo (ya_alineado). */
    UPDATE ev
    SET id_cargado = ca.id_cambio
    FROM @eventos AS ev
    INNER JOIN #staging_eventos AS e ON e.id_evento = ev.id_evento
    INNER JOIN DesarrolloPartido.CAMBIO AS ca ON ca.id_partido = ev.id_partido
                                             AND ca.id_jugador_sale = e.id_jugador
                                             AND ca.id_jugador_entra = e.id_jugador_entra
    WHERE e.tipo = 'CAMBIO' AND e.accion IS NULL AND e.errores IS NULL;

    -- Goles iguales (copia numera los que se repiten igual, para emparejarlos de a uno).
    WITH conjunto AS (
        SELECT ev.id_evento, ev.id_partido, e.id_jugador, ev.id_tipo_gol, e.periodo, ISNULL(e.minuto, 255) AS minuto,
               ISNULL(e.minuto_adicional, 0) AS minuto_adicional,
               ROW_NUMBER() OVER (PARTITION BY ev.id_partido, e.id_jugador, ev.id_tipo_gol, e.periodo, e.minuto,
                                               ISNULL(e.minuto_adicional, 0)
                                  ORDER BY e.id_evento) AS copia
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo IN ('GOL', 'PENAL') AND e.accion IS NULL AND e.errores IS NULL
    ),
    cargados AS (
        SELECT g.id_gol, g.id_partido, g.id_jugador_autor, g.id_tipo_gol, g.periodo, ISNULL(g.minuto, 255) AS minuto,
               g.minuto_adicional,
               ROW_NUMBER() OVER (PARTITION BY g.id_partido, g.id_jugador_autor, g.id_tipo_gol, g.periodo, g.minuto,
                                               g.minuto_adicional
                                  ORDER BY g.id_gol) AS copia
        FROM DesarrolloPartido.GOL AS g
        WHERE g.id_partido IN (SELECT id_partido FROM conjunto)
    )
    UPDATE ev
    SET id_cargado = ca.id_gol
    FROM @eventos AS ev
    INNER JOIN conjunto AS c ON c.id_evento = ev.id_evento
    INNER JOIN cargados AS ca ON ca.id_partido = c.id_partido AND ca.id_jugador_autor = c.id_jugador
                             AND ca.id_tipo_gol = c.id_tipo_gol AND ca.periodo = c.periodo
                             AND ca.minuto = c.minuto AND ca.minuto_adicional = c.minuto_adicional AND ca.copia = c.copia;

    -- Los goles que quedan sin pareja, en orden de minuto.
    WITH conjunto AS (
        SELECT ev.id_evento, ev.id_partido, e.id_jugador, ev.es_en_contra, IIF(e.periodo = 'PENALES', 1, 0) AS es_definicion,
               ROW_NUMBER() OVER (PARTITION BY ev.id_partido, e.id_jugador, ev.es_en_contra, IIF(e.periodo = 'PENALES', 1, 0)
                                  ORDER BY ISNULL(e.minuto, 255), ISNULL(e.minuto_adicional, 0), e.id_evento) AS orden,
               COUNT(*) OVER (PARTITION BY ev.id_partido, e.id_jugador, ev.es_en_contra, IIF(e.periodo = 'PENALES', 1, 0))
                   AS sin_pareja
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo IN ('GOL', 'PENAL') AND e.accion IS NULL AND e.errores IS NULL AND ev.id_cargado IS NULL
    ),
    cargados AS (
        SELECT g.id_gol, g.id_partido, g.id_jugador_autor, tg.es_en_contra, IIF(g.periodo = 'PENALES', 1, 0) AS es_definicion,
               ROW_NUMBER() OVER (PARTITION BY g.id_partido, g.id_jugador_autor, tg.es_en_contra, IIF(g.periodo = 'PENALES', 1, 0)
                                  ORDER BY ISNULL(g.minuto, 255), g.minuto_adicional, g.id_gol) AS orden,
               COUNT(*) OVER (PARTITION BY g.id_partido, g.id_jugador_autor, tg.es_en_contra, IIF(g.periodo = 'PENALES', 1, 0))
                   AS sin_pareja
        FROM DesarrolloPartido.GOL AS g
        INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
        WHERE g.id_partido IN (SELECT id_partido FROM conjunto)
          AND NOT EXISTS (SELECT 1 FROM @eventos AS x
                          INNER JOIN #staging_eventos AS xe ON xe.id_evento = x.id_evento
                          WHERE xe.tipo IN ('GOL', 'PENAL') AND x.id_cargado = g.id_gol)
    )
    UPDATE ev
    SET id_cargado = ca.id_gol
    FROM @eventos AS ev
    INNER JOIN conjunto AS c ON c.id_evento = ev.id_evento
    INNER JOIN cargados AS ca ON ca.id_partido = c.id_partido AND ca.id_jugador_autor = c.id_jugador
                             AND ca.es_en_contra = c.es_en_contra AND ca.es_definicion = c.es_definicion
                             AND ca.orden = c.orden AND ca.sin_pareja = c.sin_pareja;

    -- Tarjetas en el mismo minuto (si cambia el motivo, se actualiza).
    WITH conjunto AS (
        SELECT ev.id_evento, ev.id_partido, e.id_jugador, e.tipo_tarjeta, ISNULL(e.es_doble_amarilla, 0) AS es_doble_amarilla,
               e.minuto, ISNULL(e.minuto_adicional, 0) AS minuto_adicional,
               ROW_NUMBER() OVER (PARTITION BY ev.id_partido, e.id_jugador, e.tipo_tarjeta, ISNULL(e.es_doble_amarilla, 0),
                                               e.minuto, ISNULL(e.minuto_adicional, 0)
                                  ORDER BY e.id_evento) AS copia
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo = 'TARJETA' AND e.accion IS NULL AND e.errores IS NULL
    ),
    cargadas AS (
        SELECT am.id_amonestacion, am.id_partido, am.id_jugador, am.tipo_tarjeta, am.es_doble_amarilla, am.minuto,
               am.minuto_adicional,
               ROW_NUMBER() OVER (PARTITION BY am.id_partido, am.id_jugador, am.tipo_tarjeta, am.es_doble_amarilla, am.minuto,
                                               am.minuto_adicional
                                  ORDER BY am.id_amonestacion) AS copia
        FROM DesarrolloPartido.AMONESTACION AS am
        WHERE am.id_partido IN (SELECT id_partido FROM conjunto) AND am.id_jugador IS NOT NULL
    )
    UPDATE ev
    SET id_cargado = ca.id_amonestacion
    FROM @eventos AS ev
    INNER JOIN conjunto AS c ON c.id_evento = ev.id_evento
    INNER JOIN cargadas AS ca ON ca.id_partido = c.id_partido AND ca.id_jugador = c.id_jugador
                             AND ca.tipo_tarjeta = c.tipo_tarjeta AND ca.es_doble_amarilla = c.es_doble_amarilla
                             AND ca.minuto = c.minuto AND ca.minuto_adicional = c.minuto_adicional AND ca.copia = c.copia;

    -- Las tarjetas que quedan sin pareja, en orden de minuto.
    WITH conjunto AS (
        SELECT ev.id_evento, ev.id_partido, e.id_jugador, e.tipo_tarjeta, ISNULL(e.es_doble_amarilla, 0) AS es_doble_amarilla,
               ROW_NUMBER() OVER (PARTITION BY ev.id_partido, e.id_jugador, e.tipo_tarjeta, ISNULL(e.es_doble_amarilla, 0)
                                  ORDER BY e.minuto, ISNULL(e.minuto_adicional, 0), e.id_evento) AS orden,
               COUNT(*) OVER (PARTITION BY ev.id_partido, e.id_jugador, e.tipo_tarjeta, ISNULL(e.es_doble_amarilla, 0))
                   AS sin_pareja
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo = 'TARJETA' AND e.accion IS NULL AND e.errores IS NULL AND ev.id_cargado IS NULL
    ),
    cargadas AS (
        SELECT am.id_amonestacion, am.id_partido, am.id_jugador, am.tipo_tarjeta, am.es_doble_amarilla,
               ROW_NUMBER() OVER (PARTITION BY am.id_partido, am.id_jugador, am.tipo_tarjeta, am.es_doble_amarilla
                                  ORDER BY am.minuto, am.minuto_adicional, am.id_amonestacion) AS orden,
               COUNT(*) OVER (PARTITION BY am.id_partido, am.id_jugador, am.tipo_tarjeta, am.es_doble_amarilla) AS sin_pareja
        FROM DesarrolloPartido.AMONESTACION AS am
        WHERE am.id_partido IN (SELECT id_partido FROM conjunto) AND am.id_jugador IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM @eventos AS x
                          INNER JOIN #staging_eventos AS xe ON xe.id_evento = x.id_evento
                          WHERE xe.tipo = 'TARJETA' AND x.id_cargado = am.id_amonestacion)
    )
    UPDATE ev
    SET id_cargado = ca.id_amonestacion
    FROM @eventos AS ev
    INNER JOIN conjunto AS c ON c.id_evento = ev.id_evento
    INNER JOIN cargadas AS ca ON ca.id_partido = c.id_partido AND ca.id_jugador = c.id_jugador
                             AND ca.tipo_tarjeta = c.tipo_tarjeta AND ca.es_doble_amarilla = c.es_doble_amarilla
                             AND ca.orden = c.orden AND ca.sin_pareja = c.sin_pareja;

    /* 4. Los goles de cada partido como quedarían (los válidos del conjunto y los cargados sin pareja, que
          quedan): ninguna selección con más goles que su resultado ni con más penales convertidos que los de
          su definición. Si pasa, se rechazan sus goles nuevos: un gol que el archivo le atribuye a otro
          jugador es otro gol, y el cargado no se borra. */
    WITH goles AS (
        SELECT e.id_evento, ev.id_cargado, ev.id_partido, IIF(e.periodo = 'PENALES', 1, 0) AS es_definicion,
               IIF(ev.es_en_contra = 1, IIF(ev.id_seleccion = p.id_seleccion_local, p.id_seleccion_visitante, p.id_seleccion_local),
                   ev.id_seleccion) AS id_seleccion_que_suma
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = ev.id_partido
        WHERE e.tipo IN ('GOL', 'PENAL') AND e.accion IS NULL AND e.errores IS NULL
        UNION ALL
        SELECT NULL, g.id_gol, g.id_partido, IIF(g.periodo = 'PENALES', 1, 0),
               IIF(tg.es_en_contra = 1, IIF(lc.id_seleccion = p.id_seleccion_local, p.id_seleccion_visitante, p.id_seleccion_local),
                   lc.id_seleccion)
        FROM DesarrolloPartido.GOL AS g
        INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
        INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = g.id_jugador_autor
        INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
        WHERE g.id_partido IN (SELECT ev.id_partido FROM @eventos AS ev
                               INNER JOIN #staging_eventos AS e ON e.id_evento = ev.id_evento
                               WHERE e.tipo IN ('GOL', 'PENAL'))
          AND NOT EXISTS (SELECT 1 FROM @eventos AS x
                          INNER JOIN #staging_eventos AS xe ON xe.id_evento = x.id_evento
                          WHERE xe.tipo IN ('GOL', 'PENAL') AND x.id_cargado = g.id_gol)
    ),
    cuentas AS (
        SELECT id_evento, id_cargado, id_partido, es_definicion, id_seleccion_que_suma,
               COUNT(*) OVER (PARTITION BY id_partido, es_definicion, id_seleccion_que_suma) AS goles
        FROM goles
    )
    UPDATE e
    SET errores = CONCAT(e.errores, @nl, N'- La selección quedaría con ', c.goles,
                         IIF(c.es_definicion = 1, N' penales convertidos en la definición', N' goles'),
                         N' y su resultado es ', r.resultado, N': no se carga ningún gol nuevo suyo. Un gol que el archivo '
                         + N'le atribuye a otro jugador es otro gol: el cargado se da de baja con usp_GOL_Baja.')
    FROM #staging_eventos AS e
    INNER JOIN cuentas AS c ON c.id_evento = e.id_evento
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
    CROSS APPLY (SELECT ISNULL(IIF(c.es_definicion = 1,
                                   IIF(c.id_seleccion_que_suma = p.id_seleccion_local, p.penales_local, p.penales_visitante),
                                   IIF(c.id_seleccion_que_suma = p.id_seleccion_local, p.goles_local, p.goles_visitante)), 0)
                        AS resultado) AS r
    WHERE c.id_cargado IS NULL AND p.goles_local IS NOT NULL AND c.goles > r.resultado;

    UPDATE #staging_eventos SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 5. Lo que le pasa a cada evento válido, antes de cargar: el que no es uno cargado es nuevo, y el que sí
          se actualiza si trae algo distinto (un motivo que no viene no cuenta). */
    UPDATE e
    SET accion = CASE WHEN (e.tipo = 'FORMACION' AND ev.ya_alineado = 0) OR (e.tipo <> 'FORMACION' AND ev.id_cargado IS NULL)
                          THEN 'INSERTADO'
                      WHEN e.tipo = 'FORMACION'
                           AND EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS al
                                       INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = al.id_formacion
                                       WHERE f.id_partido = ev.id_partido AND al.id_jugador = e.id_jugador
                                         AND (al.es_titular <> e.es_titular
                                              OR al.posicion_en_cancha IS DISTINCT FROM ISNULL(e.posicion_en_cancha,
                                                                                               al.posicion_en_cancha)))
                          THEN 'ACTUALIZADO'
                      WHEN e.tipo = 'CAMBIO'
                           AND EXISTS (SELECT 1 FROM DesarrolloPartido.CAMBIO AS ca
                                       WHERE ca.id_cambio = ev.id_cargado
                                         AND (ca.minuto <> e.minuto OR ca.minuto_adicional <> ISNULL(e.minuto_adicional, 0)
                                              OR ca.en_entretiempo <> ISNULL(e.en_entretiempo, 0)
                                              OR ca.motivo <> ISNULL(e.motivo, ca.motivo)))
                          THEN 'ACTUALIZADO'
                      WHEN e.tipo IN ('GOL', 'PENAL')
                           AND EXISTS (SELECT 1 FROM DesarrolloPartido.GOL AS g
                                       WHERE g.id_gol = ev.id_cargado
                                         AND (g.id_tipo_gol <> ev.id_tipo_gol OR g.periodo <> e.periodo
                                              OR g.minuto IS DISTINCT FROM e.minuto
                                              OR g.minuto_adicional <> ISNULL(e.minuto_adicional, 0)))
                          THEN 'ACTUALIZADO'
                      WHEN e.tipo = 'TARJETA'
                           AND EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION AS am
                                       WHERE am.id_amonestacion = ev.id_cargado
                                         AND (am.minuto <> e.minuto OR am.minuto_adicional <> ISNULL(e.minuto_adicional, 0)
                                              OR am.motivo <> ISNULL(e.motivo, am.motivo)))
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_eventos AS e
    INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
    WHERE e.accion IS NULL;

    /* 6. Carga, todos juntos. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- Formaciones nuevas, con el esquema que sale de las posiciones habituales de los titulares.
        INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico)
        SELECT ev.id_partido, ev.id_seleccion,
               CONCAT(SUM(IIF(e.es_titular = 1 AND ev.posicion_habitual = 'DEFENSOR', 1, 0)), '-',
                      SUM(IIF(e.es_titular = 1 AND ev.posicion_habitual = 'MEDIOCAMPISTA', 1, 0)), '-',
                      SUM(IIF(e.es_titular = 1 AND ev.posicion_habitual = 'DELANTERO', 1, 0)))
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo = 'FORMACION' AND e.accion = 'INSERTADO' AND ev.formacion_existe = 0
        GROUP BY ev.id_partido, ev.id_seleccion;

        -- Jugadores de las formaciones: los alineados que pasan al banco (o del banco a titulares) o cambian de
        -- posición, y los nuevos.
        UPDATE al
        SET es_titular         = e.es_titular,
            posicion_en_cancha = ISNULL(e.posicion_en_cancha, al.posicion_en_cancha)
        FROM DesarrolloPartido.ALINEACION AS al
        INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = al.id_formacion
        INNER JOIN @eventos AS ev ON ev.id_partido = f.id_partido AND ev.id_seleccion = f.id_seleccion
        INNER JOIN #staging_eventos AS e ON e.id_evento = ev.id_evento AND e.id_jugador = al.id_jugador
        WHERE e.tipo = 'FORMACION' AND e.accion = 'ACTUALIZADO';

        INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
        SELECT f.id_formacion, e.id_jugador, e.es_titular, e.posicion_en_cancha
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_partido = ev.id_partido AND f.id_seleccion = ev.id_seleccion
        WHERE e.tipo = 'FORMACION' AND e.accion = 'INSERTADO';

        -- Cambios: los cargados que cambian (un motivo que no viene queda como está) y los nuevos (sin motivo,
        -- TACTICO).
        UPDATE ca
        SET minuto           = e.minuto,
            minuto_adicional = ISNULL(e.minuto_adicional, 0),
            en_entretiempo   = ISNULL(e.en_entretiempo, 0),
            motivo           = ISNULL(e.motivo, ca.motivo)
        FROM DesarrolloPartido.CAMBIO AS ca
        INNER JOIN @eventos AS ev ON ev.id_cargado = ca.id_cambio
        INNER JOIN #staging_eventos AS e ON e.id_evento = ev.id_evento
        WHERE e.tipo = 'CAMBIO' AND e.accion = 'ACTUALIZADO';

        INSERT INTO DesarrolloPartido.CAMBIO
            (id_partido, id_jugador_sale, id_jugador_entra, minuto, minuto_adicional, en_entretiempo, motivo)
        SELECT ev.id_partido, e.id_jugador, e.id_jugador_entra, e.minuto, ISNULL(e.minuto_adicional, 0),
               ISNULL(e.en_entretiempo, 0), ISNULL(e.motivo, 'TACTICO')
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo = 'CAMBIO' AND e.accion = 'INSERTADO';

        -- Goles: los cargados con otro tipo, período o minuto, y los nuevos.
        UPDATE g
        SET id_tipo_gol      = ev.id_tipo_gol,
            periodo          = e.periodo,
            minuto           = e.minuto,
            minuto_adicional = ISNULL(e.minuto_adicional, 0)
        FROM DesarrolloPartido.GOL AS g
        INNER JOIN @eventos AS ev ON ev.id_cargado = g.id_gol
        INNER JOIN #staging_eventos AS e ON e.id_evento = ev.id_evento
        WHERE e.tipo IN ('GOL', 'PENAL') AND e.accion = 'ACTUALIZADO';

        INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto, minuto_adicional)
        SELECT ev.id_partido, e.id_jugador, ev.id_tipo_gol, e.periodo, e.minuto, ISNULL(e.minuto_adicional, 0)
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo IN ('GOL', 'PENAL') AND e.accion = 'INSERTADO';

        -- Tarjetas: las cargadas que cambian (un motivo que no viene queda como está) y las nuevas (sin motivo,
        -- "Sin detalle en la fuente").
        UPDATE am
        SET minuto           = e.minuto,
            minuto_adicional = ISNULL(e.minuto_adicional, 0),
            motivo           = ISNULL(e.motivo, am.motivo)
        FROM DesarrolloPartido.AMONESTACION AS am
        INNER JOIN @eventos AS ev ON ev.id_cargado = am.id_amonestacion
        INNER JOIN #staging_eventos AS e ON e.id_evento = ev.id_evento
        WHERE e.tipo = 'TARJETA' AND e.accion = 'ACTUALIZADO';

        INSERT INTO DesarrolloPartido.AMONESTACION
            (id_partido, id_jugador, tipo_tarjeta, es_doble_amarilla, minuto, minuto_adicional, motivo)
        SELECT ev.id_partido, e.id_jugador, e.tipo_tarjeta, ISNULL(e.es_doble_amarilla, 0), e.minuto,
               ISNULL(e.minuto_adicional, 0), ISNULL(e.motivo, 'Sin detalle en la fuente')
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo = 'TARJETA' AND e.accion = 'INSERTADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ============================================================================
   ÁRBITROS Y DESIGNACIONES
   El equipo arbitral de cada partido, que importa
   Arbitraje.usp_ImportarDesignacionesCSV (23_SP_Importar_Mundial2026.sql).
   ============================================================================ */

/*
  usp_ImportarArbitros
  Upsert de árbitros por país (código FIFA), apellido y nombre, desde
  #staging_arbitros. Columnas que usa: id_registro (distinto en cada fila),
  codigo_fifa, nombre, apellido, categoria, fecha_nacimiento, errores y
  accion. Acepta la categoría CONFEDERATION, en inglés. En uno existente, la
  fecha de nacimiento que no viene no se borra, y si está activo o no queda
  como está. Los idiomas no se importan: se registran con
  usp_ARBITRO_IDIOMA_Alta.
  Valida cada árbitro pendiente: país registrado; nombre y apellido
  obligatorios y de hasta 60 caracteres; categoría FIFA o CONFEDERACION;
  fecha de nacimiento no futura; que no venga dos veces. Con eso cubre las
  reglas de usp_ARBITRO_Alta.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ImportarArbitros
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- El país y el árbitro ya registrados de cada fila pendiente.
    DECLARE @registrados TABLE (
        id_registro  INT PRIMARY KEY,
        id_pais      SMALLINT,
        id_arbitro   INT
    );

    IF OBJECT_ID(N'tempdb..#staging_arbitros') IS NULL
        THROW 50001, N'Arbitraje.usp_ImportarArbitros: no se importó nada, falta la tabla #staging_arbitros con los árbitros.', 1;

    UPDATE #staging_arbitros
    SET codigo_fifa = UPPER(NULLIF(TRIM(codigo_fifa), '')),
        nombre      = NULLIF(TRIM(nombre), N''),
        apellido    = NULLIF(TRIM(apellido), N''),
        categoria   = IIF(UPPER(TRIM(categoria)) = 'CONFEDERATION', 'CONFEDERACION', UPPER(NULLIF(TRIM(categoria), '')))
    WHERE accion IS NULL;

    INSERT INTO @registrados (id_registro, id_pais, id_arbitro)
    SELECT st.id_registro, pa.id_pais, a.id_arbitro
    FROM #staging_arbitros AS st
    LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = st.codigo_fifa
    LEFT JOIN Arbitraje.ARBITRO AS a ON a.id_pais = pa.id_pais AND a.apellido = st.apellido AND a.nombre = st.nombre
    WHERE st.accion IS NULL;

    /* 1. Las reglas de cada árbitro. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_fifa IS NULL THEN @nl + N'- El código FIFA del país es obligatorio.'
                 WHEN r.id_pais IS NULL     THEN @nl + N'- No hay un país registrado con código FIFA "' + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.nombre IS NULL OR st.apellido IS NULL
                     THEN @nl + N'- El nombre y el apellido son obligatorios.'
                 WHEN LEN(st.nombre) > 60 OR LEN(st.apellido) > 60
                     THEN @nl + N'- El nombre y el apellido no pueden superar los 60 caracteres.'
            END,
            CASE WHEN st.categoria IS NULL THEN @nl + N'- La categoría es obligatoria.'
                 WHEN st.categoria NOT IN ('FIFA', 'CONFEDERACION')
                     THEN @nl + N'- La categoría "' + st.categoria + N'" no es FIFA ni CONFEDERACION.'
            END,
            IIF(st.fecha_nacimiento > CONVERT(DATE, GETDATE()), @nl + N'- La fecha de nacimiento no puede ser futura.', NULL)), N'')
    FROM #staging_arbitros AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- Este árbitro viene ', r.veces, N' veces.')
    FROM #staging_arbitros AS st
    INNER JOIN (SELECT codigo_fifa, nombre, apellido, COUNT(*) AS veces FROM #staging_arbitros
                WHERE codigo_fifa IS NOT NULL AND nombre IS NOT NULL AND apellido IS NOT NULL
                GROUP BY codigo_fifa, nombre, apellido HAVING COUNT(*) > 1) AS r
            ON r.codigo_fifa = st.codigo_fifa AND r.nombre = st.nombre AND r.apellido = st.apellido
    WHERE st.accion IS NULL;

    UPDATE #staging_arbitros SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 2. Lo que le pasa a cada árbitro válido, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN r.id_arbitro IS NULL THEN 'INSERTADO'
                      WHEN st.categoria <> a.categoria OR st.fecha_nacimiento <> ISNULL(a.fecha_nacimiento, '19000101')
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_arbitros AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
    LEFT JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = r.id_arbitro
    WHERE st.accion IS NULL;

    /* 3. Carga, todos juntos. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE a
        SET categoria        = st.categoria,
            fecha_nacimiento = ISNULL(st.fecha_nacimiento, a.fecha_nacimiento)
        FROM Arbitraje.ARBITRO AS a
        INNER JOIN @registrados AS r ON r.id_arbitro = a.id_arbitro
        INNER JOIN #staging_arbitros AS st ON st.id_registro = r.id_registro
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, fecha_nacimiento, categoria)
        SELECT r.id_pais, st.nombre, st.apellido, st.fecha_nacimiento, st.categoria
        FROM #staging_arbitros AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        WHERE st.accion = 'INSERTADO'
        ORDER BY st.id_registro;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/*
  usp_ImportarDesignaciones
  Upsert de designaciones arbitrales por partido (número) y árbitro, desde
  #staging_designaciones. Columnas que usa: id_registro (distinto en cada
  fila), numero_partido, id_arbitro, rol, errores y accion. Acepta los roles
  en español o como los publica la FIFA, en inglés: Referee, Assistant
  referee 1 y 2, Fourth official, Reserve assistant referee, Video assistant
  referee, Assistant video assistant referee y Support video assistant
  referee. Un árbitro que ya está designado en el partido con otro rol
  cambia de rol. Las designaciones del partido que no vienen quedan como
  están, y el informe y la sanción post-partido no se tocan.
  Es una carga histórica: no exige, como usp_DESIGNACION_ARBITRAL_Alta, que
  el partido esté PROGRAMADO ni que el árbitro esté activo.
  Valida cada designación pendiente: partido y árbitro existentes; rol
  válido; que el árbitro no sea del país de una de las dos selecciones del
  partido (conflicto de nacionalidad). Y con las válidas, cada partido como
  quedaría: cada rol con un solo árbitro y cada árbitro con un solo rol; las
  designaciones que lo rompen se rechazan.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ImportarDesignaciones
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- El partido, el árbitro y su designación ya registrados de cada fila pendiente.
    DECLARE @registradas TABLE (
        id_registro     INT PRIMARY KEY,
        id_partido      INT,
        arbitro_existe  BIT,
        pais_conflicto  VARCHAR(60),   -- el país del árbitro, si juega el partido
        rol_actual      VARCHAR(17)    -- el que el árbitro ya tiene en el partido
    );

    IF OBJECT_ID(N'tempdb..#staging_designaciones') IS NULL
        THROW 50001, N'Arbitraje.usp_ImportarDesignaciones: no se importó nada, falta la tabla #staging_designaciones con las designaciones.', 1;

    UPDATE #staging_designaciones
    SET rol = CASE UPPER(NULLIF(TRIM(rol), ''))
                  WHEN 'REFEREE'                           THEN 'PRINCIPAL'
                  WHEN 'ASSISTANT REFEREE 1'               THEN 'ASISTENTE_1'
                  WHEN 'ASSISTANT REFEREE 2'               THEN 'ASISTENTE_2'
                  WHEN 'FOURTH OFFICIAL'                   THEN 'CUARTO'
                  WHEN 'RESERVE ASSISTANT REFEREE'         THEN 'ASISTENTE_RESERVA'
                  WHEN 'VIDEO ASSISTANT REFEREE'           THEN 'VAR'
                  WHEN 'ASSISTANT VIDEO ASSISTANT REFEREE' THEN 'AVAR'
                  WHEN 'SUPPORT VIDEO ASSISTANT REFEREE'   THEN 'VAR_APOYO'
                  ELSE UPPER(NULLIF(TRIM(rol), ''))
              END
    WHERE accion IS NULL;

    INSERT INTO @registradas (id_registro, id_partido, arbitro_existe, pais_conflicto, rol_actual)
    SELECT st.id_registro, p.id_partido, IIF(a.id_arbitro IS NULL, 0, 1),
           (SELECT TOP (1) pa.nombre
            FROM Torneo.SELECCION AS s
            INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
            WHERE s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante) AND s.id_pais = a.id_pais),
           d.rol
    FROM #staging_designaciones AS st
    LEFT JOIN Torneo.PARTIDO AS p ON p.numero_partido = st.numero_partido
    LEFT JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = st.id_arbitro
    LEFT JOIN Arbitraje.DESIGNACION_ARBITRAL AS d ON d.id_partido = p.id_partido AND d.id_arbitro = a.id_arbitro
    WHERE st.accion IS NULL;

    /* 1. Las reglas de cada designación. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.numero_partido IS NULL THEN @nl + N'- El número de partido es obligatorio.'
                 WHEN r.id_partido IS NULL     THEN @nl + N'- No hay un partido con el número '
                                                         + CAST(st.numero_partido AS NVARCHAR(3)) + N'.'
            END,
            CASE WHEN st.id_arbitro IS NULL THEN @nl + N'- El árbitro es obligatorio.'
                 WHEN r.arbitro_existe = 0  THEN @nl + N'- No existe un árbitro con id ' + CAST(st.id_arbitro AS NVARCHAR(10)) + N'.'
            END,
            CASE WHEN st.rol IS NULL THEN @nl + N'- El rol es obligatorio.'
                 WHEN st.rol NOT IN ('PRINCIPAL', 'ASISTENTE_1', 'ASISTENTE_2', 'CUARTO', 'VAR',
                                     'ASISTENTE_RESERVA', 'AVAR', 'VAR_APOYO')
                     THEN @nl + N'- El rol "' + st.rol + N'" no es PRINCIPAL, ASISTENTE_1, ASISTENTE_2, CUARTO, VAR, '
                              + N'ASISTENTE_RESERVA, AVAR ni VAR_APOYO.'
            END,
            IIF(r.pais_conflicto IS NOT NULL,
                @nl + N'- Conflicto de nacionalidad: el árbitro es de ' + r.pais_conflicto + N', que juega este partido.', NULL)), N'')
    FROM #staging_designaciones AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro;

    /* 2. Cada partido como quedaría con las designaciones válidas (las registradas de los árbitros
          que no vienen, más las que vienen): cada rol con un solo árbitro y cada árbitro con un
          solo rol. Las que lo rompen se rechazan. */
    WITH validas AS (
        SELECT st.id_registro, r.id_partido, st.id_arbitro, st.rol
        FROM #staging_designaciones AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
        WHERE st.errores IS NULL
    ),
    equipo AS (
        SELECT id_partido, id_arbitro, rol FROM validas
        UNION ALL
        SELECT d.id_partido, d.id_arbitro, d.rol
        FROM Arbitraje.DESIGNACION_ARBITRAL AS d
        WHERE d.id_partido IN (SELECT id_partido FROM validas)
          AND NOT EXISTS (SELECT 1 FROM validas AS v WHERE v.id_partido = d.id_partido AND v.id_arbitro = d.id_arbitro)
    )
    UPDATE st
    SET errores = CONCAT(IIF(ro.veces > 1, CONCAT(@nl, N'- El rol ', v.rol, N' lo tendrían ', ro.veces, N' árbitros en el partido.'), N''),
                         IIF(ar.veces > 1, CONCAT(@nl, N'- El árbitro viene ', ar.veces, N' veces para el partido.'), N''))
    FROM #staging_designaciones AS st
    INNER JOIN validas AS v ON v.id_registro = st.id_registro
    CROSS APPLY (SELECT COUNT(*) AS veces FROM equipo AS e WHERE e.id_partido = v.id_partido AND e.rol = v.rol) AS ro
    CROSS APPLY (SELECT COUNT(*) AS veces FROM equipo AS e WHERE e.id_partido = v.id_partido AND e.id_arbitro = v.id_arbitro) AS ar
    WHERE ro.veces > 1 OR ar.veces > 1;

    UPDATE #staging_designaciones SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 3. Lo que le pasa a cada designación válida, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN r.rol_actual IS NULL  THEN 'INSERTADO'
                      WHEN r.rol_actual <> st.rol THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_designaciones AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
    WHERE st.accion IS NULL;

    /* 4. Carga, todos juntos. Los cambios de rol van en un solo UPDATE: dos árbitros que se
          intercambian el rol no chocan con la restricción de un rol por partido. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE d
        SET rol = st.rol
        FROM Arbitraje.DESIGNACION_ARBITRAL AS d
        INNER JOIN @registradas AS r ON r.id_partido = d.id_partido
        INNER JOIN #staging_designaciones AS st ON st.id_registro = r.id_registro AND st.id_arbitro = d.id_arbitro
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol)
        SELECT r.id_partido, st.id_arbitro, st.rol
        FROM #staging_designaciones AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
        WHERE st.accion = 'INSERTADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ============================================================================
   PUBLICIDAD
   Las campañas del Dossier Mundial (21_SP_Importar_Publicidad.sql).
   ============================================================================ */

/*
  usp_ImportarCampanias
  Upsert de campañas publicitarias con su anunciante, sus piezas y el
  mercado de interés de cada pieza, desde dos tablas de staging:
    #staging_campanias  una fila por campaña. Columnas que usa: id_registro,
                        anunciante (razón social), id_pais (del anunciante),
                        nombre, fecha_inicio, fecha_fin, errores y accion.
    #staging_piezas     una fila por pieza y mercado. Columnas que usa:
                        id_registro (el de su campaña), titulo, id_idioma e
                        id_pais_interes (NULL: la pieza no trae mercado).
  Clave natural: la razón social del anunciante, el nombre de la campaña en
  ese anunciante y el título de la pieza en esa campaña.
  Valida cada campaña pendiente: anunciante, país del anunciante, nombre y
  fechas obligatorios; razón social y nombre de hasta 150 caracteres; país
  existente; fecha de fin no anterior a la de inicio; al menos una pieza;
  título de cada pieza obligatorio y de hasta 150 caracteres; idioma y país
  de interés existentes; que una pieza no venga con dos idiomas; que no
  venga dos veces la misma campaña del mismo anunciante; que un anunciante
  no venga con países distintos; y que las fechas nuevas de una campaña ya
  cargada no dejen afuera un partido en el que se exhibe una de sus piezas.
  Con eso cubre las reglas de usp_ANUNCIANTE_Alta, usp_CAMPANIA_Alta y
  _Modificacion, usp_PIEZA_PUBLICITARIA_Alta y usp_PIEZA_PAIS_INTERES_Alta.
  Los motivos de las piezas se anotan en su campaña.
  Una campaña queda INSERTADO si no existía; ACTUALIZADO si cambiaron sus
  fechas o el país de su anunciante, o si le falta alguna pieza, el idioma
  de una pieza o un mercado; si no, SIN CAMBIOS. Las piezas y los mercados
  que la campaña ya tiene y no vienen no se borran: pueden estar exhibidas,
  y la exhibición es el historial para facturar.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_ImportarCampanias
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    IF OBJECT_ID(N'tempdb..#staging_campanias') IS NULL OR OBJECT_ID(N'tempdb..#staging_piezas') IS NULL
        THROW 50001, N'Publicidad.usp_ImportarCampanias: no se importó nada, faltan las tablas #staging_campanias y #staging_piezas con las campañas y sus piezas.', 1;

    UPDATE #staging_campanias
    SET anunciante = NULLIF(TRIM(anunciante), N''),
        nombre     = NULLIF(TRIM(nombre), N'')
    WHERE accion IS NULL;

    UPDATE #staging_piezas
    SET titulo = NULLIF(TRIM(titulo), N'');

    /* 1. Cada regla anota su motivo en las campañas que no la cumplen. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.anunciante IS NULL      THEN @nl + N'- El anunciante es obligatorio.'
                 WHEN LEN(st.anunciante) > 150   THEN @nl + N'- La razón social del anunciante no puede superar los 150 caracteres.'
            END,
            CASE WHEN st.id_pais IS NULL THEN @nl + N'- El país del anunciante es obligatorio.'
                 WHEN NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p WHERE p.id_pais = st.id_pais)
                     THEN @nl + N'- No existe el país con id ' + CAST(st.id_pais AS NVARCHAR(10)) + N'.'
            END,
            CASE WHEN st.nombre IS NULL      THEN @nl + N'- El nombre de la campaña es obligatorio.'
                 WHEN LEN(st.nombre) > 150   THEN @nl + N'- El nombre de la campaña no puede superar los 150 caracteres.'
            END,
            CASE WHEN st.fecha_inicio IS NULL OR st.fecha_fin IS NULL
                     THEN @nl + N'- Las fechas de inicio y de fin son obligatorias.'
                 WHEN st.fecha_fin < st.fecha_inicio
                     THEN @nl + N'- La fecha de fin no puede ser anterior a la de inicio.'
            END,
            IIF(NOT EXISTS (SELECT 1 FROM #staging_piezas AS sp WHERE sp.id_registro = st.id_registro),
                @nl + N'- La campaña no tiene piezas.', NULL),
            pz.errores), N'')
    FROM #staging_campanias AS st
    -- Los motivos de sus piezas, una vez cada uno.
    OUTER APPLY (SELECT STRING_AGG(m.motivo, N'') WITHIN GROUP (ORDER BY m.motivo) AS errores
                 FROM (SELECT DISTINCT v.motivo
                       FROM #staging_piezas AS sp
                       LEFT JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = sp.id_idioma
                       LEFT JOIN DatosGenerales.PAIS AS p ON p.id_pais = sp.id_pais_interes
                       CROSS APPLY (VALUES
                           (IIF(sp.titulo IS NULL, @nl + N'- Hay una pieza sin título.', NULL)),
                           (IIF(LEN(sp.titulo) > 150, @nl + N'- El título de la pieza "' + LEFT(sp.titulo, 40)
                                                      + N'..." no puede superar los 150 caracteres.', NULL)),
                           (IIF(sp.id_idioma IS NOT NULL AND i.id_idioma IS NULL,
                                @nl + N'- No existe el idioma con id ' + CAST(sp.id_idioma AS NVARCHAR(10)) + N'.', NULL)),
                           (IIF(sp.id_pais_interes IS NOT NULL AND p.id_pais IS NULL,
                                @nl + N'- No existe el país de interés con id ' + CAST(sp.id_pais_interes AS NVARCHAR(10)) + N'.', NULL))
                       ) AS v (motivo)
                       WHERE sp.id_registro = st.id_registro AND v.motivo IS NOT NULL) AS m) AS pz
    WHERE st.accion IS NULL;

    -- Una pieza con dos idiomas: no se sabe cuál es.
    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- La pieza "', d.titulo, N'" viene con idiomas distintos.')
    FROM #staging_campanias AS st
    INNER JOIN (SELECT id_registro, MIN(titulo) AS titulo
                FROM (SELECT id_registro, titulo
                      FROM #staging_piezas
                      WHERE titulo IS NOT NULL
                      GROUP BY id_registro, titulo
                      HAVING COUNT(DISTINCT id_idioma) > 1) AS x
                GROUP BY id_registro) AS d ON d.id_registro = st.id_registro
    WHERE st.accion IS NULL;

    -- La misma campaña del mismo anunciante más de una vez: no se sabe cuál cargar y se rechazan todas.
    WITH repetidas AS (
        SELECT errores, COUNT(*) OVER (PARTITION BY anunciante, nombre) AS veces
        FROM #staging_campanias
        WHERE accion IS NULL AND anunciante IS NOT NULL AND nombre IS NOT NULL
    )
    UPDATE repetidas
    SET errores = CONCAT(errores, @nl, N'- Esta campaña del mismo anunciante viene ', veces, N' veces.')
    WHERE veces > 1;

    -- Un anunciante es de un solo país.
    WITH anunciantes AS (
        SELECT errores,
               MIN(id_pais) OVER (PARTITION BY anunciante) AS pais_minimo,
               MAX(id_pais) OVER (PARTITION BY anunciante) AS pais_maximo
        FROM #staging_campanias
        WHERE accion IS NULL AND anunciante IS NOT NULL AND id_pais IS NOT NULL
    )
    UPDATE anunciantes
    SET errores = CONCAT(errores, @nl, N'- El anunciante viene con países distintos en sus campañas.')
    WHERE pais_minimo <> pais_maximo;

    -- Las fechas nuevas de una campaña cargada no pueden dejar afuera un partido en el que ya se exhibe.
    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- Con esas fechas quedaría afuera el partido ', x.numero_partido,
                         N', en el que ya se exhibe una pieza de la campaña.')
    FROM #staging_campanias AS st
    INNER JOIN Publicidad.ANUNCIANTE AS an ON an.razon_social = st.anunciante
    INNER JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante AND c.nombre = st.nombre
    CROSS APPLY (SELECT TOP (1) p.numero_partido
                 FROM Publicidad.EXHIBICION AS e
                 INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = e.id_pieza
                 INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = e.id_partido
                 WHERE pz.id_campania = c.id_campania
                   AND CAST(p.fecha_hora_local AS DATE) NOT BETWEEN st.fecha_inicio AND st.fecha_fin
                 ORDER BY p.numero_partido) AS x
    WHERE st.accion IS NULL AND st.fecha_fin >= st.fecha_inicio;

    UPDATE #staging_campanias SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 2. Lo que le pasa a cada campaña válida, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN c.id_campania IS NULL THEN 'INSERTADO'
                      WHEN c.fecha_inicio <> st.fecha_inicio OR c.fecha_fin <> st.fecha_fin OR an.id_pais <> st.id_pais
                           OR EXISTS (SELECT 1
                                      FROM #staging_piezas AS sp
                                      LEFT JOIN Publicidad.PIEZA_PUBLICITARIA AS pz
                                             ON pz.id_campania = c.id_campania AND pz.titulo = sp.titulo
                                      WHERE sp.id_registro = st.id_registro
                                        AND (pz.id_pieza IS NULL
                                             OR (sp.id_idioma IS NOT NULL AND pz.id_idioma IS DISTINCT FROM sp.id_idioma)
                                             OR (sp.id_pais_interes IS NOT NULL
                                                 AND NOT EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
                                                                 WHERE ppi.id_pieza = pz.id_pieza
                                                                   AND ppi.id_pais = sp.id_pais_interes))))
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_campanias AS st
    LEFT JOIN Publicidad.ANUNCIANTE AS an ON an.razon_social = st.anunciante
    LEFT JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante AND c.nombre = st.nombre
    WHERE st.accion IS NULL;

    /* 3. Carga, todas juntas. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- Anunciantes nuevos, y los que cambiaron de país.
        INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais)
        SELECT DISTINCT st.anunciante, st.id_pais
        FROM #staging_campanias AS st
        WHERE st.accion IN ('INSERTADO', 'ACTUALIZADO')
          AND NOT EXISTS (SELECT 1 FROM Publicidad.ANUNCIANTE AS an WHERE an.razon_social = st.anunciante);

        UPDATE an
        SET id_pais = st.id_pais
        FROM Publicidad.ANUNCIANTE AS an
        INNER JOIN (SELECT DISTINCT anunciante, id_pais FROM #staging_campanias
                    WHERE accion IN ('INSERTADO', 'ACTUALIZADO')) AS st ON st.anunciante = an.razon_social
        WHERE an.id_pais <> st.id_pais;

        -- Campañas: las que cambiaron de fechas y las nuevas.
        UPDATE c
        SET fecha_inicio = st.fecha_inicio, fecha_fin = st.fecha_fin
        FROM Publicidad.CAMPANIA AS c
        INNER JOIN Publicidad.ANUNCIANTE AS an ON an.id_anunciante = c.id_anunciante
        INNER JOIN #staging_campanias AS st ON st.anunciante = an.razon_social AND st.nombre = c.nombre
        WHERE st.accion = 'ACTUALIZADO' AND (c.fecha_inicio <> st.fecha_inicio OR c.fecha_fin <> st.fecha_fin);

        INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin)
        SELECT an.id_anunciante, st.nombre, st.fecha_inicio, st.fecha_fin
        FROM #staging_campanias AS st
        INNER JOIN Publicidad.ANUNCIANTE AS an ON an.razon_social = st.anunciante
        WHERE st.accion = 'INSERTADO';

        -- Piezas: una por título en cada campaña, con el idioma que traiga (si no trae, no se borra el guardado).
        WITH piezas AS (
            SELECT c.id_campania, sp.titulo, MAX(sp.id_idioma) AS id_idioma
            FROM #staging_piezas AS sp
            INNER JOIN #staging_campanias AS st ON st.id_registro = sp.id_registro
            INNER JOIN Publicidad.ANUNCIANTE AS an ON an.razon_social = st.anunciante
            INNER JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante AND c.nombre = st.nombre
            WHERE st.accion IN ('INSERTADO', 'ACTUALIZADO')
            GROUP BY c.id_campania, sp.titulo
        )
        UPDATE pz
        SET id_idioma = p.id_idioma
        FROM Publicidad.PIEZA_PUBLICITARIA AS pz
        INNER JOIN piezas AS p ON p.id_campania = pz.id_campania AND p.titulo = pz.titulo
        WHERE p.id_idioma IS NOT NULL AND pz.id_idioma IS DISTINCT FROM p.id_idioma;

        WITH piezas AS (
            SELECT c.id_campania, sp.titulo, MAX(sp.id_idioma) AS id_idioma
            FROM #staging_piezas AS sp
            INNER JOIN #staging_campanias AS st ON st.id_registro = sp.id_registro
            INNER JOIN Publicidad.ANUNCIANTE AS an ON an.razon_social = st.anunciante
            INNER JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante AND c.nombre = st.nombre
            WHERE st.accion IN ('INSERTADO', 'ACTUALIZADO')
            GROUP BY c.id_campania, sp.titulo
        )
        INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo)
        SELECT p.id_campania, p.id_idioma, p.titulo
        FROM piezas AS p
        WHERE NOT EXISTS (SELECT 1 FROM Publicidad.PIEZA_PUBLICITARIA AS pz
                          WHERE pz.id_campania = p.id_campania AND pz.titulo = p.titulo);

        -- Mercados de interés que les faltan a las piezas.
        INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
        SELECT DISTINCT pz.id_pieza, sp.id_pais_interes
        FROM #staging_piezas AS sp
        INNER JOIN #staging_campanias AS st ON st.id_registro = sp.id_registro
        INNER JOIN Publicidad.ANUNCIANTE AS an ON an.razon_social = st.anunciante
        INNER JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante AND c.nombre = st.nombre
        INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania AND pz.titulo = sp.titulo
        WHERE st.accion IN ('INSERTADO', 'ACTUALIZADO')
          AND sp.id_pais_interes IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
                          WHERE ppi.id_pieza = pz.id_pieza AND ppi.id_pais = sp.id_pais_interes);

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- Los tipos de tabla de la versión anterior, por si la base los tiene. Los SP en bloque los
-- recibían como parámetro; ahora ninguno los usa así, y un tipo que un SP solo usa en una
-- variable se puede borrar (los procesos de 23 a 28 que los usaban se recrean después).
DROP TYPE IF EXISTS DatosGenerales.TT_INDICADOR_ECONOMICO;
DROP TYPE IF EXISTS DatosGenerales.TT_COTIZACION;
DROP TYPE IF EXISTS DatosGenerales.TT_FERIADO;
DROP TYPE IF EXISTS Torneo.TT_SEDE;
DROP TYPE IF EXISTS Torneo.TT_SELECCION;
DROP TYPE IF EXISTS Torneo.TT_JUGADOR;
DROP TYPE IF EXISTS Torneo.TT_PARTIDO;
DROP TYPE IF EXISTS DesarrolloPartido.TT_ALINEACION_PARTIDO;
DROP TYPE IF EXISTS DesarrolloPartido.TT_CAMBIO;
DROP TYPE IF EXISTS DesarrolloPartido.TT_GOL;
DROP TYPE IF EXISTS DesarrolloPartido.TT_AMONESTACION;
GO


-- Evidencia: SP de importación creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE p.name LIKE N'usp[_]Importar%' OR p.name IN (N'usp_RegistrarImportacion', N'usp_BorrarImportacion')
ORDER BY s.name, p.name;
GO
