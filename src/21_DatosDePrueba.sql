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

 Fecha: 27/10/2026
 Archivo: 21_DatosDePrueba.sql
 Objetivo: Llenar la base con un torneo completo de prueba, para tener datos
           con los que consultar vistas, funciones y reportes. Todo se carga
           con los SP de ABM y de negocio, nunca con INSERT directo.
           Requiere haber ejecutado 00 a 20 sobre una base sin sedes cargadas
           (se ejecuta una sola vez, después de recrear la base).
================================================================================

 Qué carga:
   - PBI per cápita 2024 (NY.GDP.PCAP.CD, valores aproximados) de los países
     de selecciones y mercados.
   - 10 sedes en 4 husos horarios, con sus 4 espacios publicitarios.
   - 16 selecciones en 4 grupos (A a D), cada una con director técnico, 3
     ayudantes y 23 convocados (3 arqueros, 8 defensores, 7 mediocampistas y
     5 delanteros). Nombres generados, no son jugadores reales.
   - 1 reemplazo de último momento (Argentina, dorsal 9, por lesión).
   - 24 árbitros ficticios de 24 países, con sus idiomas.
   - 9 anunciantes de 9 países, 10 campañas (una de 2025, como historial) y
     sus piezas con mercados de interés.
   - 32 partidos: 24 de grupos, cuartos, semifinales, tercer puesto y final.
     Cada uno con terna arbitral, formaciones (4-3-3, 11 titulares y banco),
     publicidad asignada, cambios, goles, tarjetas, resultado y asistencia.
     Los cruces de eliminación directa salen de las posiciones de los grupos.

 Casos que quedan cargados:
   - Doble amarilla (partido 3) y roja directa (partido 6).
   - Suspensión por acumulación: el primer defensor del local recibe amarilla
     en los partidos impares, así el cabeza de cada grupo acumula dos en las
     fechas 1 y 2 y queda afuera de la formación de la fecha 3.
   - Cambio por lesión en el minuto 15 (partidos múltiplos de 5).
   - Partidos a las 23 UTC, en prime time en más de cuatro mercados.
   - Designación rechazada por conflicto de nacionalidad (partido 1).
   - Definición por penales (partido 26) y gol en el alargue (partido 29).
   - Amarilla a un director técnico (partido 10).
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Se ejecuta sobre la base recién creada: si ya hay sedes, no se carga nada.
IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS) OR EXISTS (SELECT 1 FROM Torneo.SEDE)
BEGIN
    PRINT N'21_DatosDePrueba.sql: la base tiene que tener los datos iniciales (20) y ninguna sede cargada. '
        + N'Recreá la base con los scripts 00 a 20 y volvé a ejecutarlo.';
    SET NOEXEC ON;
END;
GO


/* ============================================================================
   1. INDICADORES ECONÓMICOS (PBI per cápita en USD, valores aproximados)
   ============================================================================ */
BEGIN TRY
    DECLARE @pbi TABLE (orden INT IDENTITY(1,1) PRIMARY KEY, codigo_fifa CHAR(3), valor DECIMAL(18,4));

    INSERT INTO @pbi (codigo_fifa, valor)
    VALUES ('USA', 85800), ('CAN', 53400), ('MEX', 13900), ('ARG', 13900), ('BRA', 10300),
           ('URU', 23900), ('COL',  7900), ('CHI', 16700), ('PAR',  6200), ('ESP', 35300),
           ('FRA', 46100), ('GER', 55800), ('ENG', 52600), ('SCO', 52600), ('AUT', 58300),
           ('SUI', 103700), ('JPN', 32500), ('KOR', 36100), ('AUS', 64700), ('RSA',  6300),
           ('MAR',  4200), ('ALG',  5700), ('SEN',  1700), ('KSA', 33100), ('QAT', 76700);

    DECLARE @i INT = 1, @total INT = (SELECT COUNT(*) FROM @pbi);
    DECLARE @id_pais SMALLINT, @valor DECIMAL(18,4);

    WHILE @i <= @total
    BEGIN
        SELECT @id_pais = pa.id_pais, @valor = p.valor
        FROM @pbi AS p
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = p.codigo_fifa
        WHERE p.orden = @i;

        EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Alta
            @id_pais = @id_pais, @codigo_indicador = 'NY.GDP.PCAP.CD', @anio = 2024, @valor = @valor;

        SET @i += 1;
    END;

    PRINT CONCAT(N'Indicadores económicos: ', @total, N' cargados.');
END TRY
BEGIN CATCH
    PRINT N'Error al cargar los indicadores: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   2. SEDES (con sus 4 espacios publicitarios)
   #sedes guarda el id de cada sede por orden, para armar el fixture.
   ============================================================================ */
IF OBJECT_ID(N'tempdb..#sedes') IS NOT NULL DROP TABLE #sedes;
CREATE TABLE #sedes (orden INT PRIMARY KEY, id_sede INT);
GO

BEGIN TRY
    DECLARE @sedes TABLE (
        orden INT IDENTITY(1,1) PRIMARY KEY, nombre_estadio VARCHAR(100), ciudad VARCHAR(80),
        codigo_fifa CHAR(3), capacidad INT, huso_horario VARCHAR(50),
        tarifa_1 DECIMAL(9,2), tarifa_2 DECIMAL(9,2), tarifa_3 DECIMAL(9,2), tarifa_4 DECIMAL(9,2),
        latitud DECIMAL(9,6), longitud DECIMAL(9,6)
    );

    INSERT INTO @sedes (nombre_estadio, ciudad, codigo_fifa, capacidad, huso_horario,
                        tarifa_1, tarifa_2, tarifa_3, tarifa_4, latitud, longitud)
    VALUES
        ('MetLife Stadium',       'East Rutherford',  'USA', 82500, 'Eastern Standard Time',          120000, 100000, 90000, 80000,  40.813600,  -74.074400),
        ('SoFi Stadium',          'Inglewood',        'USA', 70240, 'Pacific Standard Time',          115000,  95000, 85000, 75000,  33.953500, -118.339000),
        ('AT&T Stadium',          'Arlington',        'USA', 80000, 'Central Standard Time',          110000,  95000, 85000, 75000,  32.747300,  -97.094500),
        ('Mercedes-Benz Stadium', 'Atlanta',          'USA', 71000, 'Eastern Standard Time',          100000,  90000, 80000, 70000,  33.755400,  -84.400800),
        ('Hard Rock Stadium',     'Miami Gardens',    'USA', 64767, 'Eastern Standard Time',           95000,  85000, 75000, 65000,  25.958000,  -80.238900),
        ('Lumen Field',           'Seattle',          'USA', 68740, 'Pacific Standard Time',           90000,  80000, 70000, 60000,  47.595200, -122.331600),
        ('Estadio Azteca',        'Ciudad de México', 'MEX', 83264, 'Central Standard Time (Mexico)',  85000,  75000, 65000, 55000,  19.302900,  -99.150500),
        ('Estadio BBVA',          'Guadalupe',        'MEX', 53500, 'Central Standard Time (Mexico)',  70000,  60000, 50000, 45000,  25.669000, -100.244000),
        ('BMO Field',             'Toronto',          'CAN', 45000, 'Eastern Standard Time',           75000,  65000, 55000, 50000,  43.633200,  -79.418600),
        ('BC Place',              'Vancouver',        'CAN', 54500, 'Pacific Standard Time',           80000,  70000, 60000, 50000,  49.276800, -123.111900);

    DECLARE @i INT = 1, @total INT = (SELECT COUNT(*) FROM @sedes);
    DECLARE @nombre VARCHAR(100), @ciudad VARCHAR(80), @id_pais SMALLINT, @capacidad INT, @huso VARCHAR(50),
            @t1 DECIMAL(9,2), @t2 DECIMAL(9,2), @t3 DECIMAL(9,2), @t4 DECIMAL(9,2),
            @latitud DECIMAL(9,6), @longitud DECIMAL(9,6), @id_sede INT;

    WHILE @i <= @total
    BEGIN
        SELECT @nombre = s.nombre_estadio, @ciudad = s.ciudad, @id_pais = pa.id_pais, @capacidad = s.capacidad,
               @huso = s.huso_horario, @t1 = s.tarifa_1, @t2 = s.tarifa_2, @t3 = s.tarifa_3, @t4 = s.tarifa_4,
               @latitud = s.latitud, @longitud = s.longitud
        FROM @sedes AS s
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = s.codigo_fifa
        WHERE s.orden = @i;

        EXEC Torneo.usp_RegistrarSede
            @nombre_estadio = @nombre, @ciudad = @ciudad, @id_pais = @id_pais, @capacidad = @capacidad,
            @huso_horario = @huso, @tarifa_espacio_1 = @t1, @tarifa_espacio_2 = @t2,
            @tarifa_espacio_3 = @t3, @tarifa_espacio_4 = @t4, @latitud = @latitud, @longitud = @longitud,
            @id_sede = @id_sede OUTPUT, @mostrar = 0;

        INSERT INTO #sedes (orden, id_sede) VALUES (@i, @id_sede);
        SET @i += 1;
    END;

    PRINT CONCAT(N'Sedes: ', @total, N' cargadas, con 4 espacios publicitarios cada una.');
END TRY
BEGIN CATCH
    PRINT N'Error al cargar las sedes: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   3. SELECCIONES, CUERPOS TÉCNICOS Y CONVOCATORIAS
   Los nombres se arman combinando dos listas: dentro de cada selección el
   apellido no se repite. #selecciones guarda grupo y posición para el fixture.
   ============================================================================ */
IF OBJECT_ID(N'tempdb..#selecciones') IS NOT NULL DROP TABLE #selecciones;
CREATE TABLE #selecciones (grupo CHAR(1), posicion TINYINT, id_seleccion INT, PRIMARY KEY (grupo, posicion));
GO

BEGIN TRY
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

    DECLARE @clubes TABLE (idx INT PRIMARY KEY, club NVARCHAR(100));
    INSERT INTO @clubes (idx, club)
    VALUES (0, N'River Plate'), (1, N'Flamengo'), (2, N'Real Madrid'), (3, N'Bayern Múnich'),
           (4, N'Manchester City'), (5, N'Ajax'), (6, N'Porto'), (7, N'Al Ahly'), (8, N'Club América'),
           (9, N'Inter Miami'), (10, N'Kashima Antlers'), (11, N'Celtic');

    DECLARE @equipos TABLE (orden INT IDENTITY(1,1) PRIMARY KEY, codigo_fifa CHAR(3), confederacion VARCHAR(10),
                            grupo CHAR(1), posicion TINYINT);
    INSERT INTO @equipos (codigo_fifa, confederacion, grupo, posicion)
    VALUES ('MEX', 'CONCACAF', 'A', 1), ('KOR', 'AFC', 'A', 2), ('RSA', 'CAF', 'A', 3), ('URU', 'CONMEBOL', 'A', 4),
           ('ARG', 'CONMEBOL', 'B', 1), ('ALG', 'CAF', 'B', 2), ('AUT', 'UEFA', 'B', 3), ('JPN', 'AFC', 'B', 4),
           ('BRA', 'CONMEBOL', 'C', 1), ('MAR', 'CAF', 'C', 2), ('SCO', 'UEFA', 'C', 3), ('USA', 'CONCACAF', 'C', 4),
           ('ESP', 'UEFA', 'D', 1), ('SEN', 'CAF', 'D', 2), ('AUS', 'AFC', 'D', 3), ('COL', 'CONMEBOL', 'D', 4);

    -- Ayudantes del cuerpo técnico, con el desplazamiento que usan en las listas de nombres.
    DECLARE @ayudantes TABLE (orden INT PRIMARY KEY, rol VARCHAR(40), desp_nombre INT, desp_apellido INT);
    INSERT INTO @ayudantes (orden, rol, desp_nombre, desp_apellido)
    VALUES (1, 'AYUDANTE_CAMPO', 7, 17), (2, 'PREPARADOR_FISICO', 11, 21), (3, 'ENTRENADOR_ARQUEROS', 19, 2);

    DECLARE @convocados Torneo.TT_CONVOCADO;
    DECLARE @s INT = 1, @a INT;
    DECLARE @codigo CHAR(3), @confederacion VARCHAR(10), @grupo CHAR(1), @posicion TINYINT;
    DECLARE @id_pais SMALLINT, @id_seleccion INT, @nombre NVARCHAR(60), @apellido NVARCHAR(60), @rol VARCHAR(40);
    DECLARE @nacimiento DATE;

    WHILE @s <= 16
    BEGIN
        SELECT @codigo = e.codigo_fifa, @confederacion = e.confederacion, @grupo = e.grupo,
               @posicion = e.posicion, @id_pais = pa.id_pais
        FROM @equipos AS e
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = e.codigo_fifa
        WHERE e.orden = @s;

        SELECT @nombre = nombre FROM @nombres WHERE idx = (@s + 3) % 26;
        SELECT @apellido = apellido FROM @apellidos WHERE idx = (@s * 5 + 13) % 26;
        SET @nacimiento = DATEADD(YEAR, -(45 + @s % 15), CAST('2026-01-15' AS DATE));

        EXEC Torneo.usp_RegistrarSeleccion
            @id_pais = @id_pais, @confederacion = @confederacion, @grupo = @grupo,
            @fecha_presentacion = '2026-06-01', @dt_nombre = @nombre, @dt_apellido = @apellido,
            @dt_fecha_nacimiento = @nacimiento, @dt_id_pais_nacimiento = @id_pais,
            @id_seleccion = @id_seleccion OUTPUT, @mostrar = 0;

        INSERT INTO #selecciones (grupo, posicion, id_seleccion) VALUES (@grupo, @posicion, @id_seleccion);

        SET @a = 1;
        WHILE @a <= 3
        BEGIN
            SELECT @rol = ay.rol, @nombre = n.nombre, @apellido = ap.apellido
            FROM @ayudantes AS ay
            INNER JOIN @nombres AS n ON n.idx = (@s + ay.desp_nombre) % 26
            INNER JOIN @apellidos AS ap ON ap.idx = (@s * 5 + ay.desp_apellido) % 26
            WHERE ay.orden = @a;

            SET @nacimiento = DATEADD(YEAR, -(35 + (@s + @a) % 20), CAST('2026-03-10' AS DATE));

            EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta
                @id_seleccion = @id_seleccion, @nombre = @nombre, @apellido = @apellido, @rol = @rol,
                @fecha_nacimiento = @nacimiento, @id_pais_nacimiento = @id_pais;

            SET @a += 1;
        END;

        -- 23 convocados: el dorsal define la posición (1, 12 y 23 son arqueros).
        DELETE FROM @convocados;
        INSERT INTO @convocados (nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento, club_origen, id_pais_nacimiento)
        SELECT n.nombre,
               ap.apellido,
               CASE WHEN k.k IN (1, 12, 23)                   THEN 'ARQUERO'
                    WHEN k.k IN (2, 3, 4, 5, 13, 14, 15, 16)  THEN 'DEFENSOR'
                    WHEN k.k IN (7, 9, 11, 21, 22)            THEN 'DELANTERO'
                    ELSE 'MEDIOCAMPISTA'
               END,
               k.k,
               DATEADD(DAY, -(6935 + (k.k * 397 + @s * 131) % 4745), CAST('2026-06-01' AS DATE)),
               c.club,
               @id_pais
        FROM (SELECT TOP (23) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS k FROM sys.all_objects) AS k
        INNER JOIN @nombres AS n ON n.idx = (k.k * 5 + @s * 3) % 26
        INNER JOIN @apellidos AS ap ON ap.idx = (k.k - 1 + @s * 7) % 26
        INNER JOIN @clubes AS c ON c.idx = (k.k + @s) % 12;

        EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = @id_seleccion, @jugadores = @convocados, @mostrar = 0;

        SET @s += 1;
    END;

    PRINT N'Selecciones: 16 cargadas, con cuerpo técnico y 23 convocados cada una.';
END TRY
BEGIN CATCH
    PRINT N'Error al cargar las selecciones: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   4. REEMPLAZO DE ÚLTIMO MOMENTO
   ============================================================================ */
BEGIN TRY
    DECLARE @id_baja INT, @id_pais SMALLINT;

    SELECT @id_baja = j.id_jugador, @id_pais = s.id_pais
    FROM Torneo.JUGADOR AS j
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
    WHERE pa.codigo_fifa = 'ARG' AND j.dorsal = 9 AND j.fecha_baja IS NULL;

    EXEC Torneo.usp_ReemplazarJugador
        @id_jugador_baja = @id_baja, @motivo = 'Lesión muscular durante la preparación',
        @fecha_cambio = '2026-06-08', @nombre = N'Franco', @apellido = N'Acosta',
        @posicion_habitual = 'DELANTERO', @fecha_nacimiento = '2001-03-14',
        @club_origen = N'Boca Juniors', @id_pais_nacimiento = @id_pais, @mostrar = 0;

    PRINT N'Reemplazo: Argentina reemplaza a su dorsal 9 por lesión.';
END TRY
BEGIN CATCH
    PRINT N'Error al registrar el reemplazo: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   5. ÁRBITROS (nombres ficticios)
   ============================================================================ */
BEGIN TRY
    DECLARE @arbitros TABLE (orden INT IDENTITY(1,1) PRIMARY KEY, nombre NVARCHAR(60), apellido NVARCHAR(60),
                             codigo_fifa CHAR(3), categoria VARCHAR(20), idiomas VARCHAR(50), nacimiento DATE);
    INSERT INTO @arbitros (nombre, apellido, codigo_fifa, categoria, idiomas, nacimiento)
    VALUES (N'Facundo',   N'Ibarra',     'ARG', 'FIFA',          'es,en', '1986-04-12'),
           (N'Rodrigo',   N'Cardoso',    'BRA', 'FIFA',          'pt,en', '1984-09-30'),
           (N'Esteban',   N'Olivera',    'URU', 'FIFA',          'es,en', '1985-01-22'),
           (N'Cristóbal', N'Vergara',    'CHI', 'CONFEDERACION', 'es',    '1988-07-05'),
           (N'Julián',    N'Restrepo',   'COL', 'FIFA',          'es,en', '1983-11-18'),
           (N'Mauricio',  N'Quispe',     'PER', 'CONFEDERACION', 'es',    '1990-02-27'),
           (N'Marco',     N'Bellini',    'ITA', 'FIFA',          'it,en', '1982-06-14'),
           (N'Felix',     N'Hartmann',   'GER', 'FIFA',          'de,en', '1985-03-03'),
           (N'James',     N'Whitaker',   'ENG', 'FIFA',          'en',    '1984-12-09'),
           (N'Daan',      N'Verhoeven',  'NED', 'FIFA',          'nl,en', '1987-08-21'),
           (N'Clément',   N'Durand',     'FRA', 'FIFA',          'fr,en', '1983-05-16'),
           (N'Tiago',     N'Moreira',    'POR', 'CONFEDERACION', 'pt,es', '1989-10-02'),
           (N'Lukas',     N'Steiner',    'SUI', 'CONFEDERACION', 'de,fr', '1988-01-29'),
           (N'Henrik',    N'Solberg',    'NOR', 'CONFEDERACION', 'no,en', '1986-07-11'),
           (N'Karim',     N'Mansour',    'EGY', 'FIFA',          'ar,en', '1984-04-25'),
           (N'Abdullah',  N'Al-Kuwari',  'QAT', 'CONFEDERACION', 'ar,en', '1990-09-08'),
           (N'Faisal',    N'Al-Harbi',   'KSA', 'FIFA',          'ar,en', '1985-02-17'),
           (N'Wei',       N'Zhang',      'CHN', 'CONFEDERACION', 'zh,en', '1987-06-30'),
           (N'Ryan',      N'Mitchell',   'USA', 'FIFA',          'en,es', '1986-11-04'),
           (N'Arturo',    N'Galindo',    'MEX', 'FIFA',          'es,en', '1982-08-19'),
           (N'Liam',      N'Carter',     'NZL', 'CONFEDERACION', 'en',    '1991-03-23'),
           (N'Nathan',    N'Hughes',     'AUS', 'CONFEDERACION', 'en',    '1989-12-12'),
           (N'Takeshi',   N'Mori',       'JPN', 'FIFA',          'ja,en', '1985-10-28'),
           (N'Ivan',      N'Kovačić',    'CRO', 'CONFEDERACION', 'hr,en', '1988-05-07');

    DECLARE @i INT = 1, @total INT = (SELECT COUNT(*) FROM @arbitros);
    DECLARE @nombre NVARCHAR(60), @apellido NVARCHAR(60), @id_pais SMALLINT, @categoria VARCHAR(20),
            @idiomas VARCHAR(50), @nacimiento DATE;

    WHILE @i <= @total
    BEGIN
        SELECT @nombre = a.nombre, @apellido = a.apellido, @id_pais = pa.id_pais, @categoria = a.categoria,
               @idiomas = a.idiomas, @nacimiento = a.nacimiento
        FROM @arbitros AS a
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = a.codigo_fifa
        WHERE a.orden = @i;

        EXEC Arbitraje.usp_RegistrarArbitro
            @id_pais = @id_pais, @nombre = @nombre, @apellido = @apellido, @categoria = @categoria,
            @idiomas = @idiomas, @fecha_nacimiento = @nacimiento, @mostrar = 0;

        SET @i += 1;
    END;

    PRINT CONCAT(N'Árbitros: ', @total, N' cargados.');
END TRY
BEGIN CATCH
    PRINT N'Error al cargar los árbitros: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   6. PUBLICIDAD: anunciantes, campañas y piezas
   La campaña de 2025 queda como historial: no es candidata en este torneo.
   ============================================================================ */
BEGIN TRY
    DECLARE @anunciantes TABLE (orden INT PRIMARY KEY, razon_social NVARCHAR(150), codigo_fifa CHAR(3), id_anunciante INT);
    INSERT INTO @anunciantes (orden, razon_social, codigo_fifa)
    VALUES (1, N'Bebidas del Plata S.A.',  'ARG'), (2, N'Samba Motors Ltda.',     'BRA'),
           (3, N'Iberia Seguros S.L.',     'ESP'), (4, N'Rheinwerk AG',           'GER'),
           (5, N'Sakura Electronics K.K.', 'JPN'), (6, N'Northstar Telecom Inc.', 'USA'),
           (7, N'Atlas Airways S.A.',      'MAR'), (8, N'Maple Foods Ltd.',       'CAN'),
           (9, N'Cervecería Azteca S.A.',  'MEX');

    DECLARE @campanias TABLE (orden INT PRIMARY KEY, anunciante INT, nombre NVARCHAR(150),
                              inicio DATE, fin DATE, id_campania INT);
    INSERT INTO @campanias (orden, anunciante, nombre, inicio, fin)
    VALUES (1,  1, N'Brindá con la Selección',     '2026-06-01', '2026-07-31'),
           (2,  2, N'Samba Motors Mundial',        '2026-06-01', '2026-07-31'),
           (3,  3, N'Seguros para la hinchada',    '2026-06-01', '2026-07-20'),
           (4,  4, N'Rheinwerk Weltmeister',       '2026-06-01', '2026-07-31'),
           (5,  5, N'Sakura en alta definición',   '2026-06-10', '2026-07-15'),
           (6,  6, N'Northstar conecta el Mundial','2026-06-01', '2026-07-31'),
           (7,  7, N'Volá a la fase de grupos',    '2026-06-11', '2026-06-30'),
           (8,  8, N'Maple Game Day',              '2026-06-15', '2026-07-19'),
           (9,  9, N'Cerveza oficial del aguante', '2026-06-01', '2026-07-31'),
           (10, 1, N'Copa de verano 2025',         '2025-06-01', '2025-07-31');

    DECLARE @piezas TABLE (orden INT IDENTITY(1,1) PRIMARY KEY, campania INT, titulo NVARCHAR(150),
                           mercados VARCHAR(100), idioma CHAR(2), duracion TINYINT);
    INSERT INTO @piezas (campania, titulo, mercados, idioma, duracion)
    VALUES (1,  N'Panel Río de la Plata',         'ARG,URU,PAR', 'es', 30),
           (1,  N'Panel Brasil',                  'BRA',         'pt', 30),
           (2,  N'Samba Motors Brasil',           'BRA',         'pt', 20),
           (2,  N'Samba Motors Cono Sur',         'ARG,CHI',     'es', 20),
           (3,  N'Iberia España',                 'ESP',         'es', 15),
           (3,  N'Iberia Latinoamérica',          'MEX,COL',     'es', 15),
           (4,  N'Rheinwerk Europa central',      'GER,AUT,SUI', 'de', 25),
           (4,  N'Rheinwerk Norteamérica',        'USA,CAN',     'en', 25),
           (5,  N'Sakura Japón',                  'JPN',         'ja', 20),
           (5,  N'Sakura Corea',                  'KOR',         'ko', 20),
           (5,  N'Sakura Oceanía',                'AUS',         'en', 20),
           (6,  N'Northstar Estados Unidos',      'USA',         'en', 30),
           (6,  N'Northstar Canadá',              'CAN',         'fr', 30),
           (6,  N'Northstar México',              'MEX',         'es', 30),
           (7,  N'Atlas Magreb',                  'MAR,ALG',     'ar', 15),
           (7,  N'Atlas Francia y Senegal',       'FRA,SEN',     'fr', 15),
           (8,  N'Maple Canadá',                  'CAN',         'en', 20),
           (8,  N'Maple Reino Unido',             'SCO,ENG',     'en', 20),
           (9,  N'Azteca México',                 'MEX',         'es', 25),
           (9,  N'Azteca comunidad latina',       'USA',         'es', 25),
           (10, N'Panel verano 2025',             'ARG',         'es', 30);

    DECLARE @i INT, @total INT, @id INT, @id_pais SMALLINT, @texto NVARCHAR(150), @fk INT,
            @inicio DATE, @fin DATE, @mercados VARCHAR(100), @idioma CHAR(2), @duracion TINYINT;

    SET @i = 1;
    WHILE @i <= (SELECT COUNT(*) FROM @anunciantes)
    BEGIN
        SELECT @texto = a.razon_social, @id_pais = pa.id_pais
        FROM @anunciantes AS a
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = a.codigo_fifa
        WHERE a.orden = @i;

        EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = @texto, @id_pais = @id_pais, @id_anunciante = @id OUTPUT;
        UPDATE @anunciantes SET id_anunciante = @id WHERE orden = @i;
        SET @i += 1;
    END;

    SET @i = 1;
    WHILE @i <= (SELECT COUNT(*) FROM @campanias)
    BEGIN
        SELECT @fk = a.id_anunciante, @texto = c.nombre, @inicio = c.inicio, @fin = c.fin
        FROM @campanias AS c
        INNER JOIN @anunciantes AS a ON a.orden = c.anunciante
        WHERE c.orden = @i;

        EXEC Publicidad.usp_CAMPANIA_Alta
            @id_anunciante = @fk, @nombre = @texto, @fecha_inicio = @inicio, @fecha_fin = @fin,
            @id_campania = @id OUTPUT;
        UPDATE @campanias SET id_campania = @id WHERE orden = @i;
        SET @i += 1;
    END;

    SET @i = 1;
    SET @total = (SELECT COUNT(*) FROM @piezas);
    WHILE @i <= @total
    BEGIN
        SELECT @fk = c.id_campania, @texto = p.titulo, @mercados = p.mercados, @idioma = p.idioma,
               @duracion = p.duracion
        FROM @piezas AS p
        INNER JOIN @campanias AS c ON c.orden = p.campania
        WHERE p.orden = @i;

        EXEC Publicidad.usp_RegistrarPiezaPublicitaria
            @id_campania = @fk, @titulo = @texto, @mercados = @mercados, @codigo_idioma = @idioma,
            @duracion_segundos = @duracion, @mostrar = 0;
        SET @i += 1;
    END;

    PRINT CONCAT(N'Publicidad: 9 anunciantes, 10 campañas y ', @total, N' piezas.');
END TRY
BEGIN CATCH
    PRINT N'Error al cargar la publicidad: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   7. RESULTADOS Y PROCEDIMIENTOS AUXILIARES DEL TORNEO
   #resultados tiene el marcador de los 90 minutos de cada partido; en
   eliminación directa, los penales convertidos y si el local hace un gol en
   el alargue. Los procedimientos temporales (#) solo existen en esta sesión.
   ============================================================================ */
IF OBJECT_ID(N'tempdb..#resultados') IS NOT NULL DROP TABLE #resultados;
CREATE TABLE #resultados (
    numero_partido     TINYINT PRIMARY KEY,
    goles_local        TINYINT,
    goles_visitante    TINYINT,
    penales_local      TINYINT NULL,
    penales_visitante  TINYINT NULL,
    gol_alargue_local  BIT NOT NULL DEFAULT (0)
);

INSERT INTO #resultados (numero_partido, goles_local, goles_visitante)
VALUES (1, 2, 1), (2, 0, 0), (3, 1, 1), (4, 3, 0), (5, 2, 2), (6, 0, 1), (7, 1, 0), (8, 2, 0),
       (9, 0, 2), (10, 1, 3), (11, 1, 1), (12, 4, 1), (13, 2, 1), (14, 0, 0), (15, 3, 1), (16, 1, 2),
       (17, 0, 1), (18, 2, 2), (19, 1, 0), (20, 2, 3), (21, 0, 0), (22, 1, 1), (23, 3, 2), (24, 0, 2),
       (25, 2, 0), (27, 3, 1), (28, 0, 1), (30, 0, 2), (31, 3, 2), (32, 2, 1);

INSERT INTO #resultados (numero_partido, goles_local, goles_visitante, penales_local, penales_visitante, gol_alargue_local)
VALUES (26, 1, 1, 4, 2, 0),
       (29, 1, 1, NULL, NULL, 1);
GO

-- Crea un partido en la sede indicada por su orden en #sedes.
IF OBJECT_ID(N'tempdb..#usp_CrearPartido', N'P') IS NOT NULL DROP PROCEDURE #usp_CrearPartido;
GO
CREATE PROCEDURE #usp_CrearPartido
    @numero     TINYINT,
    @sede       INT,
    @fase       VARCHAR(15),
    @utc        DATETIME2(0),
    @local      INT,
    @visitante  INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_sede INT = (SELECT id_sede FROM #sedes WHERE orden = @sede);

    EXEC Torneo.usp_PARTIDO_Alta
        @numero_partido = @numero, @id_sede = @id_sede, @fase = @fase, @fecha_hora_utc = @utc,
        @id_seleccion_local = @local, @id_seleccion_visitante = @visitante;
END;
GO

-- Crea los partidos de una ronda de eliminación directa a partir de los
-- resultados anteriores: 1 cuartos, 2 semifinales, 3 tercer puesto y final.
-- La ronda es un número porque en un procedimiento temporal comparar una
-- variable de texto con un literal da conflicto de intercalación.
IF OBJECT_ID(N'tempdb..#usp_CrearEliminatorias', N'P') IS NOT NULL DROP PROCEDURE #usp_CrearEliminatorias;
GO
CREATE PROCEDURE #usp_CrearEliminatorias
    @ronda TINYINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @a INT, @b INT, @c INT, @d INT;

    IF @ronda = 1
    BEGIN
        -- Posiciones: 3 puntos por partido ganado; desempata diferencia de gol y goles a favor.
        DECLARE @posiciones TABLE (grupo CHAR(1), posicion INT, id_seleccion INT);

        WITH resultados AS (
            SELECT id_seleccion_local AS id_seleccion, CAST(goles_local AS INT) AS gf, CAST(goles_visitante AS INT) AS gc
            FROM Torneo.PARTIDO WHERE fase = 'GRUPOS' AND estado = 'FINALIZADO'
            UNION ALL
            SELECT id_seleccion_visitante, goles_visitante, goles_local
            FROM Torneo.PARTIDO WHERE fase = 'GRUPOS' AND estado = 'FINALIZADO'
        ),
        tabla AS (
            SELECT r.id_seleccion, s.grupo,
                   SUM(CASE WHEN r.gf > r.gc THEN 3 WHEN r.gf = r.gc THEN 1 ELSE 0 END) AS puntos,
                   SUM(r.gf - r.gc) AS diferencia,
                   SUM(r.gf) AS goles_a_favor
            FROM resultados AS r
            INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = r.id_seleccion
            GROUP BY r.id_seleccion, s.grupo
        )
        INSERT INTO @posiciones (grupo, posicion, id_seleccion)
        SELECT grupo,
               ROW_NUMBER() OVER (PARTITION BY grupo ORDER BY puntos DESC, diferencia DESC, goles_a_favor DESC, id_seleccion),
               id_seleccion
        FROM tabla;

        SELECT @a = id_seleccion FROM @posiciones WHERE grupo = 'A' AND posicion = 1;
        SELECT @b = id_seleccion FROM @posiciones WHERE grupo = 'B' AND posicion = 2;
        EXEC #usp_CrearPartido 25, 1, 'CUARTOS', '2026-06-29 19:00', @a, @b;

        SELECT @a = id_seleccion FROM @posiciones WHERE grupo = 'B' AND posicion = 1;
        SELECT @b = id_seleccion FROM @posiciones WHERE grupo = 'A' AND posicion = 2;
        EXEC #usp_CrearPartido 26, 7, 'CUARTOS', '2026-06-29 23:00', @a, @b;

        SELECT @a = id_seleccion FROM @posiciones WHERE grupo = 'C' AND posicion = 1;
        SELECT @b = id_seleccion FROM @posiciones WHERE grupo = 'D' AND posicion = 2;
        EXEC #usp_CrearPartido 27, 3, 'CUARTOS', '2026-06-30 19:00', @a, @b;

        SELECT @a = id_seleccion FROM @posiciones WHERE grupo = 'D' AND posicion = 1;
        SELECT @b = id_seleccion FROM @posiciones WHERE grupo = 'C' AND posicion = 2;
        EXEC #usp_CrearPartido 28, 2, 'CUARTOS', '2026-06-30 23:00', @a, @b;
        RETURN;
    END;

    -- Ganador y perdedor de cada partido de eliminación directa ya jugado.
    DECLARE @llaves TABLE (numero_partido TINYINT PRIMARY KEY, ganador INT, perdedor INT);
    INSERT INTO @llaves (numero_partido, ganador, perdedor)
    SELECT numero_partido,
           IIF(goles_local > goles_visitante OR (goles_local = goles_visitante AND penales_local > penales_visitante),
               id_seleccion_local, id_seleccion_visitante),
           IIF(goles_local > goles_visitante OR (goles_local = goles_visitante AND penales_local > penales_visitante),
               id_seleccion_visitante, id_seleccion_local)
    FROM Torneo.PARTIDO
    WHERE fase <> 'GRUPOS' AND estado = 'FINALIZADO';

    IF @ronda = 2
    BEGIN
        SELECT @a = ganador FROM @llaves WHERE numero_partido = 25;
        SELECT @b = ganador FROM @llaves WHERE numero_partido = 26;
        SELECT @c = ganador FROM @llaves WHERE numero_partido = 27;
        SELECT @d = ganador FROM @llaves WHERE numero_partido = 28;
        EXEC #usp_CrearPartido 29, 4, 'SEMIFINAL', '2026-07-03 19:00', @a, @b;
        EXEC #usp_CrearPartido 30, 3, 'SEMIFINAL', '2026-07-03 23:00', @c, @d;
    END
    ELSE IF @ronda = 3
    BEGIN
        SELECT @a = perdedor, @c = ganador FROM @llaves WHERE numero_partido = 29;
        SELECT @b = perdedor, @d = ganador FROM @llaves WHERE numero_partido = 30;
        EXEC #usp_CrearPartido 31, 5, 'TERCER_PUESTO', '2026-07-06 23:00', @a, @b;
        EXEC #usp_CrearPartido 32, 1, 'FINAL',         '2026-07-07 19:00', @c, @d;
    END;
END;
GO

-- Designa la terna con los árbitros menos usados que cumplen las reglas:
-- sin conflicto de nacionalidad, sin otro partido a menos de 24 horas y con
-- categoría FIFA para principal y VAR (se eligen primero).
IF OBJECT_ID(N'tempdb..#usp_DesignarArbitros', N'P') IS NOT NULL DROP PROCEDURE #usp_DesignarArbitros;
GO
CREATE PROCEDURE #usp_DesignarArbitros
    @id_partido INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @utc DATETIME2(0), @pais_local SMALLINT, @pais_visitante SMALLINT;
    DECLARE @terna TABLE (rol TINYINT PRIMARY KEY, id_arbitro INT);
    DECLARE @paso TINYINT = 1, @rol TINYINT;
    DECLARE @principal INT, @asistente_1 INT, @asistente_2 INT, @cuarto INT, @var INT;

    SELECT @utc = p.fecha_hora_utc, @pais_local = sl.id_pais, @pais_visitante = sv.id_pais
    FROM Torneo.PARTIDO AS p
    INNER JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = p.id_seleccion_local
    INNER JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = p.id_seleccion_visitante
    WHERE p.id_partido = @id_partido;

    -- Roles: 1 principal, 2 y 3 asistentes, 4 cuarto árbitro, 5 VAR.
    WHILE @paso <= 5
    BEGIN
        SET @rol = CHOOSE(@paso, 1, 5, 2, 3, 4);

        INSERT INTO @terna (rol, id_arbitro)
        SELECT TOP (1) @rol, a.id_arbitro
        FROM Arbitraje.ARBITRO AS a
        WHERE a.activo = 1
          AND a.id_pais NOT IN (@pais_local, @pais_visitante)
          AND (a.categoria = 'FIFA' OR @rol NOT IN (1, 5))
          AND NOT EXISTS (SELECT 1 FROM @terna AS t WHERE t.id_arbitro = a.id_arbitro)
          AND NOT EXISTS (SELECT 1
                          FROM Arbitraje.DESIGNACION_ARBITRAL AS d
                          INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
                          WHERE d.id_arbitro = a.id_arbitro
                            AND ABS(DATEDIFF(MINUTE, p.fecha_hora_utc, @utc)) < 1440)
        ORDER BY IIF(@rol IN (1, 5) OR a.categoria <> 'FIFA', 0, 1),
                 (SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL AS d WHERE d.id_arbitro = a.id_arbitro),
                 a.id_arbitro;

        SET @paso += 1;
    END;

    SELECT @principal = id_arbitro FROM @terna WHERE rol = 1;
    SELECT @asistente_1 = id_arbitro FROM @terna WHERE rol = 2;
    SELECT @asistente_2 = id_arbitro FROM @terna WHERE rol = 3;
    SELECT @cuarto = id_arbitro FROM @terna WHERE rol = 4;
    SELECT @var = id_arbitro FROM @terna WHERE rol = 5;

    EXEC Arbitraje.usp_DesignarTernaArbitral
        @id_partido = @id_partido, @id_principal = @principal, @id_asistente_1 = @asistente_1,
        @id_asistente_2 = @asistente_2, @id_cuarto = @cuarto, @id_var = @var, @mostrar = 0;
END;
GO

-- Devuelve el jugador de la formación de una selección en un partido, por
-- posición habitual, titular o suplente y orden de dorsal (1 = el más bajo).
IF OBJECT_ID(N'tempdb..#usp_Jugador', N'P') IS NOT NULL DROP PROCEDURE #usp_Jugador;
GO
CREATE PROCEDURE #usp_Jugador
    @id_partido    INT,
    @id_seleccion  INT,
    @posicion      VARCHAR(15),
    @orden         INT,
    @titular       BIT,
    @id_jugador    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @id_jugador = NULL;

    SELECT @id_jugador = x.id_jugador
    FROM (SELECT a.id_jugador, ROW_NUMBER() OVER (ORDER BY j.dorsal) AS orden
          FROM DesarrolloPartido.ALINEACION AS a
          INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
          INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
          WHERE f.id_partido = @id_partido AND f.id_seleccion = @id_seleccion
            AND a.es_titular = @titular AND j.posicion_habitual = @posicion) AS x
    WHERE x.orden = @orden;
END;
GO

-- Juega un partido que ya tiene terna y formaciones: asigna la publicidad, lo
-- inicia, registra cambios, goles y tarjetas según #resultados y lo finaliza.
--   Cambios: defensores 3 y 4 al minuto 60 (el 3, por lesión al 15 en los
--            partidos múltiplos de 5, solo el local) y mediocampista 3 al 75.
--   Goles: los delanteros titulares, con asistencia de los mediocampistas 1 y 2.
--   Tarjetas: amarilla al defensor 1 del local en los partidos impares y al
--             mediocampista 2 del visitante en los múltiplos de 3.
IF OBJECT_ID(N'tempdb..#usp_JugarPartido', N'P') IS NOT NULL DROP PROCEDURE #usp_JugarPartido;
GO
CREATE PROCEDURE #usp_JugarPartido
    @id_partido INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @numero TINYINT, @local INT, @visitante INT, @capacidad INT, @asistencia INT;
    DECLARE @gl TINYINT, @gv TINYINT, @pl TINYINT, @pv TINYINT, @alargue BIT;
    DECLARE @lado TINYINT, @sel INT, @goles TINYINT, @i INT, @orden INT, @minuto TINYINT, @periodo VARCHAR(20);
    DECLARE @autor INT, @asistente INT, @tipo TINYINT, @sale INT, @entra INT, @receptor INT;

    DECLARE @jugada     TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
    DECLARE @cabezazo   TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
    DECLARE @penal      TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
    DECLARE @tiro_libre TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'TIRO LIBRE');

    SELECT @numero = p.numero_partido, @local = p.id_seleccion_local, @visitante = p.id_seleccion_visitante,
           @capacidad = s.capacidad
    FROM Torneo.PARTIDO AS p
    INNER JOIN Torneo.SEDE AS s ON s.id_sede = p.id_sede
    WHERE p.id_partido = @id_partido;

    SELECT @gl = goles_local, @gv = goles_visitante, @pl = penales_local, @pv = penales_visitante,
           @alargue = gol_alargue_local
    FROM #resultados
    WHERE numero_partido = @numero;

    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido, @mostrar = 0;
    EXEC Torneo.usp_IniciarPartido @id_partido = @id_partido;

    SET @lado = 1;
    WHILE @lado <= 2
    BEGIN
        SET @sel   = IIF(@lado = 1, @local, @visitante);
        SET @goles = IIF(@lado = 1, @gl, @gv);

        -- Cambios, en orden de minuto. Si el banco no tiene reemplazo, no se hace.
        EXEC #usp_Jugador @id_partido, @sel, 'DEFENSOR', 3, 1, @sale OUTPUT;
        EXEC #usp_Jugador @id_partido, @sel, 'DEFENSOR', 1, 0, @entra OUTPUT;
        IF @sale IS NOT NULL AND @entra IS NOT NULL
        BEGIN
            IF @lado = 1 AND @numero % 5 = 0
                EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
                    @id_jugador_entra = @entra, @minuto = 15, @motivo = 'LESION';
            ELSE
                EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
                    @id_jugador_entra = @entra, @minuto = 60, @motivo = 'TACTICO';
        END;

        EXEC #usp_Jugador @id_partido, @sel, 'DEFENSOR', 4, 1, @sale OUTPUT;
        EXEC #usp_Jugador @id_partido, @sel, 'DEFENSOR', 2, 0, @entra OUTPUT;
        IF @sale IS NOT NULL AND @entra IS NOT NULL
            EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
                @id_jugador_entra = @entra, @minuto = 60, @motivo = 'TACTICO';

        EXEC #usp_Jugador @id_partido, @sel, 'MEDIOCAMPISTA', 3, 1, @sale OUTPUT;
        EXEC #usp_Jugador @id_partido, @sel, 'MEDIOCAMPISTA', 1, 0, @entra OUTPUT;
        IF @sale IS NOT NULL AND @entra IS NOT NULL
            EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
                @id_jugador_entra = @entra, @minuto = 75, @motivo = 'PRECAUCION';

        -- Goles del tiempo reglamentario.
        SET @i = 0;
        WHILE @i < @goles
        BEGIN
            SET @minuto  = 8 + 17 * @i + @numero % 7 + (@lado - 1) * 3;
            SET @periodo = IIF(@minuto <= 45, 'PRIMER_TIEMPO', 'SEGUNDO_TIEMPO');
            SET @tipo    = CHOOSE(@i % 4 + 1, @jugada, @cabezazo, @penal, @tiro_libre);
            SET @orden   = @i % 3 + 1;
            EXEC #usp_Jugador @id_partido, @sel, 'DELANTERO', @orden, 1, @autor OUTPUT;

            SET @asistente = NULL;
            IF @i % 4 IN (0, 1)
            BEGIN
                SET @orden = @i % 4 + 1;
                EXEC #usp_Jugador @id_partido, @sel, 'MEDIOCAMPISTA', @orden, 1, @asistente OUTPUT;
            END;

            EXEC DesarrolloPartido.usp_RegistrarGol
                @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
                @periodo = @periodo, @minuto = @minuto, @id_jugador_asistencia = @asistente, @mostrar = 0;

            SET @i += 1;
        END;

        SET @lado += 1;
    END;

    -- Gol del local en el alargue.
    IF @alargue = 1
    BEGIN
        EXEC #usp_Jugador @id_partido, @local, 'DELANTERO', 1, 1, @autor OUTPUT;
        EXEC #usp_Jugador @id_partido, @local, 'MEDIOCAMPISTA', 1, 1, @asistente OUTPUT;
        EXEC DesarrolloPartido.usp_RegistrarGol
            @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @jugada,
            @periodo = 'ALARGUE', @minuto = 105, @id_jugador_asistencia = @asistente, @mostrar = 0;
    END;

    -- Definición por penales: patean los delanteros y los mediocampistas 1 y 2.
    SET @lado = 1;
    WHILE @lado <= 2 AND @pl IS NOT NULL
    BEGIN
        SET @sel   = IIF(@lado = 1, @local, @visitante);
        SET @goles = IIF(@lado = 1, @pl, @pv);
        SET @i = 0;
        WHILE @i < @goles
        BEGIN
            SET @orden = IIF(@i < 3, @i + 1, @i - 2);
            IF @i < 3
                EXEC #usp_Jugador @id_partido, @sel, 'DELANTERO', @orden, 1, @autor OUTPUT;
            ELSE
                EXEC #usp_Jugador @id_partido, @sel, 'MEDIOCAMPISTA', @orden, 1, @autor OUTPUT;

            EXEC DesarrolloPartido.usp_RegistrarGol
                @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @penal,
                @periodo = 'PENALES', @mostrar = 0;
            SET @i += 1;
        END;
        SET @lado += 1;
    END;

    -- Tarjetas.
    IF @numero % 2 = 1
    BEGIN
        EXEC #usp_Jugador @id_partido, @local, 'DEFENSOR', 1, 1, @receptor OUTPUT;
        EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA',
            @minuto = 35, @motivo = 'Falta táctica para cortar un contraataque', @id_jugador = @receptor, @mostrar = 0;
    END;

    IF @numero % 3 = 0
    BEGIN
        EXEC #usp_Jugador @id_partido, @visitante, 'MEDIOCAMPISTA', 2, 1, @receptor OUTPUT;
        EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA',
            @minuto = 52, @motivo = 'Protesta al árbitro', @id_jugador = @receptor, @mostrar = 0;
    END;

    IF @numero = 3
    BEGIN
        -- La segunda amarilla registra sola la roja por doble amarilla.
        EXEC #usp_Jugador @id_partido, @visitante, 'DEFENSOR', 2, 1, @receptor OUTPUT;
        EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA',
            @minuto = 30, @motivo = 'Entrada imprudente', @id_jugador = @receptor, @mostrar = 0;
        EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA',
            @minuto = 70, @motivo = 'Demora deliberada en la reanudación', @id_jugador = @receptor, @mostrar = 0;
    END;

    IF @numero = 6
    BEGIN
        EXEC #usp_Jugador @id_partido, @local, 'DEFENSOR', 2, 1, @receptor OUTPUT;
        EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'ROJA',
            @minuto = 80, @motivo = 'Juego brusco grave', @id_jugador = @receptor, @mostrar = 0;
    END;

    IF @numero = 10
    BEGIN
        SELECT @receptor = id_persona_ct
        FROM Torneo.PERSONA_CUERPO_TECNICO
        WHERE id_seleccion = @local AND rol = 'DIRECTOR_TECNICO';

        EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA',
            @minuto = 60, @motivo = 'Protestas desde el área técnica', @id_persona_ct = @receptor, @mostrar = 0;
    END;

    SET @asistencia = @capacidad * (85 + @numero % 13) / 100;
    EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido, @asistencia = @asistencia, @mostrar = 0;
END;
GO


/* ============================================================================
   8. FIXTURE DE LA FASE DE GRUPOS
   3 fechas; cada grupo juega sus dos partidos el mismo día, a las 19 y a las
   23 UTC, en sedes distintas. Fecha 1: 1-2 y 3-4; fecha 2: 1-3 y 4-2;
   fecha 3: 4-1 y 2-3.
   ============================================================================ */
BEGIN TRY
    DECLARE @fixture TABLE (numero TINYINT PRIMARY KEY, sede INT, utc DATETIME2(0), local INT, visitante INT);

    WITH cruces AS (
        SELECT * FROM (VALUES (0, 0, 1, 2), (0, 1, 3, 4),
                              (1, 0, 1, 3), (1, 1, 4, 2),
                              (2, 0, 4, 1), (2, 1, 2, 3)) AS c (fecha, turno, pos_local, pos_visitante)
    ),
    grupos AS (
        SELECT * FROM (VALUES (0, 'A'), (1, 'B'), (2, 'C'), (3, 'D')) AS g (orden, grupo)
    )
    INSERT INTO @fixture (numero, sede, utc, local, visitante)
    SELECT c.fecha * 8 + g.orden * 2 + c.turno + 1,
           (c.fecha * 8 + g.orden * 2 + c.turno) % 10 + 1,
           DATEADD(HOUR, IIF(c.turno = 0, 19, 23),
                   DATEADD(DAY, c.fecha * 5 + g.orden, CAST('2026-06-11' AS DATETIME2(0)))),
           sl.id_seleccion,
           sv.id_seleccion
    FROM cruces AS c
    CROSS JOIN grupos AS g
    INNER JOIN #selecciones AS sl ON sl.grupo = g.grupo AND sl.posicion = c.pos_local
    INNER JOIN #selecciones AS sv ON sv.grupo = g.grupo AND sv.posicion = c.pos_visitante;

    DECLARE @numero TINYINT = 1, @sede INT, @utc DATETIME2(0), @local INT, @visitante INT;

    WHILE @numero <= 24
    BEGIN
        SELECT @sede = sede, @utc = utc, @local = local, @visitante = visitante
        FROM @fixture
        WHERE numero = @numero;

        EXEC #usp_CrearPartido @numero, @sede, 'GRUPOS', @utc, @local, @visitante;
        SET @numero += 1;
    END;

    PRINT N'Fixture: 24 partidos de la fase de grupos creados.';
END TRY
BEGIN CATCH
    PRINT N'Error al crear el fixture: ' + ERROR_MESSAGE();
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   9. DESARROLLO DEL TORNEO
   Los partidos se juegan en orden: así cada formación deja afuera a los
   suspendidos de los partidos anteriores. Las formaciones se arman acá (y no
   en un procedimiento temporal) porque usan el tipo tabla TT_ALINEACION.
   ============================================================================ */
DECLARE @numero TINYINT = 1, @id_partido INT, @local INT, @visitante INT, @fecha DATE;
DECLARE @lado TINYINT, @id_seleccion INT;
DECLARE @alineacion DesarrolloPartido.TT_ALINEACION;

BEGIN TRY
    -- Designación descartada: un árbitro mexicano no puede dirigir el partido 1 (México - Corea del Sur).
    DECLARE @otros TABLE (orden INT IDENTITY(1,1), id_arbitro INT);
    DECLARE @mexicano INT, @a1 INT, @a2 INT, @a3 INT, @a4 INT;

    SELECT @id_partido = id_partido FROM Torneo.PARTIDO WHERE numero_partido = 1;
    SELECT @mexicano = a.id_arbitro
    FROM Arbitraje.ARBITRO AS a
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
    WHERE pa.codigo_fifa = 'MEX';

    INSERT INTO @otros (id_arbitro)
    SELECT TOP (4) a.id_arbitro
    FROM Arbitraje.ARBITRO AS a
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
    WHERE pa.codigo_fifa NOT IN ('MEX', 'KOR') AND a.categoria = 'FIFA'
    ORDER BY a.id_arbitro DESC;

    SELECT @a1 = id_arbitro FROM @otros WHERE orden = 1;
    SELECT @a2 = id_arbitro FROM @otros WHERE orden = 2;
    SELECT @a3 = id_arbitro FROM @otros WHERE orden = 3;
    SELECT @a4 = id_arbitro FROM @otros WHERE orden = 4;

    BEGIN TRY
        EXEC Arbitraje.usp_DesignarTernaArbitral
            @id_partido = @id_partido, @id_principal = @mexicano, @id_asistente_1 = @a1,
            @id_asistente_2 = @a2, @id_cuarto = @a3, @id_var = @a4, @mostrar = 0;
        PRINT N'ATENCIÓN: la designación con conflicto de nacionalidad no fue rechazada.';
    END TRY
    BEGIN CATCH
        PRINT N'Designación descartada (esperado): ' + ERROR_MESSAGE();
    END CATCH;

    WHILE @numero <= 32
    BEGIN
        IF @numero = 25 EXEC #usp_CrearEliminatorias @ronda = 1;
        IF @numero = 29 EXEC #usp_CrearEliminatorias @ronda = 2;
        IF @numero = 31 EXEC #usp_CrearEliminatorias @ronda = 3;

        SELECT @id_partido = id_partido, @local = id_seleccion_local, @visitante = id_seleccion_visitante,
               @fecha = CAST(fecha_hora_local AS DATE)
        FROM Torneo.PARTIDO
        WHERE numero_partido = @numero;

        EXEC #usp_DesignarArbitros @id_partido = @id_partido;

        -- Formación 4-3-3 de cada selección con los convocados disponibles en la fecha
        -- del partido: titulares por orden de dorsal en cada posición, el resto al banco.
        SET @lado = 1;
        WHILE @lado <= 2
        BEGIN
            SET @id_seleccion = IIF(@lado = 1, @local, @visitante);
            DELETE FROM @alineacion;

            WITH disponibles AS (
                SELECT j.id_jugador, j.posicion_habitual,
                       ROW_NUMBER() OVER (PARTITION BY j.posicion_habitual ORDER BY j.dorsal) AS orden
                FROM Torneo.JUGADOR AS j
                INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                WHERE l.id_seleccion = @id_seleccion
                  AND j.fecha_alta <= @fecha
                  AND (j.fecha_baja IS NULL OR j.fecha_baja > @fecha)
                  AND j.id_jugador NOT IN (SELECT id_jugador
                                           FROM DesarrolloPartido.fn_JugadoresSuspendidos(@id_partido))
            )
            INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
            SELECT id_jugador,
                   IIF(orden <= CASE posicion_habitual WHEN 'ARQUERO' THEN 1 WHEN 'DEFENSOR' THEN 4 ELSE 3 END, 1, 0),
                   CASE posicion_habitual
                        WHEN 'ARQUERO'       THEN IIF(orden = 1, 'ARQUERO', NULL)
                        WHEN 'DEFENSOR'      THEN CHOOSE(orden, 'DEFENSOR CENTRAL', 'DEFENSOR CENTRAL',
                                                         'LATERAL DERECHO', 'LATERAL IZQUIERDO')
                        WHEN 'MEDIOCAMPISTA' THEN CHOOSE(orden, 'MEDIOCAMPISTA CENTRAL', 'VOLANTE DERECHO',
                                                         'VOLANTE IZQUIERDO')
                        ELSE                      CHOOSE(orden, 'CENTRODELANTERO', 'EXTREMO DERECHO',
                                                         'EXTREMO IZQUIERDO')
                   END
            FROM disponibles;

            EXEC DesarrolloPartido.usp_RegistrarFormacion
                @id_partido = @id_partido, @id_seleccion = @id_seleccion, @esquema_tactico = '4-3-3',
                @jugadores = @alineacion, @mostrar = 0;

            SET @lado += 1;
        END;

        EXEC #usp_JugarPartido @id_partido = @id_partido;
        SET @numero += 1;
    END;

    PRINT N'Torneo: 32 partidos jugados.';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Error en el partido ', @numero, N': ', ERROR_MESSAGE());
    SET NOEXEC ON;
END CATCH;
GO


/* ============================================================================
   10. RESUMEN
   ============================================================================ */
SELECT s.name + N'.' + t.name AS tabla, SUM(p.rows) AS filas
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
INNER JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY s.name, t.name
ORDER BY s.name, t.name;

-- Fixture con resultados.
SELECT numero_partido, fase, seleccion_local, resultado, seleccion_visitante, asistencia, estado
FROM Torneo.vw_Fixture
ORDER BY numero_partido;

-- Suspensiones generadas (acumulación, doble amarilla y roja directa).
SELECT pa.nombre AS seleccion, j.dorsal, j.apellido, j.nombre, p.numero_partido AS partido_origen,
       s.motivo, s.partidos_de_suspension
FROM DesarrolloPartido.fn_Sanciones() AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = s.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = s.id_partido_origen
ORDER BY p.numero_partido, pa.nombre;

-- Partidos en prime time en más de cuatro mercados.
SELECT p.numero_partido, p.fecha_hora_utc, COUNT(*) AS mercados_en_prime_time
FROM Torneo.PARTIDO AS p
CROSS APPLY Publicidad.fn_MercadosEnPrimeTime(p.id_partido) AS m
WHERE m.en_prime_time = 1
GROUP BY p.numero_partido, p.fecha_hora_utc
HAVING COUNT(*) > 4
ORDER BY p.numero_partido;
GO

SET NOEXEC OFF;
GO
