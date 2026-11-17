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
           Wikipedia (doc/Tecnica_de_Scraping.docx):
             Torneo.usp_CargarJugadores           carga masiva de jugadores
             Torneo.usp_ImportarJugadoresCSV      importa el archivo jugadores.csv
             Torneo.usp_CargarCuerpoTecnico       carga masiva de cuerpos técnicos
             Torneo.usp_ImportarCuerpoTecnicoCSV  importa el archivo cuerpo_tecnico.csv
           La forma de trabajo común está en 17_SP_Utilidades_Importacion.sql.
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
      de ahí a #staging_jugadores, donde se convierten el dorsal y la fecha
      de nacimiento.
   3. Un UPDATE marca RECHAZADO, con su motivo, lo que no se pudo convertir.
   4. Torneo.usp_CargarJugadores valida las demás con las reglas de los
      jugadores y de cada lista de convocados y carga las válidas, todas
      juntas. En la misma transacción se registra la importación (su número
      queda en @id_importacion) y las rechazadas, en Torneo.ERRORES_JUGADOR.
   5. Se devuelve el resumen y los rechazados con sus motivos.
   Un jugador se reconoce por su selección, apellido y nombre: importar dos
   veces el mismo archivo no duplica nada.

 Se usa SQL dinámico solo para leer el archivo, porque BULK INSERT no acepta
 la ruta en una variable.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_CargarJugadores
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
CREATE OR ALTER PROCEDURE Torneo.usp_CargarJugadores
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @salto_linea    NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia    BIT      = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @min_convocados TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_CONVOCADOS');
    DECLARE @max_convocados TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS');
    DECLARE @min_arqueros   TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_ARQUEROS_CONVOCADOS');

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
        THROW 50001, N'Torneo.usp_CargarJugadores: no se importó nada, falta la tabla #staging_jugadores con los jugadores.', 1;

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
            CASE WHEN st.codigo_fifa IS NULL THEN @salto_linea + N'- El código FIFA de la selección es obligatorio.'
                 WHEN r.id_lista IS NULL     THEN @salto_linea + N'- No hay una selección con lista de convocados con código FIFA "'
                                                       + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.nombre IS NULL OR st.apellido IS NULL
                     THEN @salto_linea + N'- El nombre y el apellido son obligatorios.'
                 WHEN LEN(st.nombre) > 60 OR LEN(st.apellido) > 60
                     THEN @salto_linea + N'- El nombre y el apellido no pueden superar los 60 caracteres.'
            END,
            CASE WHEN st.posicion IS NULL THEN @salto_linea + N'- La posición es obligatoria.'
                 WHEN st.posicion NOT IN ('ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO')
                     THEN @salto_linea + N'- La posición "' + st.posicion + N'" no es ARQUERO, DEFENSOR, MEDIOCAMPISTA ni DELANTERO '
                              + N'(ni GK, DF, MF o FW).'
            END,
            CASE WHEN st.dorsal IS NULL THEN @salto_linea + N'- El dorsal es obligatorio.'
                 WHEN st.dorsal NOT BETWEEN 1 AND 99
                     THEN @salto_linea + N'- El dorsal ' + CAST(st.dorsal AS NVARCHAR(3)) + N' no está entre 1 y 99.'
            END,
            IIF(st.fecha_nacimiento > CONVERT(DATE, GETDATE()), @salto_linea + N'- La fecha de nacimiento no puede ser futura.', NULL),
            IIF(LEN(st.club_origen) > 100, @salto_linea + N'- El club no puede superar los 100 caracteres.', NULL)), N'')
    FROM #staging_jugadores AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro;

    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- Este jugador viene ', r.veces, N' veces.')
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
    SET errores = CONCAT(@salto_linea, N'- El dorsal ', st.dorsal, N' lo tendrían ', rp.veces, N' convocados activos de la selección.')
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
    SET errores = CONCAT(st.errores, @salto_linea,
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

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @salto_linea  NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido    NVARCHAR(MAX);
    DECLARE @encabezado   NVARCHAR(400);
    DECLARE @mensaje      NVARCHAR(2048);
    DECLARE @sql          NVARCHAR(MAX);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso      VARCHAR(100)   = 'Torneo.usp_ImportarJugadoresCSV';
    DECLARE @leidos       INT;
    DECLARE @insertados   INT;
    DECLARE @actualizados INT;
    DECLARE @sin_cambios  INT;
    DECLARE @rechazados   INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @salto_linea + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.csv'
        SET @errores += @salto_linea + N'- El archivo tiene que ser un .csv (el jugadores.csv del scraping).';

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
                @salto_linea + N'- El dorsal "' + dorsal_txt + N'" no es un número entre 1 y 99.', NULL),
            IIF(fecha_txt IS NOT NULL AND fecha_nacimiento IS NULL,
                @salto_linea + N'- La fecha de nacimiento "' + fecha_txt + N'" no es una fecha AAAA-MM-DD.', NULL)), N'');

    UPDATE #staging_jugadores SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. El SP de carga valida las demás y carga las válidas, todas juntas; después se
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
  usp_CargarCuerpoTecnico
  Upsert de las personas del cuerpo técnico de las selecciones por
  selección, apellido y nombre, desde #staging_cuerpo_tecnico. Columnas que
  usa: id_registro (distinto en cada fila), codigo_fifa (de la selección),
  nombre, apellido, rol, fecha_nacimiento, codigo_fifa_nacimiento (del país
  de nacimiento), errores y accion. Los directores técnicos los importa
  usp_ImportarCuerpoTecnicoCSV (19) del scraping de Wikipedia; el resto del
  cuerpo técnico lo carga 33_Cargar_DatosComplementarios.sql. En una persona
  existente, la fecha y el país de nacimiento que no vienen no se borran.
  Valida cada persona pendiente: selección registrada; nombre y apellido
  obligatorios y de hasta 60 caracteres; rol DIRECTOR_TECNICO,
  AYUDANTE_CAMPO, PREPARADOR_FISICO, ENTRENADOR_ARQUEROS, MEDICO u OTRO;
  fecha de nacimiento no futura; país de nacimiento registrado; que no venga
  dos veces. Y con las válidas, cada cuerpo técnico como quedaría (las
  personas registradas que no vienen, más las que vienen): un solo director
  técnico por selección; los directores técnicos que lo rompen se rechazan.
  Con eso cubre las reglas de usp_PERSONA_CUERPO_TECNICO_Alta y
  _Modificacion.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_CargarCuerpoTecnico
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @salto_linea NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- La selección, el país de nacimiento y la persona ya registrada de cada fila pendiente.
    DECLARE @registradas TABLE (
        id_registro         INT PRIMARY KEY,
        id_seleccion        INT,
        id_pais_nacimiento  SMALLINT,
        id_persona_ct       INT
    );

    IF OBJECT_ID(N'tempdb..#staging_cuerpo_tecnico') IS NULL
        THROW 50001, N'Torneo.usp_CargarCuerpoTecnico: no se importó nada, falta la tabla #staging_cuerpo_tecnico con el cuerpo técnico.', 1;

    UPDATE #staging_cuerpo_tecnico
    SET codigo_fifa            = UPPER(NULLIF(TRIM(codigo_fifa), '')),
        nombre                 = NULLIF(TRIM(nombre), N''),
        apellido               = NULLIF(TRIM(apellido), N''),
        rol                    = UPPER(NULLIF(TRIM(rol), '')),
        codigo_fifa_nacimiento = UPPER(NULLIF(TRIM(codigo_fifa_nacimiento), ''))
    WHERE accion IS NULL;

    INSERT INTO @registradas (id_registro, id_seleccion, id_pais_nacimiento, id_persona_ct)
    SELECT st.id_registro, s.id_seleccion, pn.id_pais, ct.id_persona_ct
    FROM #staging_cuerpo_tecnico AS st
    LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = st.codigo_fifa
    LEFT JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
    LEFT JOIN DatosGenerales.PAIS AS pn ON pn.codigo_fifa = st.codigo_fifa_nacimiento
    LEFT JOIN Torneo.PERSONA_CUERPO_TECNICO AS ct
           ON ct.id_seleccion = s.id_seleccion AND ct.apellido = st.apellido AND ct.nombre = st.nombre
    WHERE st.accion IS NULL;

    /* 1. Las reglas de cada persona. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_fifa IS NULL  THEN @salto_linea + N'- El código FIFA de la selección es obligatorio.'
                 WHEN r.id_seleccion IS NULL THEN @salto_linea + N'- No hay una selección registrada con código FIFA "'
                                                       + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.nombre IS NULL OR st.apellido IS NULL
                     THEN @salto_linea + N'- El nombre y el apellido son obligatorios.'
                 WHEN LEN(st.nombre) > 60 OR LEN(st.apellido) > 60
                     THEN @salto_linea + N'- El nombre y el apellido no pueden superar los 60 caracteres.'
            END,
            CASE WHEN st.rol IS NULL THEN @salto_linea + N'- El rol es obligatorio.'
                 WHEN st.rol NOT IN ('DIRECTOR_TECNICO', 'AYUDANTE_CAMPO', 'PREPARADOR_FISICO',
                                     'ENTRENADOR_ARQUEROS', 'MEDICO', 'OTRO')
                     THEN @salto_linea + N'- El rol "' + st.rol + N'" no es DIRECTOR_TECNICO, AYUDANTE_CAMPO, '
                              + N'PREPARADOR_FISICO, ENTRENADOR_ARQUEROS, MEDICO ni OTRO.'
            END,
            IIF(st.fecha_nacimiento > CONVERT(DATE, GETDATE()), @salto_linea + N'- La fecha de nacimiento no puede ser futura.', NULL),
            IIF(st.codigo_fifa_nacimiento IS NOT NULL AND r.id_pais_nacimiento IS NULL,
                @salto_linea + N'- No hay un país registrado con código FIFA "' + st.codigo_fifa_nacimiento
                    + N'" (país de nacimiento).', NULL)), N'')
    FROM #staging_cuerpo_tecnico AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro;

    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- Esta persona viene ', r.veces, N' veces para la selección.')
    FROM #staging_cuerpo_tecnico AS st
    INNER JOIN (SELECT codigo_fifa, nombre, apellido, COUNT(*) AS veces FROM #staging_cuerpo_tecnico
                WHERE codigo_fifa IS NOT NULL AND nombre IS NOT NULL AND apellido IS NOT NULL
                GROUP BY codigo_fifa, nombre, apellido HAVING COUNT(*) > 1) AS r
            ON r.codigo_fifa = st.codigo_fifa AND r.nombre = st.nombre AND r.apellido = st.apellido
    WHERE st.accion IS NULL;

    /* 2. Cada cuerpo técnico como quedaría con las personas válidas: un solo director técnico
          por selección. Se rechazan los directores técnicos que vienen para una selección que
          quedaría con más de uno. */
    WITH validas AS (
        SELECT st.id_registro, r.id_seleccion, r.id_persona_ct, st.rol
        FROM #staging_cuerpo_tecnico AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
        WHERE st.errores IS NULL
    ),
    directores AS (
        SELECT e.id_seleccion, COUNT(*) AS cantidad
        FROM (SELECT id_seleccion, rol FROM validas
              UNION ALL
              SELECT ct.id_seleccion, ct.rol
              FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
              WHERE ct.id_seleccion IN (SELECT id_seleccion FROM validas)
                AND NOT EXISTS (SELECT 1 FROM validas AS v WHERE v.id_persona_ct = ct.id_persona_ct)) AS e
        WHERE e.rol = 'DIRECTOR_TECNICO'
        GROUP BY e.id_seleccion
        HAVING COUNT(*) > 1
    )
    UPDATE st
    SET errores = CONCAT(@salto_linea, N'- La selección quedaría con ', d.cantidad, N' directores técnicos: puede tener uno solo.')
    FROM #staging_cuerpo_tecnico AS st
    INNER JOIN validas AS v ON v.id_registro = st.id_registro
    INNER JOIN directores AS d ON d.id_seleccion = v.id_seleccion
    WHERE v.rol = 'DIRECTOR_TECNICO';

    UPDATE #staging_cuerpo_tecnico SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 3. Lo que le pasa a cada persona válida, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN r.id_persona_ct IS NULL THEN 'INSERTADO'
                      WHEN st.rol <> ct.rol
                        OR st.fecha_nacimiento <> ISNULL(ct.fecha_nacimiento, '19000101')
                        OR r.id_pais_nacimiento <> ISNULL(ct.id_pais_nacimiento, 0)
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_cuerpo_tecnico AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
    LEFT JOIN Torneo.PERSONA_CUERPO_TECNICO AS ct ON ct.id_persona_ct = r.id_persona_ct
    WHERE st.accion IS NULL;

    /* 4. Carga, todos juntos. Los cambios de rol van antes que las altas: el director técnico
          nuevo de una selección puede reemplazar al que pasa a otro rol. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE ct
        SET rol                = st.rol,
            fecha_nacimiento   = ISNULL(st.fecha_nacimiento, ct.fecha_nacimiento),
            id_pais_nacimiento = ISNULL(r.id_pais_nacimiento, ct.id_pais_nacimiento)
        FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
        INNER JOIN @registradas AS r ON r.id_persona_ct = ct.id_persona_ct
        INNER JOIN #staging_cuerpo_tecnico AS st ON st.id_registro = r.id_registro
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO Torneo.PERSONA_CUERPO_TECNICO
            (id_seleccion, id_pais_nacimiento, nombre, apellido, fecha_nacimiento, rol)
        SELECT r.id_seleccion, r.id_pais_nacimiento, st.nombre, st.apellido, st.fecha_nacimiento, st.rol
        FROM #staging_cuerpo_tecnico AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
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

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @salto_linea  NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido    NVARCHAR(MAX);
    DECLARE @encabezado   NVARCHAR(400);
    DECLARE @mensaje      NVARCHAR(2048);
    DECLARE @sql          NVARCHAR(MAX);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso      VARCHAR(100)   = 'Torneo.usp_ImportarCuerpoTecnicoCSV';
    DECLARE @leidos       INT;
    DECLARE @insertados   INT;
    DECLARE @actualizados INT;
    DECLARE @sin_cambios  INT;
    DECLARE @rechazados   INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @salto_linea + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.csv'
        SET @errores += @salto_linea + N'- El archivo tiene que ser un .csv (el cuerpo_tecnico.csv del scraping).';

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

    /* 2. Las filas, como vienen, y de ahí a #staging_cuerpo_tecnico, la tabla que lee el SP de
          carga. FORMAT = 'CSV' respeta las comillas; el fin de línea es el del archivo. */
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

    /* 3. El SP de carga valida y carga las válidas, todas juntas; después se registran la
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
WHERE s.name = N'Torneo' AND p.name IN (N'usp_CargarJugadores', N'usp_ImportarJugadoresCSV',
                                        N'usp_CargarCuerpoTecnico', N'usp_ImportarCuerpoTecnicoCSV');
GO
