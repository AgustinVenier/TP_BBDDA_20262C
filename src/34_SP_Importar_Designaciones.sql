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

 Fecha: 03/11/2026
 Archivo: 34_SP_Importar_Designaciones.sql
 Objetivo: Crear el proceso de importación de las designaciones arbitrales
           desde el CSV que genera el scraping de Wikipedia (scraping/README.md):
             Arbitraje.usp_ImportarDesignacionesCSV  importa designaciones.csv
           Los partidos y las selecciones tienen que estar cargados antes
           (Torneo.usp_ImportarPartidosJSON, en 23_SP_Importar_Mundial2026.sql).
           Requiere haber ejecutado 00 a 23. Su script de testing es
           74_Test_SP_Importar_Designaciones.sql.
================================================================================

 Formato: CSV en UTF-8, separado por comas, con comillas solo en los valores
 que las necesitan, y esta primera fila con los nombres de las columnas:
   fecha,codigo_local,codigo_visitante,rol,nombre,apellido,pais,codigo_pais
 Una fila por partido y rol. La fecha es la local del partido (AAAA-MM-DD), las
 selecciones se identifican por su código FIFA en cualquier orden, y el rol es
 PRINCIPAL, ASISTENTE_1, ASISTENTE_2, CUARTO o VAR. codigo_pais es el código FIFA
 del país del árbitro (la columna pais, con su nombre, es solo informativa).

 Cómo importa (igual que 23, 24, 25, 27 y 28, pero sin SP masivo en 16: la
 designación y el alta del árbitro se resuelven acá, con un SELECT y un INSERT):
   1. Se controla el archivo: que se pueda leer y que su primera fila tenga
      esas columnas. Si no, o si alguna fila no es CSV válido, no se importa
      nada (THROW 50002).
   2. BULK INSERT pasa las filas, tal como vienen, a una tabla temporal, y de
      ahí a #staging_designaciones, donde se convierte la fecha.
   3. Se aplican las reglas sobre toda la tabla, con UPDATE: el rol, el nombre
      y el apellido; que existan el partido y el país del árbitro; el conflicto
      de nacionalidad; que el partido no tenga ya a otro en ese rol y que un
      árbitro no figure dos veces en un partido. Cada fila que no las cumple
      se marca RECHAZADO con sus motivos.
   4. Con un INSERT se dan de alta los árbitros que todavía no están (categoría
      FIFA: el archivo trae solo a los designados por la FIFA para el Mundial) y
      con otro se cargan todas las designaciones válidas. En la misma
      transacción se registra la importación (DatosGenerales.IMPORTACION, su
      número queda en @id_importacion) y las filas rechazadas, en
      Arbitraje.ERRORES_DESIGNACION.
   5. Se devuelve el resumen y los rechazados con sus motivos.
   Importar dos veces el mismo archivo no duplica nada: una designación que ya
   está cargada queda SIN CAMBIOS, y un árbitro se reconoce por su país,
   apellido y nombre.

 A diferencia de Arbitraje.usp_DesignarTernaArbitral, que designa antes del
 partido, acá se cargan designaciones de partidos ya jugados: no se exige el
 estado PROGRAMADO ni que pasen 24 horas entre dos partidos de un mismo árbitro.
 Los idiomas de los árbitros no vienen en la fuente: quedan sin cargar.

 Se usa SQL dinámico solo para leer el archivo, porque BULK INSERT no acepta
 la ruta en una variable.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_ImportarDesignacionesCSV
  Importa las designaciones arbitrales del CSV @ruta_archivo.
  Valida: ruta obligatoria y terminada en .csv. Si el archivo no se puede
  leer, no tiene las columnas esperadas o alguna fila no es CSV válido, no se
  importa nada (THROW 50002). Rechaza las filas con un rol, un nombre o un
  apellido inválidos, de un partido o un país que no existen, con conflicto de
  nacionalidad, repetidas o que contradicen una designación ya cargada. Registra
  la importación (su número queda en @id_importacion) y los rechazados en
  Arbitraje.ERRORES_DESIGNACION, y devuelve el resumen y los rechazados con sus
  motivos.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ImportarDesignacionesCSV
    @ruta_archivo    NVARCHAR(400),
    @id_importacion  INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores         NVARCHAR(2048) = N'';
    DECLARE @nl              NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido       NVARCHAR(MAX);
    DECLARE @encabezado      NVARCHAR(400);
    DECLARE @mensaje         NVARCHAR(2048);
    DECLARE @sql             NVARCHAR(MAX);
    DECLARE @tran_propia     BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso         VARCHAR(100)   = CONCAT(OBJECT_SCHEMA_NAME(@@PROCID), '.', OBJECT_NAME(@@PROCID));
    DECLARE @leidos          INT;
    DECLARE @insertados      INT;
    DECLARE @sin_cambios     INT;
    DECLARE @rechazados      INT;
    DECLARE @arbitros_nuevos INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @nl + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.csv'
        SET @errores += @nl + N'- El archivo tiene que ser un .csv (el designaciones.csv del scraping).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ImportarDesignacionesCSV: no se pudo importar el archivo.' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* 1. El archivo: la primera fila tiene que tener las columnas esperadas. */
    EXEC DatosGenerales.usp_LeerArchivoUTF8 @ruta_archivo = @ruta_archivo, @contenido = @contenido OUTPUT;

    SET @encabezado = REPLACE(REPLACE(LEFT(@contenido, CHARINDEX(NCHAR(10), @contenido + NCHAR(10)) - 1),
                                      NCHAR(13), N''), N' ', N'');
    IF @encabezado <> N'fecha,codigo_local,codigo_visitante,rol,nombre,apellido,pais,codigo_pais'
    BEGIN
        SET @mensaje = N'Arbitraje.usp_ImportarDesignacionesCSV: no se importó nada, la primera fila del archivo tiene que ser '
                     + N'"fecha,codigo_local,codigo_visitante,rol,nombre,apellido,pais,codigo_pais" y es "'
                     + LEFT(@encabezado, 200) + N'".';
        THROW 50002, @mensaje, 1;
    END;

    /* 2. Las filas, como vienen. FORMAT = 'CSV' respeta las comillas. El fin de
          línea es el del archivo: CRLF (Windows) o LF. */
    CREATE TABLE #crudo (
        fecha_txt         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        codigo_local      NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        codigo_visitante  NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        rol               NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        pais              NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        codigo_pais       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL
    );

    BEGIN TRY
        SET @sql = N'BULK INSERT #crudo FROM N''' + REPLACE(@ruta_archivo, N'''', N'''''')
                 + N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', FIELDTERMINATOR = '','', '
                 + N'ROWTERMINATOR = ''' + IIF(CHARINDEX(NCHAR(13) + NCHAR(10), @contenido) > 0, N'0x0d0a', N'0x0a')
                 + N''', FIELDQUOTE = ''"'', MAXERRORS = 0);';
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'Arbitraje.usp_ImportarDesignacionesCSV: no se importó nada, hay filas que no son CSV válido '
                     + N'(tienen que tener 8 columnas): ' + ERROR_MESSAGE();
        THROW 50002, @mensaje, 1;
    END CATCH;

    CREATE TABLE #staging_designaciones (
        id_registro       INT PRIMARY KEY,   -- línea del archivo
        -- Tal como vienen en el archivo
        fecha_txt         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        codigo_local      NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        codigo_visitante  NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        rol               NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        pais              NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        codigo_pais       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        -- Lo que se resuelve contra la base
        fecha             DATE          NULL,
        id_partido        INT           NULL,
        id_pais           SMALLINT      NULL,
        id_arbitro        INT           NULL,
        -- Lo que le pasa a cada registro
        errores           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion            VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    INSERT INTO #staging_designaciones (id_registro, fecha_txt, codigo_local, codigo_visitante, rol, nombre, apellido, pais, codigo_pais)
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) + 1,
           NULLIF(TRIM(fecha_txt), N''), UPPER(NULLIF(TRIM(codigo_local), N'')), UPPER(NULLIF(TRIM(codigo_visitante), N'')),
           UPPER(NULLIF(TRIM(rol), N'')), NULLIF(TRIM(nombre), N''), NULLIF(TRIM(apellido), N''), NULLIF(TRIM(pais), N''),
           UPPER(NULLIF(TRIM(REPLACE(codigo_pais, NCHAR(13), N'')), N''))
    FROM #crudo
    WHERE CONCAT(fecha_txt, codigo_local, codigo_visitante, rol, nombre, apellido, pais, REPLACE(codigo_pais, NCHAR(13), N'')) <> N'';

    /* 3. Las reglas, sobre toda la tabla. */
    -- La fecha, el rol, el nombre y el apellido.
    UPDATE #staging_designaciones
    SET fecha  = TRY_CONVERT(DATE, fecha_txt, 23);

    UPDATE #staging_designaciones
    SET errores = NULLIF(CONCAT(
            IIF(fecha IS NULL, @nl + N'- La fecha "' + ISNULL(fecha_txt, N'') + N'" no es una fecha AAAA-MM-DD.', NULL),
            IIF(codigo_local IS NULL OR codigo_visitante IS NULL,
                @nl + N'- Faltan los códigos de las dos selecciones del partido.', NULL),
            IIF(ISNULL(rol, N'') NOT IN (N'PRINCIPAL', N'ASISTENTE_1', N'ASISTENTE_2', N'CUARTO', N'VAR'),
                @nl + N'- El rol "' + ISNULL(rol, N'') + N'" no es PRINCIPAL, ASISTENTE_1, ASISTENTE_2, CUARTO ni VAR.', NULL),
            IIF(nombre IS NULL, @nl + N'- El nombre es obligatorio.',
                IIF(LEN(nombre) > 60, @nl + N'- El nombre no puede superar los 60 caracteres.', NULL)),
            IIF(apellido IS NULL, @nl + N'- El apellido es obligatorio.',
                IIF(LEN(apellido) > 60, @nl + N'- El apellido no puede superar los 60 caracteres.', NULL))), N'');

    -- El país del árbitro y el partido (por fecha local y selecciones, en cualquier orden).
    UPDATE st
    SET id_pais = pa.id_pais
    FROM #staging_designaciones AS st
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = st.codigo_pais;

    UPDATE st
    SET id_partido = par.id_partido
    FROM #staging_designaciones AS st
    CROSS APPLY (SELECT CASE WHEN COUNT(*) = 1 THEN MIN(p.id_partido) END AS id_partido
                 FROM Torneo.PARTIDO AS p
                 INNER JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = p.id_seleccion_local
                 INNER JOIN DatosGenerales.PAIS AS pl ON pl.id_pais = sl.id_pais
                 INNER JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = p.id_seleccion_visitante
                 INNER JOIN DatosGenerales.PAIS AS pv ON pv.id_pais = sv.id_pais
                 WHERE CAST(p.fecha_hora_local AS DATE) = st.fecha
                   AND ((pl.codigo_fifa = st.codigo_local AND pv.codigo_fifa = st.codigo_visitante)
                     OR (pl.codigo_fifa = st.codigo_visitante AND pv.codigo_fifa = st.codigo_local))) AS par
    WHERE st.fecha IS NOT NULL;

    UPDATE #staging_designaciones
    SET errores = CONCAT(errores, IIF(id_pais IS NULL,
            @nl + N'- El país del árbitro ' + ISNULL(pais + N' ', N'') + N'(código ' + ISNULL(codigo_pais, N'sin código') + N') no está cargado.', NULL))
    WHERE id_pais IS NULL;

    UPDATE #staging_designaciones
    SET errores = CONCAT(errores,
            @nl + N'- No hay un partido (o hay más de uno) entre ', codigo_local, N' y ', codigo_visitante, N' el ', fecha_txt, N'.')
    WHERE id_partido IS NULL AND fecha IS NOT NULL AND codigo_local IS NOT NULL AND codigo_visitante IS NOT NULL;

    -- Conflicto de nacionalidad: ninguno puede ser del país de una de las dos selecciones.
    UPDATE st
    SET errores = CONCAT(st.errores, @nl + N'- Conflicto de nacionalidad: ', st.apellido, N', ', st.nombre, N' (', st.rol,
                         N') es de ', pa.nombre, N', que juega este partido.')
    FROM #staging_designaciones AS st
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = st.id_partido
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = st.id_pais
    INNER JOIN Torneo.SELECCION AS s ON s.id_pais = st.id_pais AND s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante);

    -- Repetidas en el archivo: un solo árbitro por rol y un solo rol por árbitro en cada partido. Se cuentan
    -- solo las filas que llegan sin errores, y la primera es la que queda.
    WITH por_rol AS (
        SELECT errores, ROW_NUMBER() OVER (PARTITION BY id_partido, rol ORDER BY id_registro) AS n
        FROM #staging_designaciones
        WHERE id_partido IS NOT NULL AND errores IS NULL
    )
    UPDATE por_rol
    SET errores = @nl + N'- El archivo trae a más de un árbitro con ese rol en el mismo partido (se toma el primero).'
    WHERE n > 1;

    WITH por_arbitro AS (
        SELECT errores, ROW_NUMBER() OVER (PARTITION BY id_partido, id_pais, apellido, nombre ORDER BY id_registro) AS n
        FROM #staging_designaciones
        WHERE id_partido IS NOT NULL AND errores IS NULL
    )
    UPDATE por_arbitro
    SET errores = @nl + N'- Un mismo árbitro no puede cumplir dos roles en el partido.'
    WHERE n > 1;

    -- Los árbitros que ya están registrados, y lo que ya está designado.
    UPDATE st
    SET id_arbitro = a.id_arbitro
    FROM #staging_designaciones AS st
    INNER JOIN Arbitraje.ARBITRO AS a ON a.id_pais = st.id_pais AND a.apellido = st.apellido AND a.nombre = st.nombre
    WHERE st.errores IS NULL;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl + N'- ', st.apellido, N', ', st.nombre, N' no está activo.')
    FROM #staging_designaciones AS st
    INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = st.id_arbitro
    WHERE st.errores IS NULL AND a.activo = 0;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl + N'- ', st.apellido, N', ', st.nombre, N' no puede ser ', st.rol,
                         N': tiene que ser de categoría FIFA.')
    FROM #staging_designaciones AS st
    INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = st.id_arbitro
    WHERE st.errores IS NULL AND st.rol IN (N'PRINCIPAL', N'VAR') AND a.categoria <> 'FIFA';

    UPDATE st
    SET accion = 'SIN CAMBIOS'
    FROM #staging_designaciones AS st
    INNER JOIN Arbitraje.DESIGNACION_ARBITRAL AS d
        ON d.id_partido = st.id_partido AND d.id_arbitro = st.id_arbitro AND d.rol = st.rol
    WHERE st.errores IS NULL;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl + N'- El partido ya tiene designado a otro árbitro como ', st.rol,
                         N': los cambios se hacen con usp_DESIGNACION_ARBITRAL_Baja y usp_DESIGNACION_ARBITRAL_Alta.')
    FROM #staging_designaciones AS st
    WHERE st.errores IS NULL AND st.accion IS NULL
      AND EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL AS d WHERE d.id_partido = st.id_partido AND d.rol = st.rol);

    UPDATE st
    SET errores = CONCAT(st.errores, @nl + N'- ', st.apellido, N', ', st.nombre,
                         N' ya está designado en este partido con otro rol.')
    FROM #staging_designaciones AS st
    WHERE st.errores IS NULL AND st.accion IS NULL
      AND EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL AS d WHERE d.id_partido = st.id_partido AND d.id_arbitro = st.id_arbitro);

    UPDATE #staging_designaciones SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. Los árbitros nuevos y las designaciones válidas, con un INSERT cada uno; después se registran la
          importación y sus rechazados, en la misma transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria)
        SELECT DISTINCT id_pais, nombre, apellido, 'FIFA'
        FROM #staging_designaciones
        WHERE accion IS NULL AND id_arbitro IS NULL;

        SET @arbitros_nuevos = @@ROWCOUNT;

        UPDATE st
        SET id_arbitro = a.id_arbitro
        FROM #staging_designaciones AS st
        INNER JOIN Arbitraje.ARBITRO AS a ON a.id_pais = st.id_pais AND a.apellido = st.apellido AND a.nombre = st.nombre
        WHERE st.accion IS NULL AND st.id_arbitro IS NULL;

        INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol)
        SELECT id_partido, id_arbitro, rol
        FROM #staging_designaciones
        WHERE accion IS NULL;

        UPDATE #staging_designaciones SET accion = 'INSERTADO' WHERE accion IS NULL;

        SELECT @leidos      = COUNT(*),
               @insertados  = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @sin_cambios = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @rechazados  = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_designaciones;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @ruta_archivo, @leidos = @leidos, @insertados = @insertados,
            @actualizados = 0, @sin_cambios = @sin_cambios, @rechazados = @rechazados,
            @id_importacion = @id_importacion OUTPUT;

        INSERT INTO Arbitraje.ERRORES_DESIGNACION (id_importacion, registro, fecha, codigo_local, codigo_visitante, rol,
                                                   nombre, apellido, codigo_pais, motivos)
        SELECT @id_importacion, id_registro, fecha_txt, codigo_local, codigo_visitante, rol, nombre, apellido,
               codigo_pais, STUFF(errores, 1, 2, N'')
        FROM #staging_designaciones
        WHERE accion = 'RECHAZADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    /* 5. Resultado. */
    SELECT @id_importacion AS id_importacion, @ruta_archivo AS origen, @leidos AS leidos, @insertados AS insertados,
           0 AS actualizados, @sin_cambios AS sin_cambios, @rechazados AS rechazados,
           @arbitros_nuevos AS arbitros_nuevos;

    SELECT CONCAT(N'Línea ', registro, N': ', ISNULL(fecha, N'(sin fecha)'), N' ', ISNULL(codigo_local, N'?'), N'-',
                  ISNULL(codigo_visitante, N'?'), N' ', ISNULL(rol, N'(sin rol)'), N' ', ISNULL(nombre, N''), N' ',
                  ISNULL(apellido, N'')) AS rechazado,
           motivos
    FROM Arbitraje.ERRORES_DESIGNACION
    WHERE id_importacion = @id_importacion
    ORDER BY registro;
END;
GO


-- Evidencia: SP de importación de designaciones creado.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Arbitraje' AND p.name = N'usp_ImportarDesignacionesCSV';
GO
