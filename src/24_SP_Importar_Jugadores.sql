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
 Archivo: 24_SP_Importar_Jugadores.sql
 Objetivo: Crear el proceso de importación de las listas de convocados desde
           el CSV que genera el scraping de Wikipedia (scraping/README.md):
             Torneo.usp_ImportarJugadoresCSV  importa el archivo jugadores.csv
           Las selecciones y sus listas tienen que estar cargadas antes
           (Torneo.usp_ImportarSeleccionesJSON, en 23_SP_Importar_Mundial2026.sql).
           Requiere haber ejecutado 00 a 23. Su script de testing es
           73_Test_SP_Importar_Mundial2026.sql, junto con el de 23.
================================================================================

 Formato: CSV en UTF-8, separado por comas, con comillas solo en los valores
 que las necesitan, y esta primera fila con los nombres de las columnas:
   codigo_fifa,dorsal,posicion,nombre,apellido,fecha_nacimiento,club
 La posición viene como GK, DF, MF o FW y la fecha como AAAA-MM-DD.

 Cómo importa (igual que 25, 27 y 28):
   1. Se controla el archivo: que se pueda leer y que su primera fila tenga
      esas columnas. Si no, o si alguna fila no es CSV válido, no se importa
      nada (THROW 50002).
   2. BULK INSERT pasa las filas, tal como vienen, a la tabla de staging, y
      ahí se convierten (la posición y el dorsal).
   3. Cada regla es un UPDATE sobre toda la tabla de staging, que anota el
      motivo en los registros que no la cumplen (RECHAZADO). Primero las de
      cada jugador; después las de cada lista como quedaría, con los
      jugadores válidos: un dorsal que se repite rechaza a los jugadores que
      lo traen, y una lista que no cumple el reglamento rechaza a todos los
      jugadores de esa selección.
   4. Los demás se cargan todos juntos con el SP de la Entrega 5
      Torneo.usp_ImportarJugadores (16_SP_Importacion.sql), con las mismas
      reglas.
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
  Importa los jugadores del CSV @ruta_archivo con usp_ImportarJugadores.
  Valida: ruta obligatoria y terminada en .csv. Si el archivo no se puede
  leer, no tiene las columnas esperadas o alguna fila no es CSV válido, no se
  importa nada (THROW 50002). Devuelve el resumen y los rechazados con sus
  motivos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarJugadoresCSV
    @ruta_archivo  NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores         NVARCHAR(2048) = N'';
    DECLARE @nl              NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido       NVARCHAR(MAX);
    DECLARE @encabezado      NVARCHAR(400);
    DECLARE @mensaje         NVARCHAR(2048);
    DECLARE @sql             NVARCHAR(MAX);
    DECLARE @min_convocados  TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_CONVOCADOS');
    DECLARE @max_convocados  TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS');
    DECLARE @min_arqueros    TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_ARQUEROS_CONVOCADOS');
    DECLARE @validos         Torneo.TT_JUGADOR;
    DECLARE @insertados      INT = 0;
    DECLARE @actualizados    INT = 0;
    DECLARE @sin_cambios     INT = 0;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');

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

    CREATE TABLE #staging_jugadores (
        id_registro       INT PRIMARY KEY,   -- línea del archivo
        codigo_fifa       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        dorsal_txt        NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        posicion_txt      NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        fecha_txt         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        club              NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        -- Convertidos
        dorsal            TINYINT       NULL,
        posicion          VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
        fecha_nacimiento  DATE          NULL,
        id_lista          INT           NULL,
        lista_vacia       BIT           NULL,
        id_jugador        INT           NULL,
        activo            BIT           NULL,
        errores           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion            VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    INSERT INTO #staging_jugadores (id_registro, codigo_fifa, dorsal_txt, posicion_txt, nombre, apellido, fecha_txt, club)
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) + 1,
           UPPER(NULLIF(TRIM(codigo_fifa), N'')), NULLIF(TRIM(dorsal_txt), N''), UPPER(NULLIF(TRIM(posicion_txt), N'')),
           NULLIF(TRIM(nombre), N''), NULLIF(TRIM(apellido), N''), NULLIF(TRIM(fecha_txt), N''),
           NULLIF(TRIM(REPLACE(club, NCHAR(13), N'')), N'')
    FROM #crudo
    WHERE CONCAT(codigo_fifa, dorsal_txt, posicion_txt, nombre, apellido, fecha_txt, REPLACE(club, NCHAR(13), N'')) <> N'';

    UPDATE st
    SET dorsal           = TRY_CONVERT(TINYINT, st.dorsal_txt),
        fecha_nacimiento = TRY_CONVERT(DATE, st.fecha_txt, 23),
        posicion         = CASE st.posicion_txt
                               WHEN N'GK' THEN 'ARQUERO'       WHEN N'GOALKEEPER' THEN 'ARQUERO'
                               WHEN N'DF' THEN 'DEFENSOR'      WHEN N'DEFENDER'   THEN 'DEFENSOR'
                               WHEN N'MF' THEN 'MEDIOCAMPISTA' WHEN N'MIDFIELDER' THEN 'MEDIOCAMPISTA'
                               WHEN N'FW' THEN 'DELANTERO'     WHEN N'FORWARD'    THEN 'DELANTERO'
                               ELSE LEFT(st.posicion_txt, 30)
                           END,
        id_lista         = lc.id_lista,
        lista_vacia      = IIF(lc.id_lista IS NOT NULL
                               AND NOT EXISTS (SELECT 1 FROM Torneo.JUGADOR AS j WHERE j.id_lista = lc.id_lista), 1, 0)
    FROM #staging_jugadores AS st
    LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = st.codigo_fifa
    LEFT JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_seleccion = s.id_seleccion;

    UPDATE st
    SET id_jugador = j.id_jugador, activo = IIF(j.fecha_baja IS NULL, 1, 0)
    FROM #staging_jugadores AS st
    INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = st.id_lista AND j.apellido = st.apellido AND j.nombre = st.nombre;

    /* 3. Validaciones, con las reglas de usp_ImportarJugadores. Primero las de cada jugador. */
    UPDATE #staging_jugadores
    SET errores = NULLIF(CONCAT(
            CASE WHEN codigo_fifa IS NULL THEN @nl + N'- El código FIFA de la selección es obligatorio.'
                 WHEN id_lista IS NULL    THEN @nl + N'- No hay una selección con lista de convocados con código FIFA "'
                                                   + codigo_fifa + N'".'
            END,
            CASE WHEN nombre IS NULL OR apellido IS NULL THEN @nl + N'- El nombre y el apellido son obligatorios.'
                 WHEN LEN(nombre) > 60 OR LEN(apellido) > 60
                     THEN @nl + N'- El nombre y el apellido no pueden superar los 60 caracteres.'
            END,
            CASE WHEN posicion_txt IS NULL THEN @nl + N'- La posición es obligatoria.'
                 WHEN posicion NOT IN ('ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO')
                     THEN @nl + N'- La posición "' + posicion_txt + N'" no es GK, DF, MF ni FW.'
            END,
            CASE WHEN dorsal_txt IS NULL THEN @nl + N'- El dorsal es obligatorio.'
                 WHEN dorsal IS NULL OR dorsal NOT BETWEEN 1 AND 99
                     THEN @nl + N'- El dorsal "' + dorsal_txt + N'" no es un número entre 1 y 99.'
            END,
            CASE WHEN fecha_txt IS NOT NULL AND fecha_nacimiento IS NULL
                     THEN @nl + N'- La fecha de nacimiento "' + fecha_txt + N'" no es una fecha AAAA-MM-DD.'
                 WHEN fecha_nacimiento > CONVERT(DATE, GETDATE())
                     THEN @nl + N'- La fecha de nacimiento no puede ser futura.'
            END,
            IIF(LEN(club) > 100, @nl + N'- El club no puede superar los 100 caracteres.', NULL)), N'');

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- El archivo trae ', r.veces, N' veces este jugador.')
    FROM #staging_jugadores AS st
    INNER JOIN (SELECT codigo_fifa, nombre, apellido, COUNT(*) AS veces FROM #staging_jugadores
                WHERE codigo_fifa IS NOT NULL AND nombre IS NOT NULL AND apellido IS NOT NULL
                GROUP BY codigo_fifa, nombre, apellido HAVING COUNT(*) > 1) AS r
            ON r.codigo_fifa = st.codigo_fifa AND r.nombre = st.nombre AND r.apellido = st.apellido;

    -- Después, cada lista como quedaría con los jugadores válidos. Un dorsal repetido
    -- entre los activos rechaza a los jugadores del archivo que lo traen.
    WITH plantel AS (
        SELECT st.id_lista, st.dorsal, st.id_registro
        FROM #staging_jugadores AS st
        WHERE st.errores IS NULL AND ISNULL(st.activo, 1) = 1
        UNION ALL
        SELECT j.id_lista, j.dorsal, NULL
        FROM Torneo.JUGADOR AS j
        WHERE j.fecha_baja IS NULL
          AND j.id_lista IN (SELECT id_lista FROM #staging_jugadores)
          AND NOT EXISTS (SELECT 1 FROM #staging_jugadores AS st
                          WHERE st.errores IS NULL AND st.id_jugador = j.id_jugador)
    ),
    repetidos AS (
        SELECT id_lista, dorsal, COUNT(*) AS veces FROM plantel GROUP BY id_lista, dorsal HAVING COUNT(*) > 1
    )
    UPDATE st
    SET errores = CONCAT(@nl, N'- El dorsal ', st.dorsal, N' lo tendrían ', r.veces, N' convocados activos de la selección.')
    FROM #staging_jugadores AS st
    INNER JOIN repetidos AS r ON r.id_lista = st.id_lista AND r.dorsal = st.dorsal
    WHERE st.errores IS NULL AND ISNULL(st.activo, 1) = 1;

    -- Una lista que no cumple el reglamento rechaza a todos los jugadores de esa selección.
    WITH plantel AS (
        SELECT st.id_lista, st.lista_vacia, st.posicion
        FROM #staging_jugadores AS st
        WHERE st.errores IS NULL AND ISNULL(st.activo, 1) = 1
        UNION ALL
        SELECT j.id_lista, 0, j.posicion_habitual
        FROM Torneo.JUGADOR AS j
        WHERE j.fecha_baja IS NULL
          AND j.id_lista IN (SELECT id_lista FROM #staging_jugadores)
          AND NOT EXISTS (SELECT 1 FROM #staging_jugadores AS st
                          WHERE st.errores IS NULL AND st.id_jugador = j.id_jugador)
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
    INNER JOIN listas AS l ON l.id_lista = st.id_lista
    WHERE l.jugadores > @max_convocados
       OR (l.vacia = 1 AND (l.jugadores < @min_convocados OR l.arqueros < @min_arqueros));

    UPDATE #staging_jugadores SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. Carga de los válidos, todos juntos, con el SP de la Entrega 5. */
    INSERT INTO @validos (codigo_fifa_seleccion, nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen)
    SELECT codigo_fifa, nombre, apellido, posicion, dorsal, fecha_nacimiento, club
    FROM #staging_jugadores
    WHERE accion IS NULL;

    IF EXISTS (SELECT 1 FROM @validos)
        EXEC Torneo.usp_ImportarJugadores
            @jugadores = @validos, @insertados = @insertados OUTPUT,
            @actualizados = @actualizados OUTPUT, @sin_cambios = @sin_cambios OUTPUT;

    /* 5. Resultado. */
    SELECT @ruta_archivo AS origen, COUNT(*) AS leidos, @insertados AS insertados, @actualizados AS actualizados,
           @sin_cambios AS sin_cambios, ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0) AS rechazados
    FROM #staging_jugadores;

    SELECT CONCAT(N'Línea ', id_registro, N': ', ISNULL(codigo_fifa, N'(sin selección)'), N' ',
                  ISNULL(dorsal_txt, N'(sin dorsal)'), N' ', ISNULL(nombre, N''), N' ', ISNULL(apellido, N'')) AS rechazado,
           STUFF(errores, 1, 2, N'') AS motivos
    FROM #staging_jugadores
    WHERE accion = 'RECHAZADO'
    ORDER BY id_registro;
END;
GO


-- Evidencia: SP de importación de jugadores creado.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Torneo' AND p.name = N'usp_ImportarJugadoresCSV';
GO
