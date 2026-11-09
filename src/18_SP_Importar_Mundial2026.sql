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
 Archivo: 18_SP_Importar_Mundial2026.sql
 Objetivo: Crear el proceso de importación del Mundial 2026 real desde los
           archivos JSON del proyecto openfootball (ver
           datos/fuentes/openfootball/README.md): sedes, selecciones y
           partidos con lo que pasó en cada uno (formaciones, cambios, goles,
           penales de la definición y tarjetas). Los jugadores se importan
           antes, desde el CSV del scraping (19_SP_Importar_Jugadores.sql).
           Y el equipo arbitral de cada partido, desde el CSV del scraping de
           Wikipedia (scraping/README.md), después de los partidos.
           Los objetos, en el orden en que se crean (las utilidades que usan,
           como usp_LeerArchivoUTF8 y usp_IdentificarJugadores, están en
           17_SP_Utilidades_Importacion.sql):
             Torneo.fn_CoordenadaDecimal              coordenada en grados con decimales
             Torneo.usp_ImportarSedesJSON             worldcup.stadiums.json
             Torneo.usp_ImportarSeleccionesJSON       worldcup.teams.json
             Torneo.usp_ImportarPartidosJSON          worldcup-full.json
             Arbitraje.usp_ImportarDesignacionesCSV   designaciones_arbitrales.csv (scraping)
           Requiere haber ejecutado 01 a 17. Su script de testing es
           68_Test_SP_Importar_Mundial2026.sql. La carga del torneo real está
           en 32_Importar_Mundial2026.sql.
================================================================================

 Cómo importa cada SP (igual que 19, 21, 22 y 23):
   1. Se controla el archivo: que se pueda leer, que sea JSON y que tenga la
      estructura del archivo de openfootball que corresponde (o, el CSV del
      equipo arbitral, sus columnas). Si no, no se importa nada (THROW 50002).
   2. OPENJSON (o BULK INSERT, el CSV) pasa los registros, tal como vienen, a
      la tabla de staging que lee el SP de la Entrega 5 (#staging_sedes, por
      ejemplo), y ahí se convierten. Todas las transformaciones se hacen acá,
      en T-SQL.
   3. Se rechazan los registros que no se pudieron convertir: un UPDATE
      sobre toda la tabla anota el motivo y los marca RECHAZADO.
   4. El SP de la Entrega 5 que corresponde (16_SP_CargaMasiva.sql) valida
      los demás con las reglas de la tabla, marca los que no las cumplen y
      carga los válidos, todos juntos. Así los registros válidos se cargan
      aunque haya otros rechazados. En la misma transacción se registra la
      importación (DatosGenerales.IMPORTACION, su número queda en el
      parámetro @id_importacion) y sus registros rechazados, en la tabla
      ERRORES_ de lo que se importó (Torneo.ERRORES_SEDE, por ejemplo).
   5. Se devuelve el resumen y los rechazados con sus motivos.
   Importar dos veces el mismo archivo no duplica nada.

 Transformaciones de los datos de openfootball:
   - Sedes: el país sale del código ISO alfa-2 (cc) y el huso horario de
     Windows, del país y el desfase UTC que trae el archivo, que es el del
     horario de verano durante el torneo (UTC-7 Pacífico, UTC-6 México
     central, UTC-5 Central, UTC-4 Este). Las coordenadas vienen en grados,
     minutos y segundos (49°16'36"N) o en grados con decimales (37.403°N). El
     archivo no tiene tarifas de publicidad: las sedes nuevas reciben las
     tarifas de lista que se pasan como parámetro.
   - Selecciones: el nombre en inglés del archivo se guarda como nombre
     alternativo, para reconocer la selección en el archivo de partidos.
   - Partidos: el archivo no numera los partidos. Se numeran por fecha y hora
     UTC (desempata el grupo y después el orden en el archivo): del 1 al 72 la
     fase de grupos y del 73 en adelante la eliminación directa. En la fase de
     grupos coincide con la numeración oficial de FIFA; en la eliminación
     directa, FIFA numera algunos partidos del mismo día en otro orden. La
     sede se reconoce porque el nombre que trae el archivo ("Atlanta Stadium,
     Atlanta") contiene la ciudad de la sede (lo que está antes del
     paréntesis). El resultado final es el del alargue (et) si lo hubo, y si
     no el de los 90 minutos (ft); p son los penales.
   - Jugadores: los archivos los nombran como "Nombre APELLIDO"; se reconocen
     dentro de la lista de su selección (ver usp_IdentificarJugadores). Un
     nombre que no se reconoce se rechaza, y se resuelve registrándolo como
     nombre alternativo del jugador (Torneo.usp_NOMBRE_ALTERNATIVO_Alta) y
     reprocesando los partidos rechazados (ver usp_ImportarPartidosJSON).
   - Formaciones: la posición en cancha de cada titular es su posición
     habitual; el esquema táctico sale de esas posiciones (ej. 4-3-3).
   - Minutos: 45+2 es el 45 con 2 de adicional. Un minuto después del 120 es
     adicional del alargue (121 es 120+1).
   - Cambios: el archivo no dice el motivo: uno nuevo se registra como
     TACTICO y uno ya cargado conserva el suyo. Un cambio en el minuto 46, 91
     o 106 se hizo en el entretiempo.
   - Goles: los de penal son de tipo PENAL, los en contra EN CONTRA y el resto
     JUGADA.
   - Penales de la definición: se cargan los convertidos, como goles del
     período PENALES. El equipo de cada uno sale de cómo cambia el marcador.
   - Tarjetas: Y es amarilla, R roja directa y Y/R la segunda amarilla, que
     se registra como amarilla y además como roja por doble amarilla. El
     archivo no tiene el motivo: una nueva se registra con "Sin detalle en la
     fuente" y una ya cargada conserva el suyo.
   - Si el archivo corrige un evento ya cargado (el minuto de un gol, por
     ejemplo), se actualiza: ver usp_CargarDesarrolloPartidos.

 Transformaciones del CSV del equipo arbitral:
   - Partido: el de esa fecha (hora local de la sede) entre esas dos
     selecciones, en cualquier orden.
   - Árbitros: uno por cada país, nombre y apellido del archivo, con la
     categoría que se pasa como parámetro (FIFA, por defecto).
   - Roles: los traduce usp_CargarDesignaciones (Referee es PRINCIPAL,
     Fourth official es CUARTO, etc.).

 Se usa SQL dinámico solo para leer el archivo, porque OPENROWSET(BULK) y
 BULK INSERT no aceptan la ruta en una variable.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   SEDES
   ============================================================================ */

/*
  fn_CoordenadaDecimal
  Una latitud o longitud en grados con decimales, a partir del texto en
  grados, minutos y segundos (49°16'36"N, los segundos pueden tener
  decimales) o en grados con decimales (37.403°N). @hemisferios son las dos
  letras válidas para el eje: 'NS' para la latitud y 'EW' para la longitud.
  Sur y oeste son negativos. NULL si el texto no tiene ese formato.
*/
CREATE OR ALTER FUNCTION Torneo.fn_CoordenadaDecimal (@texto NVARCHAR(50), @hemisferios NCHAR(2))
RETURNS DECIMAL(12,6)
AS
BEGIN
    DECLARE @g INT = CHARINDEX(N'°', @texto);
    DECLARE @m INT = CHARINDEX(N'''', @texto);
    DECLARE @s INT = CHARINDEX(N'"', @texto);
    DECLARE @hemisferio NCHAR(1) = UPPER(RIGHT(@texto, 1));

    IF @g < 2 OR CHARINDEX(@hemisferio, @hemisferios) = 0 OR (@s > 0 AND @m = 0)
        RETURN NULL;

    RETURN (TRY_CONVERT(DECIMAL(12,6), LEFT(@texto, @g - 1))
            + IIF(@m > @g, TRY_CONVERT(DECIMAL(12,6), SUBSTRING(@texto, @g + 1, @m - @g - 1)), 0) / 60
            + IIF(@s > @m AND @m > 0, TRY_CONVERT(DECIMAL(12,6), SUBSTRING(@texto, @m + 1, @s - @m - 1)), 0) / 3600)
           * IIF(@hemisferio IN (N'S', N'W'), -1, 1);
END;
GO

/*
  usp_ImportarSedesJSON
  Importa las sedes del archivo worldcup.stadiums.json de openfootball
  (@ruta_archivo) con usp_CargarSedes. Las tarifas son las de los 4
  espacios publicitarios de las sedes nuevas, que el archivo no trae.
  Valida: ruta obligatoria y terminada en .json; tarifas no negativas. Si el
  archivo no se puede leer, no es JSON o no tiene la lista "stadiums", no se
  importa nada (THROW 50002). Rechaza los registros que no puede convertir
  (país, huso, capacidad y coordenadas); las reglas de las sedes las aplica
  usp_CargarSedes. Registra la importación (su número queda en
  @id_importacion) y los rechazados en Torneo.ERRORES_SEDE, y devuelve el
  resumen y los rechazados con sus motivos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarSedesJSON
    @ruta_archivo      NVARCHAR(400),
    @tarifa_espacio_1  DECIMAL(9,2) = 120000,
    @tarifa_espacio_2  DECIMAL(9,2) = 100000,
    @tarifa_espacio_3  DECIMAL(9,2) = 90000,
    @tarifa_espacio_4  DECIMAL(9,2) = 80000,
    @id_importacion    INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido     NVARCHAR(MAX);
    DECLARE @mensaje       NVARCHAR(2048);
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
    ELSE IF @ruta_archivo NOT LIKE N'%.json'
        SET @errores += @nl + N'- El archivo tiene que ser un .json (worldcup.stadiums.json de openfootball).';

    IF @tarifa_espacio_1 IS NULL OR @tarifa_espacio_2 IS NULL OR @tarifa_espacio_3 IS NULL OR @tarifa_espacio_4 IS NULL
       OR @tarifa_espacio_1 < 0 OR @tarifa_espacio_2 < 0 OR @tarifa_espacio_3 < 0 OR @tarifa_espacio_4 < 0
        SET @errores += @nl + N'- Las 4 tarifas son obligatorias y no pueden ser negativas.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarSedesJSON: no se pudo importar el archivo.' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* 1. El archivo. */
    EXEC DatosGenerales.usp_LeerArchivoUTF8 @ruta_archivo = @ruta_archivo, @contenido = @contenido OUTPUT;

    IF ISJSON(@contenido) = 0
        SET @mensaje = N'el archivo no es un JSON válido.';
    ELSE IF JSON_QUERY(@contenido, N'$.stadiums') IS NULL
        SET @mensaje = N'el archivo no tiene la lista "stadiums" (no es worldcup.stadiums.json de openfootball).';

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'Torneo.usp_ImportarSedesJSON: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    -- usp_CargarSedes lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_sedes (
        id_registro     INT PRIMARY KEY,
        -- Tal como vienen en el archivo
        pais_txt        NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        huso_txt        NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        capacidad_txt   NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        coordenadas     NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
        -- Lo que lee usp_CargarSedes, ya convertido
        nombre_estadio  VARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
        ciudad          VARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
        codigo_fifa     VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
        capacidad       INT           NULL,
        huso_horario    VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        latitud         DECIMAL(12,6) NULL,
        longitud        DECIMAL(12,6) NULL,
        tarifa_1        DECIMAL(9,2)  NULL,
        tarifa_2        DECIMAL(9,2)  NULL,
        tarifa_3        DECIMAL(9,2)  NULL,
        tarifa_4        DECIMAL(9,2)  NULL,
        -- Lo que le pasa a cada registro: lo completan este SP y usp_CargarSedes
        errores         NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion          VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    /* 2. Los registros, como vienen en el archivo, y su conversión. */
    INSERT INTO #staging_sedes (id_registro, nombre_estadio, ciudad, pais_txt, huso_txt, capacidad_txt, coordenadas,
                                tarifa_1, tarifa_2, tarifa_3, tarifa_4)
    SELECT CAST(s.[key] AS INT) + 1,
           NULLIF(TRIM(d.nombre), N''), NULLIF(TRIM(d.ciudad), N''), UPPER(NULLIF(TRIM(d.pais), N'')),
           UPPER(REPLACE(NULLIF(TRIM(d.huso), N''), N' ', N'')), NULLIF(TRIM(d.capacidad), N''),
           NULLIF(TRIM(d.coordenadas), N''),
           @tarifa_espacio_1, @tarifa_espacio_2, @tarifa_espacio_3, @tarifa_espacio_4
    FROM OPENJSON(@contenido, N'$.stadiums') AS s
    CROSS APPLY OPENJSON(s.value)
        WITH (nombre NVARCHAR(400) '$.name', ciudad NVARCHAR(400) '$.city', pais NVARCHAR(50) '$.cc',
              huso NVARCHAR(50) '$.timezone', capacidad NVARCHAR(50) '$.capacity',
              coordenadas NVARCHAR(100) '$.coords') AS d;

    -- País: el único con ese código ISO alfa-2.
    UPDATE st
    SET codigo_fifa = (SELECT MAX(p.codigo_fifa) FROM DatosGenerales.PAIS AS p
                       WHERE p.codigo_iso2 = st.pais_txt HAVING COUNT(*) = 1)
    FROM #staging_sedes AS st;

    -- Huso de Windows según el país y el desfase del horario de verano.
    UPDATE st
    SET huso_horario = h.huso_horario
    FROM #staging_sedes AS st
    INNER JOIN (VALUES ('US', 'UTC-7', 'Pacific Standard Time'),  ('CA', 'UTC-7', 'Pacific Standard Time'),
                       ('US', 'UTC-6', 'Mountain Standard Time'), ('CA', 'UTC-6', 'Mountain Standard Time'),
                       ('US', 'UTC-5', 'Central Standard Time'),  ('CA', 'UTC-5', 'Central Standard Time'),
                       ('US', 'UTC-4', 'Eastern Standard Time'),  ('CA', 'UTC-4', 'Eastern Standard Time'),
                       ('MX', 'UTC-7', 'Mountain Standard Time (Mexico)'),
                       ('MX', 'UTC-6', 'Central Standard Time (Mexico)'),
                       ('MX', 'UTC-5', 'Eastern Standard Time (Mexico)'))
               AS h (pais, desfase, huso_horario)
            ON h.pais = st.pais_txt AND h.desfase = st.huso_txt;

    -- Capacidad y coordenadas: "49°16'36"N 123°6'43"W" o "37.403°N 121.970°W".
    UPDATE st
    SET capacidad = TRY_CONVERT(INT, st.capacidad_txt),
        latitud   = Torneo.fn_CoordenadaDecimal(c.lat, N'NS'),
        longitud  = Torneo.fn_CoordenadaDecimal(c.lon, N'EW')
    FROM #staging_sedes AS st
    CROSS APPLY (SELECT LEFT(st.coordenadas, CHARINDEX(N' ', st.coordenadas + N' ') - 1) AS lat,
                        TRIM(SUBSTRING(st.coordenadas, CHARINDEX(N' ', st.coordenadas + N' ') + 1, 100)) AS lon) AS c;

    /* 3. Lo que no se pudo convertir. Las reglas de las sedes las aplica usp_CargarSedes. */
    UPDATE st
    SET errores = NULLIF(CONCAT(
            IIF(st.pais_txt IS NOT NULL AND st.codigo_fifa IS NULL,
                @nl + N'- El país "' + st.pais_txt + N'" no es un código ISO alfa-2 de un país registrado.', NULL),
            IIF(st.huso_txt IS NOT NULL AND st.huso_horario IS NULL,
                @nl + N'- No se reconoce el huso "' + st.huso_txt + N'" para ese país.', NULL),
            IIF(st.capacidad_txt IS NOT NULL AND st.capacidad IS NULL,
                @nl + N'- La capacidad "' + st.capacidad_txt + N'" no es un número entero.', NULL),
            IIF(st.coordenadas IS NOT NULL AND (st.latitud IS NULL OR st.longitud IS NULL),
                @nl + N'- Las coordenadas "' + st.coordenadas + N'" no son una latitud y una longitud.', NULL)), N'')
    FROM #staging_sedes AS st;

    UPDATE #staging_sedes SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. El SP de la Entrega 5 valida las demás y carga las válidas, todas juntas; después se
          registran la importación y sus rechazados, en la misma transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Torneo.usp_CargarSedes;

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_sedes;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @ruta_archivo, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @rechazados = @rechazados,
            @id_importacion = @id_importacion OUTPUT;

        INSERT INTO Torneo.ERRORES_SEDE (id_importacion, registro, nombre_estadio, ciudad, pais, huso_horario, capacidad,
                                         coordenadas, motivos)
        SELECT @id_importacion, id_registro, nombre_estadio, ciudad, pais_txt, huso_txt, capacidad_txt, coordenadas,
               STUFF(errores, 1, 2, N'')
        FROM #staging_sedes
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

    SELECT CONCAT(registro, N'. ', ISNULL(nombre_estadio, N'(sin nombre)')) AS rechazado, motivos
    FROM Torneo.ERRORES_SEDE
    WHERE id_importacion = @id_importacion
    ORDER BY registro;
END;
GO


/* ============================================================================
   SELECCIONES
   ============================================================================ */

/*
  usp_ImportarSeleccionesJSON
  Importa las selecciones del archivo worldcup.teams.json de openfootball
  (@ruta_archivo) con usp_CargarSelecciones: código FIFA, confederación,
  grupo y el nombre en inglés, que queda como nombre alternativo. Las listas
  de convocados nuevas se presentan en @fecha_presentacion.
  Valida: ruta obligatoria y terminada en .json. Si el archivo no se puede
  leer, no es JSON o no es una lista de selecciones con código FIFA, no se
  importa nada (THROW 50002); tampoco si hay que crear alguna lista y la
  fecha de presentación falta o es futura (THROW 50001, de
  usp_CargarSelecciones). Registra la importación (su número queda en
  @id_importacion) y las rechazadas en Torneo.ERRORES_SELECCION, y devuelve
  el resumen y las rechazadas con sus motivos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarSeleccionesJSON
    @ruta_archivo        NVARCHAR(400),
    @fecha_presentacion  DATE = NULL,
    @id_importacion      INT  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido     NVARCHAR(MAX);
    DECLARE @mensaje       NVARCHAR(2048);
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
    ELSE IF @ruta_archivo NOT LIKE N'%.json'
        SET @errores += @nl + N'- El archivo tiene que ser un .json (worldcup.teams.json de openfootball).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarSeleccionesJSON: no se pudo importar el archivo.' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* 1. El archivo: una lista de selecciones con su código FIFA. */
    EXEC DatosGenerales.usp_LeerArchivoUTF8 @ruta_archivo = @ruta_archivo, @contenido = @contenido OUTPUT;

    IF ISJSON(@contenido) = 0
        SET @mensaje = N'el archivo no es un JSON válido.';
    ELSE IF JSON_VALUE(@contenido, N'$[0].fifa_code') IS NULL
        SET @mensaje = N'el archivo no es una lista de selecciones con su código FIFA (no es worldcup.teams.json de openfootball).';

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'Torneo.usp_ImportarSeleccionesJSON: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    -- usp_CargarSelecciones lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_selecciones (
        id_registro         INT PRIMARY KEY,
        codigo_fifa         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        confederacion       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        grupo               NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre_alternativo  NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,   -- el nombre que trae el archivo
        errores             NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion              VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    /* 2. Los registros, como vienen en el archivo: no hay nada que convertir. */
    INSERT INTO #staging_selecciones (id_registro, nombre_alternativo, codigo_fifa, grupo, confederacion)
    SELECT CAST(s.[key] AS INT) + 1, NULLIF(TRIM(d.nombre), N''), UPPER(NULLIF(TRIM(d.codigo), N'')),
           UPPER(NULLIF(TRIM(d.grupo), N'')), UPPER(NULLIF(TRIM(d.confederacion), N''))
    FROM OPENJSON(@contenido) AS s
    CROSS APPLY OPENJSON(s.value)
        WITH (nombre NVARCHAR(400) '$.name', codigo NVARCHAR(50) '$.fifa_code',
              grupo NVARCHAR(50) '$.group', confederacion NVARCHAR(50) '$.confed') AS d;

    /* 3. El SP de la Entrega 5 valida y carga las válidas, todas juntas; después se registran la
          importación y sus rechazadas, en la misma transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Torneo.usp_CargarSelecciones @fecha_presentacion = @fecha_presentacion;

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_selecciones;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @ruta_archivo, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @rechazados = @rechazados,
            @id_importacion = @id_importacion OUTPUT;

        INSERT INTO Torneo.ERRORES_SELECCION (id_importacion, registro, nombre, codigo_fifa, grupo, confederacion, motivos)
        SELECT @id_importacion, id_registro, nombre_alternativo, codigo_fifa, grupo, confederacion, STUFF(errores, 1, 2, N'')
        FROM #staging_selecciones
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

    SELECT CONCAT(registro, N'. ', ISNULL(codigo_fifa, N'(sin código)'), N' ', ISNULL(nombre, N'')) AS rechazado, motivos
    FROM Torneo.ERRORES_SELECCION
    WHERE id_importacion = @id_importacion
    ORDER BY registro;
END;
GO


/* ============================================================================
   PARTIDOS
   ============================================================================ */

/*
  usp_ImportarPartidosJSON
  Importa los partidos del archivo worldcup-full.json de openfootball
  (@ruta_archivo) con usp_CargarPartidos y, de los partidos válidos, lo que
  pasó en cada uno (formaciones, cambios, goles, penales convertidos en la
  definición y tarjetas) con usp_CargarDesarrolloPartidos. Las sedes, las
  selecciones y los jugadores tienen que estar cargados antes.
  Los partidos se numeran desde @primer_numero (1 para el fixture completo;
  otro número si el archivo es solo una parte, para no pisar los que ya
  tienen esos números).
  Con @reprocesar_importacion, el número de una importación anterior del
  mismo archivo, reprocesa solo los partidos que tuvieron algún rechazo en
  ella (en Torneo.ERRORES_PARTIDO o en DesarrolloPartido.ERRORES_EVENTO),
  después de corregir lo que los rechazó: los demás ya están cargados y no
  se vuelven a procesar. Se lee el archivo entero, porque el número de cada
  partido sale del orden de todos, pero se reprocesa el partido completo
  (una formación necesita sus 11 titulares, y los cambios, goles y tarjetas,
  la formación): lo que ya estaba queda SIN CAMBIOS y se carga lo que
  faltaba. Lo que se vuelve a rechazar queda con el número de la nueva
  importación, que se puede volver a reprocesar.
  Valida: ruta obligatoria y terminada en .json; primer número entre 1 y
  255; la importación a reprocesar, de este proceso y de este archivo. Si el
  archivo no se puede leer, no es JSON o no tiene la lista "matches", o si
  en un reproceso no tiene los partidos rechazados en esa importación (el
  archivo cambió o se numera desde otro número), no se importa nada (THROW
  50002). Rechaza los registros que no
  puede convertir (ronda, fecha, selecciones y estadio que no reconoce,
  números que no son números, jugadores que no reconoce, minutos y
  tarjetas); las reglas las aplican los SP de la Entrega 5. Registra la
  importación (su número queda en @id_importacion) y los rechazados en
  Torneo.ERRORES_PARTIDO y DesarrolloPartido.ERRORES_EVENTO. Devuelve el
  resumen de partidos y de eventos, los rechazados con sus motivos, y los
  partidos cuyo resultado no coincide con los goles cargados (porque se
  rechazó alguno).
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarPartidosJSON
    @ruta_archivo            NVARCHAR(400),
    @primer_numero           TINYINT = 1,
    @reprocesar_importacion  INT     = NULL,
    @id_importacion          INT     = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores          NVARCHAR(2048) = N'';
    DECLARE @nl               NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido        NVARCHAR(MAX);
    DECLARE @mensaje          NVARCHAR(2048);
    DECLARE @partidos_grupos  INT;
    DECLARE @tran_propia      BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso          VARCHAR(100)   = CONCAT(OBJECT_SCHEMA_NAME(@@PROCID), '.', OBJECT_NAME(@@PROCID));
    DECLARE @leidos           INT;
    DECLARE @insertados       INT;
    DECLARE @actualizados     INT;
    DECLARE @sin_cambios      INT;
    DECLARE @rechazados       INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @nl + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.json'
        SET @errores += @nl + N'- El archivo tiene que ser un .json (worldcup-full.json de openfootball).';

    IF ISNULL(@primer_numero, 0) = 0
        SET @errores += @nl + N'- El primer número de partido tiene que estar entre 1 y 255.';

    IF @reprocesar_importacion IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM DatosGenerales.IMPORTACION
                       WHERE id_importacion = @reprocesar_importacion AND proceso = @proceso AND origen = @ruta_archivo)
        SET @errores += @nl + CONCAT(N'- No hay una importación ', @reprocesar_importacion,
                                     N' de este archivo con este proceso para reprocesar.');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_ImportarPartidosJSON: no se pudo importar el archivo.' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* 1. El archivo. */
    EXEC DatosGenerales.usp_LeerArchivoUTF8 @ruta_archivo = @ruta_archivo, @contenido = @contenido OUTPUT;

    IF ISJSON(@contenido) = 0
        SET @mensaje = N'el archivo no es un JSON válido.';
    ELSE IF JSON_QUERY(@contenido, N'$.matches') IS NULL
        SET @mensaje = N'el archivo no tiene la lista "matches" (no es worldcup-full.json de openfootball).';

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'Torneo.usp_ImportarPartidosJSON: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    -- usp_CargarPartidos lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_partidos (
        id_registro            INT PRIMARY KEY,
        -- Tal como vienen en el archivo
        ronda                  NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
        fecha_txt              NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        hora_txt               NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        equipo_1               NVARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
        equipo_2               NVARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
        estadio_txt            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        asistencia_txt         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        ft_1                   NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        ft_2                   NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        et_1                   NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        et_2                   NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        pen_1                  NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        pen_2                  NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        detalle                NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,   -- el partido completo, para leer sus eventos
        -- Para convertir
        grupo                  CHAR(1)       COLLATE DATABASE_DEFAULT NULL,
        id_seleccion_1         INT           NULL,
        id_seleccion_2         INT           NULL,
        sedes_posibles         INT           NULL,
        -- Lo que lee usp_CargarPartidos, ya convertido
        numero_partido         TINYINT       NULL,
        nombre_estadio         VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        fase                   VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
        fecha_hora_utc         DATETIME2(0)  NULL,
        codigo_fifa_local      VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
        codigo_fifa_visitante  VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
        goles_local            TINYINT       NULL,
        goles_visitante        TINYINT       NULL,
        penales_local          TINYINT       NULL,
        penales_visitante      TINYINT       NULL,
        asistencia             INT           NULL,
        -- Lo que le pasa a cada registro: lo completan este SP y usp_CargarPartidos
        errores                NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion                 VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    -- usp_CargarDesarrolloPartidos lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_eventos (
        id_evento           INT IDENTITY(1,1) PRIMARY KEY,
        tipo                VARCHAR(12)   COLLATE DATABASE_DEFAULT NOT NULL,  -- FORMACION, CAMBIO, GOL, PENAL, TARJETA
        id_registro         INT           NOT NULL,                           -- partido en el archivo
        numero_partido      TINYINT       NOT NULL,
        lado                TINYINT       NULL,                               -- selección del jugador: 1 = team1, 2 = team2
        orden               INT           NULL,                               -- posición en su lista del archivo
        -- Tal como vienen en el archivo
        nombre_txt          NVARCHAR(200) COLLATE DATABASE_DEFAULT NULL,      -- en los cambios, el que sale
        nombre_entra_txt    NVARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
        minuto_txt          NVARCHAR(20)  COLLATE DATABASE_DEFAULT NULL,
        tipo_txt            NVARCHAR(20)  COLLATE DATABASE_DEFAULT NULL,
        de_penal            BIT           NULL,
        en_contra           BIT           NULL,
        marcador_1          TINYINT       NULL,
        -- Lo que lee usp_CargarDesarrolloPartidos, ya convertido
        codigo_fifa         VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
        id_jugador          INT           NULL,
        id_jugador_entra    INT           NULL,
        id_jugador_asistencia INT         NULL,                               -- el archivo no trae asistencias
        es_titular          BIT           NULL,
        posicion_en_cancha  VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
        minuto              TINYINT       NULL,
        minuto_adicional    TINYINT       NULL,
        en_entretiempo      BIT           NULL,
        motivo              VARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,
        periodo             VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL,
        tipo_gol            VARCHAR(40)   COLLATE DATABASE_DEFAULT NULL,
        tipo_tarjeta        VARCHAR(8)    COLLATE DATABASE_DEFAULT NULL,
        es_doble_amarilla   BIT           NULL,
        errores             NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion              VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    -- Jugadores que nombra el archivo: Torneo.usp_IdentificarJugadores los reconoce.
    CREATE TABLE #nombres_fuente (
        id_nombre      INT IDENTITY(1,1) PRIMARY KEY,
        codigo_fifa    VARCHAR(10)    COLLATE DATABASE_DEFAULT NOT NULL,
        nombre_fuente  NVARCHAR(200)  COLLATE DATABASE_DEFAULT NOT NULL,
        id_jugador     INT            NULL,
        paso           TINYINT        NULL,
        error          NVARCHAR(1000) COLLATE DATABASE_DEFAULT NULL
    );

    /* 2. Los partidos, como vienen en el archivo. */
    INSERT INTO #staging_partidos (id_registro, ronda, fecha_txt, hora_txt, equipo_1, equipo_2, estadio_txt,
                                   asistencia_txt, ft_1, ft_2, et_1, et_2, pen_1, pen_2, detalle)
    SELECT CAST(m.[key] AS INT) + 1, NULLIF(TRIM(d.ronda), N''), NULLIF(TRIM(d.fecha), N''), NULLIF(TRIM(d.hora), N''),
           NULLIF(TRIM(d.equipo_1), N''), NULLIF(TRIM(d.equipo_2), N''), NULLIF(TRIM(d.estadio), N''),
           NULLIF(TRIM(d.asistencia), N''), d.ft_1, d.ft_2, d.et_1, d.et_2, d.pen_1, d.pen_2, m.value
    FROM OPENJSON(@contenido, N'$.matches') AS m
    CROSS APPLY OPENJSON(m.value)
        WITH (ronda NVARCHAR(100) '$.round', fecha NVARCHAR(50) '$.date', hora NVARCHAR(50) '$.time',
              equipo_1 NVARCHAR(200) '$.team1', equipo_2 NVARCHAR(200) '$.team2', estadio NVARCHAR(400) '$.ground',
              asistencia NVARCHAR(50) '$.attendance',
              ft_1 NVARCHAR(10) '$.score.ft[0]', ft_2 NVARCHAR(10) '$.score.ft[1]',
              et_1 NVARCHAR(10) '$.score.et[0]', et_2 NVARCHAR(10) '$.score.et[1]',
              pen_1 NVARCHAR(10) '$.score.p[0]', pen_2 NVARCHAR(10) '$.score.p[1]') AS d;

    -- Fase y grupo (para numerar); hora UTC ("13:00 UTC-6"); resultado y asistencia.
    UPDATE st
    SET fase = CASE WHEN r.ronda LIKE '%GROUP%' OR r.ronda LIKE 'GRUPO%'                           THEN 'GRUPOS'
                    WHEN r.ronda IN ('ROUND OF 32', 'DIECISEISAVOS DE FINAL')                      THEN 'DIECISEISAVOS'
                    WHEN r.ronda IN ('ROUND OF 16', 'OCTAVOS DE FINAL')                            THEN 'OCTAVOS'
                    WHEN r.ronda LIKE 'QUARTER%' OR r.ronda = 'CUARTOS DE FINAL'                   THEN 'CUARTOS'
                    WHEN r.ronda LIKE 'SEMI%'                                                      THEN 'SEMIFINAL'
                    WHEN r.ronda LIKE '%THIRD%' OR r.ronda LIKE 'BRONZE%' OR r.ronda LIKE 'TERCER%' THEN 'TERCER_PUESTO'
                    WHEN r.ronda = 'FINAL'                                                          THEN 'FINAL'
               END,
        grupo             = IIF(r.ronda LIKE '%GROUP [A-L]', RIGHT(r.ronda, 1), NULL),
        fecha_hora_utc    = DATEADD(HOUR, -h.desfase, h.local),
        goles_local       = TRY_CONVERT(TINYINT, ISNULL(st.et_1, st.ft_1)),
        goles_visitante   = TRY_CONVERT(TINYINT, ISNULL(st.et_2, st.ft_2)),
        penales_local     = TRY_CONVERT(TINYINT, st.pen_1),
        penales_visitante = TRY_CONVERT(TINYINT, st.pen_2),
        asistencia        = TRY_CONVERT(INT, st.asistencia_txt)
    FROM #staging_partidos AS st
    CROSS APPLY (SELECT UPPER(st.ronda) AS ronda) AS r
    CROSS APPLY (SELECT TRY_CONVERT(DATETIME2(0), st.fecha_txt + N' ' + LEFT(st.hora_txt, CHARINDEX(N' ', st.hora_txt + N' ') - 1), 120) AS local,
                        TRY_CONVERT(INT, SUBSTRING(st.hora_txt, NULLIF(CHARINDEX(N'UTC', st.hora_txt), 0) + 3, 10)) AS desfase) AS h;

    -- Número: por fecha y hora UTC, grupo y orden en el archivo; la fase de grupos primero.
    SELECT @partidos_grupos = COUNT(*)
    FROM #staging_partidos
    WHERE fase = 'GRUPOS' AND fecha_hora_utc IS NOT NULL;

    WITH orden AS (
        SELECT id_registro, fase,
               ROW_NUMBER() OVER (PARTITION BY IIF(fase = 'GRUPOS', 0, 1)
                                  ORDER BY fecha_hora_utc, grupo, id_registro) AS n
        FROM #staging_partidos
        WHERE fase IS NOT NULL AND fecha_hora_utc IS NOT NULL
    )
    UPDATE st
    SET numero_partido = IIF(n.numero <= 255, n.numero, NULL)
    FROM #staging_partidos AS st
    INNER JOIN orden AS o ON o.id_registro = st.id_registro
    CROSS APPLY (SELECT @primer_numero - 1 + o.n + IIF(o.fase = 'GRUPOS', 0, @partidos_grupos) AS numero) AS n;

    -- Reproceso: quedan solo los partidos con algún rechazo en esa importación. Ya numerados, porque
    -- el número sale del orden de todos. Tienen que ser los mismos que entonces (mismo registro, fecha
    -- y selecciones, o mismo número si se rechazaron sus eventos); si no, no se reprocesa nada.
    IF @reprocesar_importacion IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM Torneo.ERRORES_PARTIDO AS e
                   LEFT JOIN #staging_partidos AS st ON st.id_registro = e.registro
                   WHERE e.id_importacion = @reprocesar_importacion
                     AND (st.id_registro IS NULL OR ISNULL(st.fecha_txt, N'') <> ISNULL(e.fecha, N'')
                          OR ISNULL(st.equipo_1, N'') <> ISNULL(e.equipo_1, N'')
                          OR ISNULL(st.equipo_2, N'') <> ISNULL(e.equipo_2, N'')))
           OR EXISTS (SELECT 1 FROM DesarrolloPartido.ERRORES_EVENTO AS e
                      LEFT JOIN #staging_partidos AS st ON st.id_registro = e.registro_partido
                      WHERE e.id_importacion = @reprocesar_importacion
                        AND ISNULL(st.numero_partido, 0) <> ISNULL(e.numero_partido, 0))
        BEGIN
            SET @mensaje = CONCAT(N'Torneo.usp_ImportarPartidosJSON: no se reprocesó nada, el archivo no tiene los ',
                                  N'partidos rechazados en la importación ', @reprocesar_importacion,
                                  N' (cambió o se numera desde otro número).');
            THROW 50002, @mensaje, 1;
        END;

        DELETE st
        FROM #staging_partidos AS st
        WHERE NOT EXISTS (SELECT 1 FROM Torneo.ERRORES_PARTIDO AS e
                          WHERE e.id_importacion = @reprocesar_importacion AND e.registro = st.id_registro)
          AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.ERRORES_EVENTO AS e
                          WHERE e.id_importacion = @reprocesar_importacion AND e.registro_partido = st.id_registro);
    END;

    -- Selecciones: por el nombre del país o un nombre alternativo registrado (sin distinguir tildes).
    UPDATE st
    SET id_seleccion_1 = (SELECT MAX(x.id_seleccion) FROM (
                              SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                              INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                              WHERE p.nombre COLLATE Latin1_General_CI_AI = st.equipo_1 COLLATE Latin1_General_CI_AI
                              UNION
                              SELECT na.id_seleccion FROM Torneo.NOMBRE_ALTERNATIVO AS na
                              WHERE na.id_jugador IS NULL
                                AND na.nombre COLLATE Latin1_General_CI_AI = st.equipo_1 COLLATE Latin1_General_CI_AI) AS x
                          HAVING COUNT(*) = 1),
        id_seleccion_2 = (SELECT MAX(x.id_seleccion) FROM (
                              SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                              INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                              WHERE p.nombre COLLATE Latin1_General_CI_AI = st.equipo_2 COLLATE Latin1_General_CI_AI
                              UNION
                              SELECT na.id_seleccion FROM Torneo.NOMBRE_ALTERNATIVO AS na
                              WHERE na.id_jugador IS NULL
                                AND na.nombre COLLATE Latin1_General_CI_AI = st.equipo_2 COLLATE Latin1_General_CI_AI) AS x
                          HAVING COUNT(*) = 1)
    FROM #staging_partidos AS st;

    UPDATE st
    SET codigo_fifa_local = p1.codigo_fifa, codigo_fifa_visitante = p2.codigo_fifa
    FROM #staging_partidos AS st
    LEFT JOIN Torneo.SELECCION AS s1 ON s1.id_seleccion = st.id_seleccion_1
    LEFT JOIN DatosGenerales.PAIS AS p1 ON p1.id_pais = s1.id_pais
    LEFT JOIN Torneo.SELECCION AS s2 ON s2.id_seleccion = st.id_seleccion_2
    LEFT JOIN DatosGenerales.PAIS AS p2 ON p2.id_pais = s2.id_pais;

    -- Sede: la que tiene su ciudad (lo que está antes del paréntesis) o su nombre en el texto del archivo.
    UPDATE st
    SET sedes_posibles = x.sedes,
        nombre_estadio = IIF(x.sedes = 1, x.nombre_estadio, NULL)
    FROM #staging_partidos AS st
    CROSS APPLY (SELECT MAX(s.nombre_estadio) AS nombre_estadio, COUNT(*) AS sedes
                 FROM Torneo.SEDE AS s
                 WHERE CHARINDEX(LEFT(s.ciudad, CHARINDEX(' (', s.ciudad + ' (') - 1), st.estadio_txt) > 0
                    OR CHARINDEX(s.nombre_estadio, st.estadio_txt) > 0) AS x;

    /* 3. Lo que no se pudo convertir. Las reglas de los partidos las aplica usp_CargarPartidos. */
    UPDATE st
    SET errores = NULLIF(CONCAT(
            IIF(st.fase IS NULL, @nl + N'- La ronda "' + ISNULL(st.ronda, N'') + N'" no es una fase reconocida.', NULL),
            IIF(st.fecha_hora_utc IS NULL,
                @nl + N'- La fecha y hora "' + ISNULL(st.fecha_txt, N'') + N' ' + ISNULL(st.hora_txt, N'')
                    + N'" no son AAAA-MM-DD y HH:MM UTC±H: el partido no se puede numerar.', NULL),
            IIF(st.fecha_hora_utc IS NOT NULL AND st.fase IS NOT NULL AND st.numero_partido IS NULL,
                @nl + N'- El número de partido pasaría de 255.', NULL),
            IIF(st.equipo_1 IS NOT NULL AND st.id_seleccion_1 IS NULL,
                @nl + N'- No hay una selección registrada con el nombre "' + st.equipo_1 + N'" (se puede registrar como nombre alternativo).', NULL),
            IIF(st.equipo_2 IS NOT NULL AND st.id_seleccion_2 IS NULL,
                @nl + N'- No hay una selección registrada con el nombre "' + st.equipo_2 + N'" (se puede registrar como nombre alternativo).', NULL),
            CASE WHEN st.estadio_txt IS NULL    THEN @nl + N'- El estadio es obligatorio.'
                 WHEN st.sedes_posibles = 0     THEN @nl + N'- El estadio "' + st.estadio_txt + N'" no corresponde a ninguna sede registrada.'
                 WHEN st.sedes_posibles > 1     THEN @nl + N'- El estadio "' + st.estadio_txt + N'" puede ser más de una sede.'
            END,
            IIF((ISNULL(st.et_1, st.ft_1) IS NOT NULL AND st.goles_local IS NULL)
                OR (ISNULL(st.et_2, st.ft_2) IS NOT NULL AND st.goles_visitante IS NULL),
                @nl + N'- Los goles del resultado no son números.', NULL),
            IIF((st.pen_1 IS NOT NULL AND st.penales_local IS NULL) OR (st.pen_2 IS NOT NULL AND st.penales_visitante IS NULL),
                @nl + N'- Los penales no son números.', NULL),
            IIF(st.asistencia_txt IS NOT NULL AND st.asistencia IS NULL,
                @nl + N'- La asistencia "' + st.asistencia_txt + N'" no es un número.', NULL)), N'')
    FROM #staging_partidos AS st;

    UPDATE #staging_partidos SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. Los SP de la Entrega 5 validan y cargan los partidos y, de los válidos, lo que pasó en cada
          uno; después se registran la importación y sus rechazados. Todo en una transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Torneo.usp_CargarPartidos;

        -- Cada INSERT lleva ORDER BY para que id_evento (el registro de ERRORES_EVENTO) siga el orden
        -- del archivo y salga igual en cada importación.
        -- Formaciones: titulares y suplentes de cada selección (lineup[0] es team1).
        INSERT INTO #staging_eventos (tipo, id_registro, numero_partido, lado, orden, nombre_txt, es_titular)
        SELECT 'FORMACION', st.id_registro, st.numero_partido, CAST(l.[key] AS INT) + 1 AS lado, CAST(j.[key] AS INT) + 1 AS orden,
               NULLIF(TRIM(JSON_VALUE(j.value, N'$.name')), N''), 1
        FROM #staging_partidos AS st
        CROSS APPLY OPENJSON(st.detalle, N'$.lineup') AS l
        CROSS APPLY OPENJSON(l.value, N'$.starter') AS j
        WHERE st.accion <> 'RECHAZADO' AND l.[key] IN (N'0', N'1')
        UNION ALL
        SELECT 'FORMACION', st.id_registro, st.numero_partido, CAST(l.[key] AS INT) + 1, 100 + CAST(j.[key] AS INT) + 1,
               NULLIF(TRIM(JSON_VALUE(j.value, N'$.name')), N''), 0
        FROM #staging_partidos AS st
        CROSS APPLY OPENJSON(st.detalle, N'$.lineup') AS l
        CROSS APPLY OPENJSON(l.value, N'$.bench') AS j
        WHERE st.accion <> 'RECHAZADO' AND l.[key] IN (N'0', N'1')
        ORDER BY id_registro, lado, orden;

        -- Cambios: el archivo no dice el motivo (queda vacío).
        INSERT INTO #staging_eventos (tipo, id_registro, numero_partido, lado, orden, nombre_txt, nombre_entra_txt, minuto_txt)
        SELECT 'CAMBIO', st.id_registro, st.numero_partido, CAST(l.[key] AS INT) + 1, CAST(c.[key] AS INT) + 1,
               NULLIF(TRIM(d.sale), N''), NULLIF(TRIM(d.entra), N''), NULLIF(TRIM(d.minuto), N'')
        FROM #staging_partidos AS st
        CROSS APPLY OPENJSON(st.detalle, N'$.lineup') AS l
        CROSS APPLY OPENJSON(l.value, N'$.subs') AS c
        CROSS APPLY OPENJSON(c.value)
            WITH (sale NVARCHAR(200) '$.off', entra NVARCHAR(200) '$.on', minuto NVARCHAR(20) '$.minute') AS d
        WHERE st.accion <> 'RECHAZADO' AND l.[key] IN (N'0', N'1')
        ORDER BY st.id_registro, CAST(l.[key] AS INT), CAST(c.[key] AS INT);

        -- Goles: goals1 son los que suman para team1; un gol en contra lo hizo un jugador del rival.
        INSERT INTO #staging_eventos (tipo, id_registro, numero_partido, lado, orden, nombre_txt, minuto_txt, de_penal, en_contra)
        SELECT 'GOL', st.id_registro, st.numero_partido, IIF(d.en_contra = N'true', 3 - x.lado, x.lado),
               CAST(g.[key] AS INT) + 1, NULLIF(TRIM(d.nombre), N''), NULLIF(TRIM(d.minuto), N''),
               IIF(d.de_penal = N'true', 1, 0), IIF(d.en_contra = N'true', 1, 0)
        FROM #staging_partidos AS st
        CROSS APPLY (VALUES (1, JSON_QUERY(st.detalle, N'$.goals1')), (2, JSON_QUERY(st.detalle, N'$.goals2'))) AS x (lado, goles)
        CROSS APPLY OPENJSON(x.goles) AS g
        CROSS APPLY OPENJSON(g.value)
            WITH (nombre NVARCHAR(200) '$.name', minuto NVARCHAR(20) '$.minute',
                  de_penal NVARCHAR(10) '$.penalty', en_contra NVARCHAR(10) '$.owngoal') AS d
        WHERE st.accion <> 'RECHAZADO'
        ORDER BY st.id_registro, x.lado, CAST(g.[key] AS INT);

        -- Penales convertidos en la definición: el equipo sale de cómo cambia el marcador.
        WITH penales AS (
            SELECT st.id_registro, st.numero_partido, CAST(p.[key] AS INT) + 1 AS orden, NULLIF(TRIM(d.nombre), N'') AS nombre,
                   d.marcador_1,
                   LAG(d.marcador_1, 1, 0) OVER (PARTITION BY st.id_registro ORDER BY CAST(p.[key] AS INT)) AS marcador_1_antes
            FROM #staging_partidos AS st
            CROSS APPLY OPENJSON(st.detalle, N'$.penalties') AS p
            CROSS APPLY OPENJSON(p.value) WITH (nombre NVARCHAR(200) '$.name', marcador_1 TINYINT '$.score[0]') AS d
            WHERE st.accion <> 'RECHAZADO' AND d.marcador_1 IS NOT NULL
        )
        INSERT INTO #staging_eventos (tipo, id_registro, numero_partido, lado, orden, nombre_txt, marcador_1)
        SELECT 'PENAL', id_registro, numero_partido, IIF(marcador_1 > marcador_1_antes, 1, 2), orden, nombre, marcador_1
        FROM penales
        ORDER BY id_registro, orden;

        -- Tarjetas: bookings[0] son las de team1. Y/R se registra como amarilla y como roja por doble
        -- amarilla. El archivo no tiene el motivo (queda vacío).
        INSERT INTO #staging_eventos (tipo, id_registro, numero_partido, lado, orden, nombre_txt, minuto_txt, tipo_txt,
                                      tipo_tarjeta, es_doble_amarilla)
        SELECT 'TARJETA', st.id_registro, st.numero_partido, CAST(b.[key] AS INT) + 1, CAST(t.[key] AS INT) + 1,
               NULLIF(TRIM(d.nombre), N''), NULLIF(TRIM(d.minuto), N''), d.tipo, c.tarjeta, c.doble
        FROM #staging_partidos AS st
        CROSS APPLY OPENJSON(st.detalle, N'$.bookings') AS b
        CROSS APPLY OPENJSON(b.value) AS t
        CROSS APPLY OPENJSON(t.value)
            WITH (tipo NVARCHAR(20) '$.type', nombre NVARCHAR(200) '$.name', minuto NVARCHAR(20) '$.minute') AS d
        OUTER APPLY (SELECT v.tarjeta, v.doble
                     FROM (VALUES (N'Y', 'AMARILLA', 0), (N'R', 'ROJA', 0), (N'Y/R', 'AMARILLA', 0), (N'Y/R', 'ROJA', 1))
                          AS v (codigo, tarjeta, doble)
                     WHERE v.codigo = UPPER(TRIM(d.tipo))) AS c
        WHERE st.accion <> 'RECHAZADO' AND b.[key] IN (N'0', N'1')
        ORDER BY st.id_registro, CAST(b.[key] AS INT), CAST(t.[key] AS INT), c.doble;

        -- Selección del jugador y minuto ("45+2": minuto 45 y 2 de adicional).
        UPDATE e
        SET codigo_fifa      = IIF(e.lado = 1, st.codigo_fifa_local, st.codigo_fifa_visitante),
            minuto           = TRY_CONVERT(TINYINT, LEFT(e.minuto_txt, CHARINDEX(N'+', e.minuto_txt + N'+') - 1)),
            minuto_adicional = IIF(CHARINDEX(N'+', e.minuto_txt) > 0,
                                   TRY_CONVERT(TINYINT, SUBSTRING(e.minuto_txt, CHARINDEX(N'+', e.minuto_txt) + 1, 10)), 0)
        FROM #staging_eventos AS e
        INNER JOIN #staging_partidos AS st ON st.id_registro = e.id_registro;

        -- Un minuto después del 120 es tiempo adicional del alargue: 121 es 120+1.
        UPDATE #staging_eventos
        SET minuto_adicional = minuto - 120, minuto = 120
        WHERE minuto > 120 AND minuto_adicional = 0;

        -- Jugadores: se reconocen dentro de la lista de su selección.
        INSERT INTO #nombres_fuente (codigo_fifa, nombre_fuente)
        SELECT codigo_fifa, nombre_txt FROM #staging_eventos WHERE codigo_fifa IS NOT NULL AND nombre_txt IS NOT NULL
        UNION
        SELECT codigo_fifa, nombre_entra_txt FROM #staging_eventos WHERE codigo_fifa IS NOT NULL AND nombre_entra_txt IS NOT NULL;

        EXEC Torneo.usp_IdentificarJugadores;

        UPDATE e
        SET id_jugador       = ns.id_jugador,
            id_jugador_entra = ne.id_jugador,
            errores          = NULLIF(CONCAT(
                IIF(e.nombre_txt IS NULL, @nl + N'- Falta el nombre del jugador.', NULL),
                IIF(ns.error IS NOT NULL, @nl + N'- ' + ns.error, NULL),
                IIF(e.tipo = 'CAMBIO' AND e.nombre_entra_txt IS NULL, @nl + N'- Falta el jugador que entra.', NULL),
                IIF(ne.error IS NOT NULL, @nl + N'- ' + ne.error, NULL)), N'')
        FROM #staging_eventos AS e
        LEFT JOIN #nombres_fuente AS ns ON ns.codigo_fifa = e.codigo_fifa AND ns.nombre_fuente = e.nombre_txt
        LEFT JOIN #nombres_fuente AS ne ON ne.codigo_fifa = e.codigo_fifa AND ne.nombre_fuente = e.nombre_entra_txt;

        -- Lo que sale de cada dato: la posición de los titulares es la habitual; el período sale del
        -- minuto; el tipo de gol, de si fue de penal o en contra; un cambio en el 46, 91 o 106 se hizo
        -- en el entretiempo.
        UPDATE e
        SET posicion_en_cancha = IIF(e.tipo = 'FORMACION' AND e.es_titular = 1, j.posicion_habitual, NULL),
            periodo  = CASE WHEN e.tipo = 'PENAL'                                  THEN 'PENALES'
                            WHEN e.tipo <> 'GOL'                                   THEN NULL
                            WHEN e.minuto_adicional > 0                            THEN 'ADICIONALES'
                            WHEN e.minuto BETWEEN 1 AND 45                         THEN 'PRIMER_TIEMPO'
                            WHEN e.minuto BETWEEN 46 AND 90                        THEN 'SEGUNDO_TIEMPO'
                            WHEN e.minuto BETWEEN 91 AND 120                       THEN 'ALARGUE'
                       END,
            tipo_gol = CASE WHEN e.tipo NOT IN ('GOL', 'PENAL')                    THEN NULL
                            WHEN e.en_contra = 1                                   THEN 'EN CONTRA'
                            WHEN e.de_penal = 1 OR e.tipo = 'PENAL'                THEN 'PENAL'
                            ELSE 'JUGADA'
                       END,
            minuto           = IIF(e.tipo = 'PENAL', NULL, e.minuto),
            minuto_adicional = IIF(e.tipo = 'PENAL', 0, e.minuto_adicional),
            en_entretiempo   = IIF(e.tipo = 'CAMBIO', IIF(e.minuto IN (46, 91, 106) AND e.minuto_adicional = 0, 1, 0), NULL)
        FROM #staging_eventos AS e
        LEFT JOIN Torneo.JUGADOR AS j ON j.id_jugador = e.id_jugador;

        UPDATE #staging_eventos
        SET errores = NULLIF(CONCAT(errores,
                CASE WHEN tipo IN ('CAMBIO', 'GOL', 'TARJETA') AND minuto_txt IS NULL
                         THEN @nl + N'- Falta el minuto.'
                     WHEN tipo IN ('CAMBIO', 'GOL', 'TARJETA') AND (minuto IS NULL OR minuto_adicional IS NULL)
                         THEN @nl + N'- El minuto "' + minuto_txt + N'" no es un número (o número+adicional).'
                END,
                IIF(tipo = 'TARJETA' AND tipo_tarjeta IS NULL,
                    @nl + N'- La tarjeta "' + ISNULL(tipo_txt, N'') + N'" no es Y, R ni Y/R.', NULL)), N'');

        UPDATE #staging_eventos SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

        EXEC DesarrolloPartido.usp_CargarDesarrolloPartidos;

        -- Registro: los totales cuentan los partidos y sus eventos.
        SELECT @leidos       = SUM(leidos),       @insertados  = SUM(insertados), @actualizados = SUM(actualizados),
               @sin_cambios  = SUM(sin_cambios),  @rechazados  = SUM(rechazados)
        FROM (SELECT COUNT(*) AS leidos,
                     ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0)   AS insertados,
                     ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0) AS actualizados,
                     ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0) AS sin_cambios,
                     ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)   AS rechazados
              FROM #staging_partidos
              UNION ALL
              SELECT COUNT(*),
                     ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
                     ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
                     ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
                     ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
              FROM #staging_eventos) AS t;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @ruta_archivo, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @rechazados = @rechazados,
            @id_importacion = @id_importacion OUTPUT;

        INSERT INTO Torneo.ERRORES_PARTIDO (id_importacion, registro, ronda, fecha, hora, equipo_1, equipo_2, estadio,
                                            asistencia, resultado, motivos)
        SELECT @id_importacion, id_registro, ronda, fecha_txt, hora_txt, equipo_1, equipo_2, estadio_txt, asistencia_txt,
               -- Cada marcador como viene; si falta uno de los dos números, va un "?".
               NULLIF(CONCAT_WS(N', ',
                   IIF(ft_1 IS NULL AND ft_2 IS NULL, NULL, CONCAT(N'ft ', ISNULL(ft_1, N'?'), N'-', ISNULL(ft_2, N'?'))),
                   IIF(et_1 IS NULL AND et_2 IS NULL, NULL, CONCAT(N'et ', ISNULL(et_1, N'?'), N'-', ISNULL(et_2, N'?'))),
                   IIF(pen_1 IS NULL AND pen_2 IS NULL, NULL, CONCAT(N'p ', ISNULL(pen_1, N'?'), N'-', ISNULL(pen_2, N'?')))), N''),
               STUFF(errores, 1, 2, N'')
        FROM #staging_partidos
        WHERE accion = 'RECHAZADO';

        INSERT INTO DesarrolloPartido.ERRORES_EVENTO (id_importacion, registro, registro_partido, numero_partido, tipo,
                                                      codigo_fifa, jugador, jugador_entra, minuto, tarjeta, motivos)
        SELECT @id_importacion, id_evento, id_registro, numero_partido, tipo, codigo_fifa, nombre_txt, nombre_entra_txt,
               minuto_txt, tipo_txt, STUFF(errores, 1, 2, N'')
        FROM #staging_eventos
        WHERE accion = 'RECHAZADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    /* 5. Resultado. */
    SELECT @id_importacion AS id_importacion, N'Partidos' AS registros, COUNT(*) AS leidos,
           ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0) AS insertados,
           ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0) AS actualizados,
           ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0) AS sin_cambios,
           ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0) AS rechazados
    FROM #staging_partidos
    UNION ALL
    SELECT @id_importacion, N'Formaciones, cambios, goles, penales y tarjetas', COUNT(*),
           ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
           ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
           ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
           ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
    FROM #staging_eventos;

    SELECT tipo, COUNT(*) AS leidos, SUM(IIF(accion = 'RECHAZADO', 1, 0)) AS rechazados
    FROM #staging_eventos
    GROUP BY tipo
    ORDER BY tipo;

    SELECT CONCAT(N'Registro ', registro, N': ', ISNULL(fecha, N''), N' ', ISNULL(equipo_1, N'?'), N' - ',
                  ISNULL(equipo_2, N'?')) AS rechazado, motivos
    FROM Torneo.ERRORES_PARTIDO
    WHERE id_importacion = @id_importacion
    ORDER BY registro;

    SELECT CONCAT(N'Partido ', e.numero_partido, N' (', st.equipo_1, N' - ', st.equipo_2, N'), ', LOWER(e.tipo),
                  N' de ', e.codigo_fifa, N': ', e.nombre_txt, IIF(e.nombre_entra_txt IS NULL, N'', N' por ' + e.nombre_entra_txt),
                  IIF(e.minuto_txt IS NULL, N'', N', minuto ' + e.minuto_txt)) AS rechazado,
           STUFF(e.errores, 1, 2, N'') AS motivos
    FROM #staging_eventos AS e
    INNER JOIN #staging_partidos AS st ON st.id_registro = e.id_registro
    WHERE e.accion = 'RECHAZADO'
    ORDER BY e.numero_partido, e.tipo, e.lado, e.orden;

    -- Partidos cuyo resultado no coincide con los goles cargados: falta alguno que se rechazó.
    SELECT p.numero_partido, f.seleccion_local, f.resultado, f.seleccion_visitante,
           CONCAT(m.goles_local, N' - ', m.goles_visitante) AS goles_cargados
    FROM #staging_partidos AS st
    INNER JOIN Torneo.PARTIDO AS p ON p.numero_partido = st.numero_partido
    INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = p.id_partido
    CROSS APPLY DesarrolloPartido.fn_MarcadorSegunGoles(p.id_partido) AS m
    WHERE st.accion <> 'RECHAZADO'
      AND (p.goles_local <> m.goles_local OR p.goles_visitante <> m.goles_visitante
           OR ISNULL(p.penales_local, 0) <> m.penales_local OR ISNULL(p.penales_visitante, 0) <> m.penales_visitante)
    ORDER BY p.numero_partido;
END;
GO


/* ============================================================================
   EQUIPO ARBITRAL
   ============================================================================ */

/*
  usp_ImportarDesignacionesCSV
  Importa el equipo arbitral de cada partido desde el CSV que genera el
  scraping de Wikipedia (designaciones_arbitrales.csv, ver
  scraping/README.md), con una fila por árbitro designado y esta primera fila
  con los nombres de las columnas:
    fecha,local,visitante,rol,nombre,apellido,pais
  fecha es la del partido (AAAA-MM-DD, en la hora local de la sede), local y
  visitante los códigos FIFA de sus selecciones (en cualquier orden), rol el
  que publica la FIFA en inglés (lo traduce usp_CargarDesignaciones) y pais
  el código FIFA del país del árbitro. Los partidos tienen que estar
  cargados antes (usp_ImportarPartidosJSON).
  Primero carga los árbitros con usp_CargarArbitros: uno por cada país,
  nombre y apellido distintos del archivo, con la categoría @categoria (el
  archivo no la trae; los árbitros del Mundial son de la lista de la FIFA).
  Después, las designaciones con usp_CargarDesignaciones.
  Valida: ruta obligatoria y terminada en .csv; categoría FIFA o
  CONFEDERACION. Si el archivo no se puede leer, no tiene las columnas
  esperadas o alguna fila no es CSV válido, no se importa nada (THROW 50002).
  Rechaza las filas con una fecha que no es fecha, las de un partido que no
  encuentra y las de un árbitro rechazado; las reglas las aplican los SP de
  la Entrega 5. Registra la importación (los totales cuentan las filas del
  archivo, es decir, las designaciones; su número queda en @id_importacion)
  y las filas rechazadas en Arbitraje.ERRORES_DESIGNACION. Devuelve el
  resumen de designaciones y de árbitros, los rechazados con sus motivos y
  los partidos del archivo a los que les falta alguno de los cinco roles que
  pide la consigna.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ImportarDesignacionesCSV
    @ruta_archivo    NVARCHAR(400),
    @categoria       VARCHAR(15) = 'FIFA',
    @id_importacion  INT         = NULL OUTPUT
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
    SET @categoria    = UPPER(NULLIF(TRIM(@categoria), ''));
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @nl + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.csv'
        SET @errores += @nl + N'- El archivo tiene que ser un .csv (el designaciones_arbitrales.csv del scraping).';

    IF @categoria IS NULL OR @categoria NOT IN ('FIFA', 'CONFEDERACION')
        SET @errores += @nl + N'- La categoría de los árbitros tiene que ser FIFA o CONFEDERACION.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ImportarDesignacionesCSV: no se pudo importar el archivo.' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* 1. El archivo: la primera fila tiene que tener las columnas esperadas. */
    EXEC DatosGenerales.usp_LeerArchivoUTF8 @ruta_archivo = @ruta_archivo, @contenido = @contenido OUTPUT;

    SET @encabezado = REPLACE(REPLACE(LEFT(@contenido, CHARINDEX(NCHAR(10), @contenido + NCHAR(10)) - 1),
                                      NCHAR(13), N''), N' ', N'');
    IF @encabezado <> N'fecha,local,visitante,rol,nombre,apellido,pais'
    BEGIN
        SET @mensaje = N'Arbitraje.usp_ImportarDesignacionesCSV: no se importó nada, la primera fila del archivo tiene que ser '
                     + N'"fecha,local,visitante,rol,nombre,apellido,pais" y es "' + LEFT(@encabezado, 200) + N'".';
        THROW 50002, @mensaje, 1;
    END;

    /* 2. Las filas, como vienen. FORMAT = 'CSV' respeta las comillas. El fin de
          línea es el del archivo: CRLF (Windows) o LF. */
    CREATE TABLE #crudo (
        fecha_txt      NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        local_txt      NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        visitante_txt  NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        rol_txt        NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
        nombre         NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido       NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        pais_txt       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL
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
                     + N'(tienen que tener 7 columnas): ' + ERROR_MESSAGE();
        THROW 50002, @mensaje, 1;
    END CATCH;

    -- usp_CargarDesignaciones lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_designaciones (
        id_registro     INT PRIMARY KEY,   -- línea del archivo
        -- Tal como vienen en el archivo
        fecha_txt       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        local_txt       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        visitante_txt   NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        rol_txt         NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
        nombre          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido        NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        pais_txt        NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        -- Para convertir
        fecha           DATE          NULL,
        -- Lo que lee usp_CargarDesignaciones, ya convertido
        numero_partido  TINYINT       NULL,
        id_arbitro      INT           NULL,
        rol             VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        -- Lo que le pasa a cada registro: lo completan este SP y usp_CargarDesignaciones
        errores         NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion          VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    -- usp_CargarArbitros lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_arbitros (
        id_registro       INT PRIMARY KEY,   -- primera línea del archivo en la que aparece
        codigo_fifa       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        categoria         VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
        fecha_nacimiento  DATE          NULL,
        idiomas           VARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,   -- el archivo no los trae
        errores           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion            VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    INSERT INTO #staging_designaciones (id_registro, fecha_txt, local_txt, visitante_txt, rol_txt, nombre, apellido, pais_txt)
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) + 1,
           NULLIF(TRIM(fecha_txt), N''), UPPER(NULLIF(TRIM(local_txt), N'')), UPPER(NULLIF(TRIM(visitante_txt), N'')),
           NULLIF(TRIM(rol_txt), N''), NULLIF(TRIM(nombre), N''), NULLIF(TRIM(apellido), N''),
           UPPER(NULLIF(TRIM(REPLACE(pais_txt, NCHAR(13), N'')), N''))
    FROM #crudo
    WHERE CONCAT(fecha_txt, local_txt, visitante_txt, rol_txt, nombre, apellido, REPLACE(pais_txt, NCHAR(13), N'')) <> N'';

    -- El rol pasa como viene ("Referee", "Fourth official"): lo traduce usp_CargarDesignaciones.
    UPDATE #staging_designaciones
    SET fecha = TRY_CONVERT(DATE, fecha_txt, 23),
        rol   = LEFT(rol_txt, 100);

    -- El partido: el de esa fecha (hora local de la sede) entre esas dos selecciones, en cualquier orden.
    UPDATE st
    SET numero_partido = (SELECT MAX(p.numero_partido)
                          FROM Torneo.PARTIDO AS p
                          INNER JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = p.id_seleccion_local
                          INNER JOIN DatosGenerales.PAIS AS pl ON pl.id_pais = sl.id_pais
                          INNER JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = p.id_seleccion_visitante
                          INNER JOIN DatosGenerales.PAIS AS pv ON pv.id_pais = sv.id_pais
                          WHERE CAST(p.fecha_hora_local AS DATE) = st.fecha
                            AND ((pl.codigo_fifa = st.local_txt AND pv.codigo_fifa = st.visitante_txt)
                              OR (pl.codigo_fifa = st.visitante_txt AND pv.codigo_fifa = st.local_txt)))
    FROM #staging_designaciones AS st
    WHERE st.fecha IS NOT NULL;

    -- Un árbitro por cada país, nombre y apellido distintos del archivo.
    INSERT INTO #staging_arbitros (id_registro, codigo_fifa, nombre, apellido, categoria)
    SELECT MIN(id_registro), pais_txt, nombre, apellido, @categoria
    FROM #staging_designaciones
    GROUP BY pais_txt, nombre, apellido;

    /* 3. Lo que no se pudo convertir. Las reglas de los árbitros y de las designaciones las
          aplican usp_CargarArbitros y usp_CargarDesignaciones. */
    UPDATE #staging_designaciones
    SET errores = NULLIF(CONCAT(
            CASE WHEN fecha_txt IS NULL THEN @nl + N'- La fecha del partido es obligatoria.'
                 WHEN fecha IS NULL     THEN @nl + N'- La fecha "' + fecha_txt + N'" no es una fecha AAAA-MM-DD.'
            END,
            CASE WHEN local_txt IS NULL OR visitante_txt IS NULL
                     THEN @nl + N'- Faltan las selecciones del partido.'
                 WHEN fecha IS NOT NULL AND numero_partido IS NULL
                     THEN @nl + N'- No hay un partido entre ' + local_txt + N' y ' + visitante_txt + N' el '
                              + CONVERT(NVARCHAR(10), fecha, 103) + N'.'
            END), N'');

    /* 4. Los SP de la Entrega 5 cargan los árbitros y, con ellos, las designaciones; después se
          registran la importación y sus rechazados. Todo en una transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Arbitraje.usp_CargarArbitros;

        -- Cada fila con su árbitro, o con los motivos por los que se rechazó.
        UPDATE st
        SET id_arbitro = a.id_arbitro,
            errores    = NULLIF(CONCAT(st.errores,
                             IIF(sa.accion = 'RECHAZADO', @nl + N'- El árbitro se rechazó:' + REPLACE(sa.errores, @nl + N'- ', @nl + N'  - '), NULL)), N'')
        FROM #staging_designaciones AS st
        INNER JOIN #staging_arbitros AS sa
                ON EXISTS (SELECT st.pais_txt, st.nombre, st.apellido INTERSECT SELECT sa.codigo_fifa, sa.nombre, sa.apellido)
        LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = sa.codigo_fifa
        LEFT JOIN Arbitraje.ARBITRO AS a ON a.id_pais = pa.id_pais AND a.apellido = sa.apellido AND a.nombre = sa.nombre
                                        AND sa.accion <> 'RECHAZADO';

        UPDATE #staging_designaciones SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

        EXEC Arbitraje.usp_CargarDesignaciones;

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_designaciones;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @ruta_archivo, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @rechazados = @rechazados,
            @id_importacion = @id_importacion OUTPUT;

        INSERT INTO Arbitraje.ERRORES_DESIGNACION (id_importacion, registro, fecha, local, visitante, rol, nombre, apellido,
                                                   pais, motivos)
        SELECT @id_importacion, id_registro, fecha_txt, local_txt, visitante_txt, rol_txt, nombre, apellido, pais_txt,
               STUFF(errores, 1, 2, N'')
        FROM #staging_designaciones
        WHERE accion = 'RECHAZADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    /* 5. Resultado. */
    SELECT @id_importacion AS id_importacion, N'Designaciones' AS registros, @leidos AS leidos, @insertados AS insertados,
           @actualizados AS actualizados, @sin_cambios AS sin_cambios, @rechazados AS rechazados
    UNION ALL
    SELECT @id_importacion, N'Árbitros', COUNT(*),
           ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
           ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
           ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
           ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
    FROM #staging_arbitros;

    SELECT CONCAT(N'Línea ', registro, N': ', ISNULL(fecha, N'(sin fecha)'), N' ', ISNULL(local, N'?'), N' - ',
                  ISNULL(visitante, N'?'), N', ', ISNULL(rol, N'(sin rol)'), N': ', ISNULL(nombre, N''), N' ',
                  ISNULL(apellido, N''), N' (', ISNULL(pais, N'?'), N')') AS rechazado,
           motivos
    FROM Arbitraje.ERRORES_DESIGNACION
    WHERE id_importacion = @id_importacion
    ORDER BY registro;

    -- Partidos del archivo a los que les falta alguno de los cinco roles que pide la consigna.
    SELECT p.numero_partido, f.seleccion_local, f.seleccion_visitante,
           STRING_AGG(r.rol, ', ') WITHIN GROUP (ORDER BY r.orden) AS roles_sin_designar
    FROM Torneo.PARTIDO AS p
    INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = p.id_partido
    CROSS JOIN (VALUES (1, 'PRINCIPAL'), (2, 'ASISTENTE_1'), (3, 'ASISTENTE_2'), (4, 'CUARTO'), (5, 'VAR')) AS r (orden, rol)
    WHERE p.numero_partido IN (SELECT numero_partido FROM #staging_designaciones)
      AND NOT EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL AS d WHERE d.id_partido = p.id_partido AND d.rol = r.rol)
    GROUP BY p.numero_partido, f.seleccion_local, f.seleccion_visitante
    ORDER BY p.numero_partido;
END;
GO


-- Evidencia: objetos de la importación del Mundial 2026 creados.
SELECT s.name AS esquema, o.name AS objeto, o.type_desc AS tipo
FROM sys.objects AS o
INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE o.name IN (N'usp_LeerArchivoUTF8', N'fn_ClaveNombre', N'fn_CoordenadaDecimal', N'usp_IdentificarJugadores',
                 N'usp_ImportarSedesJSON', N'usp_ImportarSeleccionesJSON', N'usp_ImportarPartidosJSON',
                 N'usp_ImportarDesignacionesCSV')
ORDER BY o.type_desc, o.name;
GO
