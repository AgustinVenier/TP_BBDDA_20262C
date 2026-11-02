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
 Archivo: 23_SP_Importar_Mundial2026.sql
 Objetivo: Crear el proceso de importación del Mundial 2026 real desde los
           archivos JSON del proyecto openfootball (ver
           datos/fuentes/openfootball/README.md): sedes, selecciones y
           partidos con lo que pasó en cada uno (formaciones, cambios, goles,
           penales de la definición y tarjetas). Los jugadores se importan
           antes, desde el CSV del scraping (24_SP_Importar_Jugadores.sql).
           Los objetos, en el orden en que se crean:
             DatosGenerales.usp_LeerArchivoUTF8   lee un archivo de texto UTF-8
             Torneo.fn_ClaveNombre                nombre sin separadores, para compararlo
             Torneo.usp_IdentificarJugadores      reconoce a un jugador por cómo lo escribe la fuente
             Torneo.fn_CoordenadaDecimal          coordenada en grados con decimales
             Torneo.usp_ImportarSedesJSON         worldcup.stadiums.json
             Torneo.usp_ImportarSeleccionesJSON   worldcup.teams.json
             Torneo.usp_ImportarPartidosJSON      worldcup-full.json
           Requiere haber ejecutado 00 a 22. Su script de testing es
           73_Test_SP_Importar_Mundial2026.sql. La carga del torneo real está
           en 32_ImportarMundial2026.sql.
================================================================================

 Cómo importa cada SP (igual que 25, 27 y 28):
   1. Se controla el archivo: que se pueda leer, que sea JSON y que tenga la
      estructura del archivo de openfootball que corresponde. Si no, no se
      importa nada (THROW 50002).
   2. OPENJSON pasa los registros, tal como vienen, a una tabla de staging, y
      ahí se convierten. Todas las transformaciones se hacen acá, en T-SQL.
   3. Cada regla es un UPDATE sobre toda la tabla de staging, que anota el
      motivo en los registros que no la cumplen (RECHAZADO).
   4. Los demás se cargan todos juntos con el SP de la Entrega 5 que
      corresponde (16_SP_Importacion.sql), que recibe un parámetro de tipo
      tabla. Como el paso 3 aplica las mismas reglas que ese SP, los
      registros válidos se cargan aunque haya otros rechazados.
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
     volviendo a importar.
   - Formaciones: la posición en cancha de cada titular es su posición
     habitual; el esquema táctico sale de esas posiciones (ej. 4-3-3).
   - Minutos: 45+2 es el 45 con 2 de adicional. Un minuto después del 120 es
     adicional del alargue (121 es 120+1).
   - Cambios: el archivo no dice el motivo: se registran como TACTICO. Un
     cambio en el minuto 46, 91 o 106 se hizo en el entretiempo.
   - Goles: los de penal son de tipo PENAL, los en contra EN CONTRA y el resto
     JUGADA.
   - Penales de la definición: se cargan los convertidos, como goles del
     período PENALES. El equipo de cada uno sale de cómo cambia el marcador.
   - Tarjetas: Y es amarilla, R roja directa y Y/R la segunda amarilla, que
     se registra como amarilla y además como roja por doble amarilla. El
     archivo no tiene el motivo: se registra "Sin detalle en la fuente".

 Se usa SQL dinámico solo para leer el archivo, porque OPENROWSET(BULK) no
 acepta la ruta en una variable.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   LECTURA DE ARCHIVOS Y RECONOCIMIENTO DE NOMBRES
   ============================================================================ */

/*
  usp_LeerArchivoUTF8
  Devuelve en @contenido el texto del archivo @ruta_archivo, codificado en
  UTF-8 (con o sin BOM), con todos sus caracteres (ř, ı, ø...). Si el archivo
  no se puede leer, no devuelve nada y avisa (THROW 50002).
  OPENROWSET(SINGLE_BLOB) trae los bytes tal cual y la columna con
  intercalación UTF-8 los interpreta como UTF-8 al pasarlos a NVARCHAR
  (SINGLE_CLOB los leería con la página de códigos de la base).
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_LeerArchivoUTF8
    @ruta_archivo  NVARCHAR(400),
    @contenido     NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql      NVARCHAR(MAX);
    DECLARE @mensaje  NVARCHAR(2048);
    DECLARE @texto    TABLE (contenido VARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8);

    SET @contenido = NULL;

    BEGIN TRY
        SET @sql = N'SELECT BulkColumn FROM OPENROWSET(BULK N'''
                 + REPLACE(@ruta_archivo, N'''', N'''''') + N''', SINGLE_BLOB) AS archivo;';
        INSERT INTO @texto (contenido)
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'DatosGenerales.usp_LeerArchivoUTF8: no se pudo leer el archivo ' + ISNULL(@ruta_archivo, N'(sin ruta)')
                     + N' (' + ERROR_MESSAGE() + N').';
        THROW 50002, @mensaje, 1;
    END CATCH;

    -- Sin la marca de orden de bytes (BOM) que agregan algunos editores.
    SELECT @contenido = CONVERT(NVARCHAR(MAX), contenido) FROM @texto;
    IF LEFT(@contenido, 1) = NCHAR(65279)
        SET @contenido = STUFF(@contenido, 1, 1, N'');
END;
GO


/*
  fn_ClaveNombre
  El nombre en minúsculas, sin espacios, guiones, apóstrofos ni puntos, y con
  ae, oe y ue como a, o y u (Rüdiger se escribe también Ruediger). Las tildes
  se comparan con una intercalación que no las distingue (_AI). Así "Al-Taamari"
  y "ALTAAMARI", u "O'Reilly" y "OREILLY", dan la misma clave.
*/
CREATE OR ALTER FUNCTION Torneo.fn_ClaveNombre (@texto NVARCHAR(400))
RETURNS NVARCHAR(400)
AS
BEGIN
    RETURN REPLACE(REPLACE(REPLACE(REPLACE(
               TRANSLATE(LOWER(@texto), N'-''.’', N'    '),
               N' ', N''), N'ae', N'a'), N'oe', N'o'), N'ue', N'u');
END;
GO


/*
  usp_IdentificarJugadores
  Reconoce a los jugadores que nombra un archivo. Trabaja sobre la tabla
  temporal #nombres_fuente que crea quien lo llama (codigo_fifa, nombre_fuente,
  id_jugador, paso, error): completa id_jugador con el jugador de esa
  selección que corresponde a nombre_fuente, o error con el motivo.
  El nombre de la fuente se separa en nombre y apellido: las palabras en
  mayúsculas son el apellido ("Julian QUINONES"); si está todo en mayúsculas,
  la primera palabra es el nombre ("MOUSA ALTAMARI"). Se prueba por pasos, en
  orden, entre los jugadores de la lista de esa selección (activos o no), y
  vale el primer paso que encuentra a alguien:
    0. Un nombre alternativo registrado para el jugador (NOMBRE_ALTERNATIVO).
    1. Nombre completo igual, en cualquier orden (Torneo.fn_ClaveNombre, sin
       distinguir tildes).
    2. Mismo apellido y primer nombre parecido (mismas tres primeras letras, o
       uno empieza con el otro): Maxi / Maximiliano.
    3. Mismo primer nombre y apellido parecido (uno empieza con el otro, o
       suenan igual según SOUNDEX): Zico / Ziko.
    4. Primer nombre y apellido que suenan igual (SOUNDEX): Mousa Altamari /
       Musa Al-Taamari.
    5. Jugadores conocidos por un solo nombre (nombre igual al apellido en la
       lista): Neymar, Casemiro.
  Si en ese paso hay más de un jugador posible, no se elige ninguno: el
  nombre se rechaza como ambiguo. Si ningún paso encuentra a nadie, el error
  sugiere hasta tres jugadores de apellido parecido. En los dos casos se
  resuelve registrando el nombre alternativo del jugador.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_IdentificarJugadores
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #partes (
        id_nombre       INT PRIMARY KEY,
        nombre          NVARCHAR(200) COLLATE DATABASE_DEFAULT,
        apellido        NVARCHAR(200) COLLATE DATABASE_DEFAULT,
        clave_completa  NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        clave_nombre    NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        clave_apellido  NVARCHAR(400) COLLATE DATABASE_DEFAULT
    );

    CREATE TABLE #candidatos (
        id_jugador      INT PRIMARY KEY,
        codigo_fifa     VARCHAR(10)   COLLATE DATABASE_DEFAULT,
        id_seleccion    INT,
        nombre          NVARCHAR(60)  COLLATE DATABASE_DEFAULT,
        apellido        NVARCHAR(60)  COLLATE DATABASE_DEFAULT,
        clave_completa  NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        clave_inversa   NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        clave_nombre    NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        clave_apellido  NVARCHAR(400) COLLATE DATABASE_DEFAULT,
        un_nombre       BIT
    );

    CREATE TABLE #coincidencias (id_nombre INT, paso TINYINT, id_jugador INT);

    -- Nombre y apellido según las mayúsculas.
    WITH palabras AS (
        SELECT n.id_nombre, w.ordinal, w.value AS palabra,
               IIF(w.value COLLATE Latin1_General_CS_AS = UPPER(w.value) AND LEN(w.value) > 1, 1, 0) AS mayuscula,
               COUNT(*) OVER (PARTITION BY n.id_nombre) AS palabras,
               SUM(IIF(w.value COLLATE Latin1_General_CS_AS = UPPER(w.value) AND LEN(w.value) > 1, 0, 1))
                   OVER (PARTITION BY n.id_nombre) AS minusculas
        FROM #nombres_fuente AS n
        CROSS APPLY STRING_SPLIT(TRIM(n.nombre_fuente), N' ', 1) AS w
        WHERE w.value <> N''
    ),
    partes AS (
        SELECT id_nombre,
               STRING_AGG(IIF(minusculas > 0, IIF(mayuscula = 0, palabra, NULL), IIF(ordinal = 1, palabra, NULL)), N' ')
                   WITHIN GROUP (ORDER BY ordinal) AS nombre,
               STRING_AGG(IIF(minusculas > 0, IIF(mayuscula = 1, palabra, NULL),
                              IIF(ordinal > 1 OR palabras = 1, palabra, NULL)), N' ')
                   WITHIN GROUP (ORDER BY ordinal) AS apellido
        FROM palabras
        GROUP BY id_nombre
    )
    INSERT INTO #partes (id_nombre, nombre, apellido)
    SELECT id_nombre, nombre, apellido FROM partes;

    UPDATE p
    SET clave_completa = Torneo.fn_ClaveNombre(n.nombre_fuente),
        clave_nombre   = Torneo.fn_ClaveNombre(LEFT(p.nombre, CHARINDEX(N' ', p.nombre + N' ') - 1)),
        clave_apellido = Torneo.fn_ClaveNombre(p.apellido)
    FROM #partes AS p
    INNER JOIN #nombres_fuente AS n ON n.id_nombre = p.id_nombre;

    INSERT INTO #candidatos (id_jugador, codigo_fifa, id_seleccion, nombre, apellido, un_nombre)
    SELECT j.id_jugador, pa.codigo_fifa, s.id_seleccion, j.nombre, j.apellido, IIF(j.nombre = j.apellido, 1, 0)
    FROM Torneo.JUGADOR AS j
    INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
    INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
    WHERE pa.codigo_fifa IN (SELECT codigo_fifa FROM #nombres_fuente);

    UPDATE #candidatos
    SET clave_completa = Torneo.fn_ClaveNombre(nombre + apellido),
        clave_inversa  = Torneo.fn_ClaveNombre(apellido + nombre),
        clave_nombre   = Torneo.fn_ClaveNombre(LEFT(nombre, CHARINDEX(N' ', nombre + N' ') - 1)),
        clave_apellido = Torneo.fn_ClaveNombre(apellido);

    -- 0. Nombre alternativo registrado.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT n.id_nombre, 0, c.id_jugador
    FROM #nombres_fuente AS n
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa
    INNER JOIN Torneo.NOMBRE_ALTERNATIVO AS na ON na.id_jugador = c.id_jugador
    WHERE na.nombre COLLATE Latin1_General_CI_AI = n.nombre_fuente COLLATE Latin1_General_CI_AI;

    -- 1. Nombre completo, en cualquier orden.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT p.id_nombre, 1, c.id_jugador
    FROM #partes AS p
    INNER JOIN #nombres_fuente AS n ON n.id_nombre = p.id_nombre
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa
    WHERE p.clave_completa COLLATE Latin1_General_CI_AI IN (c.clave_completa COLLATE Latin1_General_CI_AI,
                                                             c.clave_inversa COLLATE Latin1_General_CI_AI);

    -- 2. Mismo apellido y primer nombre parecido.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT p.id_nombre, 2, c.id_jugador
    FROM #partes AS p
    INNER JOIN #nombres_fuente AS n ON n.id_nombre = p.id_nombre
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa
    WHERE p.nombre IS NOT NULL AND p.apellido IS NOT NULL AND p.nombre <> p.apellido
      AND p.clave_apellido COLLATE Latin1_General_CI_AI = c.clave_apellido COLLATE Latin1_General_CI_AI
      AND (LEFT(p.clave_nombre, 3) COLLATE Latin1_General_CI_AI = LEFT(c.clave_nombre, 3) COLLATE Latin1_General_CI_AI
           OR p.clave_nombre COLLATE Latin1_General_CI_AI LIKE c.clave_nombre + N'%' COLLATE Latin1_General_CI_AI
           OR c.clave_nombre COLLATE Latin1_General_CI_AI LIKE p.clave_nombre + N'%' COLLATE Latin1_General_CI_AI);

    -- 3. Mismo primer nombre y apellido parecido.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT p.id_nombre, 3, c.id_jugador
    FROM #partes AS p
    INNER JOIN #nombres_fuente AS n ON n.id_nombre = p.id_nombre
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa
    WHERE p.nombre IS NOT NULL AND p.apellido IS NOT NULL AND p.nombre <> p.apellido
      AND p.clave_nombre COLLATE Latin1_General_CI_AI = c.clave_nombre COLLATE Latin1_General_CI_AI
      AND (p.clave_apellido COLLATE Latin1_General_CI_AI LIKE c.clave_apellido + N'%' COLLATE Latin1_General_CI_AI
           OR c.clave_apellido COLLATE Latin1_General_CI_AI LIKE p.clave_apellido + N'%' COLLATE Latin1_General_CI_AI
           OR SOUNDEX(p.clave_apellido) = SOUNDEX(c.clave_apellido));

    -- 4. Primer nombre y apellido que suenan igual.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT p.id_nombre, 4, c.id_jugador
    FROM #partes AS p
    INNER JOIN #nombres_fuente AS n ON n.id_nombre = p.id_nombre
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa
    WHERE p.nombre IS NOT NULL AND p.apellido IS NOT NULL AND p.nombre <> p.apellido
      AND SOUNDEX(p.clave_nombre) = SOUNDEX(c.clave_nombre)
      AND SOUNDEX(p.clave_apellido) = SOUNDEX(c.clave_apellido);

    -- 5. Jugadores de un solo nombre: alguna palabra de la fuente es ese nombre.
    INSERT INTO #coincidencias (id_nombre, paso, id_jugador)
    SELECT DISTINCT n.id_nombre, 5, c.id_jugador
    FROM #nombres_fuente AS n
    INNER JOIN #candidatos AS c ON c.codigo_fifa = n.codigo_fifa AND c.un_nombre = 1
    CROSS APPLY STRING_SPLIT(TRIM(n.nombre_fuente), N' ') AS w
    WHERE Torneo.fn_ClaveNombre(w.value) COLLATE Latin1_General_CI_AI = c.clave_nombre COLLATE Latin1_General_CI_AI;

    -- Vale el primer paso con coincidencias: con un solo jugador, es ese; con más, es ambiguo.
    WITH primer_paso AS (
        SELECT id_nombre, MIN(paso) AS paso FROM #coincidencias GROUP BY id_nombre
    ),
    resultado AS (
        SELECT c.id_nombre, c.paso, COUNT(DISTINCT c.id_jugador) AS jugadores, MIN(c.id_jugador) AS id_jugador
        FROM #coincidencias AS c
        INNER JOIN primer_paso AS pp ON pp.id_nombre = c.id_nombre AND pp.paso = c.paso
        GROUP BY c.id_nombre, c.paso
    )
    UPDATE n
    SET id_jugador = IIF(r.jugadores = 1, r.id_jugador, NULL),
        paso       = r.paso,
        error      = IIF(r.jugadores = 1, NULL,
                         CONCAT(N'"', n.nombre_fuente, N'" puede ser ', r.jugadores, N' jugadores de la lista de ',
                                n.codigo_fifa, N': ',
                                (SELECT STRING_AGG(CONCAT(c.nombre, N' ', c.apellido), N', ')
                                 FROM (SELECT DISTINCT id_jugador FROM #coincidencias AS x
                                       WHERE x.id_nombre = r.id_nombre AND x.paso = r.paso) AS x
                                 INNER JOIN #candidatos AS c ON c.id_jugador = x.id_jugador),
                                N'. Hay que registrar el nombre alternativo del que corresponde.'))
    FROM #nombres_fuente AS n
    INNER JOIN resultado AS r ON r.id_nombre = n.id_nombre;

    UPDATE n
    SET error = CONCAT(N'"', n.nombre_fuente, N'" no coincide con ningún jugador de la lista de ', n.codigo_fifa,
                       ISNULL(N'. Parecidos: ' + (SELECT STRING_AGG(CONCAT(c.nombre, N' ', c.apellido), N', ')
                                                  FROM (SELECT TOP (3) c.nombre, c.apellido
                                                        FROM #candidatos AS c
                                                        WHERE c.codigo_fifa = n.codigo_fifa
                                                          AND DIFFERENCE(c.clave_apellido, p.clave_apellido) >= 3
                                                        ORDER BY DIFFERENCE(c.clave_apellido, p.clave_apellido) DESC,
                                                                 DIFFERENCE(c.clave_nombre, p.clave_nombre) DESC) AS c), N''),
                       N'. Si es uno de ellos, hay que registrar su nombre alternativo.')
    FROM #nombres_fuente AS n
    LEFT JOIN #partes AS p ON p.id_nombre = n.id_nombre
    WHERE n.paso IS NULL;
END;
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
  (@ruta_archivo), con usp_ImportarSedes. Las tarifas son las de los 4
  espacios publicitarios de las sedes nuevas, que el archivo no trae.
  Valida: ruta obligatoria y terminada en .json; tarifas no negativas. Si el
  archivo no se puede leer, no es JSON o no tiene la lista "stadiums", no se
  importa nada (THROW 50002). Devuelve el resumen y los rechazados con sus
  motivos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarSedesJSON
    @ruta_archivo      NVARCHAR(400),
    @tarifa_espacio_1  DECIMAL(9,2) = 120000,
    @tarifa_espacio_2  DECIMAL(9,2) = 100000,
    @tarifa_espacio_3  DECIMAL(9,2) = 90000,
    @tarifa_espacio_4  DECIMAL(9,2) = 80000
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido     NVARCHAR(MAX);
    DECLARE @mensaje       NVARCHAR(2048);
    DECLARE @validas       Torneo.TT_SEDE;
    DECLARE @insertados    INT = 0;
    DECLARE @actualizados  INT = 0;
    DECLARE @sin_cambios   INT = 0;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');

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

    CREATE TABLE #staging_sedes (
        id_registro     INT PRIMARY KEY,
        -- Tal como vienen en el archivo
        nombre_txt      NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        ciudad_txt      NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        pais_txt        NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        huso_txt        NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        capacidad_txt   NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        coordenadas     NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
        -- Convertidos
        codigo_fifa     VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
        huso_horario    VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        capacidad       INT           NULL,
        latitud         DECIMAL(12,6) NULL,
        longitud        DECIMAL(12,6) NULL,
        errores         NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion          VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    /* 2. Los registros, como vienen en el archivo. */
    INSERT INTO #staging_sedes (id_registro, nombre_txt, ciudad_txt, pais_txt, huso_txt, capacidad_txt, coordenadas)
    SELECT CAST(s.[key] AS INT) + 1,
           NULLIF(TRIM(d.nombre), N''), NULLIF(TRIM(d.ciudad), N''), UPPER(NULLIF(TRIM(d.pais), N'')),
           UPPER(REPLACE(NULLIF(TRIM(d.huso), N''), N' ', N'')), NULLIF(TRIM(d.capacidad), N''),
           NULLIF(TRIM(d.coordenadas), N'')
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

    -- Coordenadas: "49°16'36"N 123°6'43"W" o "37.403°N 121.970°W".
    UPDATE st
    SET capacidad = TRY_CONVERT(INT, st.capacidad_txt),
        latitud   = Torneo.fn_CoordenadaDecimal(c.lat, N'NS'),
        longitud  = Torneo.fn_CoordenadaDecimal(c.lon, N'EW')
    FROM #staging_sedes AS st
    CROSS APPLY (SELECT LEFT(st.coordenadas, CHARINDEX(N' ', st.coordenadas + N' ') - 1) AS lat,
                        TRIM(SUBSTRING(st.coordenadas, CHARINDEX(N' ', st.coordenadas + N' ') + 1, 100)) AS lon) AS c;

    /* 3. Validaciones, con las reglas de usp_ImportarSedes. */
    UPDATE st
    SET errores = NULLIF(CONCAT(
            IIF(st.nombre_txt IS NULL, @nl + N'- El nombre del estadio es obligatorio.', NULL),
            IIF(LEN(st.nombre_txt) > 100, @nl + N'- El nombre del estadio no puede superar los 100 caracteres.', NULL),
            IIF(st.ciudad_txt IS NULL, @nl + N'- La ciudad es obligatoria.', NULL),
            IIF(LEN(st.ciudad_txt) > 80, @nl + N'- La ciudad no puede superar los 80 caracteres.', NULL),
            IIF(st.codigo_fifa IS NULL,
                @nl + N'- El país "' + ISNULL(st.pais_txt, N'') + N'" no es un código ISO alfa-2 de un país registrado.', NULL),
            IIF(st.huso_horario IS NULL, @nl + N'- No se reconoce el huso "' + ISNULL(st.huso_txt, N'') + N'" para ese país.', NULL),
            IIF(st.capacidad IS NULL OR st.capacidad <= 0,
                @nl + N'- La capacidad "' + ISNULL(st.capacidad_txt, N'') + N'" no es un número mayor que cero.', NULL),
            IIF(st.coordenadas IS NOT NULL AND (st.latitud IS NULL OR st.longitud IS NULL OR st.latitud NOT BETWEEN -90 AND 90
                                                OR st.longitud NOT BETWEEN -180 AND 180),
                @nl + N'- Las coordenadas "' + st.coordenadas + N'" no son una latitud y una longitud válidas.', NULL),
            IIF(st.capacidad > 0 AND EXISTS (SELECT 1 FROM Torneo.SEDE AS s
                                             INNER JOIN Torneo.PARTIDO AS p ON p.id_sede = s.id_sede
                                             WHERE s.nombre_estadio = st.nombre_txt AND p.asistencia > st.capacidad),
                @nl + N'- La capacidad es menor que la asistencia de un partido ya jugado en la sede.', NULL)), N'')
    FROM #staging_sedes AS st;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- El archivo trae ', r.veces, N' veces este estadio.')
    FROM #staging_sedes AS st
    INNER JOIN (SELECT nombre_txt, COUNT(*) AS veces FROM #staging_sedes
                WHERE nombre_txt IS NOT NULL GROUP BY nombre_txt HAVING COUNT(*) > 1) AS r
            ON r.nombre_txt = st.nombre_txt;

    UPDATE #staging_sedes SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. Carga de las válidas, todas juntas, con el SP de la Entrega 5. */
    INSERT INTO @validas (nombre_estadio, ciudad, codigo_fifa_pais, capacidad, huso_horario, latitud, longitud,
                          tarifa_espacio_1, tarifa_espacio_2, tarifa_espacio_3, tarifa_espacio_4)
    SELECT nombre_txt, ciudad_txt, codigo_fifa, capacidad, huso_horario, latitud, longitud,
           @tarifa_espacio_1, @tarifa_espacio_2, @tarifa_espacio_3, @tarifa_espacio_4
    FROM #staging_sedes
    WHERE accion IS NULL;

    IF EXISTS (SELECT 1 FROM @validas)
        EXEC Torneo.usp_ImportarSedes
            @sedes = @validas, @insertados = @insertados OUTPUT,
            @actualizados = @actualizados OUTPUT, @sin_cambios = @sin_cambios OUTPUT;

    /* 5. Resultado. */
    SELECT @ruta_archivo AS origen, COUNT(*) AS leidos, @insertados AS insertados, @actualizados AS actualizados,
           @sin_cambios AS sin_cambios, ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0) AS rechazados
    FROM #staging_sedes;

    SELECT CONCAT(id_registro, N'. ', ISNULL(nombre_txt, N'(sin nombre)')) AS rechazado,
           STUFF(errores, 1, 2, N'') AS motivos
    FROM #staging_sedes
    WHERE accion = 'RECHAZADO'
    ORDER BY id_registro;
END;
GO


/* ============================================================================
   SELECCIONES
   ============================================================================ */

/*
  usp_ImportarSeleccionesJSON
  Importa las selecciones del archivo worldcup.teams.json de openfootball
  (@ruta_archivo), con usp_ImportarSelecciones: código FIFA, confederación,
  grupo y el nombre en inglés, que queda como nombre alternativo. Las listas
  de convocados nuevas se presentan en @fecha_presentacion.
  Valida: ruta obligatoria y terminada en .json; si hay que crear alguna
  lista, fecha de presentación obligatoria y no futura. Si el archivo no se
  puede leer, no es JSON o no es una lista de selecciones con código FIFA, no
  se importa nada (THROW 50002). Devuelve el resumen y las rechazadas con sus
  motivos.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarSeleccionesJSON
    @ruta_archivo        NVARCHAR(400),
    @fecha_presentacion  DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido     NVARCHAR(MAX);
    DECLARE @mensaje       NVARCHAR(2048);
    DECLARE @cupo_grupo    TINYINT        = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                                             WHERE codigo = 'SELECCIONES_POR_GRUPO');
    DECLARE @validas       Torneo.TT_SELECCION;
    DECLARE @insertados    INT = 0;
    DECLARE @actualizados  INT = 0;
    DECLARE @sin_cambios   INT = 0;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');

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

    CREATE TABLE #staging_selecciones (
        id_registro     INT PRIMARY KEY,
        -- Tal como vienen en el archivo
        nombre_txt      NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        codigo_fifa     NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        grupo           NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        confederacion   NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        -- Lo que ya está registrado
        id_pais         SMALLINT      NULL,
        id_seleccion    INT           NULL,
        grupo_actual    CHAR(1)       COLLATE DATABASE_DEFAULT NULL,
        tiene_lista     BIT           NULL,
        errores         NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion          VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    /* 2. Los registros, como vienen en el archivo. */
    INSERT INTO #staging_selecciones (id_registro, nombre_txt, codigo_fifa, grupo, confederacion)
    SELECT CAST(s.[key] AS INT) + 1, NULLIF(TRIM(d.nombre), N''), UPPER(NULLIF(TRIM(d.codigo), N'')),
           UPPER(NULLIF(TRIM(d.grupo), N'')), UPPER(NULLIF(TRIM(d.confederacion), N''))
    FROM OPENJSON(@contenido) AS s
    CROSS APPLY OPENJSON(s.value)
        WITH (nombre NVARCHAR(400) '$.name', codigo NVARCHAR(50) '$.fifa_code',
              grupo NVARCHAR(50) '$.group', confederacion NVARCHAR(50) '$.confed') AS d;

    UPDATE st
    SET id_pais = p.id_pais, id_seleccion = s.id_seleccion, grupo_actual = s.grupo,
        tiene_lista = IIF(EXISTS (SELECT 1 FROM Torneo.LISTA_CONVOCADOS AS lc
                                  WHERE lc.id_seleccion = s.id_seleccion), 1, 0)
    FROM #staging_selecciones AS st
    INNER JOIN DatosGenerales.PAIS AS p ON p.codigo_fifa = st.codigo_fifa
    LEFT JOIN Torneo.SELECCION AS s ON s.id_pais = p.id_pais;

    /* 3. Validaciones, con las reglas de usp_ImportarSelecciones. */
    UPDATE st
    SET errores = NULLIF(CONCAT(
            CASE WHEN st.codigo_fifa IS NULL THEN @nl + N'- El código FIFA es obligatorio.'
                 WHEN st.id_pais IS NULL     THEN @nl + N'- No hay un país con código FIFA "' + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.confederacion IS NULL AND st.id_seleccion IS NULL
                     THEN @nl + N'- La confederación es obligatoria.'
                 WHEN st.confederacion NOT IN (N'AFC', N'CAF', N'CONCACAF', N'CONMEBOL', N'OFC', N'UEFA')
                     THEN @nl + N'- La confederación "' + st.confederacion + N'" no es AFC, CAF, CONCACAF, CONMEBOL, OFC ni UEFA.'
            END,
            IIF(st.grupo COLLATE Latin1_General_BIN NOT LIKE N'[A-L]',
                @nl + N'- El grupo "' + st.grupo + N'" no es una letra de la A a la L.', NULL),
            IIF(st.grupo <> ISNULL(st.grupo_actual, N'')
                AND EXISTS (SELECT 1 FROM Torneo.PARTIDO AS p
                            WHERE p.fase = 'GRUPOS' AND st.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)),
                @nl + N'- La selección ya tiene partidos de la fase de grupos: no se le puede cambiar el grupo.', NULL),
            IIF(LEN(st.nombre_txt) > 120, @nl + N'- El nombre no puede superar los 120 caracteres.', NULL),
            IIF(EXISTS (SELECT 1 FROM Torneo.NOMBRE_ALTERNATIVO AS na
                        WHERE na.id_jugador IS NULL AND na.nombre = st.nombre_txt
                          AND na.id_seleccion <> ISNULL(st.id_seleccion, 0)),
                @nl + N'- El nombre "' + st.nombre_txt + N'" ya es de otra selección.', NULL)), N'')
    FROM #staging_selecciones AS st;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- El archivo trae ', r.veces, N' veces esta selección.')
    FROM #staging_selecciones AS st
    INNER JOIN (SELECT codigo_fifa, COUNT(*) AS veces FROM #staging_selecciones
                WHERE codigo_fifa IS NOT NULL GROUP BY codigo_fifa HAVING COUNT(*) > 1) AS r
            ON r.codigo_fifa = st.codigo_fifa;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- El archivo usa el nombre "', st.nombre_txt, N'" para más de una selección.')
    FROM #staging_selecciones AS st
    WHERE EXISTS (SELECT 1 FROM #staging_selecciones AS o
                  WHERE o.nombre_txt = st.nombre_txt AND o.codigo_fifa <> st.codigo_fifa);

    -- Grupos como quedarían con las selecciones válidas: si uno se pasa del cupo, se rechazan las suyas.
    WITH grupos AS (
        SELECT ISNULL(st.grupo, st.grupo_actual) AS grupo
        FROM #staging_selecciones AS st
        WHERE st.errores IS NULL
        UNION ALL
        SELECT s.grupo
        FROM Torneo.SELECCION AS s
        WHERE NOT EXISTS (SELECT 1 FROM #staging_selecciones AS st
                          WHERE st.errores IS NULL AND st.id_seleccion = s.id_seleccion)
    ),
    excedidos AS (
        SELECT grupo, COUNT(*) AS selecciones FROM grupos
        WHERE grupo IS NOT NULL GROUP BY grupo HAVING COUNT(*) > @cupo_grupo
    )
    UPDATE st
    SET errores = CONCAT(@nl, N'- El grupo ', e.grupo, N' quedaría con ', e.selecciones, N' selecciones y el máximo es ',
                         @cupo_grupo, N' (SELECCIONES_POR_GRUPO).')
    FROM #staging_selecciones AS st
    INNER JOIN excedidos AS e ON e.grupo = ISNULL(st.grupo, st.grupo_actual)
    WHERE st.errores IS NULL;

    UPDATE #staging_selecciones SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    -- La fecha es un dato de la importación, no de cada registro: si falta, no se importa nada.
    IF EXISTS (SELECT 1 FROM #staging_selecciones WHERE accion IS NULL AND ISNULL(tiene_lista, 0) = 0)
       AND (@fecha_presentacion IS NULL OR @fecha_presentacion > CONVERT(DATE, GETDATE()))
    BEGIN
        SET @errores = N'Torneo.usp_ImportarSeleccionesJSON: no se importó nada.' + @nl
                     + N'- Hay selecciones sin lista de convocados: la fecha de presentación es obligatoria y no puede ser futura.';
        THROW 50001, @errores, 1;
    END;

    /* 4. Carga de las válidas, todas juntas, con el SP de la Entrega 5. */
    INSERT INTO @validas (codigo_fifa, confederacion, grupo, nombre_alternativo)
    SELECT codigo_fifa, confederacion, grupo, nombre_txt
    FROM #staging_selecciones
    WHERE accion IS NULL;

    IF EXISTS (SELECT 1 FROM @validas)
        EXEC Torneo.usp_ImportarSelecciones
            @selecciones = @validas, @fecha_presentacion = @fecha_presentacion,
            @insertados = @insertados OUTPUT, @actualizados = @actualizados OUTPUT, @sin_cambios = @sin_cambios OUTPUT;

    /* 5. Resultado. */
    SELECT @ruta_archivo AS origen, COUNT(*) AS leidos, @insertados AS insertados, @actualizados AS actualizados,
           @sin_cambios AS sin_cambios, ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0) AS rechazados
    FROM #staging_selecciones;

    SELECT CONCAT(id_registro, N'. ', ISNULL(codigo_fifa, N'(sin código)'), N' ', ISNULL(nombre_txt, N'')) AS rechazado,
           STUFF(errores, 1, 2, N'') AS motivos
    FROM #staging_selecciones
    WHERE accion = 'RECHAZADO'
    ORDER BY id_registro;
END;
GO


/* ============================================================================
   PARTIDOS
   ============================================================================ */

/*
  usp_ImportarPartidosJSON
  Importa los partidos del archivo worldcup-full.json de openfootball
  (@ruta_archivo) con usp_ImportarPartidos y, de los partidos válidos, lo que
  pasó en cada uno (formaciones, cambios, goles, penales convertidos en la
  definición y tarjetas) con usp_ImportarDesarrolloPartidos. Las sedes, las
  selecciones y los jugadores tienen que estar cargados antes.
  Los partidos se numeran desde @primer_numero (1 para el fixture completo;
  otro número si el archivo es solo una parte, para no pisar los que ya
  tienen esos números).
  Valida: ruta obligatoria y terminada en .json; primer número entre 1 y
  255. Si el archivo no se puede
  leer, no es JSON o no tiene la lista "matches", no se importa nada
  (THROW 50002). Devuelve el resumen de partidos y de eventos, los
  rechazados con sus motivos, y los partidos cuyo resultado no coincide con
  los goles cargados (porque se rechazó alguno).
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ImportarPartidosJSON
    @ruta_archivo   NVARCHAR(400),
    @primer_numero  TINYINT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores              NVARCHAR(2048) = N'';
    DECLARE @nl                   NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido            NVARCHAR(MAX);
    DECLARE @mensaje              NVARCHAR(2048);
    DECLARE @partidos_grupos      INT;
    DECLARE @partidos             Torneo.TT_PARTIDO;
    DECLARE @alineaciones         DesarrolloPartido.TT_ALINEACION_PARTIDO;
    DECLARE @cambios              DesarrolloPartido.TT_CAMBIO;
    DECLARE @goles                DesarrolloPartido.TT_GOL;
    DECLARE @amonestaciones       DesarrolloPartido.TT_AMONESTACION;
    DECLARE @insertados           INT = 0;
    DECLARE @actualizados         INT = 0;
    DECLARE @sin_cambios          INT = 0;
    DECLARE @eventos_insertados   INT = 0;
    DECLARE @eventos_sin_cambios  INT = 0;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');

    IF @ruta_archivo IS NULL
        SET @errores += @nl + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.json'
        SET @errores += @nl + N'- El archivo tiene que ser un .json (worldcup-full.json de openfootball).';

    IF ISNULL(@primer_numero, 0) = 0
        SET @errores += @nl + N'- El primer número de partido tiene que estar entre 1 y 255.';

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

    CREATE TABLE #staging_partidos (
        id_registro       INT PRIMARY KEY,
        -- Tal como vienen en el archivo
        ronda             NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
        fecha_txt         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        hora_txt          NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        equipo_1          NVARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
        equipo_2          NVARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
        estadio_txt       NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        asistencia_txt    NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        ft_1              NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        ft_2              NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        et_1              NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        et_2              NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        pen_1             NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        pen_2             NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
        detalle           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,   -- el partido completo, para leer sus eventos
        -- Convertidos
        fase              VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
        grupo             CHAR(1)       COLLATE DATABASE_DEFAULT NULL,
        fecha_hora_local  DATETIME2(0)  NULL,
        fecha_hora_utc    DATETIME2(0)  NULL,
        id_seleccion_1    INT           NULL,
        id_seleccion_2    INT           NULL,
        codigo_1          VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
        codigo_2          VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
        id_sede           INT           NULL,
        sedes_posibles    INT           NULL,
        nombre_estadio    VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        capacidad         INT           NULL,
        goles_1           TINYINT       NULL,
        goles_2           TINYINT       NULL,
        penales_1         TINYINT       NULL,
        penales_2         TINYINT       NULL,
        asistencia        INT           NULL,
        numero_partido    TINYINT       NULL,
        id_partido        INT           NULL,
        errores           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion            VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
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

    -- Fase (como la traduce usp_ImportarPartidos) y grupo; hora local y UTC ("13:00 UTC-6").
    UPDATE st
    SET fase = CASE WHEN r.ronda LIKE '%GROUP%' OR r.ronda LIKE 'GRUPO%'                           THEN 'GRUPOS'
                    WHEN r.ronda IN ('ROUND OF 32', 'DIECISEISAVOS DE FINAL')                      THEN 'DIECISEISAVOS'
                    WHEN r.ronda IN ('ROUND OF 16', 'OCTAVOS DE FINAL')                            THEN 'OCTAVOS'
                    WHEN r.ronda LIKE 'QUARTER%' OR r.ronda = 'CUARTOS DE FINAL'                   THEN 'CUARTOS'
                    WHEN r.ronda LIKE 'SEMI%'                                                      THEN 'SEMIFINAL'
                    WHEN r.ronda LIKE '%THIRD%' OR r.ronda LIKE 'BRONZE%' OR r.ronda LIKE 'TERCER%' THEN 'TERCER_PUESTO'
                    WHEN r.ronda = 'FINAL'                                                          THEN 'FINAL'
               END,
        grupo = IIF(r.ronda LIKE '%GROUP [A-L]', RIGHT(r.ronda, 1), NULL),
        fecha_hora_local = h.local,
        fecha_hora_utc   = DATEADD(HOUR, -h.desfase, h.local),
        goles_1          = TRY_CONVERT(TINYINT, ISNULL(st.et_1, st.ft_1)),
        goles_2          = TRY_CONVERT(TINYINT, ISNULL(st.et_2, st.ft_2)),
        penales_1        = TRY_CONVERT(TINYINT, st.pen_1),
        penales_2        = TRY_CONVERT(TINYINT, st.pen_2),
        asistencia       = TRY_CONVERT(INT, st.asistencia_txt)
    FROM #staging_partidos AS st
    CROSS APPLY (SELECT UPPER(st.ronda) AS ronda) AS r
    CROSS APPLY (SELECT TRY_CONVERT(DATETIME2(0), st.fecha_txt + N' ' + LEFT(st.hora_txt, CHARINDEX(N' ', st.hora_txt + N' ') - 1), 120) AS local,
                        TRY_CONVERT(INT, SUBSTRING(st.hora_txt, NULLIF(CHARINDEX(N'UTC', st.hora_txt), 0) + 3, 10)) AS desfase) AS h;

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
    SET codigo_1 = p1.codigo_fifa, codigo_2 = p2.codigo_fifa
    FROM #staging_partidos AS st
    LEFT JOIN Torneo.SELECCION AS s1 ON s1.id_seleccion = st.id_seleccion_1
    LEFT JOIN DatosGenerales.PAIS AS p1 ON p1.id_pais = s1.id_pais
    LEFT JOIN Torneo.SELECCION AS s2 ON s2.id_seleccion = st.id_seleccion_2
    LEFT JOIN DatosGenerales.PAIS AS p2 ON p2.id_pais = s2.id_pais;

    -- Sede: la que tiene su ciudad (lo que está antes del paréntesis) o su nombre en el texto del archivo.
    UPDATE st
    SET id_sede = x.id_sede, sedes_posibles = x.sedes
    FROM #staging_partidos AS st
    CROSS APPLY (SELECT MAX(s.id_sede) AS id_sede, COUNT(*) AS sedes
                 FROM Torneo.SEDE AS s
                 WHERE CHARINDEX(LEFT(s.ciudad, CHARINDEX(' (', s.ciudad + ' (') - 1), st.estadio_txt) > 0
                    OR CHARINDEX(s.nombre_estadio, st.estadio_txt) > 0) AS x;

    UPDATE st
    SET nombre_estadio = s.nombre_estadio, capacidad = s.capacidad
    FROM #staging_partidos AS st
    INNER JOIN Torneo.SEDE AS s ON s.id_sede = st.id_sede
    WHERE st.sedes_posibles = 1;

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

    UPDATE st SET id_partido = p.id_partido
    FROM #staging_partidos AS st INNER JOIN Torneo.PARTIDO AS p ON p.numero_partido = st.numero_partido;

    /* 3. Validaciones, con las reglas de usp_ImportarPartidos. */
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
            IIF(st.id_seleccion_1 = st.id_seleccion_2, @nl + N'- La selección local y la visitante son la misma.', NULL),
            IIF(st.fase = 'GRUPOS'
                AND (st.id_seleccion_1 IS NULL OR st.id_seleccion_2 IS NULL
                     OR NOT EXISTS (SELECT 1 FROM Torneo.SELECCION AS s1
                                    INNER JOIN Torneo.SELECCION AS s2 ON s2.grupo = s1.grupo
                                    WHERE s1.id_seleccion = st.id_seleccion_1 AND s2.id_seleccion = st.id_seleccion_2)),
                @nl + N'- En la fase de grupos tienen que estar las dos selecciones y ser del mismo grupo.', NULL),
            CASE WHEN st.estadio_txt IS NULL THEN @nl + N'- El estadio es obligatorio.'
                 WHEN st.sedes_posibles = 0  THEN @nl + N'- El estadio "' + st.estadio_txt + N'" no corresponde a ninguna sede registrada.'
                 WHEN st.sedes_posibles > 1  THEN @nl + N'- El estadio "' + st.estadio_txt + N'" puede ser más de una sede.'
            END,
            IIF((st.ft_1 IS NOT NULL OR st.ft_2 IS NOT NULL OR st.et_1 IS NOT NULL OR st.et_2 IS NOT NULL)
                AND (st.goles_1 IS NULL OR st.goles_2 IS NULL),
                @nl + N'- El resultado no tiene los goles de las dos selecciones (o no son números).', NULL),
            IIF((st.pen_1 IS NOT NULL OR st.pen_2 IS NOT NULL) AND (st.penales_1 IS NULL OR st.penales_2 IS NULL),
                @nl + N'- Los penales no son de las dos selecciones (o no son números).', NULL),
            IIF(st.penales_1 IS NOT NULL
                AND (st.fase = 'GRUPOS' OR st.goles_1 <> st.goles_2 OR st.penales_1 = st.penales_2),
                @nl + N'- Hay penales solo en eliminación directa, con empate en goles, y no pueden terminar empatados.', NULL),
            IIF(st.fase <> 'GRUPOS' AND st.goles_1 = st.goles_2 AND st.penales_1 IS NULL,
                @nl + N'- Un empate de eliminación directa se define por penales y el archivo no los trae.', NULL),
            IIF(st.goles_1 IS NOT NULL AND (st.id_seleccion_1 IS NULL OR st.id_seleccion_2 IS NULL),
                @nl + N'- Un partido con resultado tiene que tener las dos selecciones.', NULL),
            -- usp_ImportarPartidos no reprograma un partido ya jugado: se rechaza en vez de ignorar el cambio.
            IIF(EXISTS (SELECT 1 FROM Torneo.PARTIDO AS p
                        WHERE p.id_partido = st.id_partido AND p.estado NOT IN ('PROGRAMADO', 'SUSPENDIDO')
                          AND (ISNULL(p.id_seleccion_local, 0) <> ISNULL(st.id_seleccion_1, 0)
                               OR ISNULL(p.id_seleccion_visitante, 0) <> ISNULL(st.id_seleccion_2, 0)
                               OR p.id_sede <> ISNULL(st.id_sede, 0) OR p.fecha_hora_utc <> ISNULL(st.fecha_hora_utc, '19000101'))),
                @nl + N'- El partido ' + CAST(st.numero_partido AS NVARCHAR(3)) + N' ya se jugó con otras selecciones, '
                    + N'sede o fecha: no se puede cambiar.', NULL),
            IIF(st.asistencia_txt IS NOT NULL AND (st.asistencia IS NULL OR st.asistencia < 0 OR st.asistencia > st.capacidad),
                @nl + N'- La asistencia "' + st.asistencia_txt + N'" no es un número entre 0 y la capacidad de la sede.', NULL),
            IIF(EXISTS (SELECT 1 FROM DesarrolloPartido.fn_MarcadorSegunGoles(st.id_partido) AS m
                        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = st.id_partido
                        WHERE st.goles_1 IS NOT NULL AND m.goles_registrados > m.penales_registrados
                          AND (st.goles_1 <> ISNULL(p.goles_local, 255) OR st.goles_2 <> ISNULL(p.goles_visitante, 255))
                          AND (st.goles_1 <> m.goles_local OR st.goles_2 <> m.goles_visitante)),
                @nl + N'- El resultado cambia y no coincide con los goles ya cargados del partido.', NULL)), N'')
    FROM #staging_partidos AS st;

    -- El fixture como quedaría con los partidos válidos: ninguna selección juega dos partidos
    -- a menos de 24 horas y ninguna sede tiene dos partidos el mismo día.
    WITH fixture AS (
        SELECT numero_partido, id_sede, fecha_hora_utc, fecha_hora_local, id_seleccion_1 AS id_local,
               id_seleccion_2 AS id_visitante
        FROM #staging_partidos
        WHERE errores IS NULL
        UNION ALL
        SELECT p.numero_partido, p.id_sede, p.fecha_hora_utc, p.fecha_hora_local, p.id_seleccion_local,
               p.id_seleccion_visitante
        FROM Torneo.PARTIDO AS p
        WHERE NOT EXISTS (SELECT 1 FROM #staging_partidos AS st
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
    WHERE st.errores IS NULL
      AND EXISTS (SELECT 1 FROM conflictos AS c WHERE c.numero_partido = st.numero_partido);

    UPDATE #staging_partidos SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. Carga de los partidos válidos, todos juntos, con el SP de la Entrega 5. */
    INSERT INTO @partidos (numero_partido, nombre_estadio, fase, fecha_hora_utc, codigo_fifa_local, codigo_fifa_visitante,
                           goles_local, goles_visitante, penales_local, penales_visitante, asistencia)
    SELECT numero_partido, nombre_estadio, fase, fecha_hora_utc, codigo_1, codigo_2,
           goles_1, goles_2, penales_1, penales_2, asistencia
    FROM #staging_partidos
    WHERE accion IS NULL;

    IF EXISTS (SELECT 1 FROM @partidos)
        EXEC Torneo.usp_ImportarPartidos
            @partidos = @partidos, @insertados = @insertados OUTPUT,
            @actualizados = @actualizados OUTPUT, @sin_cambios = @sin_cambios OUTPUT;

    /* 2 a 4 para lo que pasó en cada partido válido. */
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
        es_titular          BIT           NULL,
        de_penal            BIT           NULL,
        en_contra           BIT           NULL,
        marcador_1          TINYINT       NULL,
        -- Convertidos
        codigo_fifa         VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
        id_jugador          INT           NULL,
        id_jugador_entra    INT           NULL,
        minuto              TINYINT       NULL,
        minuto_adicional    TINYINT       NULL,
        periodo             VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL,
        tipo_gol            VARCHAR(40)   COLLATE DATABASE_DEFAULT NULL,
        tipo_tarjeta        VARCHAR(8)    COLLATE DATABASE_DEFAULT NULL,
        es_doble_amarilla   BIT           NULL,
        errores             NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion              VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    -- Formaciones: titulares y suplentes de cada selección (lineup[0] es team1).
    INSERT INTO #staging_eventos (tipo, id_registro, numero_partido, lado, orden, nombre_txt, es_titular)
    SELECT 'FORMACION', st.id_registro, st.numero_partido, CAST(l.[key] AS INT) + 1, CAST(j.[key] AS INT) + 1,
           NULLIF(TRIM(JSON_VALUE(j.value, N'$.name')), N''), 1
    FROM #staging_partidos AS st
    CROSS APPLY OPENJSON(st.detalle, N'$.lineup') AS l
    CROSS APPLY OPENJSON(l.value, N'$.starter') AS j
    WHERE st.accion IS NULL AND l.[key] IN (N'0', N'1')
    UNION ALL
    SELECT 'FORMACION', st.id_registro, st.numero_partido, CAST(l.[key] AS INT) + 1, 100 + CAST(j.[key] AS INT) + 1,
           NULLIF(TRIM(JSON_VALUE(j.value, N'$.name')), N''), 0
    FROM #staging_partidos AS st
    CROSS APPLY OPENJSON(st.detalle, N'$.lineup') AS l
    CROSS APPLY OPENJSON(l.value, N'$.bench') AS j
    WHERE st.accion IS NULL AND l.[key] IN (N'0', N'1');

    -- Cambios.
    INSERT INTO #staging_eventos (tipo, id_registro, numero_partido, lado, orden, nombre_txt, nombre_entra_txt, minuto_txt)
    SELECT 'CAMBIO', st.id_registro, st.numero_partido, CAST(l.[key] AS INT) + 1, CAST(c.[key] AS INT) + 1,
           NULLIF(TRIM(d.sale), N''), NULLIF(TRIM(d.entra), N''), NULLIF(TRIM(d.minuto), N'')
    FROM #staging_partidos AS st
    CROSS APPLY OPENJSON(st.detalle, N'$.lineup') AS l
    CROSS APPLY OPENJSON(l.value, N'$.subs') AS c
    CROSS APPLY OPENJSON(c.value)
        WITH (sale NVARCHAR(200) '$.off', entra NVARCHAR(200) '$.on', minuto NVARCHAR(20) '$.minute') AS d
    WHERE st.accion IS NULL AND l.[key] IN (N'0', N'1');

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
    WHERE st.accion IS NULL;

    -- Penales convertidos en la definición: el equipo sale de cómo cambia el marcador.
    WITH penales AS (
        SELECT st.id_registro, st.numero_partido, CAST(p.[key] AS INT) + 1 AS orden, NULLIF(TRIM(d.nombre), N'') AS nombre,
               d.marcador_1,
               LAG(d.marcador_1, 1, 0) OVER (PARTITION BY st.id_registro ORDER BY CAST(p.[key] AS INT)) AS marcador_1_antes
        FROM #staging_partidos AS st
        CROSS APPLY OPENJSON(st.detalle, N'$.penalties') AS p
        CROSS APPLY OPENJSON(p.value) WITH (nombre NVARCHAR(200) '$.name', marcador_1 TINYINT '$.score[0]') AS d
        WHERE st.accion IS NULL AND d.marcador_1 IS NOT NULL
    )
    INSERT INTO #staging_eventos (tipo, id_registro, numero_partido, lado, orden, nombre_txt, marcador_1)
    SELECT 'PENAL', id_registro, numero_partido, IIF(marcador_1 > marcador_1_antes, 1, 2), orden, nombre, marcador_1
    FROM penales;

    -- Tarjetas: bookings[0] son las de team1. Y/R se registra como amarilla y como roja por doble amarilla.
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
    WHERE st.accion IS NULL AND b.[key] IN (N'0', N'1');

    -- Selección del jugador y minuto ("45+2": minuto 45 y 2 de adicional).
    UPDATE e
    SET codigo_fifa      = IIF(e.lado = 1, st.codigo_1, st.codigo_2),
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
    CREATE TABLE #nombres_fuente (
        id_nombre      INT IDENTITY(1,1) PRIMARY KEY,
        codigo_fifa    VARCHAR(10)    COLLATE DATABASE_DEFAULT NOT NULL,
        nombre_fuente  NVARCHAR(200)  COLLATE DATABASE_DEFAULT NOT NULL,
        id_jugador     INT            NULL,
        paso           TINYINT        NULL,
        error          NVARCHAR(1000) COLLATE DATABASE_DEFAULT NULL
    );

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

    -- Lo que sale de cada dato, con las reglas de usp_ImportarDesarrolloPartidos.
    UPDATE e
    SET periodo  = CASE WHEN e.tipo = 'PENAL'              THEN 'PENALES'
                        WHEN e.minuto_adicional > 0        THEN 'ADICIONALES'
                        WHEN e.minuto BETWEEN 1 AND 45     THEN 'PRIMER_TIEMPO'
                        WHEN e.minuto BETWEEN 46 AND 90    THEN 'SEGUNDO_TIEMPO'
                        WHEN e.minuto BETWEEN 91 AND 120   THEN 'ALARGUE'
                   END,
        tipo_gol = CASE WHEN e.en_contra = 1 THEN 'EN CONTRA'
                        WHEN e.de_penal = 1 OR e.tipo = 'PENAL' THEN 'PENAL'
                        ELSE 'JUGADA'
                   END
    FROM #staging_eventos AS e
    WHERE e.tipo IN ('GOL', 'PENAL');

    UPDATE #staging_eventos
    SET errores = NULLIF(CONCAT(errores,
            CASE WHEN tipo IN ('CAMBIO', 'GOL', 'TARJETA') AND minuto_txt IS NULL
                     THEN @nl + N'- Falta el minuto.'
                 WHEN tipo IN ('CAMBIO', 'GOL', 'TARJETA') AND (minuto IS NULL OR minuto_adicional IS NULL)
                     THEN @nl + N'- El minuto "' + minuto_txt + N'" no es un número (o número+adicional).'
                 WHEN tipo = 'CAMBIO' AND (minuto NOT BETWEEN 1 AND 120 OR minuto_adicional > 30)
                     THEN @nl + N'- El minuto de un cambio va del 1 al 120, con hasta 30 de adicional.'
                 WHEN tipo = 'TARJETA' AND (minuto > 120 OR minuto_adicional > 30)
                     THEN @nl + N'- El minuto de una tarjeta va del 0 al 120, con hasta 30 de adicional.'
                 WHEN tipo = 'GOL' AND (periodo IS NULL OR minuto_adicional > 30
                                        OR (periodo = 'ADICIONALES' AND minuto NOT IN (45, 90, 105, 120)))
                     THEN @nl + N'- El minuto "' + minuto_txt + N'" no corresponde a ningún período '
                              + N'(1 a 120; los adicionales, después del 45, 90, 105 o 120).'
            END,
            IIF(tipo = 'CAMBIO' AND id_jugador = id_jugador_entra, @nl + N'- Sale y entra el mismo jugador.', NULL),
            IIF(tipo = 'TARJETA' AND tipo_tarjeta IS NULL,
                @nl + N'- La tarjeta "' + ISNULL(tipo_txt, N'') + N'" no es Y, R ni Y/R.', NULL)), N'');

    -- Formaciones: un jugador una sola vez, y cada formación tiene que quedar con
    -- 11 titulares (los ya cargados más los nuevos).
    UPDATE e
    SET errores = CONCAT(e.errores, @nl, N'- El jugador figura más de una vez en la formación.')
    FROM #staging_eventos AS e
    WHERE e.tipo = 'FORMACION' AND e.id_jugador IS NOT NULL
      AND EXISTS (SELECT 1 FROM #staging_eventos AS o
                  WHERE o.tipo = 'FORMACION' AND o.numero_partido = e.numero_partido
                    AND o.id_jugador = e.id_jugador AND o.id_evento <> e.id_evento);

    WITH formaciones AS (
        SELECT e.numero_partido, e.lado,
               SUM(IIF(e.es_titular = 1 AND e.errores IS NULL AND ya.alineado IS NULL, 1, 0))
               + MAX(cargados.titulares) AS titulares
        FROM #staging_eventos AS e
        INNER JOIN #staging_partidos AS st ON st.id_registro = e.id_registro
        CROSS APPLY (SELECT COUNT(*) AS titulares
                     FROM DesarrolloPartido.ALINEACION AS al
                     INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = al.id_formacion
                     INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                     WHERE p.numero_partido = e.numero_partido AND al.es_titular = 1
                       AND f.id_seleccion = IIF(e.lado = 1, st.id_seleccion_1, st.id_seleccion_2)) AS cargados
        OUTER APPLY (SELECT TOP (1) 1 AS alineado
                     FROM DesarrolloPartido.ALINEACION AS al
                     INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = al.id_formacion
                     INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                     WHERE p.numero_partido = e.numero_partido AND al.id_jugador = e.id_jugador) AS ya
        WHERE e.tipo = 'FORMACION'
        GROUP BY e.numero_partido, e.lado
    )
    UPDATE e
    SET errores = CONCAT(e.errores, @nl, N'- La formación de la selección quedaría con ', f.titulares,
                         N' titulares reconocidos y tienen que ser 11: no se carga ningún jugador de esa formación.')
    FROM #staging_eventos AS e
    INNER JOIN formaciones AS f ON f.numero_partido = e.numero_partido AND f.lado = e.lado
    WHERE e.tipo = 'FORMACION' AND f.titulares <> 11;

    -- Cambios, goles, penales y tarjetas: el jugador tiene que estar en la formación del partido.
    UPDATE e
    SET errores = CONCAT(e.errores, @nl, N'- El jugador no está en la formación del partido (o se rechazó).')
    FROM #staging_eventos AS e
    WHERE e.tipo <> 'FORMACION'
      AND EXISTS (SELECT 1 FROM (VALUES (e.id_jugador), (e.id_jugador_entra)) AS j (id_jugador)
                  WHERE j.id_jugador IS NOT NULL
                    AND NOT EXISTS (SELECT 1 FROM #staging_eventos AS f
                                    WHERE f.tipo = 'FORMACION' AND f.errores IS NULL
                                      AND f.numero_partido = e.numero_partido AND f.id_jugador = j.id_jugador)
                    AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS a
                                    INNER JOIN DesarrolloPartido.FORMACION AS fo ON fo.id_formacion = a.id_formacion
                                    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = fo.id_partido
                                    WHERE p.numero_partido = e.numero_partido AND a.id_jugador = j.id_jugador));

    -- Cada jugador sale y entra una sola vez por partido, contando los cambios ya cargados.
    WITH cambios AS (
        SELECT numero_partido, id_jugador, id_jugador_entra
        FROM #staging_eventos
        WHERE tipo = 'CAMBIO' AND errores IS NULL
        UNION ALL
        SELECT p.numero_partido, ca.id_jugador_sale, ca.id_jugador_entra
        FROM DesarrolloPartido.CAMBIO AS ca
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = ca.id_partido
        WHERE NOT EXISTS (SELECT 1 FROM #staging_eventos AS e
                          WHERE e.tipo = 'CAMBIO' AND e.errores IS NULL AND e.numero_partido = p.numero_partido
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
    SET errores = CONCAT(e.errores, @nl, N'- Un jugador de este cambio sale o entra más de una vez en el partido.')
    FROM #staging_eventos AS e
    WHERE e.tipo = 'CAMBIO' AND e.errores IS NULL
      AND EXISTS (SELECT 1 FROM repetidos AS r
                  WHERE r.numero_partido = e.numero_partido
                    AND ((r.tipo = 'S' AND r.id_jugador = e.id_jugador) OR (r.tipo = 'E' AND r.id_jugador = e.id_jugador_entra)));

    UPDATE #staging_eventos SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

    /* 4. Carga de los eventos válidos, todos juntos, con el SP de la Entrega 5. */
    INSERT INTO @alineaciones (numero_partido, id_jugador, es_titular, posicion_en_cancha)
    SELECT e.numero_partido, e.id_jugador, e.es_titular, IIF(e.es_titular = 1, j.posicion_habitual, NULL)
    FROM #staging_eventos AS e
    INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = e.id_jugador
    WHERE e.tipo = 'FORMACION' AND e.accion IS NULL;

    INSERT INTO @cambios (numero_partido, id_jugador_sale, id_jugador_entra, minuto, minuto_adicional, en_entretiempo, motivo)
    SELECT numero_partido, id_jugador, id_jugador_entra, minuto, minuto_adicional,
           IIF(minuto IN (46, 91, 106) AND minuto_adicional = 0, 1, 0), 'TACTICO'
    FROM #staging_eventos
    WHERE tipo = 'CAMBIO' AND accion IS NULL;

    INSERT INTO @goles (numero_partido, id_jugador_autor, tipo_gol, periodo, minuto, minuto_adicional)
    SELECT numero_partido, id_jugador, tipo_gol, periodo, IIF(tipo = 'PENAL', NULL, minuto), ISNULL(minuto_adicional, 0)
    FROM #staging_eventos
    WHERE tipo IN ('GOL', 'PENAL') AND accion IS NULL;

    INSERT INTO @amonestaciones (numero_partido, id_jugador, tipo_tarjeta, es_doble_amarilla, minuto, minuto_adicional, motivo)
    SELECT numero_partido, id_jugador, tipo_tarjeta, es_doble_amarilla, minuto, minuto_adicional, 'Sin detalle en la fuente'
    FROM #staging_eventos
    WHERE tipo = 'TARJETA' AND accion IS NULL;

    IF EXISTS (SELECT 1 FROM #staging_eventos WHERE accion IS NULL)
        EXEC DesarrolloPartido.usp_ImportarDesarrolloPartidos
            @alineaciones = @alineaciones, @cambios = @cambios, @goles = @goles, @amonestaciones = @amonestaciones,
            @insertados = @eventos_insertados OUTPUT, @sin_cambios = @eventos_sin_cambios OUTPUT;

    /* 5. Resultado. */
    SELECT N'Partidos' AS registros, COUNT(*) AS leidos, @insertados AS insertados, @actualizados AS actualizados,
           @sin_cambios AS sin_cambios, ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0) AS rechazados
    FROM #staging_partidos
    UNION ALL
    SELECT N'Formaciones, cambios, goles, penales y tarjetas', COUNT(*), @eventos_insertados, 0,
           @eventos_sin_cambios, ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
    FROM #staging_eventos;

    SELECT tipo, COUNT(*) AS leidos, SUM(IIF(accion = 'RECHAZADO', 1, 0)) AS rechazados
    FROM #staging_eventos
    GROUP BY tipo
    ORDER BY tipo;

    SELECT CONCAT(N'Registro ', id_registro, N': ', ISNULL(fecha_txt, N''), N' ', ISNULL(equipo_1, N'?'), N' - ',
                  ISNULL(equipo_2, N'?')) AS rechazado,
           STUFF(errores, 1, 2, N'') AS motivos
    FROM #staging_partidos
    WHERE accion = 'RECHAZADO'
    ORDER BY id_registro;

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
    WHERE st.accion IS NULL
      AND (p.goles_local <> m.goles_local OR p.goles_visitante <> m.goles_visitante
           OR ISNULL(p.penales_local, 0) <> m.penales_local OR ISNULL(p.penales_visitante, 0) <> m.penales_visitante)
    ORDER BY p.numero_partido;
END;
GO


-- Evidencia: objetos de la importación del Mundial 2026 creados.
SELECT s.name AS esquema, o.name AS objeto, o.type_desc AS tipo
FROM sys.objects AS o
INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE o.name IN (N'usp_LeerArchivoUTF8', N'fn_ClaveNombre', N'fn_CoordenadaDecimal', N'usp_IdentificarJugadores',
                 N'usp_ImportarSedesJSON', N'usp_ImportarSeleccionesJSON', N'usp_ImportarPartidosJSON')
ORDER BY o.type_desc, o.name;
GO
