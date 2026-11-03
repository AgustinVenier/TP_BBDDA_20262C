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
 Archivo: 32_DatosComplementarios.sql
 Objetivo: Completar el Mundial 2026 real con lo que no traen las fuentes
           importadas, para que todas las tablas tengan datos y los reportes
           muestren información representativa. No repite nada de lo que ya
           se importa: sedes, selecciones, jugadores, partidos y árbitros
           vienen del 31 (openfootball y scraping), las campañas argentinas
           del Dossier Mundial y las cotizaciones y feriados de las APIs
           vienen del 29, y el PBI per cápita del 26.
           Requiere haber ejecutado 00 a 31. Se puede ejecutar más de una
           vez: lo que ya está cargado no se vuelve a cargar.
================================================================================

 Qué carga (son datos inventados, porque no hay una fuente de donde sacarlos):
   1. El cuerpo técnico de cada selección que no lo tiene: director técnico,
      ayudante de campo, preparador físico y entrenador de arqueros. Los
      nombres se arman combinando dos listas y no son personas reales.
   2. Los idiomas de cada árbitro que no los tiene: el del país del árbitro
      y el inglés, que es el idioma de trabajo de los árbitros FIFA.
   3. Anunciantes de 8 países (Argentina ya la cubre el Dossier), con 8
      campañas del torneo y una de 2025, como historial. Sus piezas apuntan
      a mercados de América, Europa, África, Asia y Oceanía, que no cubren
      las del Dossier (solo Argentina).
   4. La publicidad de cada partido: las 4 piezas que propone
      Publicidad.usp_AsignarPublicidadPartido, como registro histórico de lo
      que se exhibió (los partidos se importaron ya jugados).
   5. El motivo LESION en el primer cambio del torneo, en el minuto 8: el
      archivo de partidos no trae el motivo de los cambios.
 Se cargan con los SP por conjuntos de la Entrega 5 (16_SP_Importacion.sql) y
 de negocio, sobre tablas armadas acá, nunca con INSERT directo. No es una
 importación, así que no se registra en DatosGenerales.IMPORTACION: si algún
 dato se rechaza, se muestran los motivos y no se ejecuta el resto.

 Casos obligatorios de la consigna (sección IV), al final del script:
   - Doble amarilla y roja directa, suspensión por acumulación que deja al
     jugador afuera del partido siguiente, importación con errores
     parciales: vienen del torneo real y de su importación (31).
   - Cambio por lesión en los primeros 20 minutos: el de la parte 5.
   - Partido en prime time en más de cuatro mercados candidatos, en el que
     la asignación elige solo cuatro piezas: los de la parte 4.
   - Designación descartada por conflicto de nacionalidad: la parte 6 la
     intenta, dentro de una transacción que se deshace.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Se ejecuta sobre la base con el torneo real (31) y el PBI per cápita (26), que usa la
-- asignación de publicidad para priorizar las piezas.
IF NOT EXISTS (SELECT 1 FROM Torneo.PARTIDO)
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO WHERE codigo_indicador = 'NY.GDP.PCAP.CD')
BEGIN
    PRINT N'32_DatosComplementarios.sql: la base tiene que tener el torneo real (31) y el PBI per cápita (26). '
        + N'Ejecutá los scripts 00 a 31 y volvé a ejecutar este.';
    SET NOEXEC ON;
END;
GO

-- Las tablas que leen los SP de la Entrega 5, por si quedaron de una ejecución anterior en esta
-- sesión. Va en un lote aparte: cada lote se compila contra las tablas que ya existen.
DROP TABLE IF EXISTS #staging_cuerpo_tecnico, #staging_arbitros, #staging_campanias, #staging_piezas,
                     #staging_designaciones;
GO


/* ============================================================================
   1. CUERPOS TÉCNICOS
   Dentro de cada cuerpo técnico el apellido no se repite: cada rol usa otro
   desplazamiento en la lista de apellidos.
   ============================================================================ */
CREATE TABLE #staging_cuerpo_tecnico (
    id_registro             INT           PRIMARY KEY,
    codigo_fifa             VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    nombre                  NVARCHAR(60)  COLLATE DATABASE_DEFAULT NULL,
    apellido                NVARCHAR(60)  COLLATE DATABASE_DEFAULT NULL,
    rol                     VARCHAR(40)   COLLATE DATABASE_DEFAULT NULL,
    fecha_nacimiento        DATE          NULL,
    codigo_fifa_nacimiento  VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    errores                 NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion                  VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

DECLARE @nombres TABLE (idx INT PRIMARY KEY, nombre NVARCHAR(60));
INSERT INTO @nombres (idx, nombre)
VALUES (0, N'Lucas'), (1, N'Mateo'), (2, N'Diego'), (3, N'Santiago'), (4, N'Joaquín'), (5, N'Tomás'),
       (6, N'Nicolás'), (7, N'Martín'), (8, N'Bruno'), (9, N'Gabriel'), (10, N'Daniel'), (11, N'Leo'),
       (12, N'Hugo'), (13, N'Adrián'), (14, N'Samuel'), (15, N'Pablo'), (16, N'Andrés'), (17, N'Iván'),
       (18, N'Kevin'), (19, N'Rafael'), (20, N'Emil'), (21, N'Yusuf'), (22, N'Kenji'), (23, N'Min-jun'),
       (24, N'Oliver'), (25, N'Ethan');

DECLARE @apellidos TABLE (idx INT PRIMARY KEY, apellido NVARCHAR(60));
INSERT INTO @apellidos (idx, apellido)
VALUES (0, N'García'), (1, N'Silva'), (2, N'Martínez'), (3, N'Rossi'), (4, N'Müller'), (5, N'Fernández'),
       (6, N'Kim'), (7, N'Tanaka'), (8, N'Smith'), (9, N'Benali'), (10, N'Diallo'), (11, N'Romero'),
       (12, N'Costa'), (13, N'Pereira'), (14, N'López'), (15, N'Herrera'), (16, N'Nakamura'), (17, N'Park'),
       (18, N'Brown'), (19, N'Haddad'), (20, N'Ndiaye'), (21, N'Suárez'), (22, N'Torres'), (23, N'Ramos'),
       (24, N'Wilson'), (25, N'Mendes');

-- Cada rol, con su desplazamiento en las listas de nombres y la edad mínima.
DECLARE @roles TABLE (orden TINYINT PRIMARY KEY, rol VARCHAR(20), desp_nombre INT, desp_apellido INT, edad INT);
INSERT INTO @roles (orden, rol, desp_nombre, desp_apellido, edad)
VALUES (0, 'DIRECTOR_TECNICO', 3, 13, 45), (1, 'AYUDANTE_CAMPO', 7, 17, 35),
       (2, 'PREPARADOR_FISICO', 11, 21, 35), (3, 'ENTRENADOR_ARQUEROS', 19, 2, 35);

-- Las selecciones se numeran por código FIFA; las que ya tienen cuerpo técnico no se tocan.
-- Cada persona nace en el país de su selección.
INSERT INTO #staging_cuerpo_tecnico (id_registro, codigo_fifa, nombre, apellido, rol, fecha_nacimiento,
                                     codigo_fifa_nacimiento)
SELECT ROW_NUMBER() OVER (ORDER BY s.n, r.orden), s.codigo_fifa, n.nombre, ap.apellido, r.rol,
       DATEADD(DAY, (s.n * 37 + r.orden * 11) % 365,
               DATEADD(YEAR, -(r.edad + (s.n + r.orden) % 15), CAST('2025-01-01' AS DATE))),
       s.codigo_fifa
FROM (SELECT se.id_seleccion, pa.codigo_fifa, ROW_NUMBER() OVER (ORDER BY pa.codigo_fifa) AS n
      FROM Torneo.SELECCION AS se
      INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais) AS s
CROSS JOIN @roles AS r
INNER JOIN @nombres AS n ON n.idx = (s.n + r.desp_nombre) % 26
INNER JOIN @apellidos AS ap ON ap.idx = (s.n * 5 + r.desp_apellido) % 26
WHERE NOT EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO AS ct WHERE ct.id_seleccion = s.id_seleccion);

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Torneo.usp_ImportarCuerpoTecnico;

    IF EXISTS (SELECT 1 FROM #staging_cuerpo_tecnico WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT codigo_fifa, nombre, apellido, rol, STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_cuerpo_tecnico WHERE accion = 'RECHAZADO' ORDER BY id_registro;
        ROLLBACK TRANSACTION;
        PRINT N'Cuerpos técnicos: hay personas rechazadas (ver la grilla); no se cargó ninguna.';
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        DECLARE @personas INT = (SELECT COUNT(*) FROM #staging_cuerpo_tecnico WHERE accion = 'INSERTADO');
        DECLARE @selecciones INT = (SELECT COUNT(DISTINCT codigo_fifa) FROM #staging_cuerpo_tecnico);
        PRINT CONCAT(N'Cuerpos técnicos: ', @personas, N' personas cargadas en ', @selecciones, N' selecciones.');
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al cargar los cuerpos técnicos: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   2. IDIOMAS DE LOS ÁRBITROS
   El idioma del país de cada árbitro (los de los países que no figuran
   acá, como Inglaterra o Estados Unidos, solo hablan inglés) y el inglés.
   ============================================================================ */
CREATE TABLE #staging_arbitros (
    id_registro       INT           PRIMARY KEY,
    codigo_fifa       VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    nombre            NVARCHAR(60)  COLLATE DATABASE_DEFAULT NULL,
    apellido          NVARCHAR(60)  COLLATE DATABASE_DEFAULT NULL,
    categoria         VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
    fecha_nacimiento  DATE          NULL,
    idiomas           VARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,
    errores           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion            VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

DECLARE @idiomas_pais TABLE (codigo_fifa CHAR(3) PRIMARY KEY, idiomas VARCHAR(20));
INSERT INTO @idiomas_pais (codigo_fifa, idiomas)
VALUES ('ALG', 'ar,fr'), ('ANG', 'pt'), ('ARG', 'es'), ('AUT', 'de'), ('BEL', 'fr,nl'), ('BOL', 'es'),
       ('BRA', 'pt'), ('CAN', 'fr'), ('CHI', 'es'), ('CHN', 'zh'), ('CIV', 'fr'), ('CMR', 'fr'),
       ('COD', 'fr'), ('COL', 'es'), ('CRC', 'es'), ('CRO', 'hr'), ('ECU', 'es'), ('EGY', 'ar'),
       ('ESP', 'es'), ('FRA', 'fr'), ('GAB', 'fr'), ('GER', 'de'), ('HAI', 'fr'), ('HON', 'es'),
       ('IRN', 'fa'), ('IRQ', 'ar'), ('ITA', 'it'), ('JOR', 'ar'), ('JPN', 'ja'), ('KOR', 'ko'),
       ('KSA', 'ar'), ('MAR', 'ar,fr'), ('MEX', 'es'), ('MTN', 'ar,fr'), ('NCA', 'es'), ('NED', 'nl'),
       ('NOR', 'no'), ('PAN', 'es'), ('PAR', 'es'), ('PER', 'es'), ('POL', 'pl'), ('POR', 'pt'),
       ('QAT', 'ar'), ('ROU', 'ro'), ('SEN', 'fr'), ('SLV', 'es'), ('SUI', 'de,fr'), ('SVN', 'sl'),
       ('SWE', 'sv'), ('TUN', 'ar,fr'), ('UAE', 'ar'), ('URU', 'es'), ('UZB', 'uz'), ('VEN', 'es');

-- Solo los árbitros que todavía no tienen idiomas; la categoría es la que ya tienen.
INSERT INTO #staging_arbitros (id_registro, codigo_fifa, nombre, apellido, categoria, idiomas)
SELECT ROW_NUMBER() OVER (ORDER BY a.id_arbitro), pa.codigo_fifa, a.nombre, a.apellido, a.categoria,
       CONCAT(ip.idiomas + ',', 'en')
FROM Arbitraje.ARBITRO AS a
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
LEFT JOIN @idiomas_pais AS ip ON ip.codigo_fifa = pa.codigo_fifa
WHERE NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA AS ai WHERE ai.id_arbitro = a.id_arbitro);

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Arbitraje.usp_ImportarArbitros;

    IF EXISTS (SELECT 1 FROM #staging_arbitros WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT codigo_fifa, nombre, apellido, idiomas, STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_arbitros WHERE accion = 'RECHAZADO' ORDER BY id_registro;
        ROLLBACK TRANSACTION;
        PRINT N'Idiomas de los árbitros: hay árbitros rechazados (ver la grilla); no se cargó ningún idioma.';
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        DECLARE @arbitros INT = (SELECT COUNT(*) FROM #staging_arbitros);
        PRINT CONCAT(N'Idiomas de los árbitros: cargados para ', @arbitros, N' árbitros.');
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al cargar los idiomas de los árbitros: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   3. ANUNCIANTES, CAMPAÑAS Y PIEZAS DE OTROS PAÍSES
   La campaña de 2025 queda como historial: no es candidata en este torneo.
   Una fila de #staging_piezas por pieza y mercado.
   ============================================================================ */
CREATE TABLE #staging_campanias (
    id_registro   INT            PRIMARY KEY,
    anunciante    NVARCHAR(150)  COLLATE DATABASE_DEFAULT NULL,
    id_pais       SMALLINT       NULL,
    nombre        NVARCHAR(150)  COLLATE DATABASE_DEFAULT NULL,
    fecha_inicio  DATE           NULL,
    fecha_fin     DATE           NULL,
    errores       NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
    accion        VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
);
CREATE TABLE #staging_piezas (
    id_registro      INT            NOT NULL,
    titulo           NVARCHAR(150)  COLLATE DATABASE_DEFAULT NULL,
    id_idioma        SMALLINT       NULL,
    id_pais_interes  SMALLINT       NULL
);

INSERT INTO #staging_campanias (id_registro, anunciante, id_pais, nombre, fecha_inicio, fecha_fin)
SELECT c.id_registro, c.anunciante, pa.id_pais, c.nombre, c.inicio, c.fin
FROM (VALUES (1, N'Samba Motors Ltda.',      'BRA', N'Samba Motors Mundial',         '2026-06-01', '2026-07-31'),
             (2, N'Iberia Seguros S.L.',     'ESP', N'Seguros para la hinchada',     '2026-06-01', '2026-07-20'),
             (3, N'Rheinwerk AG',            'GER', N'Rheinwerk Weltmeister',        '2026-06-01', '2026-07-31'),
             (4, N'Sakura Electronics K.K.', 'JPN', N'Sakura en alta definición',    '2026-06-10', '2026-07-15'),
             (5, N'Northstar Telecom Inc.',  'USA', N'Northstar conecta el Mundial', '2026-06-01', '2026-07-31'),
             (6, N'Atlas Airways S.A.',      'MAR', N'Volá a la fase de grupos',     '2026-06-11', '2026-06-30'),
             (7, N'Maple Foods Ltd.',        'CAN', N'Maple Game Day',               '2026-06-15', '2026-07-19'),
             (8, N'Cervecería Azteca S.A.',  'MEX', N'Cerveza oficial del aguante',  '2026-06-01', '2026-07-31'),
             (9, N'Cervecería Azteca S.A.',  'MEX', N'Verano Azteca 2025',           '2025-06-01', '2025-07-31')
     ) AS c (id_registro, anunciante, pais, nombre, inicio, fin)
LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = c.pais;

INSERT INTO #staging_piezas (id_registro, titulo, id_idioma, id_pais_interes)
SELECT p.campania, p.titulo, i.id_idioma, pa.id_pais
FROM (VALUES (1, N'Samba Motors Brasil',          'pt', 'BRA'),
             (1, N'Samba Motors Cono Sur',        'es', 'URU,PAR,CHI'),
             (2, N'Iberia España',                'es', 'ESP'),
             (2, N'Iberia Latinoamérica',         'es', 'MEX,COL'),
             (3, N'Rheinwerk Europa central',     'de', 'GER,AUT,SUI'),
             (3, N'Rheinwerk Norteamérica',       'en', 'USA,CAN'),
             (4, N'Sakura Japón',                 'ja', 'JPN'),
             (4, N'Sakura Corea',                 'ko', 'KOR'),
             (4, N'Sakura Oceanía',               'en', 'AUS'),
             (5, N'Northstar Estados Unidos',     'en', 'USA'),
             (5, N'Northstar Canadá',             'fr', 'CAN'),
             (5, N'Northstar México',             'es', 'MEX'),
             (6, N'Atlas Magreb',                 'ar', 'MAR,ALG'),
             (6, N'Atlas Francia y Senegal',      'fr', 'FRA,SEN'),
             (7, N'Maple Canadá',                 'en', 'CAN'),
             (7, N'Maple Reino Unido',            'en', 'SCO,ENG'),
             (8, N'Azteca México',                'es', 'MEX'),
             (8, N'Azteca comunidad latina',      'es', 'USA'),
             (9, N'Panel verano 2025',            'es', 'MEX')
     ) AS p (campania, titulo, idioma, mercados)
CROSS APPLY STRING_SPLIT(p.mercados, ',') AS m
LEFT JOIN DatosGenerales.IDIOMA AS i ON i.codigo_iso = p.idioma
LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = m.value;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Publicidad.usp_ImportarCampanias;

    IF EXISTS (SELECT 1 FROM #staging_campanias WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT anunciante, nombre, STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_campanias WHERE accion = 'RECHAZADO' ORDER BY id_registro;
        ROLLBACK TRANSACTION;
        PRINT N'Publicidad: hay campañas rechazadas (ver la grilla); no se cargó ninguna.';
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        SELECT N'Campañas de otros países' AS carga, COUNT(*) AS campanias,
               ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0)   AS insertadas,
               ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0) AS actualizadas,
               ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0) AS sin_cambios
        FROM #staging_campanias;
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al cargar la publicidad: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   4. PUBLICIDAD DE CADA PARTIDO
   Sin @id_partido, el SP asigna la de todos los partidos que todavía no la
   tienen. Devuelve cuántos asignó y los que no pudo, con sus motivos.
   ============================================================================ */
BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido;

    IF EXISTS (SELECT 1 FROM Torneo.PARTIDO AS p
               WHERE NOT EXISTS (SELECT 1 FROM Publicidad.EXHIBICION AS ex WHERE ex.id_partido = p.id_partido))
        PRINT N'Publicidad de los partidos: quedaron partidos sin publicidad (ver la grilla).';
    ELSE
        PRINT N'Publicidad de los partidos: todos los partidos tienen sus 4 piezas.';
END TRY
BEGIN CATCH
    PRINT N'Error al asignar la publicidad de los partidos: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   5. CAMBIO POR LESIÓN
   El primer cambio del torneo dentro de los primeros 20 minutos (si ya hay
   uno por lesión, ese): uno tan temprano casi siempre es por lesión.
   ============================================================================ */
BEGIN TRY
    DECLARE @id_cambio INT, @motivo VARCHAR(30);

    SELECT TOP (1) @id_cambio = c.id_cambio, @motivo = c.motivo
    FROM DesarrolloPartido.CAMBIO AS c
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
    WHERE c.minuto <= 20
    ORDER BY IIF(c.motivo = 'LESION', 0, 1), c.minuto, p.numero_partido;

    IF @id_cambio IS NULL
        PRINT N'Cambio por lesión: no hay cambios en los primeros 20 minutos.';
    ELSE IF @motivo <> 'LESION'
    BEGIN
        EXEC DesarrolloPartido.usp_CAMBIO_Modificacion @id_cambio = @id_cambio, @motivo = 'LESION';
        PRINT N'Cambio por lesión: registrado el motivo del primer cambio del torneo.';
    END;
END TRY
BEGIN CATCH
    PRINT N'Error al registrar el cambio por lesión: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   6. DESIGNACIÓN DESCARTADA POR CONFLICTO DE NACIONALIDAD
   Un árbitro del país de una de las selecciones, como cuarto árbitro del
   primer partido de esa selección. La regla está en el SP de la Entrega 5
   (y en usp_DesignarTernaArbitral y usp_DESIGNACION_ARBITRAL_Alta). Se
   prueba dentro de una transacción que se deshace, así no queda nada.
   ============================================================================ */
CREATE TABLE #staging_designaciones (
    id_registro     INT           PRIMARY KEY,
    numero_partido  TINYINT       NULL,
    id_arbitro      INT           NULL,
    rol             VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
    errores         NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion          VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_designaciones (id_registro, numero_partido, id_arbitro, rol)
SELECT TOP (1) 1, p.numero_partido, a.id_arbitro, 'CUARTO'
FROM Torneo.PARTIDO AS p
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)
INNER JOIN Arbitraje.ARBITRO AS a ON a.id_pais = s.id_pais
ORDER BY p.numero_partido, a.id_arbitro;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Arbitraje.usp_ImportarDesignaciones;

    SELECT N'Designación descartada' AS caso, f.numero_partido, f.seleccion_local, f.seleccion_visitante,
           st.rol, a.nombre + N' ' + a.apellido AS arbitro, pa.nombre AS pais_del_arbitro, st.accion,
           STUFF(st.errores, 1, 2, N'') AS motivos
    FROM #staging_designaciones AS st
    INNER JOIN Torneo.vw_Fixture AS f ON f.numero_partido = st.numero_partido
    INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = st.id_arbitro
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais;

    IF EXISTS (SELECT 1 FROM #staging_designaciones WHERE accion <> 'RECHAZADO')
        PRINT N'ATENCIÓN: la designación con conflicto de nacionalidad no fue rechazada.';
    ELSE
        PRINT N'Designación descartada (esperado): el árbitro es del país de una de las selecciones.';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al probar la designación con conflicto de nacionalidad: ' + ERROR_MESSAGE();
END CATCH;

DROP TABLE #staging_designaciones;
GO


/* ============================================================================
   7. RESUMEN Y CASOS OBLIGATORIOS
   ============================================================================ */
SELECT s.name + N'.' + t.name AS tabla, SUM(p.rows) AS filas
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
INNER JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE s.name IN (N'Torneo', N'DesarrolloPartido', N'Arbitraje', N'Publicidad')
  AND t.name NOT LIKE N'ERRORES[_]%'
GROUP BY s.name, t.name
ORDER BY s.name, t.name;

-- Anunciantes, campañas y piezas por país del anunciante (las del Dossier son de Argentina).
SELECT pa.nombre AS pais, COUNT(DISTINCT an.id_anunciante) AS anunciantes, COUNT(DISTINCT c.id_campania) AS campanias,
       COUNT(pz.id_pieza) AS piezas, MIN(c.fecha_inicio) AS desde, MAX(c.fecha_fin) AS hasta
FROM Publicidad.ANUNCIANTE AS an
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = an.id_pais
LEFT JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante
LEFT JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania
GROUP BY pa.nombre
ORDER BY anunciantes DESC, pa.nombre;

-- Expulsiones por doble amarilla y por roja directa.
SELECT p.numero_partido, pa.nombre AS seleccion, j.apellido, j.nombre,
       IIF(am.es_doble_amarilla = 1, 'DOBLE AMARILLA', 'ROJA DIRECTA') AS expulsion, am.minuto
FROM DesarrolloPartido.AMONESTACION AS am
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = am.id_partido
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = am.id_jugador
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
WHERE am.tipo_tarjeta = 'ROJA'
ORDER BY expulsion, p.numero_partido;

-- Suspendidos por acumulación de amarillas que quedaron afuera de la formación del partido siguiente.
SELECT p.numero_partido AS partido_que_cumple, s.numero_partido_origen, pa.nombre AS seleccion, j.apellido, j.nombre,
       s.motivo
FROM Torneo.PARTIDO AS p
CROSS APPLY DesarrolloPartido.fn_JugadoresSuspendidos(p.id_partido) AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = s.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
WHERE s.motivo = 'ACUMULACION DE AMARILLAS'
  AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS a
                  INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
                  WHERE f.id_partido = p.id_partido AND a.id_jugador = s.id_jugador)
ORDER BY p.numero_partido, pa.nombre;

-- Cambios por lesión en los primeros 20 minutos.
SELECT p.numero_partido, pa.nombre AS seleccion, js.apellido AS sale, je.apellido AS entra, c.minuto, c.motivo
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
INNER JOIN Torneo.JUGADOR AS js ON js.id_jugador = c.id_jugador_sale
INNER JOIN Torneo.JUGADOR AS je ON je.id_jugador = c.id_jugador_entra
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = js.id_lista
INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
WHERE c.motivo = 'LESION' AND c.minuto <= 20;

-- Partidos en prime time en más de cuatro mercados candidatos (mercados de las piezas de
-- campañas vigentes ese día): la asignación eligió solo cuatro piezas.
SELECT p.numero_partido, p.fecha_hora_utc, COUNT(*) AS mercados_candidatos_en_prime_time,
       (SELECT COUNT(*) FROM Publicidad.fn_PrioridadPiezas(p.id_partido))               AS piezas_candidatas,
       (SELECT COUNT(*) FROM Publicidad.EXHIBICION AS ex WHERE ex.id_partido = p.id_partido) AS piezas_exhibidas
FROM Torneo.PARTIDO AS p
CROSS APPLY Publicidad.fn_MercadosEnPrimeTime(p.id_partido) AS m
WHERE m.en_prime_time = 1
  AND EXISTS (SELECT 1
              FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
              INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = ppi.id_pieza
              INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
              WHERE ppi.id_pais = m.id_pais
                AND CAST(p.fecha_hora_local AS DATE) BETWEEN c.fecha_inicio AND c.fecha_fin)
GROUP BY p.id_partido, p.numero_partido, p.fecha_hora_utc
HAVING COUNT(*) > 4
ORDER BY p.numero_partido;

-- Importaciones con errores parciales: se cargaron los registros válidos y se informaron los rechazados.
SELECT id_importacion, proceso, origen, leidos, insertados, actualizados, sin_cambios, rechazados
FROM DatosGenerales.IMPORTACION
WHERE rechazados > 0
ORDER BY id_importacion;
GO

SET NOEXEC OFF;
GO
