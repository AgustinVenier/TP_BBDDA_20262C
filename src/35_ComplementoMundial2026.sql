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
 Archivo: 35_ComplementoMundial2026.sql
 Objetivo: Completar el Mundial 2026 real que carga 32_ImportarMundial2026.sql
           con los datos que ninguna fuente publica, inventados para que sean
           verosímiles, y mostrar los casos obligatorios de la consigna sobre
           el torneo real:
             1. Idiomas de los árbitros.
             2. Motivo de los cambios (lesiones).
             3. Ayudantes del cuerpo técnico.
             4. Reemplazos de último momento en las listas (reales).
             5. Informes post-partido y sanciones de los árbitros.
             6. Publicidad: anunciantes, campañas, piezas y la asignación de
                las piezas a los espacios de cada partido.
             7. Una designación arbitral rechazada por conflicto de nacionalidad.
             8. Evidencia de los casos obligatorios.
           Para la base del torneo real: ejecutar 00 a 30, el 34, el 32 y
           después este script. Sobre la base del torneo de prueba (31) no hace
           nada: el 31 ya trae estos datos.
================================================================================

 Qué se inventa y con qué criterio:
   1. Idiomas: todos los árbitros hablan inglés (el idioma de trabajo de los
      árbitros FIFA) y, además, el idioma oficial de su país. Se cargan solo a
      los árbitros que todavía no tienen idiomas.
   2. Cambios: el archivo de partidos no dice el motivo y el importador los
      registra como TACTICO. Un cambio antes del minuto 30 y fuera del
      entretiempo casi siempre es por lesión: esos pasan a LESION. Así queda el
      cambio por lesión en los primeros 20 minutos que pide la consigna.
   3. Ayudantes: Wikipedia publica solo al director técnico. Cada selección
      recibe un ayudante de campo y un preparador físico, nacidos en su país,
      con nombres armados combinando el nombre de un jugador con el apellido
      de otro de la misma selección, para que suenen de ese país.
   4. Reemplazos: no se inventan. Son los que publica la página de planteles
      de Wikipedia ("X withdrew injured and was replaced by Y on June N")
      entre la presentación de las listas (1 de junio, la fecha de la
      importación) y el primer partido de cada selección. El reemplazante ya
      está en la lista (vino en el CSV): se le pone la fecha y el motivo del
      alta. El lesionado no está (el CSV es la lista final): se lo agrega dado
      de baja, con el dorsal y la posición del reemplazante, porque la fuente
      no los publica y el reemplazante hereda el dorsal (como en
      usp_ReemplazarJugador).
   5. Informes y sanciones: el informe post-partido del árbitro principal
      resume la disciplina real del partido (amarillas y expulsiones, con
      jugador y minuto). Sanciones hay dos, ficticias pero basadas en hechos
      del torneo: la terna del partido de la expulsión de Balogun, que la
      FIFA dejó sin efecto, y la del partido inaugural, con tres expulsiones.
   6. Publicidad: los mismos anunciantes, campañas y piezas ficticios del 31.
      Las piezas se asignan a los espacios de cada partido con el mismo
      criterio que Publicidad.usp_AsignarPublicidadPartido (la pieza de mayor
      prioridad según fn_PrioridadPiezas va al espacio de mayor tarifa). Ese
      SP solo asigna partidos PROGRAMADOS y uno por vez; los del torneo real ya
      se jugaron, así que la asignación se hace acá para todos juntos, con un
      INSERT.
   7. Todas las designaciones ya están cargadas y los partidos terminaron: el
      intento de designar a un árbitro del país de una de las selecciones se
      rechaza también por eso, pero el mensaje muestra el conflicto.
 Se puede ejecutar más de una vez: lo que ya está cargado no se repite.
 Sin bucles: cada sección es un INSERT o un UPDATE sobre todas las filas.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Solo sobre la base del torneo real: los partidos tienen que venir de la importación (32).
IF NOT EXISTS (SELECT 1 FROM Torneo.PARTIDO)
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.IMPORTACION WHERE proceso = 'Torneo.usp_ImportarSedesJSON')
BEGIN
    PRINT N'35_ComplementoMundial2026.sql: la base tiene que tener el torneo real del 32. '
        + N'Recreá la base con 00 a 30, el 34 y el 32, y volvé a ejecutarlo.';
    SET NOEXEC ON;
END;
GO


/* ============================================================================
   1. IDIOMAS DE LOS ÁRBITROS
   ============================================================================ */
BEGIN TRY
    DECLARE @idioma_pais TABLE (codigo_fifa CHAR(3) PRIMARY KEY, codigo_iso CHAR(2));
    INSERT INTO @idioma_pais (codigo_fifa, codigo_iso)
    VALUES ('ALG', 'ar'), ('ANG', 'pt'), ('ARG', 'es'), ('AUS', 'en'), ('BEL', 'nl'), ('BRA', 'pt'),
           ('CAN', 'fr'), ('CHI', 'es'), ('CHN', 'zh'), ('CMR', 'fr'), ('COL', 'es'), ('CRC', 'es'),
           ('CRO', 'hr'), ('EGY', 'ar'), ('ENG', 'en'), ('ESP', 'es'), ('FRA', 'fr'), ('GAB', 'fr'),
           ('GER', 'de'), ('HON', 'es'), ('ITA', 'it'), ('JAM', 'en'), ('JOR', 'ar'), ('JPN', 'ja'),
           ('KSA', 'ar'), ('MAR', 'ar'), ('MEX', 'es'), ('MTN', 'ar'), ('NCA', 'es'), ('NED', 'nl'),
           ('NOR', 'no'), ('NZL', 'en'), ('PAR', 'es'), ('PER', 'es'), ('POL', 'pl'), ('POR', 'pt'),
           ('QAT', 'ar'), ('ROU', 'ro'), ('RSA', 'en'), ('SLV', 'es'), ('SUI', 'de'), ('SVN', 'sl'),
           ('SWE', 'sv'), ('UAE', 'ar'), ('URU', 'es'), ('USA', 'en'), ('UZB', 'uz'), ('VEN', 'es');

    -- Inglés y el idioma del país (si es otro), para los árbitros sin idiomas.
    INSERT INTO Arbitraje.ARBITRO_IDIOMA (id_arbitro, id_idioma)
    SELECT DISTINCT a.id_arbitro, i.id_idioma
    FROM Arbitraje.ARBITRO AS a
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
    LEFT JOIN @idioma_pais AS ip ON ip.codigo_fifa = pa.codigo_fifa
    INNER JOIN DatosGenerales.IDIOMA AS i ON i.codigo_iso IN ('en', ip.codigo_iso)
    WHERE NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA AS ai WHERE ai.id_arbitro = a.id_arbitro);

    PRINT CONCAT(N'Idiomas: ', @@ROWCOUNT, N' idiomas de árbitros cargados.');
END TRY
BEGIN CATCH
    PRINT N'Error al cargar los idiomas de los árbitros: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   2. CAMBIOS POR LESIÓN
   ============================================================================ */
UPDATE DesarrolloPartido.CAMBIO
SET motivo = 'LESION'
WHERE motivo = 'TACTICO' AND en_entretiempo = 0 AND minuto < 30;

PRINT CONCAT(N'Cambios: ', @@ROWCOUNT, N' cambios antes del minuto 30 pasan a LESION.');
GO


/* ============================================================================
   3. AYUDANTES DEL CUERPO TÉCNICO
   Nombre del jugador 14.º y apellido del 22.º de la lista (por dorsal) para
   el ayudante de campo; nombre del 17.º y apellido del 24.º para el
   preparador físico: suplentes, para que no queden apellidos de las figuras.
   Se saltean los conocidos por un solo nombre (Casemiro Casemiro); si por
   eso la lista queda más corta, la posición da la vuelta.
   ============================================================================ */
WITH plantel AS (
    SELECT l.id_seleccion, s.id_pais, j.nombre, j.apellido,
           ROW_NUMBER() OVER (PARTITION BY l.id_seleccion ORDER BY j.dorsal, j.id_jugador) AS n,
           COUNT(*) OVER (PARTITION BY l.id_seleccion) AS total
    FROM Torneo.JUGADOR AS j
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
    WHERE j.fecha_baja IS NULL AND j.nombre <> j.apellido
)
INSERT INTO Torneo.PERSONA_CUERPO_TECNICO (id_seleccion, id_pais_nacimiento, nombre, apellido, rol)
SELECT pn.id_seleccion, pn.id_pais, pn.nombre, pa.apellido, r.rol
FROM (VALUES ('AYUDANTE_CAMPO', 14, 22), ('PREPARADOR_FISICO', 17, 24)) AS r (rol, de_nombre, de_apellido)
INNER JOIN plantel AS pn ON pn.n = (r.de_nombre - 1) % pn.total + 1
INNER JOIN plantel AS pa ON pa.id_seleccion = pn.id_seleccion AND pa.n = (r.de_apellido - 1) % pa.total + 1
WHERE NOT EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
                  WHERE ct.id_seleccion = pn.id_seleccion AND ct.rol = r.rol);

PRINT CONCAT(N'Cuerpo técnico: ', @@ROWCOUNT, N' ayudantes cargados.');
GO


/* ============================================================================
   4. REEMPLAZOS DE ÚLTIMO MOMENTO (de Wikipedia, 2026 FIFA World Cup squads)
   ============================================================================ */
BEGIN TRY
    DECLARE @reemplazos TABLE (
        codigo_fifa     CHAR(3),
        nombre_sale     NVARCHAR(60),
        apellido_sale   NVARCHAR(60),
        fecha_baja      DATE,
        motivo_baja     VARCHAR(200),
        nombre_entra    NVARCHAR(60),
        apellido_entra  NVARCHAR(60),
        fecha_alta      DATE,
        motivo_alta     VARCHAR(200)
    );
    INSERT INTO @reemplazos
    VALUES ('BIH', N'Osman',      N'Hadžikić',    '2026-06-01', 'Lesión', N'Mladen',      N'Jurkas',      '2026-06-01', 'Reemplazo de Osman Hadzikic, lesionado'),
           ('BIH', N'Nidal',      N'Čelik',       '2026-06-11', 'Lesión', N'Arjan',       N'Malić',       '2026-06-11', 'Reemplazo de Nidal Celik, lesionado'),
           ('BRA', N'Wesley',     N'Wesley',      '2026-06-07', 'Lesión', N'Éderson',     N'Silva',       '2026-06-07', 'Reemplazo de Wesley, lesionado'),
           ('HAI', N'Leverton',   N'Pierre',      '2026-06-11', 'Lesión', N'Garven',      N'Metusala',    '2026-06-11', 'Reemplazo de Leverton Pierre, lesionado'),
           ('MAR', N'Abde',       N'Ezzalzouli',  '2026-06-10', 'Lesión', N'Amine',       N'Sbaï',        '2026-06-10', 'Reemplazo de Abde Ezzalzouli, lesionado'),
           ('MAR', N'Nayef',      N'Aguerd',      '2026-06-10', 'Lesión', N'Marwane',     N'Saâdane',     '2026-06-10', 'Reemplazo de Nayef Aguerd, lesionado'),
           ('GER', N'Lennart',    N'Karl',        '2026-06-05', 'Lesión', N'Assan',       N'Ouédraogo',   '2026-06-05', 'Reemplazo de Lennart Karl, lesionado'),
           ('JPN', N'Wataru',     N'Endo',        '2026-06-11', 'Lesión', N'Shūto',       N'Machino',     '2026-06-11', 'Reemplazo de Wataru Endo, lesionado'),
           ('NED', N'Jurriën',    N'Timber',      '2026-06-08', 'Lesión', N'Lutsharel',   N'Geertruida',  '2026-06-08', 'Reemplazo de Jurrien Timber, lesionado'),
           ('IRQ', N'Ahmed',      N'Yahya',       '2026-06-06', 'Lesión en el isquiotibial', N'Ahmed', N'Maknzi', '2026-06-06', 'Reemplazo de Ahmed Yahya, lesionado'),
           ('ARG', N'Leonardo',   N'Balerdi',     '2026-06-06', 'Lesión en el gemelo', N'Marcos', N'Senesi',    '2026-06-11', 'Reemplazo de Leonardo Balerdi, lesionado'),
           ('AUT', N'Christoph',  N'Baumgartner', '2026-06-02', 'Lesión', N'Dejan',       N'Ljubičić',    '2026-06-10', 'Reemplazo de Christoph Baumgartner, lesionado'),
           ('JOR', N'Ibrahim',    N'Sabra',       '2026-06-05', 'Lesión', N'Mohammad',    N'Abu Ghoush',  '2026-06-08', 'Reemplazo de Ibrahim Sabra, lesionado'),
           ('UZB', N'Jaloliddin', N'Masharipov',  '2026-06-15', 'Lesión en la espalda', N'Ruslanbek', N'Jiyanov', '2026-06-15', 'Reemplazo de Jaloliddin Masharipov, lesionado'),
           ('ENG', N'Tino',       N'Livramento',  '2026-06-16', 'Lesión', N'Trevoh',      N'Chalobah',    '2026-06-16', 'Reemplazo de Tino Livramento, lesionado'),
           ('GHA', N'Alexander',  N'Djiku',       '2026-06-01', 'Lesión', N'Derrick',     N'Luckassen',   '2026-06-01', 'Reemplazo de Alexander Djiku, lesionado');

    BEGIN TRANSACTION;

    -- El lesionado, dado de baja, con el dorsal y la posición del reemplazante.
    INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_alta, motivo_alta,
                                fecha_baja, motivo_baja)
    SELECT l.id_lista, r.nombre_sale, r.apellido_sale, e.posicion_habitual, e.dorsal, l.fecha_presentacion,
           e.motivo_alta, r.fecha_baja, r.motivo_baja
    FROM @reemplazos AS r
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = r.codigo_fifa
    INNER JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = s.id_seleccion
    INNER JOIN Torneo.JUGADOR AS e
        ON e.id_lista = l.id_lista AND e.nombre = r.nombre_entra AND e.apellido = r.apellido_entra
    WHERE NOT EXISTS (SELECT 1 FROM Torneo.JUGADOR AS x
                      WHERE x.id_lista = l.id_lista AND x.nombre = r.nombre_sale AND x.apellido = r.apellido_sale);

    -- El reemplazante: fecha y motivo de su alta.
    UPDATE e
    SET fecha_alta = r.fecha_alta, motivo_alta = r.motivo_alta
    FROM @reemplazos AS r
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = r.codigo_fifa
    INNER JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = s.id_seleccion
    INNER JOIN Torneo.JUGADOR AS e
        ON e.id_lista = l.id_lista AND e.nombre = r.nombre_entra AND e.apellido = r.apellido_entra
    WHERE ISNULL(e.motivo_alta, '') <> r.motivo_alta;

    COMMIT TRANSACTION;

    DECLARE @registrados INT = (SELECT COUNT(*) FROM Torneo.JUGADOR WHERE motivo_alta LIKE 'Reemplazo de %');
    PRINT CONCAT(N'Reemplazos: ', @registrados, N' reemplazos de último momento registrados.');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al registrar los reemplazos: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   5. INFORMES POST-PARTIDO Y SANCIONES DE LOS ÁRBITROS
   ============================================================================ */
-- El informe del árbitro principal: resultado y disciplina del partido (los jugadores, por
-- dorsal y selección).
UPDATE d
SET informe_postpartido = CONCAT(
        pl.nombre, ' ', p.goles_local, '-', p.goles_visitante, ' ', pv.nombre,
        IIF(p.penales_local IS NOT NULL, CONCAT(' (', p.penales_local, '-', p.penales_visitante, ' en penales)'), ''),
        '. ',
        IIF(ISNULL(t.amarillas, 0) + ISNULL(t.rojas, 0) = 0, 'Sin amonestaciones ni expulsiones.',
            CONCAT('Amarillas: ', ISNULL(t.amarillas, 0), '. Expulsiones: ', ISNULL(t.rojas, 0), '.')),
        ' ' + x.expulsiones)
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
INNER JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = p.id_seleccion_local
INNER JOIN DatosGenerales.PAIS AS pl ON pl.id_pais = sl.id_pais
INNER JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = p.id_seleccion_visitante
INNER JOIN DatosGenerales.PAIS AS pv ON pv.id_pais = sv.id_pais
CROSS APPLY (SELECT SUM(IIF(a.tipo_tarjeta = 'AMARILLA', 1, 0)) AS amarillas,
                    SUM(IIF(a.tipo_tarjeta = 'ROJA', 1, 0))     AS rojas
             FROM DesarrolloPartido.AMONESTACION AS a
             WHERE a.id_partido = p.id_partido) AS t
OUTER APPLY (SELECT STRING_AGG(CONCAT('Expulsado el dorsal ', j.dorsal, ' de ', pj.nombre, ' (minuto ', a.minuto, ', ',
                                      IIF(a.es_doble_amarilla = 1, 'doble amarilla', 'roja directa'), ').'), ' ')
                    WITHIN GROUP (ORDER BY a.minuto) AS expulsiones
             FROM DesarrolloPartido.AMONESTACION AS a
             INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
             INNER JOIN Torneo.LISTA_CONVOCADOS AS lj ON lj.id_lista = j.id_lista
             INNER JOIN Torneo.SELECCION AS sj ON sj.id_seleccion = lj.id_seleccion
             INNER JOIN DatosGenerales.PAIS AS pj ON pj.id_pais = sj.id_pais
             WHERE a.id_partido = p.id_partido AND a.tipo_tarjeta = 'ROJA') AS x
WHERE d.rol = 'PRINCIPAL' AND d.informe_postpartido IS NULL;

PRINT CONCAT(N'Informes: ', @@ROWCOUNT, N' informes post-partido cargados.');

-- Sanciones: el principal y el VAR del partido de la expulsión de Balogun (USA-BIH, dieciseisavos) y
-- el principal del partido inaugural.
UPDATE d
SET sancion = CASE WHEN p.numero_partido = 1
                   THEN 'Evaluación de desempeño: la Comisión de Árbitros revisa las tres expulsiones del partido inaugural.'
                   WHEN d.rol = 'PRINCIPAL'
                   THEN 'Observación de la Comisión de Árbitros por la expulsión de Balogun, cuya suspensión la FIFA dejó sin efecto.'
                   ELSE 'Observación de la Comisión de Árbitros por la revisión del VAR que llevó a la expulsión de Balogun.'
              END
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
INNER JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = p.id_seleccion_local
INNER JOIN DatosGenerales.PAIS AS pl ON pl.id_pais = sl.id_pais
INNER JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = p.id_seleccion_visitante
INNER JOIN DatosGenerales.PAIS AS pv ON pv.id_pais = sv.id_pais
WHERE d.sancion IS NULL
  AND ((p.numero_partido = 1 AND d.rol = 'PRINCIPAL')
    OR (p.fase = 'DIECISEISAVOS' AND 'USA' IN (pl.codigo_fifa, pv.codigo_fifa) AND 'BIH' IN (pl.codigo_fifa, pv.codigo_fifa)
        AND d.rol IN ('PRINCIPAL', 'VAR')));

PRINT CONCAT(N'Sanciones: ', @@ROWCOUNT, N' sanciones a árbitros cargadas.');
GO


/* ============================================================================
   6. PUBLICIDAD
   La campaña de 2025 queda como historial: no es candidata en este torneo.
   ============================================================================ */
BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais)
    SELECT a.razon_social, pa.id_pais
    FROM (VALUES (N'Bebidas del Plata S.A.',  'ARG'), (N'Samba Motors Ltda.',     'BRA'),
                 (N'Iberia Seguros S.L.',     'ESP'), (N'Rheinwerk AG',           'GER'),
                 (N'Sakura Electronics K.K.', 'JPN'), (N'Northstar Telecom Inc.', 'USA'),
                 (N'Atlas Airways S.A.',      'MAR'), (N'Maple Foods Ltd.',       'CAN'),
                 (N'Cervecería Azteca S.A.',  'MEX')) AS a (razon_social, codigo_fifa)
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = a.codigo_fifa
    WHERE NOT EXISTS (SELECT 1 FROM Publicidad.ANUNCIANTE AS x WHERE x.razon_social = a.razon_social);

    INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin)
    SELECT an.id_anunciante, c.nombre, c.inicio, c.fin
    FROM (VALUES (N'Bebidas del Plata S.A.',  N'Brindá con la Selección',      '2026-06-01', '2026-07-31'),
                 (N'Samba Motors Ltda.',      N'Samba Motors Mundial',         '2026-06-01', '2026-07-31'),
                 (N'Iberia Seguros S.L.',     N'Seguros para la hinchada',     '2026-06-01', '2026-07-20'),
                 (N'Rheinwerk AG',            N'Rheinwerk Weltmeister',        '2026-06-01', '2026-07-31'),
                 (N'Sakura Electronics K.K.', N'Sakura en alta definición',    '2026-06-10', '2026-07-15'),
                 (N'Northstar Telecom Inc.',  N'Northstar conecta el Mundial', '2026-06-01', '2026-07-31'),
                 (N'Atlas Airways S.A.',      N'Volá a la fase de grupos',     '2026-06-11', '2026-06-30'),
                 (N'Maple Foods Ltd.',        N'Maple Game Day',               '2026-06-15', '2026-07-19'),
                 (N'Cervecería Azteca S.A.',  N'Cerveza oficial del aguante',  '2026-06-01', '2026-07-31'),
                 (N'Bebidas del Plata S.A.',  N'Copa de verano 2025',          '2025-06-01', '2025-07-31'))
         AS c (anunciante, nombre, inicio, fin)
    INNER JOIN Publicidad.ANUNCIANTE AS an ON an.razon_social = c.anunciante
    WHERE NOT EXISTS (SELECT 1 FROM Publicidad.CAMPANIA AS x
                      WHERE x.id_anunciante = an.id_anunciante AND x.nombre = c.nombre);

    DECLARE @piezas TABLE (titulo NVARCHAR(150) PRIMARY KEY, campania NVARCHAR(150), mercados VARCHAR(100),
                           idioma CHAR(2), duracion TINYINT);
    INSERT INTO @piezas (campania, titulo, mercados, idioma, duracion)
    VALUES (N'Brindá con la Selección',      N'Panel Río de la Plata',     'ARG,URU,PAR', 'es', 30),
           (N'Brindá con la Selección',      N'Panel Brasil',              'BRA',         'pt', 30),
           (N'Samba Motors Mundial',         N'Samba Motors Brasil',       'BRA',         'pt', 20),
           (N'Samba Motors Mundial',         N'Samba Motors Cono Sur',     'ARG,CHI',     'es', 20),
           (N'Seguros para la hinchada',     N'Iberia España',             'ESP',         'es', 15),
           (N'Seguros para la hinchada',     N'Iberia Latinoamérica',      'MEX,COL',     'es', 15),
           (N'Rheinwerk Weltmeister',        N'Rheinwerk Europa central',  'GER,AUT,SUI', 'de', 25),
           (N'Rheinwerk Weltmeister',        N'Rheinwerk Norteamérica',    'USA,CAN',     'en', 25),
           (N'Sakura en alta definición',    N'Sakura Japón',              'JPN',         'ja', 20),
           (N'Sakura en alta definición',    N'Sakura Corea',              'KOR',         'ko', 20),
           (N'Sakura en alta definición',    N'Sakura Oceanía',            'AUS',         'en', 20),
           (N'Northstar conecta el Mundial', N'Northstar Estados Unidos',  'USA',         'en', 30),
           (N'Northstar conecta el Mundial', N'Northstar Canadá',          'CAN',         'fr', 30),
           (N'Northstar conecta el Mundial', N'Northstar México',          'MEX',         'es', 30),
           (N'Volá a la fase de grupos',     N'Atlas Magreb',              'MAR,ALG',     'ar', 15),
           (N'Volá a la fase de grupos',     N'Atlas Francia y Senegal',   'FRA,SEN',     'fr', 15),
           (N'Maple Game Day',               N'Maple Canadá',              'CAN',         'en', 20),
           (N'Maple Game Day',               N'Maple Reino Unido',         'SCO,ENG',     'en', 20),
           (N'Cerveza oficial del aguante',  N'Azteca México',             'MEX',         'es', 25),
           (N'Cerveza oficial del aguante',  N'Azteca comunidad latina',   'USA',         'es', 25),
           (N'Copa de verano 2025',          N'Panel verano 2025',         'ARG',         'es', 30);

    INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo, duracion_segundos)
    SELECT c.id_campania, i.id_idioma, p.titulo, p.duracion
    FROM @piezas AS p
    INNER JOIN Publicidad.CAMPANIA AS c ON c.nombre = p.campania
    INNER JOIN DatosGenerales.IDIOMA AS i ON i.codigo_iso = p.idioma
    WHERE NOT EXISTS (SELECT 1 FROM Publicidad.PIEZA_PUBLICITARIA AS x
                      WHERE x.id_campania = c.id_campania AND x.titulo = p.titulo);

    -- Los mercados de interés de cada pieza.
    INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
    SELECT pz.id_pieza, pa.id_pais
    FROM @piezas AS p
    INNER JOIN Publicidad.CAMPANIA AS c ON c.nombre = p.campania
    INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania AND pz.titulo = p.titulo
    CROSS APPLY STRING_SPLIT(p.mercados, ',') AS m
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = m.value
    WHERE NOT EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES AS x
                      WHERE x.id_pieza = pz.id_pieza AND x.id_pais = pa.id_pais);

    -- Las cuatro piezas de mayor prioridad de cada partido, en los espacios de su sede de mayor a
    -- menor tarifa (el criterio de usp_AsignarPublicidadPartido), para los partidos sin publicidad.
    INSERT INTO Publicidad.EXHIBICION (id_partido, id_espacio, id_pieza, costo, codigo_moneda)
    SELECT p.id_partido, e.id_espacio, pr.id_pieza, e.tarifa_usd, 'USD'
    FROM Torneo.PARTIDO AS p
    CROSS APPLY (SELECT id_espacio, tarifa_usd, ROW_NUMBER() OVER (ORDER BY tarifa_usd DESC, numero_espacio) AS orden
                 FROM Publicidad.ESPACIO_PUBLICITARIO
                 WHERE id_sede = p.id_sede) AS e
    CROSS APPLY Publicidad.fn_PrioridadPiezas(p.id_partido) AS pr
    WHERE pr.prioridad = e.orden
      AND NOT EXISTS (SELECT 1 FROM Publicidad.EXHIBICION AS x WHERE x.id_partido = p.id_partido);

    COMMIT TRANSACTION;

    SELECT 'Publicidad' AS seccion,
           (SELECT COUNT(*) FROM Publicidad.ANUNCIANTE) AS anunciantes,
           (SELECT COUNT(*) FROM Publicidad.CAMPANIA) AS campanias,
           (SELECT COUNT(*) FROM Publicidad.PIEZA_PUBLICITARIA) AS piezas,
           (SELECT COUNT(DISTINCT id_partido) FROM Publicidad.EXHIBICION) AS partidos_con_publicidad,
           (SELECT COUNT(*) FROM Publicidad.EXHIBICION) AS exhibiciones;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT N'Error al cargar la publicidad: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   7. DESIGNACIÓN RECHAZADA POR CONFLICTO DE NACIONALIDAD
   El primer partido que tenga una selección del país de algún árbitro: se
   intenta designar a ese árbitro como cuarto árbitro.
   ============================================================================ */
DECLARE @id_partido INT, @id_arbitro INT, @numero TINYINT, @arbitro NVARCHAR(130), @pais VARCHAR(60);

SELECT TOP (1) @id_partido = p.id_partido, @numero = p.numero_partido, @id_arbitro = a.id_arbitro,
       @arbitro = a.nombre + N' ' + a.apellido, @pais = pa.nombre
FROM Torneo.PARTIDO AS p
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)
INNER JOIN Arbitraje.ARBITRO AS a ON a.id_pais = s.id_pais
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
ORDER BY p.numero_partido, a.apellido;

BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id_arbitro, @rol = 'CUARTO';
    PRINT N'ATENCIÓN: la designación con conflicto de nacionalidad no fue rechazada.';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Designación rechazada, como se esperaba: ', @arbitro, N' (', @pais, N') en el partido ', @numero,
                 N'.', NCHAR(13), NCHAR(10), ERROR_MESSAGE());
END CATCH;
GO


/* ============================================================================
   8. EVIDENCIA DE LOS CASOS OBLIGATORIOS Y DE LO COMPLETADO
   ============================================================================ */
-- Expulsiones: por doble amarilla y roja directa.
SELECT 'Expulsiones' AS caso, p.numero_partido, IIF(am.es_doble_amarilla = 1, 'DOBLE AMARILLA', 'ROJA DIRECTA') AS tipo,
       j.nombre, j.apellido, am.minuto
FROM DesarrolloPartido.AMONESTACION AS am
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = am.id_partido
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = am.id_jugador
WHERE am.tipo_tarjeta = 'ROJA'
ORDER BY tipo, p.numero_partido;

-- Jugadores suspendidos: los que no pueden jugar un partido por una sanción anterior.
SELECT 'Suspendidos' AS caso, p.numero_partido, j.nombre, j.apellido, su.motivo, su.numero_partido_origen,
       IIF(EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS al
                   INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = al.id_formacion
                   WHERE f.id_partido = p.id_partido AND al.id_jugador = su.id_jugador), 'JUGÓ', 'AFUERA') AS formacion
FROM Torneo.PARTIDO AS p
CROSS APPLY DesarrolloPartido.fn_JugadoresSuspendidos(p.id_partido) AS su
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = su.id_jugador
ORDER BY su.motivo, p.numero_partido;

-- Cambios por lesión en los primeros 20 minutos.
SELECT 'Lesión antes del minuto 20' AS caso, p.numero_partido, js.apellido AS sale, je.apellido AS entra, c.minuto
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
INNER JOIN Torneo.JUGADOR AS js ON js.id_jugador = c.id_jugador_sale
INNER JOIN Torneo.JUGADOR AS je ON je.id_jugador = c.id_jugador_entra
WHERE c.motivo = 'LESION' AND c.minuto <= 20
ORDER BY c.minuto, p.numero_partido;

-- Partidos con más de cuatro piezas candidatas que lo ven en prime time: fn_PrioridadPiezas elige cuatro.
SELECT TOP (10) 'Prime time en más de 4 mercados' AS caso, p.numero_partido, p.fecha_hora_utc,
       pt.mercados_en_prime_time, pt.piezas_en_prime_time
FROM Torneo.PARTIDO AS p
CROSS APPLY (SELECT COUNT(*) AS mercados_en_prime_time
             FROM Publicidad.fn_MercadosEnPrimeTime(p.id_partido) AS m
             WHERE m.en_prime_time = 1
               AND EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES AS ppi WHERE ppi.id_pais = m.id_pais)) AS mp
CROSS APPLY (SELECT mp.mercados_en_prime_time,
                    (SELECT COUNT(*) FROM Publicidad.fn_PrioridadPiezas(p.id_partido) AS pr
                     WHERE pr.mercados_en_prime_time > 0) AS piezas_en_prime_time) AS pt
WHERE pt.mercados_en_prime_time > 4
ORDER BY pt.mercados_en_prime_time DESC, p.numero_partido;

-- Cuerpo técnico por selección.
SELECT 'Cuerpo técnico' AS caso, pa.nombre AS seleccion,
       MAX(IIF(ct.rol = 'DIRECTOR_TECNICO', ct.nombre + ' ' + ct.apellido, NULL))  AS director_tecnico,
       MAX(IIF(ct.rol = 'AYUDANTE_CAMPO', ct.nombre + ' ' + ct.apellido, NULL))    AS ayudante_campo,
       MAX(IIF(ct.rol = 'PREPARADOR_FISICO', ct.nombre + ' ' + ct.apellido, NULL)) AS preparador_fisico
FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
GROUP BY pa.nombre
ORDER BY pa.nombre;

-- Reemplazos de último momento.
SELECT 'Reemplazos' AS caso, pa.nombre AS seleccion, b.nombre + ' ' + b.apellido AS sale, b.fecha_baja, b.motivo_baja,
       a.nombre + ' ' + a.apellido AS entra, a.fecha_alta, a.dorsal
FROM Torneo.JUGADOR AS b
INNER JOIN Torneo.JUGADOR AS a ON a.id_lista = b.id_lista AND a.dorsal = b.dorsal AND a.fecha_baja IS NULL
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = b.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE b.fecha_baja IS NOT NULL
ORDER BY a.fecha_alta, pa.nombre;

-- Informes y sanciones de los árbitros (los partidos con expulsiones o sanción).
SELECT 'Informes y sanciones' AS caso, p.numero_partido, d.rol, ar.nombre + ' ' + ar.apellido AS arbitro,
       d.informe_postpartido, d.sancion
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
INNER JOIN Arbitraje.ARBITRO AS ar ON ar.id_arbitro = d.id_arbitro
WHERE d.sancion IS NOT NULL OR (d.rol = 'PRINCIPAL' AND d.informe_postpartido LIKE '%Expulsado%')
ORDER BY p.numero_partido, d.rol;
GO

SET NOEXEC OFF;
GO
