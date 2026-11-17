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
 Archivo: 20_SP_Importar_Publicidad.sql
 Objetivo: Crear el proceso de importación de las campañas publicitarias del
           Mundial 2026 publicadas en el Dossier Mundial
           (https://dossiermundial.netlify.app/), con su anunciante y sus
           piezas. Los SP, en el orden en que se crean:
             Publicidad.usp_CargarCampanias        carga masiva de campañas, con su anunciante y sus piezas
             Publicidad.usp_ProcesarCampaniasJSON  valida la respuesta de la API y carga sus campañas
             Publicidad.usp_ImportarCampaniasAPI   consulta la API y procesa la respuesta
           El pedido a la API lo hace DatosGenerales.usp_ConsumirAPI
           (17_SP_Utilidades_Importacion.sql). Requiere haber ejecutado 01 a
           19. Su script de testing es 70_Test_SP_Importar_Publicidad.sql.
================================================================================

 Fuente: la página no trae las campañas en el HTML: las lee con JavaScript
 de la colección "campanas" de una base Firebase Firestore, con la
 configuración pública que está en su código (ver
 doc/Fuentes_de_Datos_y_APIs.docx). usp_ImportarCampaniasAPI pide esa misma
 colección a la API REST de Firestore, con la clave pública de la página.
 Responde en JSON, con los valores tipados de Firestore. Ej.:
   {"documents": [{"name": "projects/.../documents/campanas/7Hc2...",
                   "fields": {"anunciante": {"stringValue": "Quilmes"},
                              "titulo":     {"stringValue": "Latas edición limitada"},
                              "youtube":    {"stringValue": "LvnvOD01Jwo"},
                              "videos":     {"arrayValue": {"values": [{"stringValue": "LvnvOD01Jwo"}]}},
                              "periodo":    {"stringValue": ""}, ...}}, ...]}

 Qué se toma de cada campaña (lo demás no tiene lugar en el modelo):
   - anunciante -> ANUNCIANTE.razon_social, tal como viene ("Visa y Banco
     Macro" es un solo anunciante: el de esa campaña), con el apóstrofo
     tipográfico (’) cambiado por el simple: la página escribe el mismo
     anunciante de las dos formas ("McDonald’s" y "McDonald's").
   - titulo -> CAMPANIA.nombre.
   - videos (o youtube, si no hay videos) -> una PIEZA_PUBLICITARIA por video
     distinto. La primera lleva el nombre de la campaña y las demás, el
     nombre con su número ("Manual para festejar como un argentino (2)"):
     así un video nuevo agrega una pieza sin cambiar el título de las otras.
     Una campaña sin videos tiene una sola pieza.
   - No se importan créditos (nombres de personas), agencia, productora,
     premios, descripción, categorías ni el enlace a la nota.
 Lo que el dossier no trae se completa con parámetros:
   - País del anunciante y mercado de interés de cada pieza: Argentina. El
     Dossier es un medio del mercado publicitario argentino y las campañas
     son para ese mercado, aunque el anunciante sea una empresa extranjera.
   - Idioma de las piezas: español.
   - Período de la campaña: el campo periodo viene vacío; se usa el período
     del torneo, del 11/06 al 19/07/2026.

 Cómo importa usp_ProcesarCampaniasJSON (los pasos tienen el mismo número
 en el código):
   1. Se controlan los parámetros (fechas, país e idioma) y el documento: que
      sea JSON, que no sea un mensaje de error de Firestore y que tenga la
      lista "documents". Si no, no se importa nada.
   2. OPENJSON pasa las campañas, tal como vienen, a #staging_campanias, y
      sus videos a #staging_piezas, una fila por pieza. Todas las
      transformaciones se hacen acá, en T-SQL.
   3. Publicidad.usp_CargarCampanias lee las dos tablas, valida las campañas
      con las reglas de anunciantes, campañas y piezas y hace el upsert de
      las válidas, todas juntas. En la misma transacción se registra la
      importación (su número queda en @id_importacion) y las rechazadas, en
      Publicidad.ERRORES_CAMPANIA.
   4. Se devuelve el resumen, las rechazadas con sus motivos y las campañas
      cargadas.

 Criterios del upsert (los de usp_CargarCampanias):
   - Clave natural: la razón social del anunciante, el nombre de la campaña
     y el título de la pieza. Importar dos veces lo mismo no cambia nada.
   - Si cambian las fechas, se actualizan, salvo que dejen afuera un partido
     en el que ya se exhibe una pieza de la campaña.
   - Las piezas y los mercados que ya están y no vienen no se borran: pueden
     estar exhibidas, y la exhibición es el historial para facturar.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   PROCESAMIENTO DEL JSON (lo usa el SP de abajo)
   ============================================================================ */

/*
  usp_CargarCampanias
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
CREATE OR ALTER PROCEDURE Publicidad.usp_CargarCampanias
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @salto_linea NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    IF OBJECT_ID(N'tempdb..#staging_campanias') IS NULL OR OBJECT_ID(N'tempdb..#staging_piezas') IS NULL
        THROW 50001, N'Publicidad.usp_CargarCampanias: no se importó nada, faltan las tablas #staging_campanias y #staging_piezas con las campañas y sus piezas.', 1;

    UPDATE #staging_campanias
    SET anunciante = NULLIF(TRIM(anunciante), N''),
        nombre     = NULLIF(TRIM(nombre), N'')
    WHERE accion IS NULL;

    UPDATE #staging_piezas
    SET titulo = NULLIF(TRIM(titulo), N'');

    /* 1. Cada regla anota su motivo en las campañas que no la cumplen. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.anunciante IS NULL      THEN @salto_linea + N'- El anunciante es obligatorio.'
                 WHEN LEN(st.anunciante) > 150   THEN @salto_linea + N'- La razón social del anunciante no puede superar los 150 caracteres.'
            END,
            CASE WHEN st.id_pais IS NULL THEN @salto_linea + N'- El país del anunciante es obligatorio.'
                 WHEN NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS AS p WHERE p.id_pais = st.id_pais)
                     THEN @salto_linea + N'- No existe el país con id ' + CAST(st.id_pais AS NVARCHAR(10)) + N'.'
            END,
            CASE WHEN st.nombre IS NULL      THEN @salto_linea + N'- El nombre de la campaña es obligatorio.'
                 WHEN LEN(st.nombre) > 150   THEN @salto_linea + N'- El nombre de la campaña no puede superar los 150 caracteres.'
            END,
            CASE WHEN st.fecha_inicio IS NULL OR st.fecha_fin IS NULL
                     THEN @salto_linea + N'- Las fechas de inicio y de fin son obligatorias.'
                 WHEN st.fecha_fin < st.fecha_inicio
                     THEN @salto_linea + N'- La fecha de fin no puede ser anterior a la de inicio.'
            END,
            IIF(NOT EXISTS (SELECT 1 FROM #staging_piezas AS sp WHERE sp.id_registro = st.id_registro),
                @salto_linea + N'- La campaña no tiene piezas.', NULL),
            pz.errores), N'')
    FROM #staging_campanias AS st
    -- Los motivos de sus piezas, una vez cada uno.
    LEFT JOIN (SELECT m.id_registro, STRING_AGG(m.motivo, N'') WITHIN GROUP (ORDER BY m.motivo) AS errores
                 FROM (SELECT DISTINCT sp.id_registro, v.motivo
                       FROM #staging_piezas AS sp
                       LEFT JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = sp.id_idioma
                       LEFT JOIN DatosGenerales.PAIS AS p ON p.id_pais = sp.id_pais_interes
                       CROSS APPLY (VALUES
                           (IIF(sp.titulo IS NULL, @salto_linea + N'- Hay una pieza sin título.', NULL)),
                           (IIF(LEN(sp.titulo) > 150, @salto_linea + N'- El título de la pieza "' + LEFT(sp.titulo, 40)
                                                      + N'..." no puede superar los 150 caracteres.', NULL)),
                           (IIF(sp.id_idioma IS NOT NULL AND i.id_idioma IS NULL,
                                @salto_linea + N'- No existe el idioma con id ' + CAST(sp.id_idioma AS NVARCHAR(10)) + N'.', NULL)),
                           (IIF(sp.id_pais_interes IS NOT NULL AND p.id_pais IS NULL,
                                @salto_linea + N'- No existe el país de interés con id ' + CAST(sp.id_pais_interes AS NVARCHAR(10)) + N'.', NULL))
                       ) AS v (motivo)
                       WHERE v.motivo IS NOT NULL) AS m
                 GROUP BY m.id_registro) AS pz ON pz.id_registro = st.id_registro
    WHERE st.accion IS NULL;

    -- Una pieza con dos idiomas: no se sabe cuál es.
    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- La pieza "', d.titulo, N'" viene con idiomas distintos.')
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
    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- Esta campaña del mismo anunciante viene ', r.veces, N' veces.')
    FROM #staging_campanias AS st
    INNER JOIN (SELECT anunciante, nombre, COUNT(*) AS veces
                FROM #staging_campanias
                WHERE accion IS NULL AND anunciante IS NOT NULL AND nombre IS NOT NULL
                GROUP BY anunciante, nombre
                HAVING COUNT(*) > 1) AS r ON r.anunciante = st.anunciante AND r.nombre = st.nombre
    WHERE st.accion IS NULL;

    -- Un anunciante es de un solo país.
    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- El anunciante viene con países distintos en sus campañas.')
    FROM #staging_campanias AS st
    INNER JOIN (SELECT anunciante
                FROM #staging_campanias
                WHERE accion IS NULL AND anunciante IS NOT NULL AND id_pais IS NOT NULL
                GROUP BY anunciante
                HAVING MIN(id_pais) <> MAX(id_pais)) AS r ON r.anunciante = st.anunciante
    WHERE st.accion IS NULL AND st.id_pais IS NOT NULL;

    -- Las fechas nuevas de una campaña cargada no pueden dejar afuera un partido en el que ya se exhibe.
    UPDATE st
    SET errores = CONCAT(st.errores, @salto_linea, N'- Con esas fechas quedaría afuera el partido ', x.numero_partido,
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


/*
  usp_ProcesarCampaniasJSON
  Importa una respuesta de la API REST de Firestore con las campañas del
  Dossier Mundial. La llama usp_ImportarCampaniasAPI. @origen es la URL o el
  texto que identifica de dónde salió y @proceso, el SP que importa (el que
  lo llama; si no viene, este). Las campañas van de @fecha_inicio a
  @fecha_fin, son de anunciantes del país con código FIFA @codigo_fifa (que
  es también el mercado de interés de sus piezas) y sus piezas están en el
  idioma con código ISO 639-1 @codigo_idioma.
  Registra la importación (su número queda en @id_importacion) y las
  rechazadas en Publicidad.ERRORES_CAMPANIA, y devuelve el resumen (leídos,
  insertados, actualizados, sin cambios, omitidos y rechazados), las
  rechazadas con sus motivos y las campañas cargadas.
  Valida: fechas obligatorias y la de fin no anterior a la de inicio; país e
  idioma existentes (THROW 50001). Si el documento no es JSON, es un mensaje
  de error de Firestore o no tiene la lista "documents", no se importa nada
  (THROW 50002).
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_ProcesarCampaniasJSON
    @json            NVARCHAR(MAX),
    @origen          NVARCHAR(1000),
    @fecha_inicio    DATE         = '2026-06-11',
    @fecha_fin       DATE         = '2026-07-19',
    @codigo_fifa     VARCHAR(10)  = 'ARG',
    @codigo_idioma   VARCHAR(10)  = 'es',
    @proceso         VARCHAR(100) = NULL,
    @id_importacion  INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @salto_linea  NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @mensaje      NVARCHAR(2048);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @id_pais      SMALLINT;
    DECLARE @id_idioma    SMALLINT;
    DECLARE @leidos       INT;
    DECLARE @insertados   INT;
    DECLARE @actualizados INT;
    DECLARE @sin_cambios  INT;
    DECLARE @rechazados   INT;

    SET @proceso = ISNULL(NULLIF(TRIM(@proceso), ''), 'Publicidad.usp_ProcesarCampaniasJSON');
    SET @codigo_fifa   = UPPER(NULLIF(TRIM(@codigo_fifa), ''));
    SET @codigo_idioma = LOWER(NULLIF(TRIM(@codigo_idioma), ''));
    SET @id_importacion = NULL;

    SELECT @id_pais = id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = @codigo_fifa;
    SELECT @id_idioma = id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = @codigo_idioma;

    /* 1. Los parámetros y el documento. */
    IF @fecha_inicio IS NULL OR @fecha_fin IS NULL
        SET @errores += @salto_linea + N'- Las fechas de inicio y de fin de las campañas son obligatorias.';
    ELSE IF @fecha_fin < @fecha_inicio
        SET @errores += @salto_linea + N'- La fecha de fin de las campañas no puede ser anterior a la de inicio.';

    IF @id_pais IS NULL
        SET @errores += @salto_linea + N'- No hay ningún país con el código FIFA ' + ISNULL(@codigo_fifa, N'(vacío)') + N'.';
    IF @id_idioma IS NULL
        SET @errores += @salto_linea + N'- No hay ningún idioma con el código ISO 639-1 ' + ISNULL(@codigo_idioma, N'(vacío)') + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_ProcesarCampaniasJSON: no se importó nada.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Si Firestore rechaza el pedido responde {"error": {"code", "message", "status"}}; si la colección está vacía, {}.
    IF ISJSON(@json) IS DISTINCT FROM 1
        SET @mensaje = N'el documento no es un JSON válido (puede ser una respuesta incompleta).';
    ELSE IF JSON_VALUE(@json, '$.error.message') IS NOT NULL
        SET @mensaje = N'Firestore devolvió un error: ' + JSON_VALUE(@json, '$.error.message');
    ELSE IF ISJSON(JSON_QUERY(@json, '$.documents'), ARRAY) IS DISTINCT FROM 1
        SET @mensaje = N'el JSON no tiene campañas (tiene que ser un objeto con la lista "documents" de la API '
                     + N'REST de Firestore).';

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'Publicidad.usp_ProcesarCampaniasJSON: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    -- usp_CargarCampanias lee y completa estas tablas: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_campanias (
        id_registro   INT            PRIMARY KEY,   -- posición de la campaña en la respuesta
        -- Tal como vienen en el JSON
        documento     NVARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,   -- id del documento en Firestore
        youtube       NVARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        videos        NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
        -- Lo que lee usp_CargarCampanias
        anunciante    NVARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
        nombre        NVARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
        id_pais       SMALLINT       NULL,
        fecha_inicio  DATE           NULL,
        fecha_fin     DATE           NULL,
        -- Lo que le pasa a cada campaña: lo completa usp_CargarCampanias
        errores       NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
        accion        VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
    );

    CREATE TABLE #staging_piezas (
        id_registro      INT            NOT NULL,   -- el de su campaña
        orden            INT            NOT NULL,
        video            NVARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,   -- id del video en YouTube
        titulo           NVARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
        id_idioma        SMALLINT       NULL,
        id_pais_interes  SMALLINT       NULL,
        PRIMARY KEY (id_registro, orden)
    );

    /* 2. Las campañas, como vienen de la API. Un elemento que no es un objeto queda sin datos
          y lo rechaza usp_CargarCampanias. El apóstrofo tipográfico se cambia por el simple:
          la página escribe "McDonald’s" y "McDonald's", y es el mismo anunciante. */
    INSERT INTO #staging_campanias (id_registro, documento, anunciante, nombre, youtube, videos, id_pais, fecha_inicio, fecha_fin)
    SELECT CAST(d.[key] AS INT) + 1,
           RIGHT(c.nombre_documento, CHARINDEX(N'/', REVERSE(c.nombre_documento) + N'/') - 1),
           REPLACE(c.anunciante, NCHAR(8217), N''''), REPLACE(c.titulo, NCHAR(8217), N''''),
           NULLIF(TRIM(c.youtube), N''), c.videos,
           @id_pais, @fecha_inicio, @fecha_fin
    FROM OPENJSON(@json, '$.documents') AS d
    OUTER APPLY OPENJSON(IIF(d.[type] = 5, d.value, N'{}'))
         WITH (nombre_documento  NVARCHAR(400)  '$.name',
               anunciante        NVARCHAR(400)  '$.fields.anunciante.stringValue',
               titulo            NVARCHAR(400)  '$.fields.titulo.stringValue',
               youtube           NVARCHAR(100)  '$.fields.youtube.stringValue',
               videos            NVARCHAR(MAX)  '$.fields.videos.arrayValue.values' AS JSON) AS c;

    /* Las piezas: un video distinto por pieza, el de la portada (youtube) primero. Los ids de
       YouTube distinguen mayúsculas, por eso se comparan en binario. */
    WITH videos AS (
        SELECT id_registro, youtube AS video, -1 AS posicion
        FROM #staging_campanias
        WHERE youtube IS NOT NULL
        UNION ALL
        SELECT st.id_registro, NULLIF(TRIM(JSON_VALUE(v.value, '$.stringValue')), N''), CAST(v.[key] AS INT)
        FROM #staging_campanias AS st
        CROSS APPLY OPENJSON(st.videos) AS v
        WHERE ISJSON(st.videos, ARRAY) = 1
    ),
    distintos AS (
        SELECT id_registro, video COLLATE Latin1_General_BIN AS video, MIN(posicion) AS posicion
        FROM videos
        WHERE video IS NOT NULL
        GROUP BY id_registro, video COLLATE Latin1_General_BIN
    ),
    numerados AS (
        SELECT id_registro, video, ROW_NUMBER() OVER (PARTITION BY id_registro ORDER BY posicion) AS orden
        FROM distintos
    )
    INSERT INTO #staging_piezas (id_registro, orden, video, titulo, id_idioma, id_pais_interes)
    SELECT st.id_registro, o.orden, n.video,
           CASE WHEN NULLIF(TRIM(st.nombre), N'') IS NULL THEN NULL
                WHEN o.orden = 1 THEN TRIM(st.nombre)
                ELSE CONCAT(TRIM(st.nombre), N' (', o.orden, N')')
           END,
           @id_idioma, @id_pais
    FROM #staging_campanias AS st
    LEFT JOIN numerados AS n ON n.id_registro = st.id_registro
    CROSS APPLY (SELECT ISNULL(n.orden, 1) AS orden) AS o;

    /* 3. El SP de carga valida y carga las válidas, todas juntas; después se registran
          la importación y sus rechazadas, en la misma transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Publicidad.usp_CargarCampanias;

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_campanias;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @origen, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @omitidos = 0,
            @rechazados = @rechazados, @id_importacion = @id_importacion OUTPUT;

        INSERT INTO Publicidad.ERRORES_CAMPANIA (id_importacion, registro, documento, anunciante, titulo, motivos)
        SELECT @id_importacion, id_registro, documento, anunciante, nombre, STUFF(errores, 1, 2, N'')
        FROM #staging_campanias
        WHERE accion = 'RECHAZADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    /* 4. Resultado. */
    SELECT @id_importacion AS id_importacion, @origen AS origen, @leidos AS leidos, @insertados AS insertados,
           @actualizados AS actualizados, @sin_cambios AS sin_cambios, 0 AS omitidos, @rechazados AS rechazados;

    SELECT registro, documento, anunciante, titulo, motivos
    FROM Publicidad.ERRORES_CAMPANIA
    WHERE id_importacion = @id_importacion
    ORDER BY registro;

    SELECT st.id_registro, st.anunciante, st.nombre AS campania, st.fecha_inicio, st.fecha_fin,
           COUNT(*) AS piezas, st.accion
    FROM #staging_campanias AS st
    INNER JOIN #staging_piezas AS sp ON sp.id_registro = st.id_registro
    WHERE st.accion <> 'RECHAZADO'
    GROUP BY st.id_registro, st.anunciante, st.nombre, st.fecha_inicio, st.fecha_fin, st.accion
    ORDER BY st.id_registro;
END;
GO


/* ============================================================================
   IMPORTACIÓN DESDE LA API
   ============================================================================ */

/*
  usp_ImportarCampaniasAPI
  Consulta con usp_ConsumirAPI la colección de campañas del Dossier Mundial
  en la API REST de Firestore y procesa la respuesta con
  usp_ProcesarCampaniasJSON, con el período @fecha_inicio a @fecha_fin
  (por defecto, el del torneo). La URL tiene el proyecto y la clave pública
  que usa la propia página (ver doc/Fuentes_de_Datos_y_APIs.docx); pide hasta
  300 campañas en una sola consulta. Si hay más, avisa que importó las
  primeras.
  Si la API no responde, responde con un código HTTP distinto de 200 o no
  devuelve un JSON válido, no se importa nada (THROW 50002). El número de la
  importación queda en @id_importacion.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_ImportarCampaniasAPI
    @fecha_inicio    DATE = '2026-06-11',
    @fecha_fin       DATE = '2026-07-19',
    @id_importacion  INT  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @url          NVARCHAR(1000) = N'https://firestore.googleapis.com/v1/projects/repositorio2026-61a28'
                                         + N'/databases/(default)/documents/campanas'
                                         + N'?pageSize=300&key=AIzaSyAvVQTFWTCHwSCMIS2le22ZQ6aQBv8oUgo';
    DECLARE @estado_http  SMALLINT;
    DECLARE @respuesta    NVARCHAR(MAX);
    DECLARE @mensaje      NVARCHAR(2048);
    DECLARE @proceso      VARCHAR(100)   = 'Publicidad.usp_ImportarCampaniasAPI';

    BEGIN TRY
        EXEC DatosGenerales.usp_ConsumirAPI @url = @url, @estado_http = @estado_http OUTPUT, @respuesta = @respuesta OUTPUT;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'falló la consulta a la API: ' + ERROR_MESSAGE();
    END CATCH;

    -- Con un pedido rechazado Firestore responde 4xx y un JSON con el motivo en error.message.
    IF @mensaje IS NULL AND @estado_http <> 200
        SET @mensaje = N'la API respondió con el código HTTP ' + CAST(@estado_http AS NVARCHAR(5))
                     + ISNULL(N': ' + IIF(ISJSON(@respuesta) = 1, JSON_VALUE(@respuesta, '$.error.message'), NULL), N'')
                     + N'.';

    IF @mensaje IS NOT NULL
    BEGIN
        SET @mensaje = N'Publicidad.usp_ImportarCampaniasAPI: no se importó nada, ' + @mensaje;
        THROW 50002, @mensaje, 1;
    END;

    IF ISJSON(@respuesta) = 1 AND JSON_VALUE(@respuesta, '$.nextPageToken') IS NOT NULL
        PRINT N'Publicidad.usp_ImportarCampaniasAPI: el Dossier tiene más de 300 campañas; se importan las primeras 300.';

    EXEC Publicidad.usp_ProcesarCampaniasJSON
        @json = @respuesta, @origen = @url, @fecha_inicio = @fecha_inicio, @fecha_fin = @fecha_fin,
        @proceso = @proceso, @id_importacion = @id_importacion OUTPUT;
END;
GO


-- Evidencia: SP de importación de campañas creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Publicidad'
  AND p.name IN (N'usp_CargarCampanias', N'usp_ProcesarCampaniasJSON', N'usp_ImportarCampaniasAPI')
ORDER BY p.name;
GO
