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
 Archivo: 17_SP_Utilidades_Importacion.sql
 Objetivo: Crear las utilidades que comparten los procesos de importación
           (18 a 24). No dependen de ninguna fuente en particular:
             DatosGenerales.usp_ConsumirAPI      hace un pedido GET a una URL https
             DatosGenerales.usp_LeerArchivoUTF8  lee un archivo de texto UTF-8
             Torneo.fn_ClaveNombre               nombre sin separadores, para compararlo
             Torneo.usp_IdentificarJugadores     reconoce a un jugador por cómo lo escribe la fuente
           usp_ConsumirAPI lo usan las importaciones que consultan una API
           (Dossier, Banco Mundial, Frankfurter y Nager.Date); las otras tres,
           las que leen los archivos de openfootball y los CSV del scraping.
           Requiere haber ejecutado 01 a 16. Su script de testing es
           67_Test_SP_Utilidades_Importacion.sql.
================================================================================

 SQL Server 2022 (el motor de la Entrega 4) no tiene un procedimiento propio
 para llamar a una API REST (sp_invoke_external_rest_endpoint recién está en
 SQL Server 2025). Por eso se usa OLE Automation con MSXML2.ServerXMLHTTP,
 que corre dentro del motor y no necesita CLR.

 OLE Automation: requiere la opción de instancia 'Ole Automation Procedures',
 que viene deshabilitada. Quien consulta una API la habilita solo mientras
 llama a este SP y después la deja como estaba, como hace
 30_Importar_Indicadores.sql. Hace falta ser sysadmin.

 usp_LeerArchivoUTF8 usa SQL dinámico porque OPENROWSET(BULK) no acepta la
 ruta del archivo en una variable.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   CONSUMO DE APIS
   ============================================================================ */

/*
  usp_ConsumirAPI
  Hace un pedido GET a @url y devuelve el código HTTP y el cuerpo de la
  respuesta como texto. Sirve para cualquier API REST que no pida
  autenticación. Valida: URL obligatoria y https, y OLE Automation habilitado
  en la instancia. Si el pedido no se puede hacer (sin conexión, servidor
  inexistente, tiempo agotado), lanza el error 50002 con el motivo que
  informa MSXML.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ConsumirAPI
    @url          NVARCHAR(2000),
    @estado_http  SMALLINT      = NULL OUTPUT,
    @respuesta    NVARCHAR(MAX) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    -- sp_OAGetProperty corta el texto en @@TEXTSIZE bytes (sqlcmd usa 4096). Vuelve a su valor al salir.
    SET TEXTSIZE 2147483647;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @http         INT;
    DECLARE @hr           INT;
    DECLARE @estado       INT;
    DECLARE @paso         NVARCHAR(50);
    DECLARE @fuente       NVARCHAR(255);
    DECLARE @descripcion  NVARCHAR(2000);
    DECLARE @blancos      NCHAR(3)       = NCHAR(13) + NCHAR(10) + N' ';
    DECLARE @texto        TABLE (texto NVARCHAR(MAX));

    SET @url = NULLIF(TRIM(@url), N'');

    IF @url IS NULL
        SET @errores += @nl + N'- La URL es obligatoria.';
    ELSE IF @url NOT LIKE N'https://%'
        SET @errores += @nl + N'- La URL tiene que empezar con https://.';

    IF NOT EXISTS (SELECT 1 FROM sys.configurations
                   WHERE name = N'Ole Automation Procedures' AND value_in_use = 1)
        SET @errores += @nl + N'- La instancia no tiene habilitada la opción ''Ole Automation Procedures'', '
                      + N'que se usa para llamar a la API (ver 17_SP_Utilidades_Importacion.sql).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_ConsumirAPI: no se pudo consultar la API.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Pedido sincrónico. Cada paso devuelve un HRESULT (0 es éxito); si uno falla, no se sigue.
    SET @paso = N'crear el objeto MSXML2.ServerXMLHTTP';
    EXEC @hr = sp_OACreate 'MSXML2.ServerXMLHTTP.6.0', @http OUTPUT;
    IF @hr = 0
    BEGIN
        -- Tiempos máximos en milisegundos: resolver el nombre, conectar, enviar y recibir.
        SET @paso = N'configurar los tiempos de espera';
        EXEC @hr = sp_OAMethod @http, 'setTimeouts', NULL, 10000, 10000, 10000, 60000;
    END;
    IF @hr = 0
    BEGIN
        SET @paso = N'abrir el pedido';
        EXEC @hr = sp_OAMethod @http, 'open', NULL, 'GET', @url, 'false';
    END;
    IF @hr = 0
    BEGIN
        SET @paso = N'enviar el pedido';
        EXEC @hr = sp_OAMethod @http, 'send';
    END;
    IF @hr = 0
    BEGIN
        SET @paso = N'leer el código de la respuesta';
        EXEC @hr = sp_OAGetProperty @http, 'status', @estado OUTPUT;
    END;
    IF @hr = 0
    BEGIN
        -- Como conjunto de resultados y no como OUTPUT, que no admite más de 4000 caracteres.
        SET @paso = N'leer la respuesta';
        INSERT INTO @texto (texto)
        EXEC @hr = sp_OAGetProperty @http, 'responseText';
    END;

    IF @hr <> 0
        EXEC sp_OAGetErrorInfo @http, @fuente OUTPUT, @descripcion OUTPUT;
    IF @http IS NOT NULL
        EXEC sp_OADestroy @http;

    IF @hr <> 0
    BEGIN
        SET @errores = N'DatosGenerales.usp_ConsumirAPI: no se pudo ' + @paso + N' ('
                     + ISNULL(TRIM(@blancos FROM @descripcion),
                              N'HRESULT ' + CONVERT(NVARCHAR(20), CONVERT(VARBINARY(4), @hr), 1))
                     + N').';
        THROW 50002, @errores, 1;
    END;

    SET @estado_http = @estado;
    SELECT @respuesta = texto FROM @texto;
END;
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


-- Evidencia: objetos creados.
SELECT s.name AS esquema, o.name AS objeto, o.type_desc AS tipo, o.modify_date AS ultima_modificacion
FROM sys.objects AS o
INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE s.name + N'.' + o.name IN (N'DatosGenerales.usp_ConsumirAPI', N'DatosGenerales.usp_LeerArchivoUTF8',
                                 N'Torneo.fn_ClaveNombre', N'Torneo.usp_IdentificarJugadores')
ORDER BY o.name;
GO
