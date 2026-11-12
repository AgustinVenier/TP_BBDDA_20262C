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

 Fecha: 25/10/2026
 Archivo: 54_Test_FuncionesYVistas.sql
 Objetivo: Probar las funciones y vistas de 04_CrearFuncionesYVistas.sql:
           cotización vigente, fixture filtrable, equipo en cancha en
           distintos minutos, marcador según los goles, sanciones y
           suspensiones (también cambiando sus parámetros), selecciones en
           competencia, simulación de prime time y feriados por mercado,
           prioridad de piezas, historial de titularidad, goleadores e
           historial de árbitros.
           Requiere haber ejecutado 01 a 28 y no depende del juego de datos.
           Arma su propio mini torneo con INSERT directos a las tablas (no
           usa ningún SP), dentro de una transacción que se deshace al final:
           no deja datos y se puede ejecutar más de una vez.
             - Países de prueba (código FIFA entre paréntesis): Portugal1
               (XVA), Ghana1 (XVB), Senegal1 (XVC) e Islandia1 (XVD), con
               selección del grupo I y 23 jugadores; Moldavia1 (XVM) y
               Japón1 (XVJ), mercados; Gambia1 (XVN), de los árbitros.
             - Sedes "Mercedes-Benz Stadium1" y "NRG Stadium1".
             - Partidos 226 a 229 (febrero de 2027):
                 226 XVA - XVB (grupos): cambio por lesión en el 17, gol en
                     contra y expulsión por doble amarilla. Termina 2 - 0.
                 227 XVC - XVD (grupos): roja directa; con terna arbitral,
                     informe y sanción del principal. Termina 0 - 1.
                 228 XVA - XVC (grupos): segunda amarilla del dorsal 8 de XVA
                     (suspensión por acumulación). Termina 1 - 1.
                 229 XVA - XVD (cuartos): sin el dorsal 8 de XVA, suspendido;
                     1 - 1 en los 90, 2 - 2 en el alargue y 4 - 3 por penales.
             - Cinco árbitros de Gambia1 y el anunciante "Puma1" con dos campañas.
           Los cambios de parámetros (FV8 y FV10) se deshacen al final de su
           caso. Si el
           grupo I no tiene lugar para las cuatro selecciones de prueba (por
           ejemplo, con las 48 del Mundial cargadas), la preparación amplía
           SELECCIONES_POR_GRUPO dentro de la transacción.
================================================================================

 Cómo leer los resultados: cada consulta tiene una columna "caso" y, en el
 comentario de arriba, el resultado esperado. Si algo falla inesperadamente se
 imprime "FALLÓ" en Mensajes. Al final, la verificación tiene que mostrar 0
 datos de prueba; si no, quedó algo sin deshacer.
 Los países de prueba se llaman como uno real con un 1 al final y usan
 códigos FIFA que empiezan con X, que no tiene ningún miembro de la FIFA: las
 consultas filtran los datos de prueba por ese código.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'DesarrolloPartido.fn_EquipoEnCancha', N'IF') IS NULL
   OR OBJECT_ID(N'DesarrolloPartido.usp_RegistrarGol', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE descripcion IN ('JUGADA', 'EN CONTRA', 'PENAL', 'CABEZAZO')
                  HAVING COUNT(*) = 4)
BEGIN
    RAISERROR(N'Faltan las funciones, los SP o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Planteles de 23 jugadores de las cuatro selecciones de prueba, por código FIFA.
-- Las tablas temporales se crean en tempdb, que puede tener otra intercalación
-- que la base: el código se compara con PAIS, por eso va con COLLATE DATABASE_DEFAULT.
DROP TABLE IF EXISTS #plantel;
CREATE TABLE #plantel (codigo_fifa CHAR(3) COLLATE DATABASE_DEFAULT, dorsal TINYINT, nombre NVARCHAR(60), apellido NVARCHAR(60), posicion VARCHAR(15));
INSERT INTO #plantel (codigo_fifa, dorsal, nombre, apellido, posicion) VALUES
    ('XVA',  1, N'Diogo',     N'Costa',     'ARQUERO'),
    ('XVA', 12, N'José',      N'Sá',        'ARQUERO'),
    ('XVA', 23, N'Rui',       N'Silva',     'ARQUERO'),
    ('XVA',  2, N'Diogo',     N'Dalot',     'DEFENSOR'),
    ('XVA',  3, N'Rúben',     N'Dias',      'DEFENSOR'),
    ('XVA',  4, N'António',   N'Silva',     'DEFENSOR'),
    ('XVA',  5, N'Nuno',      N'Mendes',    'DEFENSOR'),
    ('XVA',  6, N'Gonçalo',   N'Inácio',    'DEFENSOR'),
    ('XVA', 13, N'Danilo',    N'Pereira',   'DEFENSOR'),
    ('XVA', 14, N'Nélson',    N'Semedo',    'DEFENSOR'),
    ('XVA', 15, N'João',      N'Cancelo',   'DEFENSOR'),
    ('XVA',  7, N'Bruno',     N'Fernandes', 'MEDIOCAMPISTA'),
    ('XVA',  8, N'Vitinha',   N'Ferreira',  'MEDIOCAMPISTA'),
    ('XVA', 10, N'Bernardo',  N'Silva',     'MEDIOCAMPISTA'),
    ('XVA', 16, N'João',      N'Neves',     'MEDIOCAMPISTA'),
    ('XVA', 17, N'Rúben',     N'Neves',     'MEDIOCAMPISTA'),
    ('XVA', 18, N'Otávio',    N'Monteiro',  'MEDIOCAMPISTA'),
    ('XVA',  9, N'Gonçalo',   N'Ramos',     'DELANTERO'),
    ('XVA', 11, N'João',      N'Félix',     'DELANTERO'),
    ('XVA', 19, N'Rafael',    N'Leão',      'DELANTERO'),
    ('XVA', 20, N'Pedro',     N'Neto',      'DELANTERO'),
    ('XVA', 21, N'Francisco', N'Conceição', 'DELANTERO'),
    ('XVA', 22, N'Cristiano', N'Ronaldo',   'DELANTERO'),
    ('XVB',  1, N'Lawrence',  N'Ati-Zigi',    'ARQUERO'),
    ('XVB', 12, N'Joseph',    N'Wollacott',   'ARQUERO'),
    ('XVB', 23, N'Benjamin',  N'Asare',       'ARQUERO'),
    ('XVB',  2, N'Alidu',     N'Seidu',       'DEFENSOR'),
    ('XVB',  3, N'Gideon',    N'Mensah',      'DEFENSOR'),
    ('XVB',  4, N'Mohammed',  N'Salisu',      'DEFENSOR'),
    ('XVB',  5, N'Alexander', N'Djiku',       'DEFENSOR'),
    ('XVB',  6, N'Tariq',     N'Lamptey',     'DEFENSOR'),
    ('XVB', 13, N'Daniel',    N'Amartey',     'DEFENSOR'),
    ('XVB', 14, N'Jonathan',  N'Mensah',      'DEFENSOR'),
    ('XVB', 15, N'Abdul',     N'Mumin',       'DEFENSOR'),
    ('XVB',  7, N'Thomas',    N'Partey',      'MEDIOCAMPISTA'),
    ('XVB',  8, N'Salis',     N'Abdul Samed', 'MEDIOCAMPISTA'),
    ('XVB', 10, N'Mohammed',  N'Kudus',       'MEDIOCAMPISTA'),
    ('XVB', 16, N'Elisha',    N'Owusu',       'MEDIOCAMPISTA'),
    ('XVB', 17, N'Ernest',    N'Nuamah',      'MEDIOCAMPISTA'),
    ('XVB', 18, N'Kamaldeen', N'Sulemana',    'MEDIOCAMPISTA'),
    ('XVB',  9, N'Iñaki',     N'Williams',    'DELANTERO'),
    ('XVB', 11, N'Jordan',    N'Ayew',        'DELANTERO'),
    ('XVB', 19, N'André',     N'Ayew',        'DELANTERO'),
    ('XVB', 20, N'Antoine',   N'Semenyo',     'DELANTERO'),
    ('XVB', 21, N'Osman',     N'Bukari',      'DELANTERO'),
    ('XVB', 22, N'Fatawu',    N'Issahaku',    'DELANTERO'),
    ('XVC',  1, N'Édouard',    N'Mendy',     'ARQUERO'),
    ('XVC', 12, N'Seny',       N'Dieng',     'ARQUERO'),
    ('XVC', 23, N'Mory',       N'Diaw',      'ARQUERO'),
    ('XVC',  2, N'Formose',    N'Mendy',     'DEFENSOR'),
    ('XVC',  3, N'Kalidou',    N'Koulibaly', 'DEFENSOR'),
    ('XVC',  4, N'Abdou',      N'Diallo',    'DEFENSOR'),
    ('XVC',  5, N'Moussa',     N'Niakhaté',  'DEFENSOR'),
    ('XVC',  6, N'Ismail',     N'Jakobs',    'DEFENSOR'),
    ('XVC', 13, N'Youssouf',   N'Sabaly',    'DEFENSOR'),
    ('XVC', 14, N'Abdoulaye',  N'Seck',      'DEFENSOR'),
    ('XVC', 15, N'Krépin',     N'Diatta',    'DEFENSOR'),
    ('XVC',  7, N'Idrissa',    N'Gueye',     'MEDIOCAMPISTA'),
    ('XVC',  8, N'Pape Matar', N'Sarr',      'MEDIOCAMPISTA'),
    ('XVC', 10, N'Pape',       N'Gueye',     'MEDIOCAMPISTA'),
    ('XVC', 16, N'Lamine',     N'Camara',    'MEDIOCAMPISTA'),
    ('XVC', 17, N'Nampalys',   N'Mendy',     'MEDIOCAMPISTA'),
    ('XVC', 18, N'Cheikhou',   N'Kouyaté',   'MEDIOCAMPISTA'),
    ('XVC',  9, N'Nicolas',    N'Jackson',   'DELANTERO'),
    ('XVC', 11, N'Sadio',      N'Mané',      'DELANTERO'),
    ('XVC', 19, N'Ismaïla',    N'Sarr',      'DELANTERO'),
    ('XVC', 20, N'Boulaye',    N'Dia',       'DELANTERO'),
    ('XVC', 21, N'Iliman',     N'Ndiaye',    'DELANTERO'),
    ('XVC', 22, N'Habib',      N'Diallo',    'DELANTERO'),
    ('XVD',  1, N'Hákon',       N'Valdimarsson', 'ARQUERO'),
    ('XVD', 12, N'Rúnar',       N'Rúnarsson',    'ARQUERO'),
    ('XVD', 23, N'Elías',       N'Ólafsson',     'ARQUERO'),
    ('XVD',  2, N'Alfons',      N'Sampsted',     'DEFENSOR'),
    ('XVD',  3, N'Hörður',      N'Magnússon',    'DEFENSOR'),
    ('XVD',  4, N'Sverrir',     N'Ingason',      'DEFENSOR'),
    ('XVD',  5, N'Guðlaugur',   N'Pálsson',      'DEFENSOR'),
    ('XVD',  6, N'Daníel',      N'Grétarsson',   'DEFENSOR'),
    ('XVD', 13, N'Valgeir',     N'Friðriksson',  'DEFENSOR'),
    ('XVD', 14, N'Kolbeinn',    N'Finnsson',     'DEFENSOR'),
    ('XVD', 15, N'Hjörtur',     N'Hermannsson',  'DEFENSOR'),
    ('XVD',  7, N'Jóhann Berg', N'Guðmundsson',  'MEDIOCAMPISTA'),
    ('XVD',  8, N'Arnór',       N'Sigurðsson',   'MEDIOCAMPISTA'),
    ('XVD', 10, N'Albert',      N'Guðmundsson',  'MEDIOCAMPISTA'),
    ('XVD', 16, N'Ísak',        N'Jóhannesson',  'MEDIOCAMPISTA'),
    ('XVD', 17, N'Stefán',      N'Þórðarson',    'MEDIOCAMPISTA'),
    ('XVD', 18, N'Mikael',      N'Anderson',     'MEDIOCAMPISTA'),
    ('XVD',  9, N'Orri',        N'Óskarsson',    'DELANTERO'),
    ('XVD', 11, N'Jón Dagur',   N'Þorsteinsson', 'DELANTERO'),
    ('XVD', 19, N'Andri',       N'Guðjohnsen',   'DELANTERO'),
    ('XVD', 20, N'Sveinn Aron', N'Guðjohnsen',   'DELANTERO'),
    ('XVD', 21, N'Willum',      N'Willumsson',   'DELANTERO'),
    ('XVD', 22, N'Kristian',    N'Hlynsson',     'DELANTERO');
GO

-- Todo el test corre en una transacción que se deshace al final: no deja datos de prueba.
BEGIN TRANSACTION;
GO


/* ============================================================================
   PREPARACIÓN DEL MINI TORNEO
   ============================================================================ */

-- Cupo de los grupos: las cuatro selecciones de prueba van al grupo I, porque
-- los partidos 226 a 228 son de la fase de grupos. Si el grupo no tiene lugar
-- (por ejemplo, con las 48 selecciones del Mundial cargadas), se amplía
-- SELECCIONES_POR_GRUPO; el ROLLBACK del final lo devuelve a su valor.
DECLARE @cupo TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'SELECCIONES_POR_GRUPO');
DECLARE @necesario TINYINT = (SELECT COUNT(*) FROM Torneo.SELECCION WHERE grupo = 'I') + 4;
IF @necesario > @cupo
BEGIN
    UPDATE DatosGenerales.PARAMETRO_REGLAMENTO SET valor = @necesario WHERE codigo = 'SELECCIONES_POR_GRUPO';
    PRINT CONCAT(N'El grupo I ya tiene ', @necesario - 4, N' selecciones: SELECCIONES_POR_GRUPO pasa de ',
                 @cupo, N' a ', @necesario, N' mientras dura el test.');
END;
GO

-- Países, selecciones, planteles, sedes, árbitros, publicidad y fixture.
INSERT INTO DatosGenerales.PAIS (nombre, codigo_fifa, huso_horario) VALUES
    ('Portugal1',  'XVA', 'GMT Standard Time'),
    ('Ghana1',     'XVB', 'Greenwich Standard Time'),
    ('Senegal1',   'XVC', 'Greenwich Standard Time'),
    ('Islandia1',  'XVD', 'Greenwich Standard Time'),
    ('Moldavia1',  'XVM', 'E. Europe Standard Time'),
    ('Japón1',     'XVJ', 'Tokyo Standard Time'),
    ('Gambia1',    'XVN', 'Greenwich Standard Time');
INSERT INTO DatosGenerales.INDICADOR_ECONOMICO (id_pais, codigo_indicador, anio, valor)
SELECT id_pais, 'NY.GDP.PCAP.CD', 2024, IIF(codigo_fifa = 'XVM', 60000, 90000)
FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XVM', 'XVJ');

INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo)
SELECT id_pais, IIF(codigo_fifa IN ('XVA', 'XVD'), 'UEFA', 'CAF'), 'I'
FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XVA', 'XVB', 'XVC', 'XVD');
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion)
SELECT s.id_seleccion, '2026-06-01'
FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE pa.codigo_fifa IN ('XVA', 'XVB', 'XVC', 'XVD');
INSERT INTO Torneo.PERSONA_CUERPO_TECNICO (id_seleccion, nombre, apellido, rol)
SELECT s.id_seleccion, v.nombre, v.apellido, 'DIRECTOR_TECNICO'
FROM (VALUES ('XVA', N'Roberto', N'Martínez'), ('XVB', N'Otto', N'Addo'),
             ('XVC', N'Pape', N'Thiaw'),        ('XVD', N'Arnar', N'Gunnlaugsson')) AS v (codigo_fifa, nombre, apellido)
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = v.codigo_fifa
INNER JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais;
INSERT INTO Torneo.JUGADOR (id_lista, dorsal, nombre, apellido, posicion_habitual, fecha_alta)
SELECT l.id_lista, p.dorsal, p.nombre, p.apellido, p.posicion, '2026-06-01'
FROM #plantel AS p
INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = p.codigo_fifa
INNER JOIN Torneo.SELECCION AS s ON s.id_pais = pa.id_pais
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = s.id_seleccion;

-- Ids de los jugadores por código FIFA y dorsal, para los lotes que siguen.
DROP TABLE IF EXISTS #jugadores;
SELECT pa.codigo_fifa, j.dorsal, j.id_jugador
INTO #jugadores
FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE pa.codigo_fifa LIKE 'XV_';

DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede1 INT, @sede2 INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Mercedes-Benz Stadium1', 'Atlanta', @id_pais_usa, 65000, 'Eastern Standard Time');
SET @sede1 = SCOPE_IDENTITY();
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('NRG Stadium1', 'Houston', @id_pais_usa, 70000, 'Central Standard Time');
SET @sede2 = SCOPE_IDENTITY();

-- Cinco árbitros de categoría FIFA de Gambia1 (sin selección).
DECLARE @id_pais_gambia SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XVN');
INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_gambia, N'Bakary',   N'Gassama', 'FIFA'),
    (@id_pais_gambia, N'Janny',    N'Sikazwe', 'FIFA'),
    (@id_pais_gambia, N'Victor',   N'Gomes',   'FIFA'),
    (@id_pais_gambia, N'Mustapha', N'Ghorbal', 'FIFA'),
    (@id_pais_gambia, N'Jean',     N'Ndala',   'FIFA');

-- Anunciante con dos campañas de febrero de 2027: la pieza 1 apunta a XVA (que
-- juega el partido 226) y la pieza 2, a XVM y XVJ (franja de PBI 9).
DECLARE @id_pais_moldavia SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XVM');
DECLARE @id_anunciante INT, @id_campania_1 INT, @id_campania_2 INT, @pieza1 INT, @pieza2 INT;
INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais) VALUES (N'Puma1', @id_pais_moldavia);
SET @id_anunciante = SCOPE_IDENTITY();
INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin) VALUES (@id_anunciante, N'Puma1 Campaña 1', '2027-02-01', '2027-02-28');
SET @id_campania_1 = SCOPE_IDENTITY();
INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin) VALUES (@id_anunciante, N'Puma1 Campaña 2', '2027-02-01', '2027-02-28');
SET @id_campania_2 = SCOPE_IDENTITY();
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo)
SELECT @id_campania_1, id_idioma, N'Puma Portugal' FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es';
SET @pieza1 = SCOPE_IDENTITY();
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, id_idioma, titulo)
SELECT @id_campania_2, id_idioma, N'Puma Global' FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en';
SET @pieza2 = SCOPE_IDENTITY();
INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
SELECT @pieza1, id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XVA'
UNION ALL
SELECT @pieza2, id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XVM', 'XVJ');

-- Fixture: tres partidos de grupos y uno de cuartos (todavía PROGRAMADOS).
DECLARE @id_seleccion_xva INT, @id_seleccion_xvb INT, @id_seleccion_xvc INT, @id_seleccion_xvd INT;
SELECT @id_seleccion_xva = s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XVA';
SELECT @id_seleccion_xvb = s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XVB';
SELECT @id_seleccion_xvc = s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XVC';
SELECT @id_seleccion_xvd = s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XVD';
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante) VALUES
    (226, @sede1, 'GRUPOS',  '2027-02-10 14:00', '2027-02-10 19:00', @id_seleccion_xva, @id_seleccion_xvb),
    (227, @sede2, 'GRUPOS',  '2027-02-11 13:00', '2027-02-11 19:00', @id_seleccion_xvc, @id_seleccion_xvd),
    (228, @sede1, 'GRUPOS',  '2027-02-15 14:00', '2027-02-15 19:00', @id_seleccion_xva, @id_seleccion_xvc),
    (229, @sede2, 'CUARTOS', '2027-02-20 13:00', '2027-02-20 19:00', @id_seleccion_xva, @id_seleccion_xvd);

-- Terna del partido 227.
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol)
SELECT p.id_partido, a.id_arbitro,
       CASE a.apellido WHEN N'Gassama' THEN 'PRINCIPAL' WHEN N'Sikazwe' THEN 'ASISTENTE_1'
                       WHEN N'Gomes' THEN 'ASISTENTE_2' WHEN N'Ghorbal' THEN 'CUARTO' ELSE 'VAR' END
FROM Torneo.PARTIDO AS p CROSS JOIN Arbitraje.ARBITRO AS a
WHERE p.numero_partido = 227 AND a.id_pais = @id_pais_gambia;
GO

-- Partido 226 (XVA - XVB, grupos), formaciones en 4-3-3 (titulares los
-- dorsales 1 a 11 y suplentes del 12 al 20): cambio por lesión del 4 de XVA
-- en el 17, amarilla al 8 de XVA, gol del 9 de XVA, gol en contra del 3 de
-- XVB, cambio táctico del 11 de XVA en el 60 y doble amarilla al 5 de XVB
-- (40 y 70, con su roja). Termina 2 - 0.
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);
DECLARE @jugada    TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @en_contra TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'EN CONTRA');
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico)
SELECT id_partido, id_seleccion_local, '4-3-3' FROM Torneo.PARTIDO WHERE id_partido = @id_partido
UNION ALL
SELECT id_partido, id_seleccion_visitante, '4-3-3' FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT f.id_formacion, j.id_jugador, IIF(j.dorsal <= 11, 1, 0), IIF(j.dorsal <= 11, j.posicion_habitual, NULL)
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido AND p.id_seleccion_local = f.id_seleccion
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = f.id_seleccion
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista
WHERE f.id_partido = @id_partido AND j.dorsal <= 20;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT f.id_formacion, j.id_jugador, IIF(j.dorsal <= 11, 1, 0), IIF(j.dorsal <= 11, j.posicion_habitual, NULL)
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido AND p.id_seleccion_visitante = f.id_seleccion
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = f.id_seleccion
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista
WHERE f.id_partido = @id_partido AND j.dorsal <= 20;
INSERT INTO DesarrolloPartido.CAMBIO (id_partido, id_jugador_sale, id_jugador_entra, minuto, motivo) VALUES
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 4),
          (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 13), 17, 'LESION'),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 11),
          (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 19), 60, 'TACTICO');
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, es_doble_amarilla, minuto, motivo) VALUES
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 8), 'AMARILLA', 0, 25, 'Falta imprudente'),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVB' AND dorsal = 5), 'AMARILLA', 0, 40, 'Sujetar a un rival'),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVB' AND dorsal = 5), 'AMARILLA', 0, 70, 'Demorar la reanudación'),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVB' AND dorsal = 5), 'ROJA',     1, 70, 'Doble amarilla');
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto) VALUES
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 9), @jugada,    'PRIMER_TIEMPO',  30),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVB' AND dorsal = 3), @en_contra, 'SEGUNDO_TIEMPO', 60);
UPDATE Torneo.PARTIDO SET goles_local = 2, goles_visitante = 0, asistencia = 50000, estado = 'FINALIZADO' WHERE id_partido = @id_partido;
GO

-- Partido 227 (XVC - XVD, grupos): gol del 9 de XVD y roja directa al 3 de
-- XVC; informe y sanción del árbitro principal. Termina 0 - 1.
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 227);
DECLARE @jugada TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico)
SELECT id_partido, id_seleccion_local, '4-3-3' FROM Torneo.PARTIDO WHERE id_partido = @id_partido
UNION ALL
SELECT id_partido, id_seleccion_visitante, '4-3-3' FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT f.id_formacion, j.id_jugador, IIF(j.dorsal <= 11, 1, 0), IIF(j.dorsal <= 11, j.posicion_habitual, NULL)
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido AND p.id_seleccion_local = f.id_seleccion
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = f.id_seleccion
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista
WHERE f.id_partido = @id_partido AND j.dorsal <= 20;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT f.id_formacion, j.id_jugador, IIF(j.dorsal <= 11, 1, 0), IIF(j.dorsal <= 11, j.posicion_habitual, NULL)
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido AND p.id_seleccion_visitante = f.id_seleccion
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = f.id_seleccion
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista
WHERE f.id_partido = @id_partido AND j.dorsal <= 20;
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto)
VALUES (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVD' AND dorsal = 9), @jugada, 'SEGUNDO_TIEMPO', 50);
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVC' AND dorsal = 3), 'ROJA', 58, 'Agresión a un rival');
UPDATE Torneo.PARTIDO SET goles_local = 0, goles_visitante = 1, asistencia = 40000, estado = 'FINALIZADO' WHERE id_partido = @id_partido;
UPDATE Arbitraje.DESIGNACION_ARBITRAL
SET informe_postpartido = 'Buen manejo del partido; la expulsión fue correcta.',
    sancion = 'Apercibimiento por demorar el informe.'
WHERE id_partido = @id_partido AND rol = 'PRINCIPAL';
GO

-- Partido 228 (XVA - XVC, grupos): XVC juega sin el 3 (suspendido por la roja
-- del 227; el 13 es titular). Gol del 9 de XVA, segunda amarilla del torneo
-- al 8 de XVA (suspensión por acumulación) y gol de cabeza del 9 de XVC.
-- Termina 1 - 1.
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 228);
DECLARE @jugada   TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @cabezazo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico)
SELECT id_partido, id_seleccion_local, '4-3-3' FROM Torneo.PARTIDO WHERE id_partido = @id_partido
UNION ALL
SELECT id_partido, id_seleccion_visitante, '4-3-3' FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT f.id_formacion, j.id_jugador, IIF(j.dorsal <= 11, 1, 0), IIF(j.dorsal <= 11, j.posicion_habitual, NULL)
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido AND p.id_seleccion_local = f.id_seleccion
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = f.id_seleccion
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista
WHERE f.id_partido = @id_partido AND j.dorsal <= 20;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT f.id_formacion, j.id_jugador, IIF(j.dorsal <= 11 OR j.dorsal = 13, 1, 0), IIF(j.dorsal <= 11 OR j.dorsal = 13, j.posicion_habitual, NULL)
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido AND p.id_seleccion_visitante = f.id_seleccion
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = f.id_seleccion
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista
WHERE f.id_partido = @id_partido AND j.dorsal <= 20 AND j.dorsal <> 3;
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto) VALUES
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 9), @jugada,   'PRIMER_TIEMPO',  20),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVC' AND dorsal = 9), @cabezazo, 'SEGUNDO_TIEMPO', 70);
INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto, motivo)
VALUES (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 8), 'AMARILLA', 50, 'Protestar');
UPDATE Torneo.PARTIDO SET goles_local = 1, goles_visitante = 1, asistencia = 55000, estado = 'FINALIZADO' WHERE id_partido = @id_partido;
GO

-- Partido 229 (XVA - XVD, cuartos): XVA juega sin el 8 (suspendido; el 16 es
-- titular). 1 - 1 en los 90 (9 de XVA y 9 de XVD), 2 - 2 en el alargue (10 de
-- cada uno) y penales: convierten el 9, 10, 11 y 7 de XVA y el 9, 10 y 11 de
-- XVD, en el orden en que se patearon. Termina 2 - 2 y 4 - 3 por penales.
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 229);
DECLARE @jugada TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @penal  TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
INSERT INTO DesarrolloPartido.FORMACION (id_partido, id_seleccion, esquema_tactico)
SELECT id_partido, id_seleccion_local, '4-3-3' FROM Torneo.PARTIDO WHERE id_partido = @id_partido
UNION ALL
SELECT id_partido, id_seleccion_visitante, '4-3-3' FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT f.id_formacion, j.id_jugador, IIF(j.dorsal <= 11 OR j.dorsal = 16, 1, 0), IIF(j.dorsal <= 11 OR j.dorsal = 16, j.posicion_habitual, NULL)
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido AND p.id_seleccion_local = f.id_seleccion
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = f.id_seleccion
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista
WHERE f.id_partido = @id_partido AND j.dorsal <= 20 AND j.dorsal <> 8;
INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
SELECT f.id_formacion, j.id_jugador, IIF(j.dorsal <= 11, 1, 0), IIF(j.dorsal <= 11, j.posicion_habitual, NULL)
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido AND p.id_seleccion_visitante = f.id_seleccion
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = f.id_seleccion
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista
WHERE f.id_partido = @id_partido AND j.dorsal <= 20;
INSERT INTO DesarrolloPartido.GOL (id_partido, id_jugador_autor, id_tipo_gol, periodo, minuto) VALUES
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 9),  @jugada, 'PRIMER_TIEMPO',  30),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVD' AND dorsal = 9),  @jugada, 'SEGUNDO_TIEMPO', 80),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 10), @jugada, 'ALARGUE',        100),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVD' AND dorsal = 10), @jugada, 'ALARGUE',        115),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 9),  @penal,  'PENALES',        NULL),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVD' AND dorsal = 9),  @penal,  'PENALES',        NULL),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 10), @penal,  'PENALES',        NULL),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVD' AND dorsal = 10), @penal,  'PENALES',        NULL),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 11), @penal,  'PENALES',        NULL),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVD' AND dorsal = 11), @penal,  'PENALES',        NULL),
    (@id_partido, (SELECT id_jugador FROM #jugadores WHERE codigo_fifa = 'XVA' AND dorsal = 7),  @penal,  'PENALES',        NULL);
UPDATE Torneo.PARTIDO SET goles_local = 2, goles_visitante = 2, penales_local = 4, penales_visitante = 3,
                          asistencia = 60000, estado = 'FINALIZADO'
WHERE id_partido = @id_partido;
GO

SELECT 'Mini torneo' AS caso, numero_partido, fase, seleccion_local, resultado, seleccion_visitante, estado
FROM Torneo.vw_Fixture WHERE numero_partido BETWEEN 226 AND 229 ORDER BY numero_partido;
GO


/* ============================================================================
   CASOS
   ============================================================================ */

/* FV1 fn_ParametrosDelSistema
   Esperado: los 20 parámetros del sistema están cargados y dentro de su rango
   (columna dentro_de_rango = 1 en todas las filas). */
SELECT 'FV1' AS caso, ps.codigo, pr.valor, ps.valor_minimo, ps.valor_maximo,
       IIF(pr.valor BETWEEN ps.valor_minimo AND ps.valor_maximo, 1, 0) AS dentro_de_rango
FROM DatosGenerales.fn_ParametrosDelSistema() AS ps
LEFT JOIN DatosGenerales.PARAMETRO_REGLAMENTO AS pr ON pr.codigo = ps.codigo
ORDER BY ps.codigo;
GO

/* FV1b fn_CotizacionVigente, con dos cotizaciones de XTS (el código de prueba
   de ISO 4217) que se deshacen al final del caso:
   1000 el jueves 11/06/2026 y 1010 el viernes 12/06/2026.
   Esperado: el 11/06, la del 11/06 (1000); el domingo 14/06, sin cotización
   ese día, la del viernes 12/06 (1010); el 10/06, antes de la primera, ninguna
   fila; el dólar, 1 en cualquier fecha. */
-- SAVE TRANSACTION marca un punto dentro de la transacción del test; el ROLLBACK del final del caso vuelve hasta ahí.
SAVE TRANSACTION FV1b;
BEGIN TRY
    INSERT INTO DatosGenerales.COTIZACION (codigo_moneda, fecha, unidades_por_usd) VALUES
        ('XTS', '2026-06-11', 1000),
        ('XTS', '2026-06-12', 1010);

    SELECT 'FV1b' AS caso, f.consulta, f.moneda, f.fecha, c.fecha_cotizacion, c.unidades_por_usd
    FROM (VALUES ('el mismo día', 'XTS', CAST('2026-06-11' AS DATE)),
                 ('fin de semana', 'XTS', CAST('2026-06-14' AS DATE)),
                 ('antes de la primera', 'XTS', CAST('2026-06-10' AS DATE)),
                 ('dólar', 'USD', CAST('2026-06-14' AS DATE))) AS f (consulta, moneda, fecha)
    OUTER APPLY DatosGenerales.fn_CotizacionVigente(f.moneda, f.fecha) AS c
    ORDER BY f.consulta;
END TRY
BEGIN CATCH
    PRINT N'FV1b: FALLÓ, error inesperado: ' + ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION FV1b;
GO

/* FV2 vw_Fixture y fn_Fixture con cada filtro (contando solo los partidos de prueba)
   Esperado: 4 partidos en total; 3 de GRUPOS; 3 de XVA; 2 en "Mercedes-Benz
   Stadium1"; 1 el 11/02/2027 en hora local (el 227). El detalle de XVA muestra
   el grupo I en los partidos de grupos. */
DECLARE @id_seleccion_xva INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XVA');
DECLARE @sede1 INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Mercedes-Benz Stadium1');

SELECT 'FV2' AS caso, filtro, partidos
FROM (VALUES ('Fixture completo', (SELECT COUNT(*) FROM Torneo.fn_Fixture(NULL, NULL, NULL, NULL) WHERE numero_partido BETWEEN 226 AND 229)),
             ('Fase GRUPOS',      (SELECT COUNT(*) FROM Torneo.fn_Fixture(NULL, 'GRUPOS', NULL, NULL) WHERE numero_partido BETWEEN 226 AND 229)),
             ('Selección XVA',    (SELECT COUNT(*) FROM Torneo.fn_Fixture(NULL, NULL, @id_seleccion_xva, NULL))),
             ('Sede Vistas 1',    (SELECT COUNT(*) FROM Torneo.fn_Fixture(@sede1, NULL, NULL, NULL))),
             ('Fecha 11/02/2027', (SELECT COUNT(*) FROM Torneo.fn_Fixture(NULL, NULL, NULL, '2027-02-11') WHERE numero_partido BETWEEN 226 AND 229))
     ) AS f (filtro, partidos);

SELECT 'FV2 XVA' AS caso, numero_partido, fase, grupo, fecha_hora_local, nombre_estadio,
       seleccion_local, resultado, seleccion_visitante
FROM Torneo.fn_Fixture(NULL, NULL, @id_seleccion_xva, NULL)
ORDER BY fecha_hora_utc;
GO

/* FV3 fn_EquipoEnCancha: el cambio por lesión del partido 226
   Esperado: XVA tiene 11 jugadores en cancha en los tres minutos. En el 10
   está el dorsal 4; en el 20 ya no, y está el 13, que entró en el 17 por
   lesión. En el 90 ya entró el 19 por el 11 (cambio del 60). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);
DECLARE @id_seleccion_xva INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);

SELECT 'FV3' AS caso, m.minuto, COUNT(*) AS en_cancha,
       STRING_AGG(CAST(e.dorsal AS VARCHAR(3)), ', ') WITHIN GROUP (ORDER BY e.dorsal) AS dorsales
FROM (VALUES (CAST(10 AS TINYINT)), (CAST(20 AS TINYINT)), (CAST(90 AS TINYINT))) AS m (minuto)
CROSS APPLY DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion_xva, m.minuto, 0) AS e
GROUP BY m.minuto
ORDER BY m.minuto;
GO

/* FV4 fn_EquipoEnCancha: la expulsión por doble amarilla del partido 226
   Esperado: XVB tiene 11 jugadores en el minuto 60 y 10 en el 80, sin el
   dorsal 5, expulsado en el 70. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);
DECLARE @id_seleccion_xvb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);

SELECT 'FV4' AS caso, m.minuto, COUNT(*) AS en_cancha,
       MAX(IIF(e.dorsal = 5, 1, 0)) AS esta_el_dorsal_5
FROM (VALUES (CAST(60 AS TINYINT)), (CAST(80 AS TINYINT))) AS m (minuto)
CROSS APPLY DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion_xvb, m.minuto, 0) AS e
GROUP BY m.minuto
ORDER BY m.minuto;
GO

/* FV5 fn_MarcadorSegunGoles
   Esperado: 226, 2 - 0 (el segundo es un gol en contra del 3 de XVB, que suma
   para XVA); 227, 0 - 1; 228, 1 - 1; 229, 2 - 2 con 1 - 1 en los 90 minutos y
   4 - 3 por penales. Todos coinciden con el resultado guardado en PARTIDO. */
SELECT 'FV5' AS caso, p.numero_partido, m.goles_local, m.goles_visitante, m.goles_local_90, m.goles_visitante_90,
       m.penales_local, m.penales_visitante, f.resultado AS resultado_guardado
FROM Torneo.PARTIDO AS p
CROSS APPLY DesarrolloPartido.fn_MarcadorSegunGoles(p.id_partido) AS m
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = p.id_partido
WHERE p.numero_partido BETWEEN 226 AND 229
ORDER BY p.numero_partido;
GO

/* FV6 fn_Sanciones (selecciones de prueba)
   Esperado: 3 sanciones de 1 partido: dorsal 5 de XVB por doble amarilla
   (partido 226), dorsal 3 de XVC por roja directa (227) y dorsal 8 de XVA por
   acumulación (228, su segunda amarilla del torneo). */
SELECT 'FV6' AS caso, pa.nombre AS seleccion, j.dorsal, s.motivo,
       p.numero_partido AS partido_origen, s.partidos_de_suspension
FROM DesarrolloPartido.fn_Sanciones() AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = s.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = s.id_partido_origen
WHERE pa.codigo_fifa LIKE 'XV_'
ORDER BY p.numero_partido;
GO

/* FV7 fn_JugadoresSuspendidos
   Esperado: en el partido 228 está suspendido el dorsal 3 de XVC y en el 229
   el dorsal 8 de XVA (cada uno cumple su primera y única fecha). En el 226 y
   el 227 no hay suspendidos. */
SELECT 'FV7' AS caso, p.numero_partido, j.dorsal, j.apellido, s.motivo, s.numero_partido_origen, s.partido_que_cumple
FROM Torneo.PARTIDO AS p
CROSS APPLY DesarrolloPartido.fn_JugadoresSuspendidos(p.id_partido) AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
WHERE p.numero_partido BETWEEN 226 AND 229
ORDER BY p.numero_partido;
GO

/* FV8 Criterios de suspensión parametrizables
   Los cambios se deshacen al final del caso. Con
   AMARILLAS_PARA_SUSPENSION = 3, el dorsal 8 de XVA ya no está suspendido
   para el partido 229 (tiene 2 amarillas); con FECHAS_SUSPENSION_ROJA_DIRECTA
   = 2, la roja del dorsal 3 de XVC pasa a 2 partidos.
   Esperado: 0 suspendidos en el 229 y 2 partidos para la roja; al final los
   dos parámetros vuelven a 2 y 1. */
DECLARE @id_partido_229 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 229);

SAVE TRANSACTION FV8;
BEGIN TRY
    UPDATE DatosGenerales.PARAMETRO_REGLAMENTO SET valor = 3 WHERE codigo = 'AMARILLAS_PARA_SUSPENSION';
    UPDATE DatosGenerales.PARAMETRO_REGLAMENTO SET valor = 2 WHERE codigo = 'FECHAS_SUSPENSION_ROJA_DIRECTA';

    SELECT 'FV8 con 3 amarillas' AS caso, COUNT(*) AS suspendidos_en_el_partido_229
    FROM DesarrolloPartido.fn_JugadoresSuspendidos(@id_partido_229);

    SELECT 'FV8 con 2 fechas por roja' AS caso, pa.nombre AS seleccion, j.dorsal, s.motivo, s.partidos_de_suspension
    FROM DesarrolloPartido.fn_Sanciones() AS s
    INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
    INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = s.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
    WHERE s.motivo = 'ROJA DIRECTA' AND pa.codigo_fifa LIKE 'XV_';
END TRY
BEGIN CATCH
    PRINT N'FV8: FALLÓ, error inesperado: ' + ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION FV8;

SELECT 'FV8 restaurado' AS caso, codigo, valor
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo IN ('AMARILLAS_PARA_SUSPENSION', 'FECHAS_SUSPENSION_ROJA_DIRECTA');
GO

/* FV9 fn_SeleccionesEnCompetencia (selecciones de prueba)
   Esperado: solo XVA, que ganó por penales el partido de cuartos (229). XVD
   lo perdió, y XVB y XVC no llegaron a la eliminación directa. */
SELECT 'FV9' AS caso, pa.nombre AS seleccion
FROM Torneo.fn_SeleccionesEnCompetencia() AS sc
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = sc.id_pais
WHERE pa.codigo_fifa LIKE 'XV_';
GO

/* FV10 fn_MercadosEnPrimeTime: simulación del partido 226 (19:00 UTC del 10/02/2027)
   Esperado, entre los países de prueba: en prime time (19 a 23 hs) XVA, XVB,
   XVC, XVD y XVN (UTC+0, a las 19) y XVM (UTC+2, a las 21); XVJ (UTC+9, a las
   04) no. XVA y XVB son los que juegan el partido. Con PRIME_TIME_DESDE = 21
   queda solo XVM; el cambio se deshace al final del caso y el parámetro
   vuelve a 19. */
DECLARE @id_partido_226 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);

SELECT 'FV10 mercados' AS caso, pa.codigo_fifa, m.huso_horario, m.hora_local, m.en_prime_time, m.juega_el_partido
FROM Publicidad.fn_MercadosEnPrimeTime(@id_partido_226) AS m
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
WHERE pa.codigo_fifa LIKE 'XV_'
ORDER BY m.en_prime_time DESC, m.hora_local, pa.codigo_fifa;

SAVE TRANSACTION FV10;
BEGIN TRY
    SELECT 'FV10 conteo' AS caso, 'Desde las 19' AS franja, COUNT(*) AS paises_de_prueba_en_prime_time
    FROM Publicidad.fn_MercadosEnPrimeTime(@id_partido_226) AS m INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
    WHERE m.en_prime_time = 1 AND pa.codigo_fifa LIKE 'XV_';

    UPDATE DatosGenerales.PARAMETRO_REGLAMENTO SET valor = 21 WHERE codigo = 'PRIME_TIME_DESDE';

    SELECT 'FV10 conteo' AS caso, 'Desde las 21' AS franja, COUNT(*) AS paises_de_prueba_en_prime_time
    FROM Publicidad.fn_MercadosEnPrimeTime(@id_partido_226) AS m INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
    WHERE m.en_prime_time = 1 AND pa.codigo_fifa LIKE 'XV_';
END TRY
BEGIN CATCH
    PRINT N'FV10: FALLÓ, error inesperado: ' + ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION FV10;
GO

/* FV10b fn_MercadosEnPrimeTime: feriados del partido 226. XVA tiene feriado
   el 10/02/2027 (el día del partido en su hora local) y XVM el 11/02/2027;
   los dos se deshacen al final del caso.
   Esperado: XVA con es_feriado = 1 y el nombre "Carnaval"; XVM con
   es_feriado = 0 (a las 21 del 10/02 todavía no es su feriado); los demás
   países de prueba sin feriado. */
DECLARE @id_partido_226 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);
DECLARE @id_pais_xva SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XVA');
DECLARE @id_pais_xvm SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XVM');

SAVE TRANSACTION FV10b;
BEGIN TRY
    INSERT INTO DatosGenerales.FERIADO (id_pais, fecha, nombre) VALUES
        (@id_pais_xva, '2027-02-10', N'Carnaval'),
        (@id_pais_xvm, '2027-02-11', N'Día de la Memoria');

    SELECT 'FV10b feriados' AS caso, pa.codigo_fifa, m.hora_local, m.es_feriado, m.feriado
    FROM Publicidad.fn_MercadosEnPrimeTime(@id_partido_226) AS m
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
    WHERE pa.codigo_fifa LIKE 'XV_'
    ORDER BY m.es_feriado DESC, pa.codigo_fifa;
END TRY
BEGIN CATCH
    PRINT N'FV10b: FALLÓ, error inesperado: ' + ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION FV10b;
GO

/* FV11 fn_PrioridadPiezas del partido 226 (piezas de prueba)
   Esperado: las 2 piezas de prueba, en este orden: primero "Puma
   Portugal", dirigida a XVA, que juega el partido, aunque su franja de PBI es
   0 (XVA no tiene PBI cargado); después "Puma Global", de franja 9
   (XVJ) con 1 mercado en prime time (XVM). Sin otras campañas vigentes en
   febrero de 2027 tienen prioridad 1 y 2; si las hubiera, aparecen con otros
   números, pero en el mismo orden. */
DECLARE @id_partido_226 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);
SELECT 'FV11' AS caso, pr.prioridad, pr.campania, pr.titulo, pr.dirigida_a_seleccion,
       pr.franja_pbi, pr.mercados_en_prime_time, pr.pbi_per_capita_max, pr.mercados_de_interes
FROM Publicidad.fn_PrioridadPiezas(@id_partido_226) AS pr
WHERE pr.titulo LIKE N'Puma%'
ORDER BY pr.prioridad;
GO

/* FV12 vw_HistorialTitularidad
   Esperado: el dorsal 8 de XVA figura como titular en los partidos 226 y 228
   y no figura en el 229, en el que estaba suspendido. En el 226, el dorsal 4
   de XVA sale en el minuto 17 y el 13 entra en el 17. */
SELECT 'FV12 XVA 8' AS caso, h.numero_partido, h.rival, h.condicion, h.jugo, h.minuto_ingreso, h.minuto_salida
FROM DesarrolloPartido.vw_HistorialTitularidad AS h
WHERE h.seleccion = 'Portugal1' AND h.dorsal = 8
ORDER BY h.numero_partido;

SELECT 'FV12 XVA partido 226' AS caso, h.dorsal, h.apellido, h.condicion, h.minuto_ingreso, h.minuto_salida
FROM DesarrolloPartido.vw_HistorialTitularidad AS h
WHERE h.seleccion = 'Portugal1' AND h.numero_partido = 226 AND h.dorsal IN (4, 13);
GO

/* FV13 vw_Goleadores (selecciones de prueba)
   Esperado: el 9 de XVA con 3 goles en 3 partidos; el 9 de XVD con 2; el 10
   de XVA, el 10 de XVD y el 9 de XVC con 1. No cuentan el gol en contra ni
   los penales de la definición. Control: 8 goles de goleadores más 1 en
   contra son los 9 goles de los resultados de los partidos 226 a 229. */
SELECT 'FV13' AS caso, seleccion, apellido, goles, partidos_con_gol
FROM DesarrolloPartido.vw_Goleadores
WHERE seleccion IN ('Portugal1', 'Ghana1', 'Senegal1', 'Islandia1')
ORDER BY goles DESC, apellido;

SELECT 'FV13 control' AS caso,
       (SELECT SUM(goles) FROM DesarrolloPartido.vw_Goleadores WHERE seleccion IN ('Portugal1', 'Ghana1', 'Senegal1', 'Islandia1')) AS goles_de_goleadores,
       (SELECT COUNT(*) FROM DesarrolloPartido.GOL AS g
        INNER JOIN DesarrolloPartido.TIPO_GOL AS t ON t.id_tipo_gol = g.id_tipo_gol
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
        WHERE t.es_en_contra = 1 AND p.numero_partido BETWEEN 226 AND 229)                      AS goles_en_contra,
       (SELECT SUM(goles_local + goles_visitante) FROM Torneo.PARTIDO
        WHERE numero_partido BETWEEN 226 AND 229)                                              AS goles_de_los_partidos;
GO

/* FV14 vw_HistorialArbitro
   Esperado: el árbitro principal del partido 227 (Bakary Gassama) tiene
   registrados su informe y su sanción (apercibimiento); en el partido hubo
   0 amarillas y 1 roja. */
SELECT 'FV14' AS caso, h.apellido, h.pais, h.rol, h.numero_partido, h.resultado,
       h.amarillas_del_partido, h.rojas_del_partido, h.informe_postpartido, h.sancion
FROM Arbitraje.vw_HistorialArbitro AS h
WHERE h.numero_partido = 227 AND h.rol = 'PRINCIPAL';
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas de datos de prueba y los parámetros con
   sus valores originales
   (AMARILLAS_PARA_SUSPENSION 2, FECHAS_SUSPENSION_ROJA_DIRECTA 1,
   PRIME_TIME_DESDE 19, SELECCIONES_POR_GRUPO 4).
   ============================================================================ */
ROLLBACK TRANSACTION;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 226 AND 229)              AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa LIKE 'XV_')                     AS paises_de_prueba,
       (SELECT COUNT(*) FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Puma1')                  AS anunciantes_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio IN ('Mercedes-Benz Stadium1', 'NRG Stadium1')) AS sedes_de_prueba;

SELECT 'Final' AS caso, codigo, valor
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo IN ('AMARILLAS_PARA_SUSPENSION', 'FECHAS_SUSPENSION_ROJA_DIRECTA', 'PRIME_TIME_DESDE',
                 'SELECCIONES_POR_GRUPO')
ORDER BY codigo;
GO

SET NOEXEC OFF;
GO
