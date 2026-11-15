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
 Archivo: 33_Cargar_DatosComplementarios.sql
 Objetivo: Completar el Mundial 2026 real con lo que no traen las fuentes
           importadas, para que todas las tablas tengan datos y los reportes
           muestren información representativa. No repite nada de lo que ya
           se importa: sedes, selecciones, jugadores, partidos y árbitros
           vienen del 32 (openfootball y scraping), las campañas argentinas
           del Dossier Mundial y las cotizaciones y feriados de las APIs
           y el PBI per cápita vienen del 31.
           Requiere haber ejecutado 01 a 32. Se puede ejecutar más de una
           vez: lo que ya está cargado no se vuelve a cargar.
================================================================================

 Qué carga (son datos inventados, porque no hay una fuente de donde sacarlos):
   0. Los feriados del período del torneo de los países que la API
      Nager.Date no cubre (no son inventados: ver la sección 0).
   1. Los roles del cuerpo técnico que le faltan a cada selección: ayudante
      de campo, preparador físico y entrenador de arqueros (el director
      técnico real lo importa el 32; si alguna selección no lo tuviera, se
      inventa también). Los nombres se arman combinando dos listas y no son
      personas reales. También completa la fecha de nacimiento que le faltaba
      a los directores técnicos reales.
   2. Los idiomas y fechas de nacimiento de cada árbitro que no los tiene: el
      del país del árbitro y el inglés (idioma FIFA), y una fecha de
      nacimiento determinística entre 32 y 47 años.
   3. Anunciantes de 8 países (Argentina ya la cubre el Dossier), con 8
      campañas del torneo y una de 2025, como historial. Sus piezas apuntan
      a mercados de América, Europa, África, Asia y Oceanía, que no cubren
      las del Dossier (solo Argentina).
   4. Las tarifas de los espacios publicitarios de cada sede con partidos,
      proporcionales a su capacidad: el archivo de sedes no trae tarifas y el
      32 les pone a todas las de lista, con lo que los ingresos de todos los
      partidos salían iguales.
   5. La publicidad de cada partido: las 4 piezas que propone
      Publicidad.usp_AsignarPublicidadPartido, como registro histórico de lo
      que se exhibió (los partidos se importaron ya jugados). El costo de cada
      exhibición es la tarifa del espacio más el recargo por ronda
      eliminatoria y por mercados de la pieza en prime time
      (Publicidad.fn_RecargosPublicidad).
   6. Los motivos de los cambios y de las tarjetas, que el archivo de
      partidos no trae. Los cambios antes del minuto 30 que no se hicieron en
      el entretiempo pasan a LESION (uno tan temprano casi siempre es por
      lesión). Las tarjetas que quedaron "Sin detalle en la fuente" reciben
      un motivo inventado de una lista según el tipo (amarilla, roja directa
      o doble amarilla), elegido con el id de la tarjeta.
   7. Los reemplazos de último momento por lesión. No son inventados: son
      los que publica la página de planteles de Wikipedia ("X withdrew
      injured and was replaced by Y on June N") entre la presentación de
      las listas (1 de junio) y el primer partido de cada selección. Lo
      inventado es el dorsal y la posición del que sale, que la fuente no
      publica: se toman del reemplazante, que hereda su dorsal.
   8. El banco de suplentes completo de cada formación: el archivo de
      partidos trae solo a los suplentes que entraron. Se agregan los demás
      convocados que estaban en la lista el día del partido, salvo los
      suspendidos para ese partido.
   9. La asistencia de unos 2 de cada 3 goles de jugada: el archivo de
      partidos no dice quién asistió. El que asiste es un compañero del
      autor que estaba en cancha en ese minuto (con más chance un
      mediocampista o un delantero que un defensor; nunca el arquero),
      elegido con un hash para que sea siempre el mismo.
   10. El informe post-partido del árbitro principal de cada partido, que
      resume la disciplina real del partido (amarillas y expulsiones, por
      dorsal y selección), y dos sanciones ficticias basadas en hechos del
      torneo: la terna del partido de la expulsión de Balogun, que la FIFA
      dejó sin efecto, y el principal del partido inaugural, con tres
      expulsiones.
 Se cargan con los SP de carga masiva (usp_Cargar...) y de negocio, sobre
 tablas armadas acá, nunca con INSERT directo. No es una importación, así
 que no se registra en DatosGenerales.IMPORTACION: si algún dato se
 rechaza, se muestran los motivos y no se ejecuta el resto.

 Casos obligatorios de la consigna (sección IV), al final del script:
   - Doble amarilla y roja directa, suspensión por acumulación que deja al
     jugador afuera del partido siguiente, importación con errores
     parciales: vienen del torneo real y de su importación (32).
   - Cambio por lesión en los primeros 20 minutos: los de la parte 6.
   - Partido en prime time en más de cuatro mercados candidatos, en el que
     la asignación elige solo cuatro piezas: los de la parte 5.
   - Designación descartada por conflicto de nacionalidad: la parte 11 la
     intenta, dentro de una transacción que se deshace.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Se ejecuta sobre la base con el torneo real (32) y el PBI per cápita (31), que usa la
-- asignación de publicidad para priorizar las piezas.
IF NOT EXISTS (SELECT 1 FROM Torneo.PARTIDO)
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO WHERE codigo_indicador = 'NY.GDP.PCAP.CD')
BEGIN
    PRINT N'33_Cargar_DatosComplementarios.sql: la base tiene que tener el torneo real (32) y el PBI per cápita (31). '
        + N'Ejecutá los scripts 01 a 32 y volvé a ejecutar este.';
    SET NOEXEC ON;
END;
GO

-- Las tablas que leen los SP de carga masiva, por si quedaron de una ejecución anterior en esta
-- sesión. Va en un lote aparte: cada lote se compila contra las tablas que ya existen.
DROP TABLE IF EXISTS #staging_cuerpo_tecnico, #staging_arbitros, #staging_campanias, #staging_piezas, #staging_sedes,
                     #staging_designaciones, #staging_eventos, #staging_reemplazos, #staging_informes,
                     #staging_feriados;
GO


/* ============================================================================
   0. FERIADOS DE LOS PAÍSES QUE NAGER.DATE NO CUBRE
   Nager.Date no tiene feriados de Irán, Arabia Saudita, Catar, Uzbekistán,
   Jordania, India ni Emiratos Árabes Unidos (responde sin contenido). Se
   cargan los feriados nacionales del período del torneo (11/06 al
   19/07/2026); Arabia Saudita, Catar y Uzbekistán no tienen ninguno en ese
   período. Son del calendario lunar islámico y su fecha se confirma con la
   observación de la luna: son las fechas previstas, a verificar con el
   calendario oficial de cada país. Solo se cargan para los países que no
   tienen ningún feriado de 2026 cargado.
   ============================================================================ */
CREATE TABLE #staging_feriados (
    id_pais  SMALLINT       NULL,
    fecha    DATE           NULL,
    nombre   NVARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,
    errores  NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
    accion   VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_feriados (id_pais, fecha, nombre)
SELECT p.id_pais, f.fecha, f.nombre
FROM (VALUES ('IR', CAST('2026-06-24' AS DATE), N'Tasua'),
             ('IR', CAST('2026-06-25' AS DATE), N'Ashura'),
             ('IN', CAST('2026-06-26' AS DATE), N'Muharram (Ashura)'),
             ('AE', CAST('2026-06-16' AS DATE), N'Año Nuevo Islámico'),
             ('JO', CAST('2026-06-16' AS DATE), N'Año Nuevo Islámico')) AS f (codigo_iso2, fecha, nombre)
INNER JOIN DatosGenerales.PAIS AS p ON p.codigo_iso2 = f.codigo_iso2
WHERE NOT EXISTS (SELECT 1 FROM DatosGenerales.FERIADO AS fe
                  WHERE fe.id_pais = p.id_pais AND fe.fecha BETWEEN '2026-01-01' AND '2026-12-31');

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC DatosGenerales.usp_CargarFeriados;

    IF EXISTS (SELECT 1 FROM #staging_feriados WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT pa.nombre AS pais, sf.fecha, sf.nombre, STUFF(sf.errores, 1, 2, N'') AS motivos
        FROM #staging_feriados AS sf
        LEFT JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = sf.id_pais
        WHERE sf.accion = 'RECHAZADO';
        ROLLBACK TRANSACTION;
        PRINT N'Feriados: hay feriados rechazados (ver la grilla); no se cargó ninguno.';
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        DECLARE @feriados INT = (SELECT COUNT(*) FROM #staging_feriados WHERE accion = 'INSERTADO');
        PRINT CONCAT(N'Feriados: ', @feriados, N' feriados de países que la API no cubre.');
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al cargar los feriados: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;

DROP TABLE #staging_feriados;
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

-- Las selecciones se numeran por código FIFA; los roles que la selección ya tiene no se tocan.
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
WHERE NOT EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
                  WHERE ct.id_seleccion = s.id_seleccion AND ct.rol = r.rol);

-- Los directores técnicos ya importados pero que no traían fecha de nacimiento en el archivo:
INSERT INTO #staging_cuerpo_tecnico (id_registro, codigo_fifa, nombre, apellido, rol, fecha_nacimiento,
                                     codigo_fifa_nacimiento)
SELECT (SELECT ISNULL(MAX(id_registro), 0) FROM #staging_cuerpo_tecnico) + ROW_NUMBER() OVER (ORDER BY ct.id_persona_ct),
       pa.codigo_fifa,
       ct.nombre,
       ct.apellido,
       ct.rol,
       DATEADD(DAY, (ct.id_persona_ct * 43) % 365,
               DATEADD(YEAR, -(45 + (ct.id_persona_ct * 11) % 24), CAST('2025-01-01' AS DATE))),
       ISNULL(pa_nac.codigo_fifa, pa.codigo_fifa)
FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = ct.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
LEFT JOIN DatosGenerales.PAIS AS pa_nac ON pa_nac.id_pais = ct.id_pais_nacimiento
WHERE ct.fecha_nacimiento IS NULL;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Torneo.usp_CargarCuerpoTecnico;

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
        DECLARE @personas INT = (SELECT COUNT(*) FROM #staging_cuerpo_tecnico WHERE accion IN ('INSERTADO', 'ACTUALIZADO'));
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
   2. IDIOMAS Y FECHAS DE NACIMIENTO DE LOS ÁRBITROS
   El idioma del país de cada árbitro (los de los países que no figuran
   acá, como Inglaterra o Estados Unidos, solo hablan inglés) y el inglés.
   También asigna una fecha de nacimiento realista y determinística
   (entre 32 y 47 años) si no la tienen, completando los datos personales.
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

-- Los árbitros que todavía no tienen idiomas o no tienen fecha de nacimiento; la categoría es la que
-- ya tienen. El nombre y el apellido salen de Arbitraje.vw_HistorialArbitro, que los devuelve legibles
-- también con los datos personales cifrados; todos los árbitros tienen designaciones, porque se
-- cargan desde el archivo de designaciones (32).
INSERT INTO #staging_arbitros (id_registro, codigo_fifa, nombre, apellido, categoria, fecha_nacimiento, idiomas)
SELECT ROW_NUMBER() OVER (ORDER BY a.id_arbitro), pa.codigo_fifa, h.nombre, h.apellido, a.categoria,
       DATEADD(DAY, (a.id_arbitro * 37) % 365,
               DATEADD(YEAR, -(32 + (a.id_arbitro * 7) % 16), CAST('2026-01-01' AS DATE))),
       CONCAT(ip.idiomas + ',', 'en')
FROM Arbitraje.ARBITRO AS a
INNER JOIN (SELECT DISTINCT id_arbitro, nombre, apellido FROM Arbitraje.vw_HistorialArbitro) AS h
        ON h.id_arbitro = a.id_arbitro
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
LEFT JOIN @idiomas_pais AS ip ON ip.codigo_fifa = pa.codigo_fifa
WHERE NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA AS ai WHERE ai.id_arbitro = a.id_arbitro)
   OR a.fecha_nacimiento IS NULL;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Arbitraje.usp_CargarArbitros;

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
        DECLARE @arbitros INT = (SELECT COUNT(*) FROM #staging_arbitros WHERE accion IN ('INSERTADO', 'ACTUALIZADO'));
        PRINT CONCAT(N'Idiomas y fechas de los árbitros: cargados para ', @arbitros, N' árbitros.');
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
    EXEC Publicidad.usp_CargarCampanias;

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
   4. TARIFAS DE LAS SEDES SEGÚN SU CAPACIDAD
   El archivo de sedes no trae tarifas, así que el 32 les puso a todas las de
   lista de Torneo.usp_ImportarSedesJSON (120000, 100000, 90000 y 80000 USD)
   y los ingresos de todos los partidos salían iguales. Cada sede con partidos
   recibe esas tarifas de lista multiplicadas por su capacidad sobre una de
   referencia de 70000 espectadores, redondeadas al millar: un estadio de
   94000 cobra 1,34 veces la lista y uno de 45000, 0,64. Va antes de asignar
   la publicidad, porque el costo de cada exhibición se calcula con la tarifa
   vigente en ese momento. Se carga con Torneo.usp_CargarSedes, que actualiza
   las tarifas de una sede existente; como el cálculo parte de la lista y no
   de la tarifa actual, ejecutarlo de nuevo da SIN CAMBIOS.
   ============================================================================ */
CREATE TABLE #staging_sedes (
    id_registro     INT           PRIMARY KEY,
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
    errores         NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion          VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_sedes (id_registro, nombre_estadio, tarifa_1, tarifa_2, tarifa_3, tarifa_4)
SELECT ROW_NUMBER() OVER (ORDER BY s.id_sede), s.nombre_estadio,
       ROUND(120000 * f.factor, -3), ROUND(100000 * f.factor, -3), ROUND(90000 * f.factor, -3), ROUND(80000 * f.factor, -3)
FROM Torneo.SEDE AS s
CROSS APPLY (SELECT s.capacidad / 70000.0 AS factor) AS f
WHERE EXISTS (SELECT 1 FROM Torneo.PARTIDO AS p WHERE p.id_sede = s.id_sede);

BEGIN TRY
    EXEC Torneo.usp_CargarSedes;

    IF EXISTS (SELECT 1 FROM #staging_sedes WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT nombre_estadio, STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_sedes WHERE accion = 'RECHAZADO' ORDER BY id_registro;
        PRINT N'Tarifas de las sedes: hay sedes rechazadas (ver la grilla); la publicidad se asigna igual.';
    END;

    SELECT N'Tarifas según capacidad' AS carga, COUNT(*) AS sedes,
           ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0)  AS actualizadas,
           ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0)  AS sin_cambios,
           ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)    AS rechazadas
    FROM #staging_sedes;

    SELECT s.nombre_estadio, s.capacidad,
           (SELECT STRING_AGG(CAST(CAST(e.tarifa_usd AS INT) AS NVARCHAR(10)), N', ') WITHIN GROUP (ORDER BY e.numero_espacio)
            FROM Publicidad.ESPACIO_PUBLICITARIO AS e WHERE e.id_sede = s.id_sede) AS tarifas_usd
    FROM Torneo.SEDE AS s
    INNER JOIN #staging_sedes AS st ON st.nombre_estadio = s.nombre_estadio
    ORDER BY s.capacidad DESC;
END TRY
BEGIN CATCH
    PRINT N'Error al cargar las tarifas de las sedes: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   5. PUBLICIDAD DE CADA PARTIDO
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
   6. MOTIVOS DE LOS CAMBIOS Y DE LAS TARJETAS
   Con DesarrolloPartido.usp_CargarDesarrolloPartidos, que de un cambio o
   una tarjeta ya cargados actualiza solo el motivo (los reconoce por el jugador, el minuto
   y, en las tarjetas, el tipo):
   - Los cambios antes del minuto 30 que no se hicieron en el entretiempo y
     todavía figuran como TACTICO pasan a LESION.
   - Las tarjetas "Sin detalle en la fuente" toman un motivo de la lista de
     su tipo: el resto de dividir su id por el largo de la lista dice cuál.
     Así se reparten entre todos los motivos. Si el script se ejecuta de
     nuevo, ya no quedan tarjetas sin detalle que cambiar.
   ============================================================================ */
CREATE TABLE #staging_eventos (
    id_evento           INT           PRIMARY KEY,
    tipo                VARCHAR(12)   COLLATE DATABASE_DEFAULT NOT NULL,
    numero_partido      TINYINT       NOT NULL,
    codigo_fifa         VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    id_jugador          INT           NULL,
    id_jugador_entra    INT           NULL,
    id_jugador_asistencia INT         NULL,
    es_titular          BIT           NULL,
    posicion_en_cancha  VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
    minuto              TINYINT       NULL,
    minuto_adicional    TINYINT       NULL,
    en_entretiempo      BIT           NULL,
    motivo              VARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,
    periodo             VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL,
    tipo_gol            VARCHAR(40)   COLLATE DATABASE_DEFAULT NULL,
    tipo_tarjeta        VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    es_doble_amarilla   BIT           NULL,
    errores             NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion              VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_eventos (id_evento, tipo, numero_partido, id_jugador, id_jugador_entra, minuto,
                              minuto_adicional, en_entretiempo, motivo)
SELECT ROW_NUMBER() OVER (ORDER BY p.numero_partido, c.minuto, c.id_cambio), 'CAMBIO', p.numero_partido,
       c.id_jugador_sale, c.id_jugador_entra, c.minuto, c.minuto_adicional, c.en_entretiempo, 'LESION'
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
WHERE c.motivo = 'TACTICO' AND c.en_entretiempo = 0 AND c.minuto < 30;

-- Las tarjetas sin detalle, numeradas a continuación de los cambios.
INSERT INTO #staging_eventos (id_evento, tipo, numero_partido, id_jugador, minuto, minuto_adicional,
                              tipo_tarjeta, es_doble_amarilla, motivo)
SELECT (SELECT COUNT(*) FROM #staging_eventos) + ROW_NUMBER() OVER (ORDER BY p.numero_partido, am.minuto, am.id_amonestacion),
       'TARJETA', p.numero_partido, am.id_jugador, am.minuto, am.minuto_adicional,
       am.tipo_tarjeta, am.es_doble_amarilla,
       -- CHOOSE(n, ...) devuelve el motivo número n de la lista; n sale del id (1 a 5 o 1 a 8).
       CASE WHEN am.es_doble_amarilla = 1 THEN 'Segunda amarilla en el partido'
            WHEN am.tipo_tarjeta = 'ROJA'
                THEN CHOOSE(am.id_amonestacion % 5 + 1,
                            'Juego brusco grave', 'Conducta violenta', 'Malograr una ocasión manifiesta de gol',
                            'Lenguaje ofensivo hacia el árbitro', 'Mano para evitar un gol')
            ELSE CHOOSE(am.id_amonestacion % 8 + 1,
                        'Falta táctica para cortar un contraataque', 'Entrada imprudente',
                        'Protestar una decisión del árbitro', 'Demorar la reanudación del juego', 'Simulación',
                        'Mano deliberada', 'Sujetar a un rival', 'Quitarse la camiseta al festejar un gol')
       END
FROM DesarrolloPartido.AMONESTACION AS am
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = am.id_partido
WHERE am.motivo = 'Sin detalle en la fuente'
  AND am.id_jugador IS NOT NULL;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC DesarrolloPartido.usp_CargarDesarrolloPartidos;

    IF EXISTS (SELECT 1 FROM #staging_eventos WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT tipo, numero_partido, id_jugador, id_jugador_entra, minuto, STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_eventos WHERE accion = 'RECHAZADO' ORDER BY id_evento;
        ROLLBACK TRANSACTION;
        PRINT N'Motivos de cambios y tarjetas: hay eventos rechazados (ver la grilla); no se cambió ninguno.';
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        DECLARE @lesiones INT = (SELECT COUNT(*) FROM #staging_eventos WHERE tipo = 'CAMBIO' AND accion = 'ACTUALIZADO');
        DECLARE @tarjetas INT = (SELECT COUNT(*) FROM #staging_eventos WHERE tipo = 'TARJETA' AND accion = 'ACTUALIZADO');
        PRINT CONCAT(N'Cambios por lesión: ', @lesiones, N' cambios antes del minuto 30 pasan a LESION.');
        PRINT CONCAT(N'Motivos de las tarjetas: ', @tarjetas, N' tarjetas sin detalle reciben un motivo.');
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al registrar los motivos de cambios y tarjetas: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;

DROP TABLE #staging_eventos;
GO


/* ============================================================================
   7. REEMPLAZOS DE ÚLTIMO MOMENTO (2026 FIFA World Cup squads, Wikipedia)
   ============================================================================ */
CREATE TABLE #staging_reemplazos (
    id_registro     INT           PRIMARY KEY,
    codigo_fifa     VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    nombre_sale     NVARCHAR(60)  COLLATE DATABASE_DEFAULT NULL,
    apellido_sale   NVARCHAR(60)  COLLATE DATABASE_DEFAULT NULL,
    fecha_baja      DATE          NULL,
    motivo_baja     VARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,
    nombre_entra    NVARCHAR(60)  COLLATE DATABASE_DEFAULT NULL,
    apellido_entra  NVARCHAR(60)  COLLATE DATABASE_DEFAULT NULL,
    fecha_alta      DATE          NULL,
    motivo_alta     VARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,
    errores         NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion          VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

-- Los motivos son VARCHAR: los nombres con letras que no tiene (Čelik, Hadžikić) van sin tilde.
INSERT INTO #staging_reemplazos (id_registro, codigo_fifa, nombre_sale, apellido_sale, fecha_baja, motivo_baja,
                                 nombre_entra, apellido_entra, fecha_alta, motivo_alta)
VALUES (1,  'BIH', N'Osman',      N'Hadžikić',    '2026-06-01', 'Lesión',                    N'Mladen',    N'Jurkas',     '2026-06-01', 'Reemplazo de Osman Hadzikic, lesionado'),
       (2,  'BIH', N'Nidal',      N'Čelik',       '2026-06-11', 'Lesión',                    N'Arjan',     N'Malić',      '2026-06-11', 'Reemplazo de Nidal Celik, lesionado'),
       (3,  'BRA', N'Wesley',     N'Wesley',      '2026-06-07', 'Lesión',                    N'Éderson',   N'Silva',      '2026-06-07', 'Reemplazo de Wesley, lesionado'),
       (4,  'HAI', N'Leverton',   N'Pierre',      '2026-06-11', 'Lesión',                    N'Garven',    N'Metusala',   '2026-06-11', 'Reemplazo de Leverton Pierre, lesionado'),
       (5,  'MAR', N'Abde',       N'Ezzalzouli',  '2026-06-10', 'Lesión',                    N'Amine',     N'Sbaï',       '2026-06-10', 'Reemplazo de Abde Ezzalzouli, lesionado'),
       (6,  'MAR', N'Nayef',      N'Aguerd',      '2026-06-10', 'Lesión',                    N'Marwane',   N'Saâdane',    '2026-06-10', 'Reemplazo de Nayef Aguerd, lesionado'),
       (7,  'GER', N'Lennart',    N'Karl',        '2026-06-05', 'Lesión',                    N'Assan',     N'Ouédraogo',  '2026-06-05', 'Reemplazo de Lennart Karl, lesionado'),
       (8,  'JPN', N'Wataru',     N'Endo',        '2026-06-11', 'Lesión',                    N'Shūto',     N'Machino',    '2026-06-11', 'Reemplazo de Wataru Endo, lesionado'),
       (9,  'NED', N'Jurriën',    N'Timber',      '2026-06-08', 'Lesión',                    N'Lutsharel', N'Geertruida', '2026-06-08', 'Reemplazo de Jurrien Timber, lesionado'),
       (10, 'IRQ', N'Ahmed',      N'Yahya',       '2026-06-06', 'Lesión en el isquiotibial', N'Ahmed',     N'Maknzi',     '2026-06-06', 'Reemplazo de Ahmed Yahya, lesionado'),
       (11, 'ARG', N'Leonardo',   N'Balerdi',     '2026-06-06', 'Lesión en el gemelo',       N'Marcos',    N'Senesi',     '2026-06-11', 'Reemplazo de Leonardo Balerdi, lesionado'),
       (12, 'AUT', N'Christoph',  N'Baumgartner', '2026-06-02', 'Lesión',                    N'Dejan',     N'Ljubičić',   '2026-06-10', 'Reemplazo de Christoph Baumgartner, lesionado'),
       (13, 'JOR', N'Ibrahim',    N'Sabra',       '2026-06-05', 'Lesión',                    N'Mohammad',  N'Abu Ghoush', '2026-06-08', 'Reemplazo de Ibrahim Sabra, lesionado'),
       (14, 'UZB', N'Jaloliddin', N'Masharipov',  '2026-06-15', 'Lesión en la espalda',      N'Ruslanbek', N'Jiyanov',    '2026-06-15', 'Reemplazo de Jaloliddin Masharipov, lesionado'),
       (15, 'ENG', N'Tino',       N'Livramento',  '2026-06-16', 'Lesión',                    N'Trevoh',    N'Chalobah',   '2026-06-16', 'Reemplazo de Tino Livramento, lesionado'),
       (16, 'GHA', N'Alexander',  N'Djiku',       '2026-06-01', 'Lesión',                    N'Derrick',   N'Luckassen',  '2026-06-01', 'Reemplazo de Alexander Djiku, lesionado');

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Torneo.usp_CargarReemplazos;

    IF EXISTS (SELECT 1 FROM #staging_reemplazos WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT codigo_fifa, nombre_sale, apellido_sale, nombre_entra, apellido_entra, STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_reemplazos WHERE accion = 'RECHAZADO' ORDER BY id_registro;
        ROLLBACK TRANSACTION;
        PRINT N'Reemplazos: hay reemplazos rechazados (ver la grilla); no se cargó ninguno.';
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        DECLARE @reemplazos INT = (SELECT COUNT(*) FROM #staging_reemplazos WHERE accion = 'INSERTADO');
        PRINT CONCAT(N'Reemplazos: ', @reemplazos, N' reemplazos de último momento registrados.');
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al registrar los reemplazos: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;

DROP TABLE #staging_reemplazos;
GO


/* ============================================================================
   8. BANCOS DE SUPLENTES COMPLETOS
   El archivo de partidos trae en el banco solo a los suplentes que entraron.
   Se agregan los demás convocados de cada selección que estaban en la lista
   el día del partido (dados de alta y no dados de baja) y no estaban
   suspendidos para ese partido (fn_JugadoresSuspendidos), con
   DesarrolloPartido.usp_CargarDesarrolloPartidos, que completa una
   formación ya cargada.
   ============================================================================ */
CREATE TABLE #staging_eventos (
    id_evento           INT           PRIMARY KEY,
    tipo                VARCHAR(12)   COLLATE DATABASE_DEFAULT NOT NULL,
    numero_partido      TINYINT       NOT NULL,
    codigo_fifa         VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    id_jugador          INT           NULL,
    id_jugador_entra    INT           NULL,
    id_jugador_asistencia INT         NULL,
    es_titular          BIT           NULL,
    posicion_en_cancha  VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
    minuto              TINYINT       NULL,
    minuto_adicional    TINYINT       NULL,
    en_entretiempo      BIT           NULL,
    motivo              VARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,
    periodo             VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL,
    tipo_gol            VARCHAR(40)   COLLATE DATABASE_DEFAULT NULL,
    tipo_tarjeta        VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    es_doble_amarilla   BIT           NULL,
    errores             NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion              VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_eventos (id_evento, tipo, numero_partido, id_jugador, es_titular)
SELECT ROW_NUMBER() OVER (ORDER BY p.numero_partido, f.id_seleccion, j.dorsal), 'FORMACION', p.numero_partido,
       j.id_jugador, 0
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = f.id_seleccion
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista
WHERE j.fecha_alta <= CAST(p.fecha_hora_local AS DATE)
  AND (j.fecha_baja IS NULL OR j.fecha_baja > CAST(p.fecha_hora_local AS DATE))
  AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS a
                  WHERE a.id_formacion = f.id_formacion AND a.id_jugador = j.id_jugador)
  AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.fn_JugadoresSuspendidos(p.id_partido) AS su
                  WHERE su.id_jugador = j.id_jugador);

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC DesarrolloPartido.usp_CargarDesarrolloPartidos;

    IF EXISTS (SELECT 1 FROM #staging_eventos WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT numero_partido, id_jugador, STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_eventos WHERE accion = 'RECHAZADO' ORDER BY id_evento;
        ROLLBACK TRANSACTION;
        PRINT N'Bancos de suplentes: hay jugadores rechazados (ver la grilla); no se agregó ninguno.';
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        DECLARE @suplentes INT = (SELECT COUNT(*) FROM #staging_eventos WHERE accion = 'INSERTADO');
        PRINT CONCAT(N'Bancos de suplentes: ', @suplentes, N' suplentes agregados a las formaciones.');
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al completar los bancos de suplentes: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;

DROP TABLE #staging_eventos;
GO


/* ============================================================================
   9. ASISTENCIAS DE LOS GOLES
   El archivo de partidos no trae quién asistió. Se inventa la asistencia de
   unos 2 de cada 3 goles de jugada (la proporción habitual en el fútbol);
   los de penal, en contra y de la definición no tienen. Qué goles y quién
   asiste salen de un hash del partido, el minuto y los dorsales, no del
   azar: cada ejecución elige lo mismo. El que asiste es un compañero del
   autor que estaba en cancha en ese minuto, según
   DesarrolloPartido.fn_EquipoEnCancha. Un mediocampista o un delantero
   tiene más chance que un defensor, y el arquero nunca asiste.
   Se cargan con DesarrolloPartido.usp_CargarDesarrolloPartidos, que a un
   gol ya cargado le agrega la asistencia. Solo se completan los goles que no tienen asistencia.
   ============================================================================ */
CREATE TABLE #staging_eventos (
    id_evento           INT           PRIMARY KEY,
    tipo                VARCHAR(12)   COLLATE DATABASE_DEFAULT NOT NULL,
    numero_partido      TINYINT       NOT NULL,
    codigo_fifa         VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    id_jugador          INT           NULL,
    id_jugador_entra    INT           NULL,
    id_jugador_asistencia INT         NULL,
    es_titular          BIT           NULL,
    posicion_en_cancha  VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
    minuto              TINYINT       NULL,
    minuto_adicional    TINYINT       NULL,
    en_entretiempo      BIT           NULL,
    motivo              VARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,
    periodo             VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL,
    tipo_gol            VARCHAR(40)   COLLATE DATABASE_DEFAULT NULL,
    tipo_tarjeta        VARCHAR(10)   COLLATE DATABASE_DEFAULT NULL,
    es_doble_amarilla   BIT           NULL,
    errores             NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion              VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

WITH goles AS (
    SELECT g.id_gol, p.id_partido, p.numero_partido, g.id_jugador_autor, l.id_seleccion,
           tg.descripcion AS tipo_gol, g.periodo, g.minuto, g.minuto_adicional
    FROM DesarrolloPartido.GOL AS g
    INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
    INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
    INNER JOIN Torneo.JUGADOR AS ja ON ja.id_jugador = g.id_jugador_autor
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = ja.id_lista
    WHERE tg.descripcion = 'JUGADA' AND g.periodo <> 'PENALES' AND g.id_jugador_asistencia IS NULL
      AND ABS(CHECKSUM(p.numero_partido, g.minuto, g.minuto_adicional, ja.dorsal)) % 3 <> 0
),
candidatos AS (
    SELECT go.id_gol, go.numero_partido, go.id_jugador_autor, go.tipo_gol, go.periodo, go.minuto, go.minuto_adicional,
           ec.id_jugador AS id_jugador_asistencia,
           ROW_NUMBER() OVER (PARTITION BY go.id_gol
                              -- Un puntaje del 0 al 99 por jugador; el de un defensor se duplica (menos chance).
                              ORDER BY ABS(CHECKSUM(go.numero_partido, go.minuto, go.minuto_adicional, j.dorsal)) % 100
                                       * IIF(j.posicion_habitual = 'DEFENSOR', 2, 1),
                                       j.dorsal) AS orden
    FROM goles AS go
    -- Los compañeros del autor que estaban en cancha en el minuto del gol.
    CROSS APPLY DesarrolloPartido.fn_EquipoEnCancha(go.id_partido, go.id_seleccion, go.minuto, go.minuto_adicional) AS ec
    INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = ec.id_jugador
    WHERE ec.id_jugador <> go.id_jugador_autor
      AND j.posicion_habitual <> 'ARQUERO'
)
INSERT INTO #staging_eventos (id_evento, tipo, numero_partido, id_jugador, id_jugador_asistencia, periodo, tipo_gol, minuto,
                              minuto_adicional)
SELECT ROW_NUMBER() OVER (ORDER BY numero_partido, minuto, minuto_adicional, id_gol), 'GOL', numero_partido,
       id_jugador_autor, id_jugador_asistencia, periodo, tipo_gol, minuto, minuto_adicional
FROM candidatos
WHERE orden = 1;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC DesarrolloPartido.usp_CargarDesarrolloPartidos;

    IF EXISTS (SELECT 1 FROM #staging_eventos WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT numero_partido, id_jugador, id_jugador_asistencia, minuto, STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_eventos WHERE accion = 'RECHAZADO' ORDER BY id_evento;
        ROLLBACK TRANSACTION;
        PRINT N'Asistencias: hay asistencias rechazadas (ver la grilla); no se cargó ninguna.';
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        DECLARE @asistencias INT = (SELECT COUNT(*) FROM #staging_eventos WHERE accion = 'ACTUALIZADO');
        PRINT CONCAT(N'Asistencias: se agregó la asistencia a ', @asistencias, N' goles (los que ya la tenían no cambian).');
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al cargar las asistencias: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;

DROP TABLE #staging_eventos;
GO


/* ============================================================================
   10. INFORMES POST-PARTIDO Y SANCIONES DE LOS ÁRBITROS
   El informe del principal: resultado y disciplina del partido (los
   jugadores por dorsal y selección: el informe es VARCHAR). Las sanciones:
   el principal y el VAR del partido de la expulsión de Balogun (USA-BIH,
   dieciseisavos) y el principal del partido inaugural.
   ============================================================================ */
CREATE TABLE #staging_informes (
    id_registro          INT           PRIMARY KEY,
    numero_partido       TINYINT       NULL,
    rol                  VARCHAR(17)   COLLATE DATABASE_DEFAULT NULL,
    informe_postpartido  VARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
    sancion              VARCHAR(500)  COLLATE DATABASE_DEFAULT NULL,
    errores              NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion               VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

WITH informes AS (
    SELECT p.numero_partido, 'PRINCIPAL' AS rol,
           CONCAT(pl.nombre, ' ', p.goles_local, '-', p.goles_visitante, ' ', pv.nombre,
                  IIF(p.penales_local IS NOT NULL, CONCAT(' (', p.penales_local, '-', p.penales_visitante, ' en penales)'), ''),
                  '. ',
                  IIF(ISNULL(t.amarillas, 0) + ISNULL(t.rojas, 0) = 0, 'Sin amonestaciones ni expulsiones.',
                      CONCAT('Amarillas: ', ISNULL(t.amarillas, 0), '. Expulsiones: ', ISNULL(t.rojas, 0), '.')),
                  ' ' + x.expulsiones) AS informe
    FROM Torneo.PARTIDO AS p
    INNER JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = p.id_seleccion_local
    INNER JOIN DatosGenerales.PAIS AS pl ON pl.id_pais = sl.id_pais
    INNER JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = p.id_seleccion_visitante
    INNER JOIN DatosGenerales.PAIS AS pv ON pv.id_pais = sv.id_pais
    LEFT JOIN (SELECT a.id_partido,
                      SUM(IIF(a.tipo_tarjeta = 'AMARILLA', 1, 0)) AS amarillas,
                      SUM(IIF(a.tipo_tarjeta = 'ROJA', 1, 0))     AS rojas
               FROM DesarrolloPartido.AMONESTACION AS a
               GROUP BY a.id_partido) AS t ON t.id_partido = p.id_partido
    LEFT JOIN (SELECT a.id_partido,
                      STRING_AGG(CONCAT('Expulsado el dorsal ', j.dorsal, ' de ', pj.nombre, ' (minuto ', a.minuto, ', ',
                                        IIF(a.es_doble_amarilla = 1, 'doble amarilla', 'roja directa'), ').'), ' ')
                          WITHIN GROUP (ORDER BY a.minuto) AS expulsiones
               FROM DesarrolloPartido.AMONESTACION AS a
               INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
               INNER JOIN Torneo.LISTA_CONVOCADOS AS lj ON lj.id_lista = j.id_lista
               INNER JOIN Torneo.SELECCION AS sj ON sj.id_seleccion = lj.id_seleccion
               INNER JOIN DatosGenerales.PAIS AS pj ON pj.id_pais = sj.id_pais
               WHERE a.tipo_tarjeta = 'ROJA'
               GROUP BY a.id_partido) AS x ON x.id_partido = p.id_partido
),
sanciones AS (
    SELECT p.numero_partido, r.rol,
           CASE WHEN p.numero_partido = 1
                THEN 'Evaluación de desempeño: la Comisión de Árbitros revisa las tres expulsiones del partido inaugural.'
                WHEN r.rol = 'PRINCIPAL'
                THEN 'Observación de la Comisión de Árbitros por la expulsión de Balogun, cuya suspensión la FIFA dejó sin efecto.'
                ELSE 'Observación de la Comisión de Árbitros por la revisión del VAR que llevó a la expulsión de Balogun.'
           END AS sancion
    FROM Torneo.PARTIDO AS p
    INNER JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = p.id_seleccion_local
    INNER JOIN DatosGenerales.PAIS AS pl ON pl.id_pais = sl.id_pais
    INNER JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = p.id_seleccion_visitante
    INNER JOIN DatosGenerales.PAIS AS pv ON pv.id_pais = sv.id_pais
    CROSS JOIN (VALUES ('PRINCIPAL'), ('VAR')) AS r (rol)
    WHERE (p.numero_partido = 1 AND r.rol = 'PRINCIPAL')
       OR (p.fase = 'DIECISEISAVOS' AND 'USA' IN (pl.codigo_fifa, pv.codigo_fifa) AND 'BIH' IN (pl.codigo_fifa, pv.codigo_fifa))
)
INSERT INTO #staging_informes (id_registro, numero_partido, rol, informe_postpartido, sancion)
SELECT ROW_NUMBER() OVER (ORDER BY ISNULL(i.numero_partido, s.numero_partido), ISNULL(i.rol, s.rol)),
       ISNULL(i.numero_partido, s.numero_partido), ISNULL(i.rol, s.rol), i.informe, s.sancion
FROM informes AS i
FULL JOIN sanciones AS s ON s.numero_partido = i.numero_partido AND s.rol = i.rol;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Arbitraje.usp_CargarInformesArbitrales;

    IF EXISTS (SELECT 1 FROM #staging_informes WHERE accion = 'RECHAZADO')
    BEGIN
        SELECT numero_partido, rol, STUFF(errores, 1, 2, N'') AS motivos
        FROM #staging_informes WHERE accion = 'RECHAZADO' ORDER BY id_registro;
        ROLLBACK TRANSACTION;
        PRINT N'Informes y sanciones: hay filas rechazadas (ver la grilla); no se cargó ninguna.';
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        DECLARE @informes INT = (SELECT COUNT(*) FROM #staging_informes WHERE accion = 'ACTUALIZADO');
        PRINT CONCAT(N'Informes y sanciones: ', @informes, N' designaciones completadas.');
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al cargar los informes y sanciones: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;

DROP TABLE #staging_informes;
GO


/* ============================================================================
   11. DESIGNACIÓN DESCARTADA POR CONFLICTO DE NACIONALIDAD
   Un árbitro del país de una de las selecciones, como cuarto árbitro del
   primer partido de esa selección. La regla está en
   Arbitraje.usp_CargarDesignaciones (y en usp_DesignarTernaArbitral y
   usp_DESIGNACION_ARBITRAL_Alta). Se prueba dentro de una transacción que se deshace, así no queda nada.
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
    EXEC Arbitraje.usp_CargarDesignaciones;

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
   12. RESUMEN Y CASOS OBLIGATORIOS
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

-- Ingresos por publicidad de cada partido: dependen de las tarifas de la sede (según su capacidad) y
-- del recargo por ronda eliminatoria y por mercados de la pieza en prime time.
SELECT COUNT(*) AS partidos_con_publicidad, MIN(i.ingresos_usd) AS ingresos_minimos_usd,
       MAX(i.ingresos_usd) AS ingresos_maximos_usd, COUNT(DISTINCT i.ingresos_usd) AS valores_distintos
FROM (SELECT ex.id_partido, SUM(CAST(ex.costo AS DECIMAL(19,2))) AS ingresos_usd
      FROM Publicidad.EXHIBICION AS ex
      WHERE ex.codigo_moneda = 'USD'
      GROUP BY ex.id_partido) AS i;

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

-- Formaciones: cada una con 11 titulares y el banco completo.
SELECT COUNT(*) AS formaciones, MIN(t.titulares) AS min_titulares, MAX(t.titulares) AS max_titulares,
       MIN(t.suplentes) AS min_suplentes, MAX(t.suplentes) AS max_suplentes
FROM (SELECT f.id_formacion, SUM(IIF(a.es_titular = 1, 1, 0)) AS titulares, SUM(IIF(a.es_titular = 0, 1, 0)) AS suplentes
      FROM DesarrolloPartido.FORMACION AS f
      INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
      GROUP BY f.id_formacion) AS t;

-- Reemplazos de último momento: el que sale (dado de baja) y el que entra, con el mismo dorsal.
SELECT pa.nombre AS seleccion, b.nombre + N' ' + b.apellido AS sale, b.fecha_baja, b.motivo_baja,
       a.nombre + N' ' + a.apellido AS entra, a.fecha_alta, a.dorsal
FROM Torneo.JUGADOR AS b
INNER JOIN Torneo.JUGADOR AS a ON a.id_lista = b.id_lista AND a.dorsal = b.dorsal AND a.fecha_baja IS NULL
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = b.id_lista
INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
WHERE b.fecha_baja IS NOT NULL
ORDER BY a.fecha_alta, pa.nombre;

-- Asistencias: cuántos goles de cada tipo la tienen (solo los de jugada) y quiénes asistieron más.
SELECT tg.descripcion AS tipo_gol, COUNT(*) AS goles, COUNT(g.id_jugador_asistencia) AS con_asistencia
FROM DesarrolloPartido.GOL AS g
INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
GROUP BY tg.descripcion
ORDER BY goles DESC;

SELECT TOP (5) pa.nombre AS seleccion, j.apellido, j.nombre, j.posicion_habitual, COUNT(*) AS asistencias
FROM DesarrolloPartido.GOL AS g
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = g.id_jugador_asistencia
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
GROUP BY pa.nombre, j.id_jugador, j.apellido, j.nombre, j.posicion_habitual
ORDER BY asistencias DESC, pa.nombre;

-- Informes y sanciones de los árbitros: los partidos con expulsiones o con sanción.
SELECT p.numero_partido, d.rol, ar.nombre + N' ' + ar.apellido AS arbitro, d.informe_postpartido, d.sancion
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
INNER JOIN Arbitraje.ARBITRO AS ar ON ar.id_arbitro = d.id_arbitro
WHERE d.sancion IS NOT NULL OR (d.rol = 'PRINCIPAL' AND d.informe_postpartido LIKE '%Expulsado%')
ORDER BY p.numero_partido, d.rol;

-- Importaciones con errores parciales: se cargaron los registros válidos y se informaron los rechazados.
SELECT id_importacion, proceso, origen, leidos, insertados, actualizados, sin_cambios, rechazados
FROM DatosGenerales.IMPORTACION
WHERE rechazados > 0
ORDER BY id_importacion;
GO

SET NOEXEC OFF;
GO
