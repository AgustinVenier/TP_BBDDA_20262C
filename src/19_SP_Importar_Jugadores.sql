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

 Fecha: 02/11/2026
 Archivo: 19_SP_Importar_Jugadores.sql
 Objetivo: Crear el proceso de importación de las listas de convocados y de
           los directores técnicos desde los CSV que genera el scraping de
           Wikipedia (scraping/README.md):
             Torneo.usp_ImportarJugadoresCSV      importa el archivo jugadores.csv
             Torneo.usp_ImportarCuerpoTecnicoCSV  importa el archivo cuerpo_tecnico.csv
           Las selecciones y sus listas tienen que estar cargadas antes
           (Torneo.usp_ImportarSeleccionesJSON, en 18_SP_Importar_Mundial2026.sql).
           Requiere haber ejecutado 01 a 18. Su script de testing es
           69_Test_SP_Importar_Jugadores.sql.
================================================================================

 Lo que sigue describe la importación de jugadores; la del cuerpo técnico
 sigue los mismos pasos con Torneo.usp_CargarCuerpoTecnico (ver su comentario).

 Formato: CSV en UTF-8, separado por comas, con comillas solo en los valores
 que las necesitan, y esta primera fila con los nombres de las columnas:
   codigo_fifa,dorsal,posicion,nombre,apellido,fecha_nacimiento,club
 La posición viene como GK, DF, MF o FW y la fecha como AAAA-MM-DD.

 Cómo importa (igual que 18, 21, 22 y 23):
   1. Se controla el archivo: que se pueda leer y que su primera fila tenga
      esas columnas. Si no, o si alguna fila no es CSV válido, no se importa
      nada (THROW 50002).
   2. BULK INSERT pasa las filas, tal como vienen, a una tabla temporal, y
      de ahí a #staging_jugadores, la tabla que lee el SP de la Entrega 5,
      donde se convierten el dorsal y la fecha de nacimiento.
   3. Se rechazan las filas que no se pudieron convertir: un UPDATE sobre
      toda la tabla anota el motivo y las marca RECHAZADO.
   4. Torneo.usp_CargarJugadores (16_SP_CargaMasiva.sql) valida las demás
      con las reglas de los jugadores y de cada lista de convocados, marca
      las que no las cumplen y carga las válidas, todas juntas. En la misma
      transacción se registra la importación (DatosGenerales.IMPORTACION, su
      número queda en @id_importacion) y las filas rechazadas, en
      Torneo.ERRORES_JUGADOR.
   5. Se devuelve el resumen y los rechazados con sus motivos.
   Importar dos veces el mismo archivo no duplica nada: un jugador se
   reconoce por su selección, apellido y nombre.

 Se usa SQL dinámico solo para leer el archivo, porque BULK INSERT no acepta
 la ruta en una variable.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_ImportarJugadoresCSV
  Importa los jugadores del CSV @ruta_archivo con usp_CargarJugadores.
  Valida: ruta obligatoria y terminada en .csv. Si el archivo no se puede
  leer, no tiene las columnas esperadas o alguna fila no es CSV válido, no se
  importa nada (THROW 50002). Rechaza las filas con un dorsal o una fecha de
  nacimiento que no se pueden convertir; las reglas de los jugadores las
  aplica usp_CargarJugadores. Registra la importación (su número queda en
  @id_importacion) y los rechazados en Torneo.ERRORES_JUGADOR, y devuelve el
  resumen y los rechazados con sus motivos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarJugadoresCSV
    @ruta_archivo    NVARCHAR(400),
    @id_importacion  INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido     NVARCHAR(MAX);
    DECLARE @encabezado    NVARCHAR(400);
    DECLARE @mensaje       NVARCHAR(2048);
    DECLARE @sql           NVARCHAR(MAX);
    DECLARE @tran_propia   BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso       VARCHAR(100)   = CONCAT(OBJECT_SCHEMA_NAME(@@PROCID), '.', OBJECT_NAME(@@PROCID));
    DECLARE @leidos        INT;
    DECLARE @insertados    INT;
    DECLARE @actualizados  INT;
    DECLARE @sin_cambios   INT;
    DECLARE @rechazados    INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @nl + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.csv'
        SET @errores += @nl + N'- El archivo tiene que ser un .csv (el jugadores.csv del scraping).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarJugadoresCSV: no se pudo importar el archivo.' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* 1. El archivo: la primera fila tiene que tener las columnas esperadas. */
    EXEC DatosGenerales.usp_LeerArchivoUTF8 @ruta_archivo = @ruta_archivo, @contenido = @contenido OUTPUT;

    SET @encabezado = REPLACE(REPLACE(LEFT(@contenido, CHARINDEX(NCHAR(10), @contenido + NCHAR(10)) - 1),
                                      NCHAR(13), N''), N' ', N'');
    IF @encabezado <> N'codigo_fifa,dorsal,posicion,nombre,apellido,fecha_nacimiento,club'
    BEGIN
        SET @mensaje = N'Torneo.usp_ImportarJugadoresCSV: no se importó nada, la primera fila del archivo tiene que ser '
                     + N'"codigo_fifa,dorsal,posicion,nombre,apellido,fecha_nacimiento,club" y es "'
                     + LEFT(@encabezado, 200) + N'".';
        THROW 50002, @mensaje, 1;
    END;

    /* 2. Las filas, como vienen. FORMAT = 'CSV' respeta las comillas. El fin de
          línea es el del archivo: CRLF (Windows) o LF. */
    CREATE TABLE #crudo (
        codigo_fifa       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        dorsal_txt        NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        posicion_txt      NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        fecha_txt         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        club              NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL
    );

    BEGIN TRY
        SET @sql = N'BULK INSERT #crudo FROM N''' + REPLACE(@ruta_archivo, N'''', N'''''')
                 + N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', FIELDTERMINATOR = '','', '
                 + N'ROWTERMINATOR = ''' + IIF(CHARINDEX(NCHAR(13) + NCHAR(10), @contenido) > 0, N'0x0d0a', N'0x0a')
                 + N''', FIELDQUOTE = ''"'', MAXERRORS = 0);';
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'Torneo.usp_ImportarJugadoresCSV: no se importó nada, hay filas que no son CSV válido '
                     + N'(tienen que tener 7 columnas): ' + ERROR_MESSAGE();
        THROW 50002, @mensaje, 1;
    END CATCH;

    -- usp_CargarJugadores lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_jugadores (
        id_registro       INT PRIMARY KEY,   -- línea del archivo
        -- Tal como vienen en el archivo
        dorsal_txt        NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        posicion_txt      NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        fecha_txt         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        -- Lo que lee usp_CargarJugadores, ya convertido
        codigo_fifa       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        posicion          VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
        dorsal            TINYINT       NULL,
        fecha_nacimiento  DATE          NULL,
        club_origen       NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        -- Lo que le pasa a cada registro: lo completan este SP y usp_CargarJugadores
        errores           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion            VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    INSERT INTO #staging_jugadores (id_registro, codigo_fifa, dorsal_txt, posicion_txt, nombre, apellido, fecha_txt, club_origen)
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) + 1,
           UPPER(NULLIF(TRIM(codigo_fifa), N'')), NULLIF(TRIM(dorsal_txt), N''), UPPER(NULLIF(TRIM(posicion_txt), N'')),
           NULLIF(TRIM(nombre), N''), NULLIF(TRIM(apellido), N''), NULLIF(TRIM(fecha_txt), N''),
           NULLIF(TRIM(REPLACE(club, NCHAR(13), N'')), N'')
    FROM #crudo
    WHERE CONCAT(codigo_fifa, dorsal_txt, posicion_txt, nombre, apellido, fecha_txt, REPLACE(club, NCHAR(13), N'')) <> N'';

    -- La posición pasa como viene (GK, DF, MF o FW): la traduce usp_CargarJugadores.
    UPDATE #staging_jugadores
    SET dorsal           = TRY_CONVERT(TINYINT, dorsal_txt),
        fecha_nacimiento = TRY_CONVERT(DATE, fecha_txt, 23),
        posicion         = LEFT(posicion_txt, 30);

    /* 3. Lo que no se pudo convertir. Las reglas de los jugadores las aplica usp_CargarJugadores. */
    UPDATE #staging_jugadores
    SET errores = NULLIF(CONCAT(
            IIF(dorsal_txt IS NOT NULL AND dorsal IS NULL,
                @nl + N'- El dorsal "' + dorsal_txt + N'" no es un número entre 1 y 99.', NULL),
            IIF(fecha_txt IS NOT NULL AND fecha_nacimiento IS NULL,
                @nl + N'- La fecha de nacimiento "' + fecha_txt + N'" no es una fecha AAAA-MM-DD.', NULL)), N'');

    UPDATE #staging_jugadores SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. El SP de la Entrega 5 valida las demás y carga las válidas, todas juntas; después se
          registran la importación y sus rechazados, en la misma transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Torneo.usp_CargarJugadores;

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_jugadores;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @ruta_archivo, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @rechazados = @rechazados,
            @id_importacion = @id_importacion OUTPUT;

        INSERT INTO Torneo.ERRORES_JUGADOR (id_importacion, registro, codigo_fifa, dorsal, posicion, nombre, apellido,
                                            fecha_nacimiento, club, motivos)
        SELECT @id_importacion, id_registro, codigo_fifa, dorsal_txt, posicion_txt, nombre, apellido, fecha_txt, club_origen,
               STUFF(errores, 1, 2, N'')
        FROM #staging_jugadores
        WHERE accion = 'RECHAZADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    /* 5. Resultado. */
    SELECT @id_importacion AS id_importacion, @ruta_archivo AS origen, @leidos AS leidos, @insertados AS insertados,
           @actualizados AS actualizados, @sin_cambios AS sin_cambios, @rechazados AS rechazados;

    SELECT CONCAT(N'Línea ', registro, N': ', ISNULL(codigo_fifa, N'(sin selección)'), N' ',
                  ISNULL(dorsal, N'(sin dorsal)'), N' ', ISNULL(nombre, N''), N' ', ISNULL(apellido, N'')) AS rechazado,
           motivos
    FROM Torneo.ERRORES_JUGADOR
    WHERE id_importacion = @id_importacion
    ORDER BY registro;
END;
GO


/*
  usp_ImportarCuerpoTecnicoCSV
  Importa el cuerpo técnico del CSV @ruta_archivo (el cuerpo_tecnico.csv del
  scraping, con el director técnico de cada selección) con
  usp_CargarCuerpoTecnico. Formato, con esta primera fila:
    codigo_fifa,rol,nombre,apellido,codigo_pais_nacimiento
  codigo_fifa es el de la selección y codigo_pais_nacimiento, el código FIFA
  del país de nacimiento (puede venir vacío).
  Valida: ruta obligatoria y terminada en .csv. Si el archivo no se puede
  leer, no tiene las columnas esperadas o alguna fila no es CSV válido, no se
  importa nada (THROW 50002). Las reglas del cuerpo técnico las aplica
  usp_CargarCuerpoTecnico. Registra la importación (su número queda en
  @id_importacion) y los rechazados en Torneo.ERRORES_CUERPO_TECNICO, y
  devuelve el resumen y los rechazados con sus motivos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarCuerpoTecnicoCSV
    @ruta_archivo    NVARCHAR(400),
    @id_importacion  INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido     NVARCHAR(MAX);
    DECLARE @encabezado    NVARCHAR(400);
    DECLARE @mensaje       NVARCHAR(2048);
    DECLARE @sql           NVARCHAR(MAX);
    DECLARE @tran_propia   BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso       VARCHAR(100)   = CONCAT(OBJECT_SCHEMA_NAME(@@PROCID), '.', OBJECT_NAME(@@PROCID));
    DECLARE @leidos        INT;
    DECLARE @insertados    INT;
    DECLARE @actualizados  INT;
    DECLARE @sin_cambios   INT;
    DECLARE @rechazados    INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @nl + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.csv'
        SET @errores += @nl + N'- El archivo tiene que ser un .csv (el cuerpo_tecnico.csv del scraping).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarCuerpoTecnicoCSV: no se pudo importar el archivo.' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* 1. El archivo: la primera fila tiene que tener las columnas esperadas. */
    EXEC DatosGenerales.usp_LeerArchivoUTF8 @ruta_archivo = @ruta_archivo, @contenido = @contenido OUTPUT;

    SET @encabezado = REPLACE(REPLACE(LEFT(@contenido, CHARINDEX(NCHAR(10), @contenido + NCHAR(10)) - 1),
                                      NCHAR(13), N''), N' ', N'');
    IF @encabezado <> N'codigo_fifa,rol,nombre,apellido,codigo_pais_nacimiento'
    BEGIN
        SET @mensaje = N'Torneo.usp_ImportarCuerpoTecnicoCSV: no se importó nada, la primera fila del archivo tiene que ser '
                     + N'"codigo_fifa,rol,nombre,apellido,codigo_pais_nacimiento" y es "' + LEFT(@encabezado, 200) + N'".';
        THROW 50002, @mensaje, 1;
    END;

    /* 2. Las filas, como vienen, y de ahí a #staging_cuerpo_tecnico, la tabla que lee el SP de la
          Entrega 5. FORMAT = 'CSV' respeta las comillas; el fin de línea es el del archivo. */
    CREATE TABLE #crudo (
        codigo_fifa             NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        rol                     NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre                  NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido                NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        codigo_pais_nacimiento  NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL
    );

    BEGIN TRY
        SET @sql = N'BULK INSERT #crudo FROM N''' + REPLACE(@ruta_archivo, N'''', N'''''')
                 + N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', FIELDTERMINATOR = '','', '
                 + N'ROWTERMINATOR = ''' + IIF(CHARINDEX(NCHAR(13) + NCHAR(10), @contenido) > 0, N'0x0d0a', N'0x0a')
                 + N''', FIELDQUOTE = ''"'', MAXERRORS = 0);';
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'Torneo.usp_ImportarCuerpoTecnicoCSV: no se importó nada, hay filas que no son CSV válido '
                     + N'(tienen que tener 5 columnas): ' + ERROR_MESSAGE();
        THROW 50002, @mensaje, 1;
    END CATCH;

    -- usp_CargarCuerpoTecnico lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_cuerpo_tecnico (
        id_registro             INT PRIMARY KEY,   -- línea del archivo
        codigo_fifa             NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre                  NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido                NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        rol                     NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        fecha_nacimiento        DATE          NULL,
        codigo_fifa_nacimiento  NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        errores                 NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion                  VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    INSERT INTO #staging_cuerpo_tecnico (id_registro, codigo_fifa, nombre, apellido, rol, codigo_fifa_nacimiento)
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) + 1,
           UPPER(NULLIF(TRIM(codigo_fifa), N'')), NULLIF(TRIM(nombre), N''), NULLIF(TRIM(apellido), N''),
           UPPER(NULLIF(TRIM(rol), N'')), UPPER(NULLIF(TRIM(REPLACE(codigo_pais_nacimiento, NCHAR(13), N'')), N''))
    FROM #crudo
    WHERE CONCAT(codigo_fifa, rol, nombre, apellido, REPLACE(codigo_pais_nacimiento, NCHAR(13), N'')) <> N'';

    /* 3. El SP de la Entrega 5 valida y carga las válidas, todas juntas; después se registran la
          importación y sus rechazados, en la misma transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Torneo.usp_CargarCuerpoTecnico;

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_cuerpo_tecnico;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @ruta_archivo, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @rechazados = @rechazados,
            @id_importacion = @id_importacion OUTPUT;

        INSERT INTO Torneo.ERRORES_CUERPO_TECNICO (id_importacion, registro, codigo_fifa, rol, nombre, apellido,
                                                   codigo_pais_nacimiento, motivos)
        SELECT @id_importacion, id_registro, codigo_fifa, rol, nombre, apellido, codigo_fifa_nacimiento,
               STUFF(errores, 1, 2, N'')
        FROM #staging_cuerpo_tecnico
        WHERE accion = 'RECHAZADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    /* 4. Resultado. */
    SELECT @id_importacion AS id_importacion, @ruta_archivo AS origen, @leidos AS leidos, @insertados AS insertados,
           @actualizados AS actualizados, @sin_cambios AS sin_cambios, @rechazados AS rechazados;

    SELECT CONCAT(N'Línea ', registro, N': ', ISNULL(codigo_fifa, N'(sin selección)'), N' ', ISNULL(rol, N'(sin rol)'), N' ',
                  ISNULL(nombre, N''), N' ', ISNULL(apellido, N'')) AS rechazado,
           motivos
    FROM Torneo.ERRORES_CUERPO_TECNICO
    WHERE id_importacion = @id_importacion
    ORDER BY registro;
END;
GO


-- Evidencia: SP de importación de jugadores y de cuerpo técnico creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Torneo' AND p.name IN (N'usp_ImportarJugadoresCSV', N'usp_ImportarCuerpoTecnicoCSV');
GO
