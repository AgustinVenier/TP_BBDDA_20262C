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
           archivos JSON de openfootball (ver doc/Fuentes_de_Datos_y_APIs.docx):
           sedes, selecciones y partidos con lo que pasó en cada uno
           (formaciones, cambios, goles, penales de la definición y
           tarjetas), y después el equipo arbitral de cada partido, desde el
           CSV del scraping de Wikipedia (doc/Tecnica_de_Scraping.docx). Los
           jugadores se importan antes (19_SP_Importar_Jugadores.sql).
           Los objetos, en el orden en que se crean:
             Torneo.fn_CoordenadaDecimal                     coordenada en grados con decimales
             Torneo.usp_CargarSedes                          carga masiva de sedes
             Torneo.usp_ImportarSedesJSON                    worldcup.stadiums.json
             Torneo.usp_CargarSelecciones                    carga masiva de selecciones
             Torneo.usp_ImportarSeleccionesJSON              worldcup.teams.json
             Torneo.usp_CargarPartidos                       carga masiva de partidos
             DesarrolloPartido.usp_CargarDesarrolloPartidos  carga masiva de lo que pasó en cada partido
             Torneo.usp_ImportarPartidosJSON                 worldcup-full.json
             Arbitraje.usp_CargarArbitros                    carga masiva de árbitros
             Arbitraje.usp_CargarDesignaciones               carga masiva de designaciones
             Arbitraje.usp_ImportarDesignacionesCSV          designaciones_arbitrales.csv (scraping)
             Arbitraje.usp_ImportarArbitrosCSV               CSV de árbitros sueltos (lo usa la aplicación)
           La forma de trabajo común y las utilidades que usan
           (usp_LeerArchivoUTF8, usp_IdentificarJugadores) están en
           17_SP_Utilidades_Importacion.sql. Requiere haber ejecutado 01 a 17.
           Su script de testing es 68_Test_SP_Importar_Mundial2026.sql; la
           carga del torneo real la hace 32_Importar_Mundial2026.sql.
================================================================================

 Cómo importa cada SP (igual que 19, 21, 22 y 23; los pasos tienen el mismo
 número en el código):
   1. Se controla el archivo: que se pueda leer, que sea JSON y que tenga la
      estructura del archivo de openfootball que corresponde (o, el CSV del
      equipo arbitral, sus columnas). Si no, no se importa nada (THROW 50002).
   2. OPENJSON (o BULK INSERT, el CSV) pasa los registros, tal como vienen, a
      la tabla de staging del SP de carga (#staging_sedes, por ejemplo), y
      ahí se convierten, en T-SQL.
   3. Un UPDATE marca RECHAZADO, con su motivo, lo que no se pudo convertir.
   4. El SP de carga valida los demás y carga los válidos, todos juntos. En
      la misma transacción se registra la importación (su número queda en
      @id_importacion) y sus rechazados, en la tabla ERRORES_ de lo que se
      importó (Torneo.ERRORES_SEDE, por ejemplo).
   5. Se devuelve el resumen y los rechazados con sus motivos.

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
   - Un gol o una tarjeta que el archivo trae con otro minuto es otro evento,
     no una corrección del cargado: ver usp_CargarDesarrolloPartidos.

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
    DECLARE @pos_grados INT = CHARINDEX(N'°', @texto);
    DECLARE @pos_minutos INT = CHARINDEX(N'''', @texto);
    DECLARE @pos_segundos INT = CHARINDEX(N'"', @texto);
    DECLARE @hemisferio NCHAR(1) = UPPER(RIGHT(@texto, 1));

    IF @pos_grados < 2 OR CHARINDEX(@hemisferio, @hemisferios) = 0 OR (@pos_segundos > 0 AND @pos_minutos = 0)
        RETURN NULL;

    RETURN (TRY_CONVERT(DECIMAL(12,6), LEFT(@texto, @pos_grados - 1))
            + IIF(@pos_minutos > @pos_grados, TRY_CONVERT(DECIMAL(12,6), SUBSTRING(@texto, @pos_grados + 1, @pos_minutos - @pos_grados - 1)), 0) / 60
            + IIF(@pos_segundos > @pos_minutos AND @pos_minutos > 0, TRY_CONVERT(DECIMAL(12,6), SUBSTRING(@texto, @pos_minutos + 1, @pos_segundos - @pos_minutos - 1)), 0) / 3600)
           * IIF(@hemisferio IN (N'S', N'W'), -1, 1);
END;
GO

/*
  usp_CargarSedes
  Upsert de sedes por nombre del estadio, desde #staging_sedes. Columnas que
  usa: nombre_estadio, ciudad, codigo_fifa (del país), capacidad,
  huso_horario, latitud, longitud, tarifa_1 a tarifa_4, errores y accion.
  Una sede nueva se registra con sus 4 espacios publicitarios, como en
  usp_RegistrarSede; en una existente, un dato que no viene no se modifica,
  y una tarifa que viene actualiza la de ese espacio, como en
  usp_ModificarSede (cambiar la tarifa no altera el costo de las
  exhibiciones ya registradas).
  Valida cada sede pendiente: nombre del estadio obligatorio, de hasta 100
  caracteres y sin repetir; ciudad de hasta 80; para las sedes nuevas,
  ciudad, país, capacidad, huso y las 4 tarifas obligatorios; países
  existentes; husos existentes en sys.time_zone_info; capacidad mayor que
  cero y no menor que la asistencia de un partido ya jugado en la sede;
  latitud y longitud juntas y dentro de rango; tarifas no negativas, y solo
  para una sede existente que tenga sus 4 espacios. Con eso cubre las reglas
  de usp_SEDE_Alta, usp_SEDE_Modificacion, usp_RegistrarSede y
  usp_ModificarSede. Si cambia el huso de una sede, recalcula la hora local
  de sus partidos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_CargarSedes
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @salto_linea NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    IF OBJECT_ID(N'tempdb..#staging_sedes') IS NULL
        THROW 50001, N'Torneo.usp_CargarSedes: no se importó nada, falta la tabla #staging_sedes con las sedes.', 1;

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
            CASE WHEN st.nombre_estadio IS NULL       THEN @salto_linea + N'- El nombre del estadio es obligatorio.'
                 WHEN LEN(st.nombre_estadio) > 100    THEN @salto_linea + N'- El nombre del estadio no puede superar los 100 caracteres.'
            END,
            IIF(LEN(st.ciudad) > 80, @salto_linea + N'- La ciudad no puede superar los 80 caracteres.', NULL),
            IIF(s.id_sede IS NULL AND st.nombre_estadio IS NOT NULL
                AND (st.ciudad IS NULL OR st.codigo_fifa IS NULL OR st.capacidad IS NULL OR st.huso_horario IS NULL
                     OR st.tarifa_1 IS NULL OR st.tarifa_2 IS NULL OR st.tarifa_3 IS NULL OR st.tarifa_4 IS NULL),
                @salto_linea + N'- Una sede nueva necesita ciudad, país, capacidad, huso horario y las 4 tarifas.', NULL),
            IIF(st.codigo_fifa IS NOT NULL AND p.id_pais IS NULL,
                @salto_linea + N'- No hay ningún país con el código FIFA ' + st.codigo_fifa + N'.', NULL),
            IIF(st.huso_horario IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM sys.time_zone_info AS z
                                WHERE z.name COLLATE DATABASE_DEFAULT = st.huso_horario),
                @salto_linea + N'- El huso horario ' + st.huso_horario + N' no existe en sys.time_zone_info.', NULL),
            IIF(st.capacidad <= 0, @salto_linea + N'- La capacidad tiene que ser mayor que cero.', NULL),
            IIF(st.capacidad > 0 AND EXISTS (SELECT 1 FROM Torneo.PARTIDO AS pa
                                             WHERE pa.id_sede = s.id_sede AND pa.asistencia > st.capacidad),
                @salto_linea + N'- La capacidad es menor que la asistencia de un partido ya jugado en la sede.', NULL),
            IIF((st.latitud IS NULL AND st.longitud IS NOT NULL) OR (st.latitud IS NOT NULL AND st.longitud IS NULL)
                OR st.latitud NOT BETWEEN -90 AND 90 OR st.longitud NOT BETWEEN -180 AND 180,
                @salto_linea + N'- La latitud y la longitud van juntas, entre -90 y 90 y entre -180 y 180.', NULL),
            IIF(st.tarifa_1 < 0 OR st.tarifa_2 < 0 OR st.tarifa_3 < 0 OR st.tarifa_4 < 0,
                @salto_linea + N'- Las tarifas no pueden ser negativas.', NULL),
            IIF(s.id_sede IS NOT NULL AND COALESCE(st.tarifa_1, st.tarifa_2, st.tarifa_3, st.tarifa_4) IS NOT NULL
                AND (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO AS e WHERE e.id_sede = s.id_sede) <> 4,
                @salto_linea + N'- La sede no tiene sus 4 espacios publicitarios: no se le pueden cambiar las tarifas.', NULL)), N'')
    FROM #staging_sedes AS st
    LEFT JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = st.codigo_fifa
    LEFT JOIN Torneo.SEDE AS s ON s.nombre_estadio = st.nombre_estadio
    WHERE st.accion IS NULL;

    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- Este estadio viene ', r.veces, N' veces.')
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
                        OR st.tarifa_1 <> e1.tarifa_usd OR st.tarifa_2 <> e2.tarifa_usd
                        OR st.tarifa_3 <> e3.tarifa_usd OR st.tarifa_4 <> e4.tarifa_usd
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_sedes AS st
    LEFT JOIN Torneo.SEDE AS s ON s.nombre_estadio = st.nombre_estadio
    LEFT JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = st.codigo_fifa
    LEFT JOIN Publicidad.ESPACIO_PUBLICITARIO AS e1 ON e1.id_sede = s.id_sede AND e1.numero_espacio = 1
    LEFT JOIN Publicidad.ESPACIO_PUBLICITARIO AS e2 ON e2.id_sede = s.id_sede AND e2.numero_espacio = 2
    LEFT JOIN Publicidad.ESPACIO_PUBLICITARIO AS e3 ON e3.id_sede = s.id_sede AND e3.numero_espacio = 3
    LEFT JOIN Publicidad.ESPACIO_PUBLICITARIO AS e4 ON e4.id_sede = s.id_sede AND e4.numero_espacio = 4
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

        -- Las tarifas que vienen para una sede existente (una que no viene queda igual).
        UPDATE e
        SET tarifa_usd = t.tarifa
        FROM Publicidad.ESPACIO_PUBLICITARIO AS e
        INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
        INNER JOIN #staging_sedes AS st ON st.nombre_estadio = s.nombre_estadio
        CROSS APPLY (VALUES (1, st.tarifa_1), (2, st.tarifa_2), (3, st.tarifa_3), (4, st.tarifa_4)) AS t (numero, tarifa)
        WHERE st.accion = 'ACTUALIZADO'
          AND t.numero = e.numero_espacio
          AND t.tarifa IS NOT NULL
          AND t.tarifa <> e.tarifa_usd;

        -- La hora local de los partidos sale de la UTC y el huso de la sede (si el huso no cambió, queda igual).
        UPDATE pa
        SET fecha_hora_local = CONVERT(DATETIME2(0), (pa.fecha_hora_utc AT TIME ZONE 'UTC') AT TIME ZONE s.huso_horario)
        FROM Torneo.PARTIDO AS pa
        INNER JOIN Torneo.SEDE AS s ON s.id_sede = pa.id_sede
        INNER JOIN #staging_sedes AS st ON st.nombre_estadio = s.nombre_estadio
        WHERE st.accion = 'ACTUALIZADO';

        -- ORDER BY: los id_sede se asignan en el orden del archivo o de la lista
        -- (con ORDER BY, SQL Server garantiza ese orden para la columna IDENTITY).
        INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario, latitud, longitud)
        SELECT st.nombre_estadio, st.ciudad, p.id_pais, st.capacidad, st.huso_horario, st.latitud, st.longitud
        FROM #staging_sedes AS st
        INNER JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = st.codigo_fifa
        WHERE st.accion = 'INSERTADO'
        ORDER BY st.id_registro;

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

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @salto_linea  NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido    NVARCHAR(MAX);
    DECLARE @mensaje      NVARCHAR(2048);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso      VARCHAR(100)   = 'Torneo.usp_ImportarSedesJSON';
    DECLARE @leidos       INT;
    DECLARE @insertados   INT;
    DECLARE @actualizados INT;
    DECLARE @sin_cambios  INT;
    DECLARE @rechazados   INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @salto_linea + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.json'
        SET @errores += @salto_linea + N'- El archivo tiene que ser un .json (worldcup.stadiums.json de openfootball).';

    IF @tarifa_espacio_1 IS NULL OR @tarifa_espacio_2 IS NULL OR @tarifa_espacio_3 IS NULL OR @tarifa_espacio_4 IS NULL
       OR @tarifa_espacio_1 < 0 OR @tarifa_espacio_2 < 0 OR @tarifa_espacio_3 < 0 OR @tarifa_espacio_4 < 0
        SET @errores += @salto_linea + N'- Las 4 tarifas son obligatorias y no pueden ser negativas.';

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

    -- El archivo no trae tarifas: las de lista son solo para las sedes nuevas. A una sede que ya
    -- existe no se le tocan (usp_CargarSedes deja igual las tarifas que vienen en NULL), así
    -- reimportar el archivo no pisa las tarifas cargadas después (33_Cargar_DatosComplementarios.sql).
    UPDATE st
    SET tarifa_1 = NULL, tarifa_2 = NULL, tarifa_3 = NULL, tarifa_4 = NULL
    FROM #staging_sedes AS st
    INNER JOIN Torneo.SEDE AS s ON s.nombre_estadio = st.nombre_estadio;

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
                @salto_linea + N'- El país "' + st.pais_txt + N'" no es un código ISO alfa-2 de un país registrado.', NULL),
            IIF(st.huso_txt IS NOT NULL AND st.huso_horario IS NULL,
                @salto_linea + N'- No se reconoce el huso "' + st.huso_txt + N'" para ese país.', NULL),
            IIF(st.capacidad_txt IS NOT NULL AND st.capacidad IS NULL,
                @salto_linea + N'- La capacidad "' + st.capacidad_txt + N'" no es un número entero.', NULL),
            IIF(st.coordenadas IS NOT NULL AND (st.latitud IS NULL OR st.longitud IS NULL),
                @salto_linea + N'- Las coordenadas "' + st.coordenadas + N'" no son una latitud y una longitud.', NULL)), N'')
    FROM #staging_sedes AS st;

    UPDATE #staging_sedes SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. El SP de carga valida las demás y carga las válidas, todas juntas; después se
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
  usp_CargarSelecciones
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
CREATE OR ALTER PROCEDURE Torneo.usp_CargarSelecciones
    @fecha_presentacion  DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores     NVARCHAR(2048);
    DECLARE @salto_linea NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT      = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @cupo_grupo  TINYINT  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
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
        THROW 50001, N'Torneo.usp_CargarSelecciones: no se importó nada, falta la tabla #staging_selecciones con las selecciones.', 1;

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
            CASE WHEN st.codigo_fifa IS NULL THEN @salto_linea + N'- El código FIFA es obligatorio.'
                 WHEN r.id_pais IS NULL      THEN @salto_linea + N'- No hay un país con código FIFA "' + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.confederacion IS NULL AND r.id_seleccion IS NULL
                     THEN @salto_linea + N'- La confederación es obligatoria.'
                 WHEN st.confederacion NOT IN ('AFC', 'CAF', 'CONCACAF', 'CONMEBOL', 'OFC', 'UEFA')
                     THEN @salto_linea + N'- La confederación "' + st.confederacion + N'" no es AFC, CAF, CONCACAF, CONMEBOL, OFC ni UEFA.'
            END,
            IIF(st.grupo COLLATE Latin1_General_BIN NOT LIKE '[A-L]',
                @salto_linea + N'- El grupo "' + st.grupo + N'" no es una letra de la A a la L.', NULL),
            IIF(st.grupo <> ISNULL(r.grupo_actual, '')
                AND EXISTS (SELECT 1 FROM Torneo.PARTIDO AS p
                            WHERE p.fase = 'GRUPOS' AND r.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)),
                @salto_linea + N'- La selección ya tiene partidos de la fase de grupos: no se le puede cambiar el grupo.', NULL),
            IIF(LEN(st.nombre_alternativo) > 120, @salto_linea + N'- El nombre no puede superar los 120 caracteres.', NULL),
            IIF(EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO AS na
                        WHERE na.id_jugador IS NULL AND na.nombre = st.nombre_alternativo
                          AND na.id_seleccion <> ISNULL(r.id_seleccion, 0)),
                @salto_linea + N'- El nombre "' + st.nombre_alternativo + N'" ya es de otra selección.', NULL)), N'')
    FROM #staging_selecciones AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro;

    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- Esta selección viene ', r.veces, N' veces.')
    FROM #staging_selecciones AS st
    INNER JOIN (SELECT codigo_fifa, COUNT(*) AS veces FROM #staging_selecciones
                WHERE codigo_fifa IS NOT NULL GROUP BY codigo_fifa HAVING COUNT(*) > 1) AS r
            ON r.codigo_fifa = st.codigo_fifa
    WHERE st.accion IS NULL;

    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- El nombre "', st.nombre_alternativo, N'" viene para más de una selección.')
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
    SET errores = CONCAT(@salto_linea, N'- El grupo ', e.grupo, N' quedaría con ', e.selecciones, N' selecciones y el máximo es ',
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
        SET @errores = N'Torneo.usp_CargarSelecciones: no se importó ninguna selección.' + @salto_linea
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

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @salto_linea  NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido    NVARCHAR(MAX);
    DECLARE @mensaje      NVARCHAR(2048);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso      VARCHAR(100)   = 'Torneo.usp_ImportarSeleccionesJSON';
    DECLARE @leidos       INT;
    DECLARE @insertados   INT;
    DECLARE @actualizados INT;
    DECLARE @sin_cambios  INT;
    DECLARE @rechazados   INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @salto_linea + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.json'
        SET @errores += @salto_linea + N'- El archivo tiene que ser un .json (worldcup.teams.json de openfootball).';

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

    /* 3. El SP de carga valida y carga las válidas, todas juntas; después se registran la
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
  usp_CargarPartidos
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
CREATE OR ALTER PROCEDURE Torneo.usp_CargarPartidos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @salto_linea NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

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
        THROW 50001, N'Torneo.usp_CargarPartidos: no se importó nada, falta la tabla #staging_partidos con los partidos.', 1;

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
    LEFT JOIN DatosGenerales.PAIS AS pl ON pl.codigo_fifa = st.codigo_fifa_local
    LEFT JOIN Torneo.SELECCION AS sl ON sl.id_pais = pl.id_pais
    LEFT JOIN DatosGenerales.PAIS AS pv ON pv.codigo_fifa = st.codigo_fifa_visitante
    LEFT JOIN Torneo.SELECCION AS sv ON sv.id_pais = pv.id_pais
    WHERE st.accion IS NULL;

    UPDATE pt
    SET capacidad        = s.capacidad,
        fecha_hora_local = CONVERT(DATETIME2(0), (pt.fecha_hora_utc AT TIME ZONE 'UTC') AT TIME ZONE s.huso_horario)
    FROM @partidos AS pt
    INNER JOIN Torneo.SEDE AS s ON s.id_sede = pt.id_sede;

    /* 1. Cada regla anota su motivo en los partidos que no la cumplen. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.numero_partido IS NULL THEN @salto_linea + N'- El número de partido es obligatorio.'
                 WHEN st.numero_partido = 0     THEN @salto_linea + N'- El número de partido tiene que ser mayor que cero.'
            END,
            IIF(pt.id_partido IS NULL AND (st.nombre_estadio IS NULL OR st.fase IS NULL OR st.fecha_hora_utc IS NULL),
                @salto_linea + N'- Un partido nuevo necesita estadio, fase y fecha.', NULL),
            IIF(pt.sede_inexistente = 1, @salto_linea + N'- El estadio "' + st.nombre_estadio + N'" no es una sede registrada.', NULL),
            IIF(st.fase NOT IN ('GRUPOS', 'DIECISEISAVOS', 'OCTAVOS', 'CUARTOS', 'SEMIFINAL', 'TERCER_PUESTO', 'FINAL'),
                @salto_linea + N'- La fase "' + st.fase + N'" no es válida.', NULL),
            IIF(pt.local_inexistente = 1,
                @salto_linea + N'- No hay una selección registrada con código FIFA "' + st.codigo_fifa_local + N'".', NULL),
            IIF(pt.visitante_inexistente = 1,
                @salto_linea + N'- No hay una selección registrada con código FIFA "' + st.codigo_fifa_visitante + N'".', NULL),
            IIF(pt.id_local = pt.id_visitante, @salto_linea + N'- La selección local y la visitante son la misma.', NULL),
            IIF(pt.fase = 'GRUPOS' AND (pt.id_local IS NULL OR pt.id_visitante IS NULL
                                        OR ISNULL(sl.grupo, '') <> ISNULL(sv.grupo, '-')),
                @salto_linea + N'- En la fase de grupos tienen que estar las dos selecciones y ser del mismo grupo.', NULL),
            IIF((st.goles_local IS NULL AND st.goles_visitante IS NOT NULL) OR (st.goles_local IS NOT NULL AND st.goles_visitante IS NULL),
                @salto_linea + N'- El resultado tiene que traer los goles de las dos selecciones.', NULL),
            IIF(st.goles_local IS NOT NULL AND (pt.id_local IS NULL OR pt.id_visitante IS NULL),
                @salto_linea + N'- Un partido con resultado tiene que tener las dos selecciones.', NULL),
            IIF((st.penales_local IS NULL AND st.penales_visitante IS NOT NULL) OR (st.penales_local IS NOT NULL AND st.penales_visitante IS NULL),
                @salto_linea + N'- Los penales tienen que ser de las dos selecciones.', NULL),
            IIF(st.penales_local IS NOT NULL
                AND (pt.fase = 'GRUPOS' OR st.goles_local IS NULL OR st.goles_local <> st.goles_visitante
                     OR st.penales_local = st.penales_visitante),
                @salto_linea + N'- Hay penales solo en eliminación directa, con empate en goles, y no pueden terminar empatados.', NULL),
            IIF(pt.fase <> 'GRUPOS' AND st.goles_local = st.goles_visitante AND st.penales_local IS NULL,
                @salto_linea + N'- Un empate de eliminación directa se define por penales, y no vienen.', NULL),
            IIF(pt.cambia_jugado = 1,
                @salto_linea + N'- El partido ' + CAST(st.numero_partido AS NVARCHAR(3)) + N' ya empezó o se jugó con otras selecciones, '
                    + N'sede, fase o fecha: no se puede cambiar.', NULL),
            IIF(st.asistencia < 0 OR st.asistencia > pt.capacidad,
                CONCAT(@salto_linea, N'- La asistencia ', st.asistencia, N' no está entre 0 y la capacidad de la sede',
                       IIF(pt.capacidad IS NULL, N'', CONCAT(N' (', pt.capacidad, N')')), N'.'), NULL),
            IIF(EXISTS (SELECT 1 FROM DesarrolloPartido.fn_MarcadorSegunGoles(pt.id_partido) AS m
                        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = pt.id_partido
                        WHERE st.goles_local IS NOT NULL AND m.goles_registrados > m.penales_registrados
                          AND (st.goles_local <> ISNULL(p.goles_local, 255) OR st.goles_visitante <> ISNULL(p.goles_visitante, 255))
                          AND (st.goles_local <> m.goles_local OR st.goles_visitante <> m.goles_visitante)),
                @salto_linea + N'- El resultado cambia y no coincide con los goles ya cargados del partido.', NULL)), N'')
    FROM #staging_partidos AS st
    INNER JOIN @partidos AS pt ON pt.id_registro = st.id_registro
    LEFT JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = pt.id_local
    LEFT JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = pt.id_visitante;

    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- El partido ', st.numero_partido, N' viene ', r.veces, N' veces.')
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
    SET errores = (SELECT STRING_AGG(CONCAT(@salto_linea, N'- Con el partido ', c.otro, N': ', c.motivo, N'.'), N'')
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
  usp_CargarDesarrolloPartidos
  Upsert de lo que pasó en partidos ya cargados (por número de partido), desde
  #staging_eventos, con un evento por fila según su tipo:
    FORMACION  un jugador de la formación de su selección (es_titular y, si
               es titular, posicion_en_cancha)
    CAMBIO     sale id_jugador y entra id_jugador_entra (minuto,
               minuto_adicional, en_entretiempo, motivo)
    GOL        lo convierte id_jugador (tipo_gol, periodo, minuto,
               minuto_adicional) y lo asiste id_jugador_asistencia
    PENAL      un penal convertido en la definición: un gol del período
               PENALES, sin minuto
    TARJETA    la recibe id_jugador (tipo_tarjeta, es_doble_amarilla,
               minuto, minuto_adicional, motivo)
  Columnas que usa: id_evento (distinto en cada fila), tipo, numero_partido,
  id_jugador, id_jugador_entra, id_jugador_asistencia, es_titular,
  posicion_en_cancha, minuto, minuto_adicional, en_entretiempo, motivo,
  periodo, tipo_gol, tipo_tarjeta, es_doble_amarilla, errores y accion.
  Es una carga histórica: no repite las reglas de los SP que registran el
  partido en vivo (equipo en cancha en ese minuto, ventanas de cambio,
  suspensiones), sino las de las tablas.
  Cada evento se busca entre los ya cargados del partido por los datos que lo
  identifican (su clave). Si está, se actualiza el resto; si no, es nuevo:
    FORMACION  lo identifica el jugador; se actualiza si es titular y su
               posición
    CAMBIO     los dos jugadores; se actualizan el minuto, el adicional, si
               fue en el entretiempo y el motivo
    GOL/PENAL  el autor, si es en contra, el período, el minuto y el
               adicional; se actualizan el tipo y la asistencia
    TARJETA    el jugador, el tipo, si es por doble amarilla, el minuto y el
               adicional; se actualiza el motivo
  Un jugador sale una sola vez por partido, así que los dos jugadores alcanzan
  para identificar un cambio. Goles puede hacer varios, y lo que distingue a
  uno de otro es el minuto: un gol o una tarjeta que viene con otro minuto es
  otro evento, y el cargado se corrige con usp_GOL_Modificacion o
  usp_AMONESTACION_Modificacion. Lo cargado que no viene no se borra.
  - La formación de cada selección se arma con sus jugadores del conjunto. El
    esquema táctico de una formación nueva sale de las posiciones habituales
    de los titulares (defensores, mediocampistas y delanteros, ej. 4-3-3); el
    de una ya cargada no se cambia.
  - El motivo de un cambio o una tarjeta puede no venir (NULL): uno nuevo se
    registra como TACTICO o "Sin detalle en la fuente", y uno cargado
    conserva el suyo.
  - La asistencia de un gol también puede no venir (NULL): uno nuevo queda
    sin asistencia y uno cargado conserva la suya, salvo que pase a ser en
    contra, que no tiene asistencia.
  Valida cada evento pendiente: tipo válido; partido existente; jugadores
  existentes y de una de las dos selecciones del partido; en la formación,
  si es titular y la posición de los titulares; en los cambios, jugadores
  distintos de la misma selección, minuto entre 1 y 120 con hasta 30 de
  adicional, los del entretiempo en el 46, 91 o 106 y motivo TACTICO,
  LESION o PRECAUCION; tipos de gol existentes y minuto de acuerdo con el
  período; la asistencia, solo en un gol que no sea en contra ni de la
  definición, de un jugador de la selección del autor y distinto de él
  (las reglas de usp_GOL_Alta); tarjetas AMARILLA o ROJA (la doble
  amarilla, solo roja), minuto entre 0 y 120 con hasta 30 de adicional y
  motivo de hasta 200 caracteres. Y con los válidos, cada partido como
  quedaría: un jugador una sola vez en la formación; cada formación con 11
  titulares (los del conjunto más los cargados que no vienen), o se
  rechazan todos los jugadores de esa formación; los jugadores de cambios,
  goles (autor y asistencia) y tarjetas, en la formación del partido (la
  cargada o la válida del conjunto); cada
  jugador sale y entra una sola vez por partido; ningún jugador con más de
  una roja ni con más de dos amarillas (dos, solo con la roja por doble
  amarilla): si pasa, se rechazan sus tarjetas nuevas; y ninguna selección
  con más goles que su resultado, ni con más penales convertidos que los de
  su definición: si pasa, se rechazan sus goles nuevos (un gol que el archivo
  trae con otro minuto o le atribuye a otro jugador es otro gol, y el cargado
  no se borra).
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_CargarDesarrolloPartidos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @salto_linea NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- Lo que ya está registrado de cada evento pendiente.
    DECLARE @eventos TABLE (
        id_evento           INT PRIMARY KEY,
        id_partido          INT,
        id_seleccion        INT,       -- del jugador que forma, sale, convierte o recibe la tarjeta
        de_un_equipo        BIT,       -- ese jugador es de una de las dos selecciones del partido
        id_seleccion_entra  INT,
        entra_de_un_equipo  BIT,
        id_seleccion_asist  INT,       -- del que asiste el gol (NULL: no existe o no tiene lista)
        posicion_habitual   VARCHAR(15),
        id_tipo_gol         TINYINT,
        es_en_contra        BIT,
        formacion_existe    BIT,
        ya_alineado         BIT,
        id_cargado          INT        -- el cambio, gol o tarjeta ya cargado que es este mismo evento
    );

    IF OBJECT_ID(N'tempdb..#staging_eventos') IS NULL
        THROW 50001, N'DesarrolloPartido.usp_CargarDesarrolloPartidos: no se importó nada, falta la tabla #staging_eventos con los eventos.', 1;

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
                          id_seleccion_asist, posicion_habitual, id_tipo_gol, es_en_contra)
    SELECT e.id_evento, p.id_partido,
           lc.id_seleccion, IIF(lc.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante), 1, 0),
           lce.id_seleccion, IIF(lce.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante), 1, 0),
           lca.id_seleccion, j.posicion_habitual, tg.id_tipo_gol, tg.es_en_contra
    FROM #staging_eventos AS e
    LEFT JOIN Torneo.PARTIDO AS p ON p.numero_partido = e.numero_partido
    LEFT JOIN Torneo.JUGADOR AS j ON j.id_jugador = e.id_jugador
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
    LEFT JOIN Torneo.JUGADOR AS je ON je.id_jugador = e.id_jugador_entra
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS lce ON lce.id_lista = je.id_lista
    LEFT JOIN Torneo.JUGADOR AS ja ON ja.id_jugador = e.id_jugador_asistencia
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS lca ON lca.id_lista = ja.id_lista
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
                @salto_linea + N'- El tipo "' + ISNULL(e.tipo, N'') + N'" no es FORMACION, CAMBIO, GOL, PENAL ni TARJETA.', NULL),
            CASE WHEN e.numero_partido IS NULL THEN @salto_linea + N'- El número de partido es obligatorio.'
                 WHEN ev.id_partido IS NULL     THEN @salto_linea + N'- No hay un partido con el número '
                                                         + CAST(e.numero_partido AS NVARCHAR(3)) + N'.'
            END,
            CASE WHEN e.id_jugador IS NULL THEN @salto_linea + N'- El jugador es obligatorio.'
                 WHEN ev.id_partido IS NOT NULL AND ev.de_un_equipo = 0
                     THEN @salto_linea + N'- El jugador no existe o no es de ninguna de las dos selecciones del partido.'
            END,
            -- Formaciones
            IIF(e.tipo = 'FORMACION' AND e.es_titular IS NULL, @salto_linea + N'- Falta si el jugador es titular o suplente.', NULL),
            IIF(e.tipo = 'FORMACION' AND e.es_titular = 1 AND e.posicion_en_cancha IS NULL,
                @salto_linea + N'- Un titular necesita su posición en la cancha.', NULL),
            -- Cambios
            CASE WHEN ISNULL(e.tipo, '') <> 'CAMBIO' THEN NULL
                 WHEN e.id_jugador_entra IS NULL THEN @salto_linea + N'- Falta el jugador que entra.'
                 WHEN ev.id_partido IS NOT NULL AND ev.entra_de_un_equipo = 0
                     THEN @salto_linea + N'- El jugador que entra no existe o no es de ninguna de las dos selecciones del partido.'
                 WHEN e.id_jugador = e.id_jugador_entra THEN @salto_linea + N'- Sale y entra el mismo jugador.'
                 WHEN ev.id_seleccion <> ev.id_seleccion_entra THEN @salto_linea + N'- El que sale y el que entra son de selecciones distintas.'
            END,
            IIF(e.tipo = 'CAMBIO' AND (e.minuto IS NULL OR e.minuto NOT BETWEEN 1 AND 120 OR ISNULL(e.minuto_adicional, 0) > 30),
                @salto_linea + N'- El minuto de un cambio va del 1 al 120, con hasta 30 de adicional.', NULL),
            IIF(e.tipo = 'CAMBIO' AND e.en_entretiempo = 1 AND (e.minuto NOT IN (46, 91, 106) OR ISNULL(e.minuto_adicional, 0) <> 0),
                @salto_linea + N'- Un cambio en el entretiempo va en el minuto 46, 91 o 106.', NULL),
            IIF(e.tipo = 'CAMBIO' AND e.motivo NOT IN ('TACTICO', 'LESION', 'PRECAUCION'),
                @salto_linea + N'- El motivo de un cambio es TACTICO, LESION o PRECAUCION.', NULL),
            -- Goles y penales
            IIF(e.tipo IN ('GOL', 'PENAL') AND ev.id_tipo_gol IS NULL,
                @salto_linea + N'- El tipo de gol "' + ISNULL(e.tipo_gol, N'') + N'" no existe.', NULL),
            IIF(e.tipo = 'PENAL' AND ISNULL(e.periodo, '') <> 'PENALES',
                @salto_linea + N'- Un penal de la definición va en el período PENALES.', NULL),
            IIF(e.tipo IN ('GOL', 'PENAL')
                AND NOT ((e.periodo = 'PENALES'        AND e.minuto IS NULL              AND ISNULL(e.minuto_adicional, 0) = 0)
                      OR (e.periodo = 'PRIMER_TIEMPO'  AND e.minuto BETWEEN 1  AND 45    AND ISNULL(e.minuto_adicional, 0) = 0)
                      OR (e.periodo = 'SEGUNDO_TIEMPO' AND e.minuto BETWEEN 46 AND 90    AND ISNULL(e.minuto_adicional, 0) = 0)
                      OR (e.periodo = 'ALARGUE'        AND e.minuto BETWEEN 91 AND 120   AND ISNULL(e.minuto_adicional, 0) = 0)
                      OR (e.periodo = 'ADICIONALES'    AND e.minuto IN (45, 90, 105, 120) AND e.minuto_adicional BETWEEN 1 AND 30)),
                @salto_linea + N'- El minuto no corresponde al período (PRIMER_TIEMPO del 1 al 45, SEGUNDO_TIEMPO del 46 al 90, '
                    + N'ALARGUE del 91 al 120, ADICIONALES después del 45, 90, 105 o 120, y PENALES sin minuto).', NULL),
            -- Asistencias (las reglas de usp_GOL_Alta; que el que asiste esté en la formación se valida en el paso 2)
            CASE WHEN e.id_jugador_asistencia IS NULL THEN NULL
                 WHEN ISNULL(e.tipo, '') <> 'GOL' OR e.periodo = 'PENALES' OR ev.es_en_contra = 1
                     THEN @salto_linea + N'- Solo un gol que no es en contra ni de la definición por penales tiene asistencia.'
                 WHEN e.id_jugador_asistencia = e.id_jugador THEN @salto_linea + N'- El autor no puede ser también el que asiste.'
                 WHEN ev.id_seleccion_asist IS NULL OR ev.id_seleccion_asist <> ev.id_seleccion
                     THEN @salto_linea + N'- El que asiste no existe o no es de la selección del autor.'
            END,
            -- Tarjetas
            CASE WHEN ISNULL(e.tipo, '') <> 'TARJETA' THEN NULL
                 WHEN e.tipo_tarjeta IS NULL OR e.tipo_tarjeta NOT IN ('AMARILLA', 'ROJA')
                     THEN @salto_linea + N'- La tarjeta tiene que ser AMARILLA o ROJA.'
                 WHEN e.es_doble_amarilla = 1 AND e.tipo_tarjeta <> 'ROJA'
                     THEN @salto_linea + N'- La doble amarilla se registra como ROJA.'
            END,
            IIF(e.tipo = 'TARJETA' AND (e.minuto IS NULL OR e.minuto > 120 OR ISNULL(e.minuto_adicional, 0) > 30),
                @salto_linea + N'- El minuto de una tarjeta va del 0 al 120, con hasta 30 de adicional.', NULL),
            IIF(e.tipo = 'TARJETA' AND LEN(e.motivo) > 200,
                @salto_linea + N'- El motivo de la tarjeta no puede superar los 200 caracteres.', NULL)), N'')
    FROM #staging_eventos AS e
    INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento;

    /* 2. Las reglas entre eventos. Un jugador figura una sola vez en la formación. */
    UPDATE e
    SET errores = CONCAT(e.errores, @salto_linea, N'- El jugador figura más de una vez en la formación.')
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
    SET errores = CONCAT(e.errores, @salto_linea, N'- La formación de la selección quedaría con ', f.titulares,
                         N' titulares y tienen que ser 11: no se carga ningún jugador de esa formación.')
    FROM #staging_eventos AS e
    INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
    INNER JOIN formaciones AS f ON f.id_partido = ev.id_partido AND f.id_seleccion = ev.id_seleccion
    WHERE e.tipo = 'FORMACION' AND f.titulares <> 11;

    -- Cambios, goles, penales y tarjetas: los jugadores (también el que asiste) tienen que estar en la formación
    -- del partido.
    UPDATE e
    SET errores = CONCAT(e.errores, @salto_linea, N'- El jugador no está en la formación del partido (o su formación se rechazó).')
    FROM #staging_eventos AS e
    INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
    WHERE e.tipo <> 'FORMACION' AND ev.id_partido IS NOT NULL
      AND EXISTS (SELECT 1 FROM (VALUES (e.id_jugador), (e.id_jugador_entra), (e.id_jugador_asistencia)) AS j (id_jugador)
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
    SET errores = CONCAT(e.errores, @salto_linea, N'- Un jugador de este cambio sale o entra más de una vez en el partido (un cambio '
                         + N'cargado no cambia de jugadores: si el archivo lo corrige, el cargado se da de baja con usp_CAMBIO_Baja).')
    FROM #staging_eventos AS e
    WHERE e.tipo = 'CAMBIO' AND e.accion IS NULL AND e.errores IS NULL
      AND EXISTS (SELECT 1 FROM repetidos AS r
                  WHERE r.numero_partido = e.numero_partido
                    AND ((r.tipo = 'S' AND r.id_jugador = e.id_jugador) OR (r.tipo = 'E' AND r.id_jugador = e.id_jugador_entra)));

    /* 3. Cada evento válido con el ya cargado que es el mismo: un cambio, el de sus dos jugadores; un gol, el
          de su autor, en contra o no, en ese período y minuto; una tarjeta, la de su jugador, de su tipo, por
          doble amarilla o no, en ese minuto. El jugador de una formación ya alineado es el mismo
          (ya_alineado). */
    UPDATE ev
    SET id_cargado = ca.id_cambio
    FROM @eventos AS ev
    INNER JOIN #staging_eventos AS e ON e.id_evento = ev.id_evento
    INNER JOIN DesarrolloPartido.CAMBIO AS ca ON ca.id_partido = ev.id_partido
                                             AND ca.id_jugador_sale = e.id_jugador
                                             AND ca.id_jugador_entra = e.id_jugador_entra
    WHERE e.tipo = 'CAMBIO' AND e.accion IS NULL AND e.errores IS NULL;

    -- Goles. copia numera los que tienen la misma clave (dos penales del mismo jugador en una definición
    -- larga, que no tienen minuto), para emparejarlos de a uno.
    WITH conjunto AS (
        SELECT ev.id_evento, ev.id_partido, e.id_jugador, ev.es_en_contra, e.periodo, ISNULL(e.minuto, 255) AS minuto,
               ISNULL(e.minuto_adicional, 0) AS minuto_adicional,
               ROW_NUMBER() OVER (PARTITION BY ev.id_partido, e.id_jugador, ev.es_en_contra, e.periodo, e.minuto,
                                               ISNULL(e.minuto_adicional, 0)
                                  ORDER BY e.id_evento) AS copia
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo IN ('GOL', 'PENAL') AND e.accion IS NULL AND e.errores IS NULL
    ),
    cargados AS (
        SELECT g.id_gol, g.id_partido, g.id_jugador_autor, tg.es_en_contra, g.periodo, ISNULL(g.minuto, 255) AS minuto,
               g.minuto_adicional,
               ROW_NUMBER() OVER (PARTITION BY g.id_partido, g.id_jugador_autor, tg.es_en_contra, g.periodo, g.minuto,
                                               g.minuto_adicional
                                  ORDER BY g.id_gol) AS copia
        FROM DesarrolloPartido.GOL AS g
        INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
        WHERE g.id_partido IN (SELECT id_partido FROM conjunto)
    )
    UPDATE ev
    SET id_cargado = ca.id_gol
    FROM @eventos AS ev
    INNER JOIN conjunto AS c ON c.id_evento = ev.id_evento
    INNER JOIN cargados AS ca ON ca.id_partido = c.id_partido AND ca.id_jugador_autor = c.id_jugador
                             AND ca.es_en_contra = c.es_en_contra AND ca.periodo = c.periodo
                             AND ca.minuto = c.minuto AND ca.minuto_adicional = c.minuto_adicional AND ca.copia = c.copia;

    -- Tarjetas, con copia como en los goles.
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

    /* 4. Cada partido como quedaría, con los eventos válidos del conjunto y los cargados que no vienen.
          Las tarjetas de cada jugador: como máximo una roja y dos amarillas, y dos solo si tiene la roja por
          doble amarilla (lo que exige usp_AMONESTACION_Alta). Si pasa, se rechazan sus tarjetas nuevas: sin
          esta regla, una amarilla que viene con otro minuto quedaría como segunda amarilla. */
    WITH tarjetas AS (
        SELECT ev.id_partido, e.id_jugador, e.tipo_tarjeta, ISNULL(e.es_doble_amarilla, 0) AS es_doble_amarilla
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo = 'TARJETA' AND e.accion IS NULL AND e.errores IS NULL
        UNION ALL
        SELECT am.id_partido, am.id_jugador, am.tipo_tarjeta, am.es_doble_amarilla
        FROM DesarrolloPartido.AMONESTACION AS am
        WHERE am.id_jugador IS NOT NULL
          AND am.id_partido IN (SELECT ev.id_partido FROM @eventos AS ev
                                INNER JOIN #staging_eventos AS e ON e.id_evento = ev.id_evento
                                WHERE e.tipo = 'TARJETA')
          AND NOT EXISTS (SELECT 1 FROM @eventos AS x
                          INNER JOIN #staging_eventos AS xe ON xe.id_evento = x.id_evento
                          WHERE xe.tipo = 'TARJETA' AND x.id_cargado = am.id_amonestacion)
    ),
    cuentas AS (
        SELECT id_partido, id_jugador,
               SUM(IIF(tipo_tarjeta = 'AMARILLA', 1, 0)) AS amarillas,
               SUM(IIF(tipo_tarjeta = 'ROJA', 1, 0)) AS rojas,
               SUM(IIF(tipo_tarjeta = 'ROJA' AND es_doble_amarilla = 1, 1, 0)) AS rojas_por_doble_amarilla
        FROM tarjetas
        GROUP BY id_partido, id_jugador
    )
    UPDATE e
    SET errores = CONCAT(e.errores, @salto_linea, N'- El jugador quedaría con ', c.amarillas, N' amarillas y ', c.rojas,
                         N' rojas en el partido: puede tener una roja y hasta dos amarillas (dos, solo con la roja por '
                         + N'doble amarilla). Una tarjeta cargada con otro minuto se corrige con usp_AMONESTACION_Modificacion.')
    FROM #staging_eventos AS e
    INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
    INNER JOIN cuentas AS c ON c.id_partido = ev.id_partido AND c.id_jugador = e.id_jugador
    WHERE e.tipo = 'TARJETA' AND e.accion IS NULL AND e.errores IS NULL AND ev.id_cargado IS NULL
      AND (c.rojas > 1 OR c.amarillas > 2 OR (c.amarillas = 2 AND c.rojas_por_doble_amarilla = 0));

    /* Los goles: ninguna selección con más goles que su resultado ni con más penales convertidos que los de
       su definición. Si pasa, se rechazan sus goles nuevos: un gol que el archivo trae con otro minuto o le
       atribuye a otro jugador es otro gol, y el cargado no se borra. */
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
    SET errores = CONCAT(e.errores, @salto_linea, N'- La selección quedaría con ', c.goles,
                         IIF(c.es_definicion = 1, N' penales convertidos en la definición', N' goles'),
                         N' y su resultado es ', r.resultado, N': no se carga ningún gol nuevo suyo. Un gol que el archivo '
                         + N'trae con otro minuto o le atribuye a otro jugador es otro gol: el cargado se corrige con '
                         + N'usp_GOL_Modificacion o se da de baja con usp_GOL_Baja.')
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
                                         AND (g.id_tipo_gol <> ev.id_tipo_gol
                                              OR g.id_jugador_asistencia IS DISTINCT FROM
                                                 IIF(ev.es_en_contra = 1, NULL,
                                                     ISNULL(e.id_jugador_asistencia, g.id_jugador_asistencia))))
                          THEN 'ACTUALIZADO'
                      WHEN e.tipo = 'TARJETA'
                           AND EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION AS am
                                       WHERE am.id_amonestacion = ev.id_cargado
                                         AND am.motivo <> ISNULL(e.motivo, am.motivo))
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

        -- Goles: los cargados con otro tipo o asistencia (una que no viene queda como está, salvo en un gol en
        -- contra, que no tiene), y los nuevos.
        UPDATE g
        SET id_tipo_gol           = ev.id_tipo_gol,
            id_jugador_asistencia = IIF(ev.es_en_contra = 1, NULL, ISNULL(e.id_jugador_asistencia, g.id_jugador_asistencia))
        FROM DesarrolloPartido.GOL AS g
        INNER JOIN @eventos AS ev ON ev.id_cargado = g.id_gol
        INNER JOIN #staging_eventos AS e ON e.id_evento = ev.id_evento
        WHERE e.tipo IN ('GOL', 'PENAL') AND e.accion = 'ACTUALIZADO';

        INSERT INTO DesarrolloPartido.GOL
            (id_partido, id_jugador_autor, id_jugador_asistencia, id_tipo_gol, periodo, minuto, minuto_adicional)
        SELECT ev.id_partido, e.id_jugador, e.id_jugador_asistencia, ev.id_tipo_gol, e.periodo, e.minuto,
               ISNULL(e.minuto_adicional, 0)
        FROM #staging_eventos AS e
        INNER JOIN @eventos AS ev ON ev.id_evento = e.id_evento
        WHERE e.tipo IN ('GOL', 'PENAL') AND e.accion = 'INSERTADO';

        -- Tarjetas: las cargadas con otro motivo (uno que no viene queda como está) y las nuevas (sin motivo,
        -- "Sin detalle en la fuente").
        UPDATE am
        SET motivo = ISNULL(e.motivo, am.motivo)
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
  50002). Rechaza los registros que no puede convertir (ronda, fecha,
  selecciones y estadio que no reconoce, números que no son números,
  jugadores que no reconoce, minutos y tarjetas); las reglas las aplican
  los SP de carga. Registra la importación (su número queda en
  @id_importacion) y los rechazados en Torneo.ERRORES_PARTIDO y
  DesarrolloPartido.ERRORES_EVENTO. Devuelve el resumen de partidos y de
  eventos, los rechazados con sus motivos, y los partidos cuyo resultado no
  coincide con los goles cargados (porque se rechazó alguno).
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarPartidosJSON
    @ruta_archivo            NVARCHAR(400),
    @primer_numero           TINYINT = 1,
    @reprocesar_importacion  INT     = NULL,
    @id_importacion          INT     = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores         NVARCHAR(2048) = N'';
    DECLARE @salto_linea     NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido       NVARCHAR(MAX);
    DECLARE @mensaje         NVARCHAR(2048);
    DECLARE @partidos_grupos INT;
    DECLARE @tran_propia     BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso         VARCHAR(100)   = 'Torneo.usp_ImportarPartidosJSON';
    DECLARE @leidos          INT;
    DECLARE @insertados      INT;
    DECLARE @actualizados    INT;
    DECLARE @sin_cambios     INT;
    DECLARE @rechazados      INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @salto_linea + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.json'
        SET @errores += @salto_linea + N'- El archivo tiene que ser un .json (worldcup-full.json de openfootball).';

    IF ISNULL(@primer_numero, 0) = 0
        SET @errores += @salto_linea + N'- El primer número de partido tiene que estar entre 1 y 255.';

    IF @reprocesar_importacion IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM DatosGenerales.IMPORTACION
                       WHERE id_importacion = @reprocesar_importacion AND proceso = @proceso AND origen = @ruta_archivo)
        SET @errores += @salto_linea + CONCAT(N'- No hay una importación ', @reprocesar_importacion,
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

    -- Selecciones: por el nombre del país o un nombre alternativo registrado (sin distinguir tildes). Un
    -- nombre que corresponde a más de una selección no identifica a ninguna.
    WITH nombres AS (
        SELECT p.nombre COLLATE Latin1_General_CI_AI AS nombre, p.codigo_fifa
        FROM Torneo.SELECCION AS s
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        UNION ALL
        SELECT na.nombre COLLATE Latin1_General_CI_AI, p.codigo_fifa
        FROM Torneo.NOMBRE_ALTERNATIVO AS na
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = na.id_seleccion
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE na.id_jugador IS NULL
    ),
    nombres_seleccion AS (
        SELECT nombre, MIN(codigo_fifa) AS codigo_fifa
        FROM nombres
        GROUP BY nombre
        HAVING COUNT(DISTINCT codigo_fifa) = 1
    )
    UPDATE st
    SET codigo_fifa_local     = n1.codigo_fifa,
        codigo_fifa_visitante = n2.codigo_fifa
    FROM #staging_partidos AS st
    LEFT JOIN nombres_seleccion AS n1 ON n1.nombre = st.equipo_1 COLLATE Latin1_General_CI_AI
    LEFT JOIN nombres_seleccion AS n2 ON n2.nombre = st.equipo_2 COLLATE Latin1_General_CI_AI;

    -- Sede: la que tiene su ciudad (lo que está antes del paréntesis) o su nombre en el texto del archivo.
    WITH posibles AS (
        SELECT st.id_registro, MAX(s.nombre_estadio) AS nombre_estadio, COUNT(s.id_sede) AS sedes
        FROM #staging_partidos AS st
        LEFT JOIN Torneo.SEDE AS s
               ON CHARINDEX(LEFT(s.ciudad, CHARINDEX(' (', s.ciudad + ' (') - 1), st.estadio_txt) > 0
               OR CHARINDEX(s.nombre_estadio, st.estadio_txt) > 0
        GROUP BY st.id_registro
    )
    UPDATE st
    SET sedes_posibles = x.sedes,
        nombre_estadio = IIF(x.sedes = 1, x.nombre_estadio, NULL)
    FROM #staging_partidos AS st
    INNER JOIN posibles AS x ON x.id_registro = st.id_registro;

    /* 3. Lo que no se pudo convertir. Las reglas de los partidos las aplica usp_CargarPartidos. */
    UPDATE st
    SET errores = NULLIF(CONCAT(
            IIF(st.fase IS NULL, @salto_linea + N'- La ronda "' + ISNULL(st.ronda, N'') + N'" no es una fase reconocida.', NULL),
            IIF(st.fecha_hora_utc IS NULL,
                @salto_linea + N'- La fecha y hora "' + ISNULL(st.fecha_txt, N'') + N' ' + ISNULL(st.hora_txt, N'')
                    + N'" no son AAAA-MM-DD y HH:MM UTC±H: el partido no se puede numerar.', NULL),
            IIF(st.fecha_hora_utc IS NOT NULL AND st.fase IS NOT NULL AND st.numero_partido IS NULL,
                @salto_linea + N'- El número de partido pasaría de 255.', NULL),
            IIF(st.equipo_1 IS NOT NULL AND st.codigo_fifa_local IS NULL,
                @salto_linea + N'- No hay una selección registrada con el nombre "' + st.equipo_1 + N'" (se puede registrar como nombre alternativo).', NULL),
            IIF(st.equipo_2 IS NOT NULL AND st.codigo_fifa_visitante IS NULL,
                @salto_linea + N'- No hay una selección registrada con el nombre "' + st.equipo_2 + N'" (se puede registrar como nombre alternativo).', NULL),
            CASE WHEN st.estadio_txt IS NULL    THEN @salto_linea + N'- El estadio es obligatorio.'
                 WHEN st.sedes_posibles = 0     THEN @salto_linea + N'- El estadio "' + st.estadio_txt + N'" no corresponde a ninguna sede registrada.'
                 WHEN st.sedes_posibles > 1     THEN @salto_linea + N'- El estadio "' + st.estadio_txt + N'" puede ser más de una sede.'
            END,
            IIF((ISNULL(st.et_1, st.ft_1) IS NOT NULL AND st.goles_local IS NULL)
                OR (ISNULL(st.et_2, st.ft_2) IS NOT NULL AND st.goles_visitante IS NULL),
                @salto_linea + N'- Los goles del resultado no son números.', NULL),
            IIF((st.pen_1 IS NOT NULL AND st.penales_local IS NULL) OR (st.pen_2 IS NOT NULL AND st.penales_visitante IS NULL),
                @salto_linea + N'- Los penales no son números.', NULL),
            IIF(st.asistencia_txt IS NOT NULL AND st.asistencia IS NULL,
                @salto_linea + N'- La asistencia "' + st.asistencia_txt + N'" no es un número.', NULL)), N'')
    FROM #staging_partidos AS st;

    UPDATE #staging_partidos SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. Los SP de carga validan y cargan los partidos y, de los válidos, lo que pasó en cada
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
        LEFT JOIN (VALUES (N'Y', 'AMARILLA', 0), (N'R', 'ROJA', 0), (N'Y/R', 'AMARILLA', 0), (N'Y/R', 'ROJA', 1))
                  AS c (codigo, tarjeta, doble) ON c.codigo = UPPER(TRIM(d.tipo))
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
                IIF(e.nombre_txt IS NULL, @salto_linea + N'- Falta el nombre del jugador.', NULL),
                IIF(ns.error IS NOT NULL, @salto_linea + N'- ' + ns.error, NULL),
                IIF(e.tipo = 'CAMBIO' AND e.nombre_entra_txt IS NULL, @salto_linea + N'- Falta el jugador que entra.', NULL),
                IIF(ne.error IS NOT NULL, @salto_linea + N'- ' + ne.error, NULL)), N'')
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
                         THEN @salto_linea + N'- Falta el minuto.'
                     WHEN tipo IN ('CAMBIO', 'GOL', 'TARJETA') AND (minuto IS NULL OR minuto_adicional IS NULL)
                         THEN @salto_linea + N'- El minuto "' + minuto_txt + N'" no es un número (o número+adicional).'
                END,
                IIF(tipo = 'TARJETA' AND tipo_tarjeta IS NULL,
                    @salto_linea + N'- La tarjeta "' + ISNULL(tipo_txt, N'') + N'" no es Y, R ni Y/R.', NULL)), N'');

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
  usp_CargarArbitros
  Upsert de árbitros por país (código FIFA), apellido y nombre, desde
  #staging_arbitros. Columnas que usa: id_registro (distinto en cada fila),
  codigo_fifa, nombre, apellido, categoria, fecha_nacimiento, idiomas,
  errores y accion. Acepta la categoría CONFEDERATION, en inglés. idiomas es
  una lista de códigos ISO 639-1 separados por comas (ej. 'es,en'), como en
  usp_RegistrarArbitro, y puede no venir: se agregan los que el árbitro no
  tiene, y los que tiene y no vienen no se borran. En uno existente, la
  fecha de nacimiento que no viene no se borra, y si está activo o no queda
  como está.
  Valida cada árbitro pendiente: país registrado; nombre y apellido
  obligatorios y de hasta 60 caracteres; categoría FIFA o CONFEDERACION;
  fecha de nacimiento no futura; idiomas registrados; que no venga dos
  veces. Con eso cubre las reglas de usp_ARBITRO_Alta y
  usp_ARBITRO_IDIOMA_Alta.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_CargarArbitros
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @salto_linea NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- El país y el árbitro ya registrados de cada fila pendiente.
    DECLARE @registrados TABLE (
        id_registro  INT PRIMARY KEY,
        id_pais      SMALLINT,
        id_arbitro   INT
    );

    -- Los idiomas de cada fila pendiente, uno por fila (id_idioma NULL: el código no existe).
    DECLARE @idiomas TABLE (
        id_registro  INT,
        codigo       VARCHAR(10),
        id_idioma    SMALLINT,
        PRIMARY KEY (id_registro, codigo)
    );

    IF OBJECT_ID(N'tempdb..#staging_arbitros') IS NULL
        THROW 50001, N'Arbitraje.usp_CargarArbitros: no se importó nada, falta la tabla #staging_arbitros con los árbitros.', 1;

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

    INSERT INTO @idiomas (id_registro, codigo, id_idioma)
    SELECT DISTINCT st.id_registro, LEFT(LOWER(TRIM(c.value)), 10), i.id_idioma
    FROM #staging_arbitros AS st
    CROSS APPLY STRING_SPLIT(st.idiomas, ',') AS c
    LEFT JOIN DatosGenerales.IDIOMA AS i ON i.codigo_iso = LOWER(TRIM(c.value))
    WHERE st.accion IS NULL AND TRIM(c.value) <> '';

    /* 1. Las reglas de cada árbitro. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_fifa IS NULL THEN @salto_linea + N'- El código FIFA del país es obligatorio.'
                 WHEN r.id_pais IS NULL     THEN @salto_linea + N'- No hay un país registrado con código FIFA "' + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.nombre IS NULL OR st.apellido IS NULL
                     THEN @salto_linea + N'- El nombre y el apellido son obligatorios.'
                 WHEN LEN(st.nombre) > 60 OR LEN(st.apellido) > 60
                     THEN @salto_linea + N'- El nombre y el apellido no pueden superar los 60 caracteres.'
            END,
            CASE WHEN st.categoria IS NULL THEN @salto_linea + N'- La categoría es obligatoria.'
                 WHEN st.categoria NOT IN ('FIFA', 'CONFEDERACION')
                     THEN @salto_linea + N'- La categoría "' + st.categoria + N'" no es FIFA ni CONFEDERACION.'
            END,
            IIF(st.fecha_nacimiento > CONVERT(DATE, GETDATE()), @salto_linea + N'- La fecha de nacimiento no puede ser futura.', NULL),
            (SELECT @salto_linea + N'- Idiomas que no existen: ' + STRING_AGG(i.codigo, ', ') + N'.'
             FROM @idiomas AS i
             WHERE i.id_registro = st.id_registro AND i.id_idioma IS NULL)), N'')
    FROM #staging_arbitros AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro;

    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- Este árbitro viene ', r.veces, N' veces.')
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
                        OR EXISTS (SELECT 1 FROM @idiomas AS i
                                   WHERE i.id_registro = st.id_registro
                                     AND NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA AS ai
                                                     WHERE ai.id_arbitro = a.id_arbitro AND ai.id_idioma = i.id_idioma))
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

        -- Los idiomas que cada árbitro todavía no tiene (el árbitro nuevo ya tiene su id).
        INSERT INTO Arbitraje.ARBITRO_IDIOMA (id_arbitro, id_idioma)
        SELECT a.id_arbitro, i.id_idioma
        FROM #staging_arbitros AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        INNER JOIN Arbitraje.ARBITRO AS a ON a.id_pais = r.id_pais AND a.apellido = st.apellido AND a.nombre = st.nombre
        INNER JOIN @idiomas AS i ON i.id_registro = st.id_registro
        WHERE st.accion IN ('INSERTADO', 'ACTUALIZADO')
          AND NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA AS ai
                          WHERE ai.id_arbitro = a.id_arbitro AND ai.id_idioma = i.id_idioma);

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/*
  usp_CargarDesignaciones
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
CREATE OR ALTER PROCEDURE Arbitraje.usp_CargarDesignaciones
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @salto_linea NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- El partido, el árbitro y su designación ya registrados de cada fila pendiente.
    DECLARE @registradas TABLE (
        id_registro     INT PRIMARY KEY,
        id_partido      INT,
        arbitro_existe  BIT,
        pais_conflicto  VARCHAR(60),   -- el país del árbitro, si juega el partido
        rol_actual      VARCHAR(17)    -- el que el árbitro ya tiene en el partido
    );

    IF OBJECT_ID(N'tempdb..#staging_designaciones') IS NULL
        THROW 50001, N'Arbitraje.usp_CargarDesignaciones: no se importó nada, falta la tabla #staging_designaciones con las designaciones.', 1;

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
            CASE WHEN st.numero_partido IS NULL THEN @salto_linea + N'- El número de partido es obligatorio.'
                 WHEN r.id_partido IS NULL     THEN @salto_linea + N'- No hay un partido con el número '
                                                         + CAST(st.numero_partido AS NVARCHAR(3)) + N'.'
            END,
            CASE WHEN st.id_arbitro IS NULL THEN @salto_linea + N'- El árbitro es obligatorio.'
                 WHEN r.arbitro_existe = 0  THEN @salto_linea + N'- No existe un árbitro con id ' + CAST(st.id_arbitro AS NVARCHAR(10)) + N'.'
            END,
            CASE WHEN st.rol IS NULL THEN @salto_linea + N'- El rol es obligatorio.'
                 WHEN st.rol NOT IN ('PRINCIPAL', 'ASISTENTE_1', 'ASISTENTE_2', 'CUARTO', 'VAR',
                                     'ASISTENTE_RESERVA', 'AVAR', 'VAR_APOYO')
                     THEN @salto_linea + N'- El rol "' + st.rol + N'" no es PRINCIPAL, ASISTENTE_1, ASISTENTE_2, CUARTO, VAR, '
                              + N'ASISTENTE_RESERVA, AVAR ni VAR_APOYO.'
            END,
            IIF(r.pais_conflicto IS NOT NULL,
                @salto_linea + N'- Conflicto de nacionalidad: el árbitro es de ' + r.pais_conflicto + N', que juega este partido.', NULL)), N'')
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
    SET errores = CONCAT(IIF(ro.veces > 1, CONCAT(@salto_linea, N'- El rol ', v.rol, N' lo tendrían ', ro.veces, N' árbitros en el partido.'), N''),
                         IIF(ar.veces > 1, CONCAT(@salto_linea, N'- El árbitro viene ', ar.veces, N' veces para el partido.'), N''))
    FROM #staging_designaciones AS st
    INNER JOIN validas AS v ON v.id_registro = st.id_registro
    INNER JOIN (SELECT id_partido, rol, COUNT(*) AS veces FROM equipo
                GROUP BY id_partido, rol) AS ro ON ro.id_partido = v.id_partido AND ro.rol = v.rol
    INNER JOIN (SELECT id_partido, id_arbitro, COUNT(*) AS veces FROM equipo
                GROUP BY id_partido, id_arbitro) AS ar ON ar.id_partido = v.id_partido AND ar.id_arbitro = v.id_arbitro
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


/*
  usp_ImportarDesignacionesCSV
  Importa el equipo arbitral de cada partido desde el CSV que genera el
  scraping de Wikipedia (designaciones_arbitrales.csv, ver
  doc/Tecnica_de_Scraping.docx), con una fila por árbitro designado y esta primera fila
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
  carga. Registra la importación (los totales cuentan las filas del
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

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @salto_linea  NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido    NVARCHAR(MAX);
    DECLARE @encabezado   NVARCHAR(400);
    DECLARE @mensaje      NVARCHAR(2048);
    DECLARE @sql          NVARCHAR(MAX);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso      VARCHAR(100)   = 'Arbitraje.usp_ImportarDesignacionesCSV';
    DECLARE @leidos       INT;
    DECLARE @insertados   INT;
    DECLARE @actualizados INT;
    DECLARE @sin_cambios  INT;
    DECLARE @rechazados   INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @categoria    = UPPER(NULLIF(TRIM(@categoria), ''));
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @salto_linea + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.csv'
        SET @errores += @salto_linea + N'- El archivo tiene que ser un .csv (el designaciones_arbitrales.csv del scraping).';

    IF @categoria IS NULL OR @categoria NOT IN ('FIFA', 'CONFEDERACION')
        SET @errores += @salto_linea + N'- La categoría de los árbitros tiene que ser FIFA o CONFEDERACION.';

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
            CASE WHEN fecha_txt IS NULL THEN @salto_linea + N'- La fecha del partido es obligatoria.'
                 WHEN fecha IS NULL     THEN @salto_linea + N'- La fecha "' + fecha_txt + N'" no es una fecha AAAA-MM-DD.'
            END,
            CASE WHEN local_txt IS NULL OR visitante_txt IS NULL
                     THEN @salto_linea + N'- Faltan las selecciones del partido.'
                 WHEN fecha IS NOT NULL AND numero_partido IS NULL
                     THEN @salto_linea + N'- No hay un partido entre ' + local_txt + N' y ' + visitante_txt + N' el '
                              + CONVERT(NVARCHAR(10), fecha, 103) + N'.'
            END), N'');

    /* 4. Los SP de carga cargan los árbitros y, con ellos, las designaciones; después se
          registran la importación y sus rechazados. Todo en una transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Arbitraje.usp_CargarArbitros;

        -- Cada fila con su árbitro, o con los motivos por los que se rechazó.
        UPDATE st
        SET id_arbitro = a.id_arbitro,
            errores    = NULLIF(CONCAT(st.errores,
                             IIF(sa.accion = 'RECHAZADO', @salto_linea + N'- El árbitro se rechazó:' + REPLACE(sa.errores, @salto_linea + N'- ', @salto_linea + N'  - '), NULL)), N'')
        FROM #staging_designaciones AS st
        INNER JOIN #staging_arbitros AS sa
                ON sa.codigo_fifa IS NOT DISTINCT FROM st.pais_txt
               AND sa.nombre      IS NOT DISTINCT FROM st.nombre
               AND sa.apellido    IS NOT DISTINCT FROM st.apellido
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


/*
  usp_ImportarArbitrosCSV
  Importa árbitros sueltos (sin partidos) desde un CSV con una fila por
  árbitro y esta primera fila con los nombres de las columnas:
    pais,nombre,apellido,categoria,fecha_nacimiento,idiomas
  pais es el código FIFA del país del árbitro; categoria, FIFA o
  CONFEDERACION (o CONFEDERATION, en inglés); fecha_nacimiento, AAAA-MM-DD
  (puede venir vacía), e idiomas, los códigos ISO 639-1 separados por comas,
  entre comillas si son más de uno ("es,en"). Solo carga árbitros: no toca
  partidos ni designaciones (esas las importa usp_ImportarDesignacionesCSV).
  Lo usa la aplicación (app_abm), en la pestaña "Importar árbitros".
  Valida: ruta obligatoria y terminada en .csv. Si el archivo no se puede
  leer, no tiene las columnas esperadas o alguna fila no es CSV válido, no
  se importa nada (THROW 50002). Rechaza las filas con una fecha de
  nacimiento que no es fecha; las reglas de los árbitros las aplica
  usp_CargarArbitros. Registra la importación (su número queda en
  @id_importacion) y las filas rechazadas en Arbitraje.ERRORES_ARBITRO.
  Devuelve el resumen y cada fila del archivo con lo que le pasó y, si se
  rechazó, sus motivos.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ImportarArbitrosCSV
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
    DECLARE @proceso      VARCHAR(100)   = 'Arbitraje.usp_ImportarArbitrosCSV';
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
        SET @errores += @salto_linea + N'- El archivo tiene que ser un .csv.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ImportarArbitrosCSV: no se pudo importar el archivo.' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* 1. El archivo: la primera fila tiene que tener las columnas esperadas. */
    EXEC DatosGenerales.usp_LeerArchivoUTF8 @ruta_archivo = @ruta_archivo, @contenido = @contenido OUTPUT;

    SET @encabezado = REPLACE(REPLACE(LEFT(@contenido, CHARINDEX(NCHAR(10), @contenido + NCHAR(10)) - 1),
                                      NCHAR(13), N''), N' ', N'');
    IF @encabezado <> N'pais,nombre,apellido,categoria,fecha_nacimiento,idiomas'
    BEGIN
        SET @mensaje = N'Arbitraje.usp_ImportarArbitrosCSV: no se importó nada, la primera fila del archivo tiene que ser '
                     + N'"pais,nombre,apellido,categoria,fecha_nacimiento,idiomas" y es "' + LEFT(@encabezado, 200) + N'".';
        THROW 50002, @mensaje, 1;
    END;

    /* 2. Las filas, como vienen. FORMAT = 'CSV' respeta las comillas. El fin de
          línea es el del archivo: CRLF (Windows) o LF. */
    CREATE TABLE #crudo (
        pais_txt       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre         NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido       NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        categoria      NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
        fecha_txt      NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        idiomas        NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL
    );

    BEGIN TRY
        SET @sql = N'BULK INSERT #crudo FROM N''' + REPLACE(@ruta_archivo, N'''', N'''''')
                 + N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', FIELDTERMINATOR = '','', '
                 + N'ROWTERMINATOR = ''' + IIF(CHARINDEX(NCHAR(13) + NCHAR(10), @contenido) > 0, N'0x0d0a', N'0x0a')
                 + N''', FIELDQUOTE = ''"'', MAXERRORS = 0);';
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'Arbitraje.usp_ImportarArbitrosCSV: no se importó nada, hay filas que no son CSV válido '
                     + N'(tienen que tener 6 columnas): ' + ERROR_MESSAGE();
        THROW 50002, @mensaje, 1;
    END CATCH;

    -- usp_CargarArbitros lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_arbitros (
        id_registro       INT PRIMARY KEY,   -- línea del archivo
        -- Tal como viene en el archivo
        fecha_txt         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        -- Lo que lee usp_CargarArbitros, ya convertido
        codigo_fifa       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        categoria         NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
        fecha_nacimiento  DATE          NULL,
        idiomas           NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        -- Lo que le pasa a cada registro: lo completan este SP y usp_CargarArbitros
        errores           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion            VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    INSERT INTO #staging_arbitros (id_registro, codigo_fifa, nombre, apellido, categoria, fecha_txt, idiomas)
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) + 1,
           UPPER(NULLIF(TRIM(pais_txt), N'')), NULLIF(TRIM(nombre), N''), NULLIF(TRIM(apellido), N''),
           NULLIF(TRIM(categoria), N''), NULLIF(TRIM(fecha_txt), N''),
           NULLIF(TRIM(REPLACE(idiomas, NCHAR(13), N'')), N'')
    FROM #crudo
    WHERE CONCAT(pais_txt, nombre, apellido, categoria, fecha_txt, REPLACE(idiomas, NCHAR(13), N'')) <> N'';

    UPDATE #staging_arbitros
    SET fecha_nacimiento = TRY_CONVERT(DATE, fecha_txt, 23);

    /* 3. Lo que no se pudo convertir. Las reglas de los árbitros las aplica usp_CargarArbitros. */
    UPDATE #staging_arbitros
    SET errores = @salto_linea + N'- La fecha de nacimiento "' + fecha_txt + N'" no es una fecha AAAA-MM-DD.',
        accion  = 'RECHAZADO'
    WHERE fecha_txt IS NOT NULL AND fecha_nacimiento IS NULL;

    /* 4. El SP de carga carga los árbitros; después se registran la importación y sus
          rechazados. Todo en una transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Arbitraje.usp_CargarArbitros;

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_arbitros;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @ruta_archivo, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @rechazados = @rechazados,
            @id_importacion = @id_importacion OUTPUT;

        INSERT INTO Arbitraje.ERRORES_ARBITRO (id_importacion, registro, pais, nombre, apellido, categoria,
                                               fecha_nacimiento, idiomas, motivos)
        SELECT @id_importacion, id_registro, codigo_fifa, nombre, apellido, categoria, fecha_txt, idiomas,
               STUFF(errores, 1, 2, N'')
        FROM #staging_arbitros
        WHERE accion = 'RECHAZADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    /* 5. Resultado: el resumen y cada fila del archivo (los motivos de las rechazadas
          son los que quedaron en Arbitraje.ERRORES_ARBITRO). */
    SELECT @id_importacion AS id_importacion, @leidos AS leidos, @insertados AS insertados,
           @actualizados AS actualizados, @sin_cambios AS sin_cambios, @rechazados AS rechazados;

    SELECT id_registro AS linea, codigo_fifa AS pais, nombre, apellido, categoria,
           fecha_txt AS fecha_nacimiento, idiomas, accion, STUFF(errores, 1, 2, N'') AS motivos
    FROM #staging_arbitros
    ORDER BY id_registro;
END;
GO


-- Evidencia: objetos de la importación del Mundial 2026 creados.
SELECT s.name AS esquema, o.name AS objeto, o.type_desc AS tipo
FROM sys.objects AS o
INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE o.name IN (N'usp_LeerArchivoUTF8', N'fn_NormalizarNombre', N'fn_CoordenadaDecimal', N'usp_IdentificarJugadores',
                 N'usp_ImportarSedesJSON', N'usp_ImportarSeleccionesJSON', N'usp_ImportarPartidosJSON',
                 N'usp_ImportarDesignacionesCSV', N'usp_CargarSedes', N'usp_CargarSelecciones', N'usp_CargarPartidos',
                 N'usp_CargarDesarrolloPartidos', N'usp_CargarArbitros', N'usp_CargarDesignaciones',
                 N'usp_ImportarArbitrosCSV')
ORDER BY o.type_desc, o.name;
GO
