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
 Objetivo: Crear lo que comparten los procesos de importación (18 a 24). No
           dependen de ninguna fuente en particular:
             DatosGenerales.usp_RegistrarImportacion  registra una importación y devuelve su número
             DatosGenerales.usp_BorrarImportacion     la borra, con sus registros rechazados
             DatosGenerales.usp_ConsumirAPI           hace un pedido GET a una URL https
             DatosGenerales.usp_LeerArchivoUTF8       lee un archivo de texto UTF-8
             Torneo.fn_NormalizarNombre               nombre sin separadores, para compararlo
             Torneo.usp_IdentificarJugadores          reconoce a un jugador por cómo lo escribe la fuente
           usp_ConsumirAPI lo usan las importaciones que consultan una API
           (Dossier, Banco Mundial, Frankfurter y Nager.Date); las tres
           últimas, las que leen los archivos de openfootball y los CSV del
           scraping.
           Requiere haber ejecutado 01 a 15. Su script de testing es
           67_Test_SP_Utilidades_Importacion.sql.
================================================================================

 Cómo importa cada proceso (18 a 23). Cada archivo tiene, uno debajo del
 otro, el SP de carga masiva del dataset (usp_Cargar...) y el SP que lee la
 fuente y lo llama (usp_Importar... o usp_Procesar...):
   1. El proceso lee el archivo o la API a una tabla temporal con el nombre
      que espera el SP de carga (#staging_sedes, por ejemplo), convierte los
      datos y marca accion = 'RECHAZADO', con el motivo en errores, los
      registros que no pudo convertir (u 'OMITIDO' los que el sistema no usa).
   2. Llama al SP de carga, que no recibe los datos por parámetro: un SP ve
      las tablas temporales del que lo llama. El SP valida todos juntos los
      registros con accion NULL, anota en errores los motivos de cada uno y
      los marca RECHAZADO; carga los demás, todos juntos, y los marca
      INSERTADO, ACTUALIZADO o SIN CAMBIOS.
   3. El proceso registra la importación (usp_RegistrarImportacion) y guarda
      los rechazados en la tabla ERRORES_ de lo que importó.
   Las reglas de cada tabla están una sola vez, en el SP de carga; el proceso
   solo rechaza lo que no puede convertir. Así se importan los registros
   válidos y se informan los errores de los demás. No se usa un parámetro de
   tipo tabla porque es de solo lectura: el SP no podría marcar los registros.
   33_Cargar_DatosComplementarios.sql y 34_Cargar_SedesAdicionales.sql usan
   los mismos SP de carga, con tablas que arman a mano.

 Dónde está cada SP de carga y qué tabla lee:
   SP                                              archivo  staging                 clave natural
   Torneo.usp_CargarSedes                          18       #staging_sedes          nombre del estadio
   Torneo.usp_CargarSelecciones                    18       #staging_selecciones    código FIFA del país
   Torneo.usp_CargarPartidos                       18       #staging_partidos       número de partido
   DesarrolloPartido.usp_CargarDesarrolloPartidos  18       #staging_eventos        lo que pasó en cada partido
   Arbitraje.usp_CargarArbitros                    18       #staging_arbitros       país + apellido + nombre
   Arbitraje.usp_CargarDesignaciones               18       #staging_designaciones  número de partido + árbitro
   Torneo.usp_CargarJugadores                      19       #staging_jugadores      selección + apellido + nombre
   Torneo.usp_CargarCuerpoTecnico                  19       #staging_cuerpo_tecnico selección + apellido + nombre
   Publicidad.usp_CargarCampanias                  20       #staging_campanias      anunciante + nombre de la campaña
                                                            y #staging_piezas       (y título de cada pieza)
   DatosGenerales.usp_CargarIndicadoresEconomicos  21       #staging_indicadores    país (ISO alfa-3) + indicador + año
   DatosGenerales.usp_CargarCotizaciones           22       #staging_cotizaciones   moneda + fecha
   DatosGenerales.usp_CargarFeriados               23       #staging_feriados       país + fecha
 Con la misma forma de trabajo, entre los SP de negocio (los usa el 33):
   Torneo.usp_CargarReemplazos                     11       #staging_reemplazos     selección + jugador que sale
   Arbitraje.usp_CargarInformesArbitrales          14       #staging_informes       número de partido + rol

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

 Criterios comunes de los SP de carga:
   - Importar dos veces lo mismo no duplica nada: si el registro existe y no
     cambió, no se modifica (SIN CAMBIOS).
   - Un dato que no viene (NULL) no borra el valor guardado, así se conserva
     la información histórica ya registrada.
   - Las traducciones de valores de las fuentes (fases y posiciones en
     inglés, por ejemplo) se hacen en T-SQL.
   - Una regla que depende de todo el conjunto (cupo de un grupo, tamaño de
     una lista de convocados, partidos a menos de 24 horas) se evalúa con
     los registros válidos y rechaza a los que la rompen.
   - La carga es una transacción. Si el que llama ya tiene una abierta, se
     hace dentro de esa.

 SQL Server 2022 no tiene un procedimiento propio
 para llamar a una API REST (sp_invoke_external_rest_endpoint recién está en
 SQL Server 2025). Por eso se usa OLE Automation con MSXML2.ServerXMLHTTP,
 que corre dentro del motor y no necesita CLR.

 OLE Automation: requiere la opción de instancia 'Ole Automation Procedures',
 que viene deshabilitada. Quien consulta una API la habilita solo mientras
 llama a este SP y después la deja como estaba, como hace
 31_Importar_APIs.sql. Hace falta ser sysadmin.

 usp_LeerArchivoUTF8 usa SQL dinámico porque OPENROWSET(BULK) no acepta la
 ruta del archivo en una variable.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @proceso = NULLIF(TRIM(@proceso), '');
    SET @origen  = NULLIF(TRIM(@origen), N'');

    IF @proceso IS NULL
        SET @errores += @salto_linea + N'- El proceso es obligatorio.';
    IF @origen IS NULL
        SET @errores += @salto_linea + N'- El origen (archivo o URL) es obligatorio.';

    IF @leidos IS NULL OR @insertados IS NULL OR @actualizados IS NULL OR @sin_cambios IS NULL
       OR @omitidos IS NULL OR @rechazados IS NULL
        SET @errores += @salto_linea + N'- Los totales son obligatorios.';
    ELSE IF @leidos < 0 OR @insertados < 0 OR @actualizados < 0 OR @sin_cambios < 0 OR @omitidos < 0 OR @rechazados < 0
        SET @errores += @salto_linea + N'- Los totales no pueden ser negativos.';
    ELSE IF @omitidos + @rechazados > @leidos
        SET @errores += @salto_linea + N'- Los omitidos y los rechazados no pueden ser más que los leídos.';

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
        DELETE e FROM Torneo.ERRORES_CUERPO_TECNICO AS e
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

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @http        INT;
    DECLARE @hresult INT;
    DECLARE @estado      INT;
    DECLARE @paso        NVARCHAR(50);
    DECLARE @fuente      NVARCHAR(255);
    DECLARE @descripcion NVARCHAR(2000);
    DECLARE @blancos     NCHAR(3)       = NCHAR(13) + NCHAR(10) + N' ';
    DECLARE @texto       TABLE (texto NVARCHAR(MAX));

    SET @url = NULLIF(TRIM(@url), N'');

    IF @url IS NULL
        SET @errores += @salto_linea + N'- La URL es obligatoria.';
    ELSE IF @url NOT LIKE N'https://%'
        SET @errores += @salto_linea + N'- La URL tiene que empezar con https://.';

    IF NOT EXISTS (SELECT 1 FROM sys.configurations
                   WHERE name = N'Ole Automation Procedures' AND value_in_use = 1)
        SET @errores += @salto_linea + N'- La instancia no tiene habilitada la opción ''Ole Automation Procedures'', '
                      + N'que se usa para llamar a la API (ver 17_SP_Utilidades_Importacion.sql).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DatosGenerales.usp_ConsumirAPI: no se pudo consultar la API.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Pedido sincrónico. Cada paso devuelve un HRESULT (0 es éxito); si uno falla, no se sigue.
    SET @paso = N'crear el objeto MSXML2.ServerXMLHTTP';
    EXEC @hresult = sp_OACreate 'MSXML2.ServerXMLHTTP.6.0', @http OUTPUT;
    IF @hresult = 0
    BEGIN
        -- Tiempos máximos en milisegundos: resolver el nombre, conectar, enviar y recibir.
        SET @paso = N'configurar los tiempos de espera';
        EXEC @hresult = sp_OAMethod @http, 'setTimeouts', NULL, 10000, 10000, 10000, 60000;
    END;
    IF @hresult = 0
    BEGIN
        SET @paso = N'abrir el pedido';
        EXEC @hresult = sp_OAMethod @http, 'open', NULL, 'GET', @url, 'false';
    END;
    IF @hresult = 0
    BEGIN
        SET @paso = N'enviar el pedido';
        EXEC @hresult = sp_OAMethod @http, 'send';
    END;
    IF @hresult = 0
    BEGIN
        SET @paso = N'leer el código de la respuesta';
        EXEC @hresult = sp_OAGetProperty @http, 'status', @estado OUTPUT;
    END;
    IF @hresult = 0
    BEGIN
        -- Como conjunto de resultados y no como OUTPUT, que no admite más de 4000 caracteres.
        SET @paso = N'leer la respuesta';
        INSERT INTO @texto (texto)
        EXEC @hresult = sp_OAGetProperty @http, 'responseText';
    END;

    IF @hresult <> 0
        EXEC sp_OAGetErrorInfo @http, @fuente OUTPUT, @descripcion OUTPUT;
    IF @http IS NOT NULL
        EXEC sp_OADestroy @http;

    IF @hresult <> 0
    BEGIN
        SET @errores = N'DatosGenerales.usp_ConsumirAPI: no se pudo ' + @paso + N' ('
                     + ISNULL(TRIM(@blancos FROM @descripcion),
                              N'HRESULT ' + CONVERT(NVARCHAR(20), CONVERT(VARBINARY(4), @hresult), 1))
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
  fn_NormalizarNombre
  Deja un nombre en una forma comparable: en minúsculas, sin espacios, guiones,
  apóstrofos ni puntos, y con ae, oe y ue como a, o y u (Rüdiger se escribe
  también Ruediger). Así "Al-Taamari" y "ALTAAMARI", u "O'Reilly" y "OREILLY",
  quedan iguales. Las tildes no las quita: se comparan con una intercalación
  que no las distingue (_AI).
*/
CREATE OR ALTER FUNCTION Torneo.fn_NormalizarNombre (@texto NVARCHAR(400))
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
    1. Nombre completo igual, en cualquier orden (Torneo.fn_NormalizarNombre, sin
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
    SET clave_completa = Torneo.fn_NormalizarNombre(n.nombre_fuente),
        clave_nombre   = Torneo.fn_NormalizarNombre(LEFT(p.nombre, CHARINDEX(N' ', p.nombre + N' ') - 1)),
        clave_apellido = Torneo.fn_NormalizarNombre(p.apellido)
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
    SET clave_completa = Torneo.fn_NormalizarNombre(nombre + apellido),
        clave_inversa  = Torneo.fn_NormalizarNombre(apellido + nombre),
        clave_nombre   = Torneo.fn_NormalizarNombre(LEFT(nombre, CHARINDEX(N' ', nombre + N' ') - 1)),
        clave_apellido = Torneo.fn_NormalizarNombre(apellido);

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
    WHERE Torneo.fn_NormalizarNombre(w.value) COLLATE Latin1_General_CI_AI = c.clave_nombre COLLATE Latin1_General_CI_AI;

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
WHERE s.name + N'.' + o.name IN (N'DatosGenerales.usp_RegistrarImportacion', N'DatosGenerales.usp_BorrarImportacion',
                                 N'DatosGenerales.usp_ConsumirAPI', N'DatosGenerales.usp_LeerArchivoUTF8',
                                 N'Torneo.fn_NormalizarNombre', N'Torneo.usp_IdentificarJugadores')
ORDER BY o.name;
GO
