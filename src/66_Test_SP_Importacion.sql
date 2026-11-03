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
 Archivo: 66_Test_SP_Importacion.sql
 Objetivo: Probar los SP de 16_SP_Importacion.sql: el registro de las
           importaciones y el upsert de cada dataset desde su tabla de
           staging (alta si el registro es nuevo, actualización si cambió,
           sin cambios si se importa dos veces lo mismo), con las reglas de
           cada tabla. Cada caso arma la tabla de staging como lo haría un
           proceso de importación de la Entrega 6, con registros válidos e
           inválidos: es el caso obligatorio de importación con errores
           parciales. Los válidos se cargan y los inválidos quedan marcados
           RECHAZADO con todos sus motivos.
           Requiere haber ejecutado 00 a 20; no depende del juego de datos.
           Todo se hace dentro de una transacción que se deshace al final,
           así que no deja datos y se puede ejecutar más de una vez:
             - Países de prueba XQA, XQB, XQC y XQE (códigos FIFA que empiezan
               con X, que no tiene ningún miembro de la FIFA).
             - Sede "Estadio Prueba Importación 66".
             - Selecciones XQA, XQB y XQC del grupo L, con 23 jugadores cada
               una XQA y XQB.
             - Partidos 221 (XQA - XQB, fase de grupos) y 222 (XQA - XQC,
               octavos de final), en agosto de 2026.
             - Árbitros "Prueba Arbitro" de XQE y de XQA, y sus designaciones
               en los partidos 221 y 222.
             - Indicadores, cotizaciones (moneda XTS, la de prueba de ISO
               4217) y feriados de los países de prueba.
             - "Anunciante Prueba 66" (XQA), con las campañas "Campaña Prueba
               66 A" y "B" y sus piezas, y el partido 226 (25/08/2026), en el
               que se exhibe una pieza de A.
           SELECCIONES_POR_GRUPO se ajusta dentro de la transacción para que
           el grupo L tenga lugar para las tres selecciones de prueba.
           Los casos que hacen fallar un SP con un error (THROW) van al final,
           fuera de esa transacción: el error la desharía.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra cada registro de la tabla de staging con lo
     que le pasó (accion: INSERTADO, ACTUALIZADO, SIN CAMBIOS o RECHAZADO) y
     sus motivos, y después los datos que quedaron.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'DesarrolloPartido.usp_ImportarDesarrolloPartidos', N'P') IS NULL
   OR OBJECT_ID(N'DatosGenerales.usp_RegistrarImportacion', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'SELECCIONES_POR_GRUPO')
BEGIN
    RAISERROR(N'Faltan los SP de importación o los datos iniciales: ejecutar los scripts 00 a 20.', 16, 1);
    SET NOEXEC ON;
END;
ELSE IF @@TRANCOUNT > 0
BEGIN
    RAISERROR(N'Hay una transacción abierta: este test usa la suya y la deshace al final. Cerrarla y volver a ejecutar.', 16, 1);
    SET NOEXEC ON;
END;
GO

IF OBJECT_ID(N'tempdb..#usp_MostrarError', N'P') IS NOT NULL
    DROP PROCEDURE #usp_MostrarError;
GO
CREATE PROCEDURE #usp_MostrarError
    @caso            VARCHAR(10),
    @error_esperado  INT
AS
BEGIN
    PRINT CONCAT(@caso, N': ',
                 IIF(ERROR_NUMBER() = @error_esperado, N'OK, falló como se esperaba.',
                     CONCAT(N'FALLÓ, error inesperado ', ERROR_NUMBER(), N'.')),
                 NCHAR(13), NCHAR(10), ERROR_MESSAGE(), NCHAR(13), NCHAR(10));
END;
GO


/* ============================================================================
   PREPARACIÓN, DENTRO DE LA TRANSACCIÓN DEL TEST
   ============================================================================ */
SET XACT_ABORT OFF;
BEGIN TRANSACTION;
GO

-- Países de prueba. XQE tiene país pero no va a tener selección.
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XQA', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'XQA', @codigo_iso2 = 'XA', @codigo_iso3 = 'XQA', @codigo_moneda = 'XTS';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XQB', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'XQB', @codigo_iso2 = 'XB', @codigo_iso3 = 'XQB', @codigo_moneda = 'XTS';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XQC', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'XQC', @codigo_iso2 = 'XC', @codigo_iso3 = 'XQC', @codigo_moneda = 'XTS';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XQE', @huso_horario = 'Argentina Standard Time',
     @codigo_fifa = 'XQE', @codigo_iso2 = 'XE', @codigo_iso3 = 'XQE', @codigo_moneda = 'XTS';

-- El grupo L tiene que tener lugar para exactamente tres selecciones más (las de prueba).
DECLARE @en_l TINYINT = (SELECT COUNT(*) FROM Torneo.SELECCION WHERE grupo = 'L');
DECLARE @cupo TINYINT = @en_l + 3;
EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'SELECCIONES_POR_GRUPO', @valor = @cupo;
SELECT 'Preparación' AS caso, @en_l AS selecciones_en_el_grupo_l, @cupo AS selecciones_por_grupo_en_el_test;
GO

-- Control: si la preparación falló, no se ejecuta nada más (la transacción ya no existe).
IF @@TRANCOUNT = 0
BEGIN
    PRINT N'FALLÓ: la preparación no se pudo hacer dentro de la transacción; no se ejecuta el resto.';
    SET NOEXEC ON;
END;
GO


/* ============================================================================
   SEDES (usp_ImportarSedes)
   ============================================================================ */

/* SD1 (OK) Importación con errores parciales.
   Esperado: 1 INSERTADO (Estadio Prueba Importación 66, con el huso
   escrito en minúsculas que se guarda como "Argentina Standard Time" y sus 4
   espacios publicitarios) y 7 RECHAZADO: sin nombre; nombre de 101
   caracteres; sede nueva sin ciudad, país, capacidad, huso ni tarifas; país
   ZZZ, huso inexistente, latitud sin longitud y tarifa negativa (los cuatro
   motivos juntos); capacidad 0; y el mismo estadio dos veces (las dos
   filas). */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

CREATE TABLE #staging_sedes (
    id_registro     INT PRIMARY KEY,
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

INSERT INTO #staging_sedes (id_registro, nombre_estadio, ciudad, codigo_fifa, capacidad, huso_horario,
                            latitud, longitud, tarifa_1, tarifa_2, tarifa_3, tarifa_4)
VALUES (1, 'Estadio Prueba Importación 66', 'Ciudad Prueba', 'xqa', 40000, ' argentina standard time ',
        -34.6, -58.4, 1000, 900, 800, 700),
       (2, NULL, 'Sin Nombre', 'XQA', 1000, 'UTC', NULL, NULL, 1, 1, 1, 1),
       (3, REPLICATE('a', 101), 'Nombre Largo', 'XQA', 1000, 'UTC', NULL, NULL, 1, 1, 1, 1),
       (4, 'Estadio Prueba Sin Datos', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
       (5, 'Estadio Prueba Todo Mal', 'Lejos', 'ZZZ', 1000, 'Hora Inventada', 91, NULL, -1, 1, 1, 1),
       (6, 'Estadio Prueba Capacidad Cero', 'Cero', 'XQA', 0, 'UTC', NULL, NULL, 1, 1, 1, 1),
       (7, 'Estadio Prueba Repetido', 'Uno', 'XQA', 1000, 'UTC', NULL, NULL, 1, 1, 1, 1),
       (8, 'Estadio Prueba Repetido', 'Dos', 'XQA', 2000, 'UTC', NULL, NULL, 1, 1, 1, 1);

EXEC Torneo.usp_ImportarSedes;

SELECT 'SD1' AS caso, id_registro, LEFT(nombre_estadio, 30) AS estadio, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_sedes ORDER BY id_registro;

SELECT 'SD1 sede' AS caso, s.nombre_estadio, s.ciudad, p.codigo_fifa, s.capacidad, s.huso_horario, s.latitud, s.longitud,
       (SELECT STRING_AGG(CONCAT(e.numero_espacio, N': ', e.tarifa_usd), N', ') WITHIN GROUP (ORDER BY e.numero_espacio)
        FROM Publicidad.ESPACIO_PUBLICITARIO AS e WHERE e.id_sede = s.id_sede) AS espacios
FROM Torneo.SEDE AS s
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE s.nombre_estadio LIKE 'Estadio Prueba%';
GO


/* SD2 (OK) Reimportación: la sede de SD1 con otra capacidad, y otra vez igual.
   Esperado: primero ACTUALIZADO (capacidad 45000; la ciudad, el país y las
   coordenadas que no vienen quedan como estaban), después SIN CAMBIOS; sigue
   habiendo una sola sede de prueba con 4 espacios. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DELETE FROM #staging_sedes;
INSERT INTO #staging_sedes (id_registro, nombre_estadio, capacidad) VALUES (1, 'Estadio Prueba Importación 66', 45000);
EXEC Torneo.usp_ImportarSedes;
SELECT 'SD2 primera vez' AS caso, nombre_estadio, accion FROM #staging_sedes;

UPDATE #staging_sedes SET accion = NULL, errores = NULL;
EXEC Torneo.usp_ImportarSedes;
SELECT 'SD2 segunda vez' AS caso, nombre_estadio, accion FROM #staging_sedes;

SELECT 'SD2 después' AS caso, s.ciudad, s.capacidad, s.latitud, s.longitud,
       (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO AS e WHERE e.id_sede = s.id_sede) AS espacios
FROM Torneo.SEDE AS s WHERE s.nombre_estadio LIKE 'Estadio Prueba%';
GO


/* ============================================================================
   SELECCIONES (usp_ImportarSelecciones)
   ============================================================================ */

/* SL1 (OK) Importación con errores parciales, con las listas presentadas el
   01/06/2026.
   Esperado: 3 INSERTADO (XQA, XQB y XQC en el grupo L, cada una con su lista
   de convocados vacía; XQA y XQB con su nombre en inglés como nombre
   alternativo; los códigos y la confederación en minúsculas se guardan en
   mayúsculas) y 5 RECHAZADO: QQQ (no hay un país con ese código) y las 4
   filas de XQE, porque viene 4 veces (además, una tiene la confederación
   MARS y otra el grupo Z). */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

CREATE TABLE #staging_selecciones (
    id_registro         INT PRIMARY KEY,
    codigo_fifa         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
    confederacion       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
    grupo               NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
    nombre_alternativo  NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
    errores             NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion              VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_selecciones (id_registro, codigo_fifa, confederacion, grupo, nombre_alternativo)
VALUES (1, 'xqa', 'conmebol', 'l', N'Testland A'),
       (2, 'XQB', 'UEFA', 'L', N'Testland B'),
       (3, 'XQC', 'CAF', 'L', NULL),
       (4, 'QQQ', 'UEFA', 'L', N'Nowhere'),
       (5, 'XQE', 'AFC', 'K', NULL),
       (6, 'XQE', 'AFC', 'K', NULL),
       (7, 'XQE', 'MARS', 'K', N'Marte'),
       (8, 'XQE', 'OFC', 'Z', NULL);
-- Las filas 5 a 8 son de XQE: las cuatro se rechazan, por repetida y por sus propios motivos.

EXEC Torneo.usp_ImportarSelecciones @fecha_presentacion = '2026-06-01';

SELECT 'SL1' AS caso, id_registro, codigo_fifa, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_selecciones ORDER BY id_registro;

SELECT 'SL1 selecciones' AS caso, p.codigo_fifa, s.confederacion, s.grupo, lc.fecha_presentacion, na.nombre AS nombre_alternativo
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
LEFT JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_seleccion = s.id_seleccion
LEFT JOIN Torneo.NOMBRE_ALTERNATIVO AS na ON na.id_seleccion = s.id_seleccion AND na.id_jugador IS NULL
WHERE p.codigo_fifa LIKE 'XQ_'
ORDER BY p.codigo_fifa;
GO


/* SL2 (OK) El cupo del grupo: XQE al grupo L, que ya está completo, y XQB
   sin cambios en otro conjunto.
   Esperado: primero XQE RECHAZADO (el grupo L quedaría con una selección más
   que SELECCIONES_POR_GRUPO); después XQB SIN CAMBIOS. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DELETE FROM #staging_selecciones;
INSERT INTO #staging_selecciones (id_registro, codigo_fifa, confederacion, grupo) VALUES (1, 'XQE', 'AFC', 'L');
EXEC Torneo.usp_ImportarSelecciones @fecha_presentacion = '2026-06-01';
SELECT 'SL2 cupo' AS caso, codigo_fifa, accion, REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_selecciones;

DELETE FROM #staging_selecciones;
INSERT INTO #staging_selecciones (id_registro, codigo_fifa, confederacion, grupo, nombre_alternativo)
VALUES (1, 'XQB', 'UEFA', 'L', N'Testland B');
EXEC Torneo.usp_ImportarSelecciones;
SELECT 'SL2 sin cambios' AS caso, codigo_fifa, accion FROM #staging_selecciones;
GO


/* ============================================================================
   JUGADORES (usp_ImportarJugadores)
   ============================================================================ */

/* JG1 (OK) Listas iniciales de XQA y XQB (23 jugadores cada una, con las
   posiciones abreviadas GK, DF, MF y FW) y filas con errores.
   Esperado: 46 INSERTADO (con fecha de alta 01/06/2026 y motivo
   "Importación") y 9 RECHAZADO: la selección QQQ; sin nombre; la posición
   XX; el dorsal 0; la fecha de nacimiento futura; "Doble Prueba" dos veces
   (las dos filas); y los 2 jugadores de XQC, porque su lista inicial tendría
   2 jugadores y tienen que ser entre MIN_CONVOCADOS y MAX_CONVOCADOS. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

CREATE TABLE #staging_jugadores (
    id_registro       INT PRIMARY KEY,
    codigo_fifa       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
    nombre            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
    apellido          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
    posicion          VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
    dorsal            TINYINT       NULL,
    fecha_nacimiento  DATE          NULL,
    club_origen       NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
    errores           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion            VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

-- 23 jugadores por selección: arqueros los dorsales 1, 12 y 23; el 1 al 11, en un 4-3-3.
WITH numeros AS (
    SELECT TOP (23) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS TINYINT) AS n FROM sys.all_objects
)
INSERT INTO #staging_jugadores (id_registro, codigo_fifa, nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen)
SELECT s.base + n.n, s.codigo, CONCAT(N'J', n.n), CONCAT(N'Prueba ', s.codigo),
       CASE WHEN n.n IN (1, 12, 23) THEN 'GK'
            WHEN n.n IN (2, 3, 4, 5, 13, 14, 15) THEN 'DF'
            WHEN n.n IN (6, 7, 8, 16, 17, 18) THEN 'MF'
            ELSE 'FW'
       END,
       n.n, DATEADD(DAY, n.n, '1998-01-01'), N'Club Prueba'
FROM numeros AS n
CROSS JOIN (VALUES ('XQA', 0), ('XQB', 100)) AS s (codigo, base);

INSERT INTO #staging_jugadores (id_registro, codigo_fifa, nombre, apellido, posicion, dorsal, fecha_nacimiento)
VALUES (201, 'QQQ', N'Sin', N'Lista', 'GK', 1, NULL),
       (202, 'XQA', NULL, N'Sin Nombre', 'FW', 40, NULL),
       (203, 'XQA', N'Mala', N'Posicion', 'XX', 41, NULL),
       (204, 'XQB', N'Cero', N'Prueba', 'MF', 0, NULL),
       (205, 'XQB', N'Futuro', N'Prueba', 'MF', 42, '2099-01-01'),
       (206, 'XQA', N'Doble', N'Prueba', 'DF', 43, NULL),
       (207, 'XQA', N'Doble', N'Prueba', 'DF', 44, NULL),
       (208, 'XQC', N'Solo', N'Uno', 'GK', 1, NULL),
       (209, 'XQC', N'Solo', N'Dos', 'FW', 9, NULL);

EXEC Torneo.usp_ImportarJugadores;

SELECT 'JG1' AS caso, accion, COUNT(*) AS filas FROM #staging_jugadores GROUP BY accion;

SELECT 'JG1 rechazados' AS caso, id_registro, codigo_fifa, nombre, apellido, posicion, dorsal,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_jugadores WHERE accion = 'RECHAZADO' ORDER BY id_registro;

SELECT 'JG1 listas' AS caso, p.codigo_fifa, COUNT(*) AS jugadores, SUM(IIF(j.posicion_habitual = 'ARQUERO', 1, 0)) AS arqueros,
       MIN(j.fecha_alta) AS fecha_alta, MIN(j.motivo_alta) AS motivo_alta
FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.codigo_fifa LIKE 'XQ_'
GROUP BY p.codigo_fifa;
GO


/* JG2 (OK) Cambios sobre las listas ya cargadas.
   Esperado: J24 de XQA INSERTADO (la lista queda con 24); J2 de XQA
   ACTUALIZADO (cambia de club); J3 de XQA SIN CAMBIOS; "Otro Prueba" de XQA
   RECHAZADO (el dorsal 5 ya lo tiene J5, que no viene en el conjunto); y los
   4 jugadores nuevos de XQB RECHAZADO (la lista quedaría con 27 convocados y
   el máximo es MAX_CONVOCADOS). */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DELETE FROM #staging_jugadores;
INSERT INTO #staging_jugadores (id_registro, codigo_fifa, nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen)
VALUES (1, 'XQA', N'J24', N'Prueba XQA', 'FW', 24, '1999-05-05', N'Club Prueba'),
       (2, 'XQA', N'J2',  N'Prueba XQA', 'DF', 2,  '1998-01-03', N'Otro Club'),
       (3, 'XQA', N'J3',  N'Prueba XQA', 'DF', 3,  '1998-01-04', N'Club Prueba'),
       (4, 'XQA', N'Otro', N'Prueba', 'MF', 5, NULL, NULL),
       (5, 'XQB', N'Nuevo1', N'Prueba', 'MF', 24, NULL, NULL),
       (6, 'XQB', N'Nuevo2', N'Prueba', 'MF', 25, NULL, NULL),
       (7, 'XQB', N'Nuevo3', N'Prueba', 'MF', 26, NULL, NULL),
       (8, 'XQB', N'Nuevo4', N'Prueba', 'MF', 27, NULL, NULL);

EXEC Torneo.usp_ImportarJugadores;

SELECT 'JG2' AS caso, id_registro, codigo_fifa, nombre, dorsal, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_jugadores ORDER BY id_registro;

SELECT 'JG2 jugadores' AS caso, j.dorsal, j.nombre, j.apellido, j.club_origen
FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.codigo_fifa = 'XQA' AND j.dorsal IN (2, 3, 5, 24)
ORDER BY j.dorsal;
GO


/* ============================================================================
   PARTIDOS (usp_ImportarPartidos)
   ============================================================================ */

/* PA1 (OK) Importación con errores parciales.
   Esperado: 2 INSERTADO: el 221 (XQA - XQB, fase de grupos, 2 a 1 con 30000
   espectadores: queda FINALIZADO) y el 222 (XQA - XQC, "Round of 16" se
   guarda como OCTAVOS, sin resultado: queda PROGRAMADO); la hora local es la
   UTC menos 3 horas (Argentina Standard Time). Y 7 RECHAZADO: número 0;
   estadio que no es sede; fase MUNDIAL; la misma selección como local y
   visitante; un empate de eliminación directa sin penales; la selección XQE,
   que no está registrada; asistencia mayor que la capacidad. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

CREATE TABLE #staging_partidos (
    id_registro            INT PRIMARY KEY,
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
    errores                NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion                 VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_partidos (id_registro, numero_partido, nombre_estadio, fase, fecha_hora_utc, codigo_fifa_local,
                               codigo_fifa_visitante, goles_local, goles_visitante, penales_local, penales_visitante, asistencia)
VALUES (1, 221, 'Estadio Prueba Importación 66', 'Group L', '2026-08-10 20:00', 'XQA', 'XQB', 2, 1, NULL, NULL, 30000),
       (2, 222, 'Estadio Prueba Importación 66', 'Round of 16', '2026-08-15 20:00', 'XQA', 'XQC', NULL, NULL, NULL, NULL, NULL),
       (3, 0,   'Estadio Prueba Importación 66', 'Final', '2026-08-20 20:00', 'XQB', 'XQC', NULL, NULL, NULL, NULL, NULL),
       (4, 223, 'Estadio Inexistente', 'Final', '2026-08-21 20:00', 'XQB', 'XQC', NULL, NULL, NULL, NULL, NULL),
       (5, 224, 'Estadio Prueba Importación 66', 'MUNDIAL', '2026-08-22 20:00', 'XQB', 'XQC', NULL, NULL, NULL, NULL, NULL),
       (6, 225, 'Estadio Prueba Importación 66', 'Final', '2026-08-23 20:00', 'XQB', 'XQB', NULL, NULL, NULL, NULL, NULL),
       (7, 230, 'Estadio Prueba Importación 66', 'Final', '2026-08-24 20:00', 'XQB', 'XQC', 1, 1, NULL, NULL, NULL),
       (8, 234, 'Estadio Prueba Importación 66', 'Final', '2026-08-25 20:00', 'XQB', 'XQE', NULL, NULL, NULL, NULL, NULL),
       (9, 237, 'Estadio Prueba Importación 66', 'Final', '2026-08-26 20:00', 'XQB', 'XQC', 2, 0, NULL, NULL, 99999);

EXEC Torneo.usp_ImportarPartidos;

SELECT 'PA1' AS caso, id_registro, numero_partido, fase, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_partidos ORDER BY id_registro;

SELECT 'PA1 partidos' AS caso, f.numero_partido, f.fase, f.seleccion_local, f.resultado, f.seleccion_visitante,
       f.asistencia, f.estado, p.fecha_hora_utc, p.fecha_hora_local
FROM Torneo.vw_Fixture AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
WHERE f.numero_partido IN (221, 222)
ORDER BY f.numero_partido;
GO


/* PA2 (OK) Sobre el fixture cargado.
   Esperado: el 222 ACTUALIZADO (2 a 2 y 4 a 3 en penales: queda FINALIZADO);
   el 221 RECHAZADO (ya se jugó: no se le puede cambiar la fecha); y el 223
   RECHAZADO (en la misma sede y el mismo día que el 221, y XQB juega los dos
   partidos con menos de 24 horas de diferencia). */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DELETE FROM #staging_partidos;
INSERT INTO #staging_partidos (id_registro, numero_partido, nombre_estadio, fase, fecha_hora_utc, codigo_fifa_local,
                               codigo_fifa_visitante, goles_local, goles_visitante, penales_local, penales_visitante)
VALUES (1, 222, NULL, NULL, NULL, NULL, NULL, 2, 2, 4, 3),
       (2, 221, NULL, NULL, '2026-08-11 20:00', NULL, NULL, NULL, NULL, NULL, NULL),
       (3, 223, 'Estadio Prueba Importación 66', 'Group L', '2026-08-10 23:00', 'XQB', 'XQC', NULL, NULL, NULL, NULL);

EXEC Torneo.usp_ImportarPartidos;

SELECT 'PA2' AS caso, id_registro, numero_partido, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_partidos ORDER BY id_registro;

SELECT 'PA2 partidos' AS caso, numero_partido, resultado, estado
FROM Torneo.vw_Fixture WHERE numero_partido IN (221, 222, 223) ORDER BY numero_partido;
GO


/* ============================================================================
   LO QUE PASÓ EN LOS PARTIDOS (usp_ImportarDesarrolloPartidos)
   ============================================================================ */

/* DP1 (OK) Formaciones y eventos del 221, y la formación de XQA en el 222,
   con errores.
   Esperado:
   - INSERTADO: las formaciones del 221 (XQA, 11 titulares y el suplente J12;
     XQB, 11 titulares), los 3 goles del 221 (J9 de XQA en el 30, el penal de
     J10 de XQA en el 45+2 y J9 de XQB en el 60: 2 a 1, como el resultado),
     el cambio de J11 por J12 de XQA en el entretiempo (el motivo "tactico" se
     guarda como TACTICO) y la amarilla de J4 de XQB. El esquema de cada
     formación sale de las posiciones de sus titulares: 4-3-3.
   - RECHAZADO: J13 de XQA, que figura dos veces en el banco del 221 (las dos
     filas); los 10 titulares de XQA en el 222, porque la formación quedaría
     con 10 y tienen que ser 11; un cambio en el minuto 130; un gol en el
     minuto 50 del PRIMER_TIEMPO; una tarjeta VERDE; un gol en el partido 239,
     que no existe; un gol de J20 de XQA, que no está en la formación; y un
     gol de J9 de XQB en el 222, que es XQA - XQC. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

CREATE TABLE #staging_eventos (
    id_evento           INT IDENTITY(1,1) PRIMARY KEY,
    tipo                VARCHAR(12)   COLLATE DATABASE_DEFAULT NULL,
    numero_partido      TINYINT       NULL,
    id_jugador          INT           NULL,
    id_jugador_entra    INT           NULL,
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

-- Los jugadores de prueba, por selección y dorsal.
SELECT p.codigo_fifa, j.dorsal, j.id_jugador, j.posicion_habitual
INTO #jugadores_prueba
FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = lc.id_seleccion
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.codigo_fifa IN ('XQA', 'XQB');

-- Formaciones del 221: titulares del 1 al 11 de cada selección y J12 y J13 (dos veces) en el banco de XQA.
INSERT INTO #staging_eventos (tipo, numero_partido, id_jugador, es_titular, posicion_en_cancha)
SELECT f.tipo, f.numero_partido, f.id_jugador, f.es_titular, f.posicion
FROM (SELECT 'FORMACION' AS tipo, 221 AS numero_partido, id_jugador, CAST(1 AS BIT) AS es_titular,
             posicion_habitual AS posicion, codigo_fifa, dorsal
      FROM #jugadores_prueba WHERE dorsal <= 11
      UNION ALL
      SELECT 'FORMACION', 221, id_jugador, 0, NULL, codigo_fifa, dorsal
      FROM #jugadores_prueba WHERE codigo_fifa = 'XQA' AND dorsal IN (12, 13)
      UNION ALL
      SELECT 'FORMACION', 221, id_jugador, 0, NULL, codigo_fifa, dorsal
      FROM #jugadores_prueba WHERE codigo_fifa = 'XQA' AND dorsal = 13) AS f
ORDER BY f.codigo_fifa, f.dorsal;

-- Formación de XQA en el 222, con 10 titulares (XQC no tiene jugadores cargados).
INSERT INTO #staging_eventos (tipo, numero_partido, id_jugador, es_titular, posicion_en_cancha)
SELECT 'FORMACION', 222, id_jugador, 1, posicion_habitual FROM #jugadores_prueba WHERE codigo_fifa = 'XQA' AND dorsal <= 10
ORDER BY dorsal;

-- Eventos del 221.
INSERT INTO #staging_eventos (tipo, numero_partido, id_jugador, id_jugador_entra, minuto, minuto_adicional, en_entretiempo,
                              motivo, periodo, tipo_gol, tipo_tarjeta, es_doble_amarilla)
SELECT v.tipo, v.numero_partido, j.id_jugador, je.id_jugador, v.minuto, v.adicional, v.entretiempo, v.motivo, v.periodo,
       v.tipo_gol, v.tarjeta, v.doble
FROM (VALUES ('GOL',     221, 'XQA', 9,  NULL, 30,  0, NULL, NULL,         'PRIMER_TIEMPO',  'JUGADA', NULL,       NULL),
             ('GOL',     221, 'XQA', 10, NULL, 45,  2, NULL, NULL,         'ADICIONALES',    'PENAL',  NULL,       NULL),
             ('GOL',     221, 'XQB', 9,  NULL, 60,  0, NULL, NULL,         'SEGUNDO_TIEMPO', 'JUGADA', NULL,       NULL),
             ('CAMBIO',  221, 'XQA', 11, 12,   46,  0, 1,    'tactico',    NULL,             NULL,     NULL,       NULL),
             ('TARJETA', 221, 'XQB', 4,  NULL, 20,  0, NULL, 'Falta',      NULL,             NULL,     'AMARILLA', 0),
             ('CAMBIO',  221, 'XQA', 7,  12,   130, 0, 0,    'TACTICO',    NULL,             NULL,     NULL,       NULL),
             ('GOL',     221, 'XQA', 9,  NULL, 50,  0, NULL, NULL,         'PRIMER_TIEMPO',  'JUGADA', NULL,       NULL),
             ('TARJETA', 221, 'XQB', 5,  NULL, 25,  0, NULL, 'Protesta',   NULL,             NULL,     'VERDE',    0),
             ('GOL',     239, 'XQA', 9,  NULL, 10,  0, NULL, NULL,         'PRIMER_TIEMPO',  'JUGADA', NULL,       NULL),
             ('GOL',     221, 'XQA', 20, NULL, 70,  0, NULL, NULL,         'SEGUNDO_TIEMPO', 'JUGADA', NULL,       NULL),
             ('GOL',     222, 'XQB', 9,  NULL, 10,  0, NULL, NULL,         'PRIMER_TIEMPO',  'JUGADA', NULL,       NULL))
     AS v (tipo, numero_partido, codigo, dorsal, dorsal_entra, minuto, adicional, entretiempo, motivo, periodo, tipo_gol,
           tarjeta, doble)
INNER JOIN #jugadores_prueba AS j ON j.codigo_fifa = v.codigo AND j.dorsal = v.dorsal
LEFT JOIN #jugadores_prueba AS je ON je.codigo_fifa = v.codigo AND je.dorsal = v.dorsal_entra;

EXEC DesarrolloPartido.usp_ImportarDesarrolloPartidos;

SELECT 'DP1' AS caso, e.id_evento, e.tipo, e.numero_partido, j.codigo_fifa, j.dorsal, je.dorsal AS entra, e.minuto,
       e.minuto_adicional, e.accion, REPLACE(STUFF(e.errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_eventos AS e
LEFT JOIN #jugadores_prueba AS j ON j.id_jugador = e.id_jugador
LEFT JOIN #jugadores_prueba AS je ON je.id_jugador = e.id_jugador_entra
ORDER BY e.id_evento;

SELECT 'DP1 cargado' AS caso, p.numero_partido, pa.codigo_fifa, f.esquema_tactico,
       SUM(IIF(a.es_titular = 1, 1, 0)) AS titulares, SUM(IIF(a.es_titular = 0, 1, 0)) AS suplentes,
       (SELECT COUNT(*) FROM DesarrolloPartido.GOL AS g
        INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = g.id_jugador_autor
        INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
        WHERE g.id_partido = p.id_partido AND lc.id_seleccion = f.id_seleccion) AS goles,
       (SELECT COUNT(*) FROM DesarrolloPartido.CAMBIO AS c
        INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
        INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
        WHERE c.id_partido = p.id_partido AND lc.id_seleccion = f.id_seleccion) AS cambios,
       (SELECT COUNT(*) FROM DesarrolloPartido.AMONESTACION AS am
        INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = am.id_jugador
        INNER JOIN Torneo.LISTA_CONVOCADOS AS lc ON lc.id_lista = j.id_lista
        WHERE am.id_partido = p.id_partido AND lc.id_seleccion = f.id_seleccion) AS tarjetas
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = f.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
WHERE p.numero_partido IN (221, 222)
GROUP BY p.id_partido, p.numero_partido, pa.codigo_fifa, f.id_seleccion, f.esquema_tactico
ORDER BY p.numero_partido, pa.codigo_fifa;
GO


/* DP2 (OK) Reimportación de los eventos válidos de DP1.
   Esperado: todos SIN CAMBIOS; no se repite nada. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DELETE FROM #staging_eventos WHERE accion = 'RECHAZADO';
UPDATE #staging_eventos SET accion = NULL, errores = NULL;

EXEC DesarrolloPartido.usp_ImportarDesarrolloPartidos;

SELECT 'DP2' AS caso, accion, COUNT(*) AS eventos FROM #staging_eventos GROUP BY accion;

SELECT 'DP2 cargado' AS caso,
       (SELECT COUNT(*) FROM DesarrolloPartido.ALINEACION AS a
        INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido WHERE p.numero_partido = 221) AS alineados_221,
       (SELECT COUNT(*) FROM DesarrolloPartido.GOL AS g
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido WHERE p.numero_partido = 221) AS goles_221;
GO


/* PA3 (OK) El resultado del 221 ya tiene sus goles cargados (2 a 1).
   Esperado: el 221 con 3 a 1 RECHAZADO (el resultado cambia y no coincide
   con los goles cargados); el partido sigue 2 a 1. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DELETE FROM #staging_partidos;
INSERT INTO #staging_partidos (id_registro, numero_partido, goles_local, goles_visitante) VALUES (1, 221, 3, 1);

EXEC Torneo.usp_ImportarPartidos;

SELECT 'PA3' AS caso, numero_partido, accion, REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_partidos;
SELECT 'PA3 partido' AS caso, numero_partido, resultado FROM Torneo.vw_Fixture WHERE numero_partido = 221;
GO


/* SD3 (OK) La sede con partidos jugados.
   Esperado: primero RECHAZADO con capacidad 20000 (es menor que la
   asistencia del 221, 30000); después ACTUALIZADO con el huso "SA Pacific
   Standard Time" (UTC-5): la hora local de los partidos 221 y 222 pasa de
   UTC-3 a UTC-5 (17:00 a 15:00). */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DELETE FROM #staging_sedes;
INSERT INTO #staging_sedes (id_registro, nombre_estadio, capacidad) VALUES (1, 'Estadio Prueba Importación 66', 20000);
EXEC Torneo.usp_ImportarSedes;
SELECT 'SD3 capacidad' AS caso, accion, REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_sedes;

DELETE FROM #staging_sedes;
INSERT INTO #staging_sedes (id_registro, nombre_estadio, huso_horario) VALUES (1, 'Estadio Prueba Importación 66', 'SA Pacific Standard Time');
EXEC Torneo.usp_ImportarSedes;
SELECT 'SD3 huso' AS caso, accion FROM #staging_sedes;

SELECT 'SD3 partidos' AS caso, numero_partido, fecha_hora_utc, fecha_hora_local
FROM Torneo.PARTIDO WHERE numero_partido IN (221, 222) ORDER BY numero_partido;
GO


/* ============================================================================
   ÁRBITROS Y DESIGNACIONES (usp_ImportarArbitros, usp_ImportarDesignaciones)
   ============================================================================ */

/* AR1 (OK) Árbitros con errores parciales, y otra vez con una fecha de nacimiento.
   Esperado: primero 4 INSERTADO ("Uno Prueba Arbitro", con el país en
   minúsculas y la categoría FIFA; "Dos", con CONFEDERATION, que se guarda
   como CONFEDERACION; "Tres", de XQA, y "Diez", de XQE) y 7 RECHAZADO: el
   país ZZZ; sin nombre; apellido de 61 caracteres; categoría NACIONAL; fecha
   de nacimiento futura; y "Nueve" dos veces (las dos filas). Después:
   "Uno" ACTUALIZADO (nacido el 01/03/1985) y "Dos" SIN CAMBIOS. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

CREATE TABLE #staging_arbitros (
    id_registro       INT PRIMARY KEY,
    codigo_fifa       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
    nombre            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
    apellido          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
    categoria         VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
    fecha_nacimiento  DATE          NULL,
    errores           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion            VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_arbitros (id_registro, codigo_fifa, nombre, apellido, categoria, fecha_nacimiento)
VALUES (1, 'xqe', N' Uno ', N'Prueba Arbitro', 'fifa', NULL),
       (2, 'XQE', N'Dos', N'Prueba Arbitro', 'Confederation', NULL),
       (3, 'XQA', N'Tres', N'Prueba Arbitro', 'FIFA', NULL),
       (4, 'ZZZ', N'Cuatro', N'Prueba Arbitro', 'FIFA', NULL),
       (5, 'XQE', NULL, N'Prueba Arbitro', 'FIFA', NULL),
       (6, 'XQE', N'Seis', REPLICATE(N'a', 61), 'FIFA', NULL),
       (7, 'XQE', N'Siete', N'Prueba Arbitro', 'NACIONAL', NULL),
       (8, 'XQE', N'Ocho', N'Prueba Arbitro', 'FIFA', '2099-01-01'),
       (9, 'XQE', N'Nueve', N'Prueba Arbitro', 'FIFA', NULL),
       (10, 'XQE', N'Nueve', N'Prueba Arbitro', 'FIFA', NULL),
       (11, 'XQE', N'Diez', N'Prueba Arbitro', 'FIFA', NULL);

EXEC Arbitraje.usp_ImportarArbitros;

SELECT 'AR1' AS caso, id_registro, codigo_fifa, nombre, LEFT(apellido, 20) AS apellido, categoria, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_arbitros ORDER BY id_registro;

DELETE FROM #staging_arbitros;
INSERT INTO #staging_arbitros (id_registro, codigo_fifa, nombre, apellido, categoria, fecha_nacimiento)
VALUES (1, 'XQE', N'Uno', N'Prueba Arbitro', 'FIFA', '1985-03-01'),
       (2, 'XQE', N'Dos', N'Prueba Arbitro', 'CONFEDERACION', NULL);
EXEC Arbitraje.usp_ImportarArbitros;
SELECT 'AR1 otra vez' AS caso, nombre, accion FROM #staging_arbitros ORDER BY id_registro;

SELECT 'AR1 árbitros' AS caso, p.codigo_fifa, a.nombre, a.apellido, a.categoria, a.fecha_nacimiento, a.activo
FROM Arbitraje.ARBITRO AS a
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais
WHERE p.codigo_fifa LIKE 'XQ_'
ORDER BY a.id_arbitro;
GO


/* DA1 (OK) Designaciones con errores parciales, en los partidos 221 y 222, que
   ya se jugaron (es una carga histórica).
   Esperado: 3 INSERTADO ("Uno" PRINCIPAL del 221, con el rol "Referee" en
   inglés; "Dos" ASISTENTE_1 del 221, con "assistant referee 1"; y "Uno"
   VAR_APOYO del 222, con "Support video assistant referee") y 7 RECHAZADO:
   "Tres" en el 221 (conflicto de nacionalidad: es de XQA, que juega el
   partido); el partido 230, que no existe; sin árbitro; un árbitro que no
   existe; el rol JUEZ; y "Dos" dos veces en el 222 (las dos filas). */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DECLARE @xqe SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XQE');
DECLARE @xqa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XQA');
DECLARE @uno INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @xqe AND nombre = N'Uno');
DECLARE @dos INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @xqe AND nombre = N'Dos');
DECLARE @tres INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @xqa AND nombre = N'Tres');

CREATE TABLE #staging_designaciones (
    id_registro     INT PRIMARY KEY,
    numero_partido  TINYINT       NULL,
    id_arbitro      INT           NULL,
    rol             VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
    errores         NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion          VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_designaciones (id_registro, numero_partido, id_arbitro, rol)
VALUES (1, 221, @uno, 'Referee'), (2, 221, @dos, 'assistant referee 1'), (3, 221, @tres, 'VAR'),
       (4, 230, @uno, 'CUARTO'), (5, 222, NULL, 'CUARTO'), (6, 222, 2000000000, 'CUARTO'), (7, 222, @uno, 'JUEZ'),
       (8, 222, @uno, 'Support video assistant referee'), (9, 222, @dos, 'CUARTO'), (10, 222, @dos, 'AVAR');

EXEC Arbitraje.usp_ImportarDesignaciones;

SELECT 'DA1' AS caso, id_registro, numero_partido, rol, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_designaciones ORDER BY id_registro;
GO


/* DA2 (OK) Sobre las designaciones cargadas.
   Esperado: "Dos" pasa de ASISTENTE_1 a CUARTO en el 221 (ACTUALIZADO);
   "Uno" VAR_APOYO del 222 SIN CAMBIOS; y "Uno" y "Diez" como PRINCIPAL del
   221, RECHAZADOS los dos (el rol lo tendrían 2 árbitros), así que "Uno"
   sigue siendo el principal. Quedan 3 designaciones de prueba: "Uno"
   PRINCIPAL y "Dos" CUARTO en el 221, y "Uno" VAR_APOYO en el 222. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DECLARE @xqe SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XQE');
DECLARE @uno INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @xqe AND nombre = N'Uno');
DECLARE @dos INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @xqe AND nombre = N'Dos');
DECLARE @diez INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE id_pais = @xqe AND nombre = N'Diez');

DELETE FROM #staging_designaciones;
INSERT INTO #staging_designaciones (id_registro, numero_partido, id_arbitro, rol)
VALUES (1, 221, @uno, 'PRINCIPAL'), (2, 221, @dos, 'Fourth official'), (3, 221, @diez, 'PRINCIPAL'),
       (4, 222, @uno, 'var_apoyo');

EXEC Arbitraje.usp_ImportarDesignaciones;

SELECT 'DA2' AS caso, id_registro, numero_partido, rol, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_designaciones ORDER BY id_registro;

SELECT 'DA2 designaciones' AS caso, p.numero_partido, d.rol, a.nombre, a.apellido
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = d.id_arbitro
WHERE p.numero_partido IN (221, 222)
ORDER BY p.numero_partido, d.rol;
GO


/* ============================================================================
   INDICADORES, COTIZACIONES Y FERIADOS
   ============================================================================ */

/* IE1 (OK) Indicadores con errores parciales, y otra vez con un valor revisado.
   Esperado: primero 2 INSERTADO (PBI per cápita de XQA en 2023 y 2024, con el
   país y el indicador en minúsculas) y 5 RECHAZADO: el país ZZZ; el
   indicador NY-GDP (caracteres no admitidos); el año 1950; sin valor; y XQB
   2023 dos veces con valores distintos (las dos filas). Después, con 2024
   revisado: 2023 SIN CAMBIOS y 2024 ACTUALIZADO (1200). */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

CREATE TABLE #staging_indicadores (
    id_registro       INT IDENTITY(1,1) PRIMARY KEY,
    codigo_iso3       NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
    codigo_indicador  NVARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
    anio              SMALLINT       NULL,
    valor             DECIMAL(18,4)  NULL,
    errores           NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
    accion            VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_indicadores (codigo_iso3, codigo_indicador, anio, valor)
VALUES ('xqa', 'ny.gdp.pcap.cd', 2023, 1000), ('XQA', 'NY.GDP.PCAP.CD', 2024, 1100),
       ('ZZZ', 'NY.GDP.PCAP.CD', 2023, 1), ('XQA', 'NY-GDP', 2023, 1), ('XQA', 'NY.GDP.PCAP.CD', 1950, 1),
       ('XQA', 'NY.GDP.PCAP.CD', 2022, NULL), ('XQB', 'NY.GDP.PCAP.CD', 2023, 10), ('XQB', 'NY.GDP.PCAP.CD', 2023, 20);

EXEC DatosGenerales.usp_ImportarIndicadoresEconomicos;

SELECT 'IE1' AS caso, id_registro, codigo_iso3, codigo_indicador, anio, valor, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_indicadores ORDER BY id_registro;

DELETE FROM #staging_indicadores;
INSERT INTO #staging_indicadores (codigo_iso3, codigo_indicador, anio, valor)
VALUES ('XQA', 'NY.GDP.PCAP.CD', 2023, 1000), ('XQA', 'NY.GDP.PCAP.CD', 2024, 1200);
EXEC DatosGenerales.usp_ImportarIndicadoresEconomicos;
SELECT 'IE1 revisado' AS caso, codigo_iso3, anio, valor, accion FROM #staging_indicadores ORDER BY anio;

SELECT 'IE1 indicadores' AS caso, p.codigo_fifa, ie.codigo_indicador, ie.anio, ie.valor
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE p.codigo_fifa LIKE 'XQ_'
ORDER BY p.codigo_fifa, ie.anio;
GO


/* CO1 (OK) Cotizaciones con errores parciales, y otra vez con un valor corregido.
   Esperado: primero 2 INSERTADO (XTS el 01/06 y el 02/06/2026) y 6
   RECHAZADO: USD (el dólar no lleva cotización); AB (no es un código de 3
   letras); una fecha futura; un valor 0; y XXX el 01/06/2026 dos veces con
   valores distintos (las dos filas). Después: el 01/06 SIN CAMBIOS y el
   02/06 ACTUALIZADO (1.7). */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

CREATE TABLE #staging_cotizaciones (
    id_registro       INT IDENTITY(1,1) PRIMARY KEY,
    codigo_moneda     NVARCHAR(50)   COLLATE DATABASE_DEFAULT NULL,
    fecha             DATE           NULL,
    unidades_por_usd  DECIMAL(19,6)  NULL,
    errores           NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
    accion            VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_cotizaciones (codigo_moneda, fecha, unidades_por_usd)
VALUES ('xts', '2026-06-01', 1.5), ('XTS', '2026-06-02', 1.6), ('USD', '2026-06-01', 1), ('AB', '2026-06-01', 1),
       ('XTS', '2099-01-01', 1), ('XTS', '2026-06-03', 0), ('XXX', '2026-06-01', 1), ('XXX', '2026-06-01', 2);

EXEC DatosGenerales.usp_ImportarCotizaciones;

SELECT 'CO1' AS caso, id_registro, codigo_moneda, fecha, unidades_por_usd, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_cotizaciones ORDER BY id_registro;

DELETE FROM #staging_cotizaciones;
INSERT INTO #staging_cotizaciones (codigo_moneda, fecha, unidades_por_usd)
VALUES ('XTS', '2026-06-01', 1.5), ('XTS', '2026-06-02', 1.7);
EXEC DatosGenerales.usp_ImportarCotizaciones;
SELECT 'CO1 corregido' AS caso, codigo_moneda, fecha, unidades_por_usd, accion FROM #staging_cotizaciones ORDER BY fecha;
GO


/* FE1 (OK) Feriados con errores parciales, y otra vez con un nombre cambiado.
   Esperado: primero 2 INSERTADO (XQA y XQB el 09/07/2026) y 5 RECHAZADO: un
   país que no existe; un nombre de más de 200 caracteres; sin nombre; y XQA
   el 10/07/2026 dos veces (las dos filas). Después: XQA SIN CAMBIOS y XQB
   ACTUALIZADO ("Otro nombre"). */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DECLARE @xqa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XQA');
DECLARE @xqb SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XQB');

CREATE TABLE #staging_feriados (
    id_registro  INT IDENTITY(1,1) PRIMARY KEY,
    id_pais      SMALLINT       NULL,
    fecha        DATE           NULL,
    nombre       NVARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
    errores      NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
    accion       VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #staging_feriados (id_pais, fecha, nombre)
VALUES (@xqa, '2026-07-09', N'Día de prueba'), (@xqb, '2026-07-09', N'Día de prueba'),
       (32000, '2026-07-09', N'País inexistente'), (@xqa, '2026-07-11', REPLICATE(N'x', 201)),
       (@xqa, '2026-07-12', N'  '), (@xqa, '2026-07-10', N'Uno'), (@xqa, '2026-07-10', N'Dos');

EXEC DatosGenerales.usp_ImportarFeriados;

SELECT 'FE1' AS caso, id_registro, id_pais, fecha, LEFT(nombre, 20) AS nombre, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_feriados ORDER BY id_registro;

DELETE FROM #staging_feriados;
INSERT INTO #staging_feriados (id_pais, fecha, nombre)
VALUES (@xqa, '2026-07-09', N'Día de prueba'), (@xqb, '2026-07-09', N'Otro nombre');
EXEC DatosGenerales.usp_ImportarFeriados;
SELECT 'FE1 cambiado' AS caso, id_pais, fecha, nombre, accion FROM #staging_feriados ORDER BY id_registro;
GO


/* ============================================================================
   CAMPAÑAS PUBLICITARIAS (usp_ImportarCampanias)
   ============================================================================ */

/* CP1 (OK) Campañas con errores parciales.
   Esperado: 2 INSERTADO y 9 RECHAZADO.
     - 1 "Campaña Prueba 66 A" del "Anunciante Prueba 66" (XQA): INSERTADO,
       con la pieza "Pieza A1" (español, mercados XQA y XQB) y "Pieza A2" (sin
       idioma, mercado XQA).
     - 2 "Campaña Prueba 66 B" del mismo anunciante: INSERTADO, con "Pieza
       B1" (español, sin mercado).
     - 3 sin anunciante; 4 razón social de 151 caracteres.
     - 5 país inexistente, sin nombre y la fecha de fin anterior a la de
       inicio (los tres motivos juntos).
     - 6 sin fechas y sin piezas.
     - 7 piezas inválidas: una sin título, una de 151 caracteres, un idioma
       y un país de interés inexistentes, y "Pieza X" en español y en inglés.
     - 8 y 9 la misma campaña del mismo anunciante dos veces.
     - 10 y 11 un anunciante con países distintos (XQA y XQB).
   Queda un solo "Anunciante Prueba 66", con sus 2 campañas y 3 piezas. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DECLARE @xqa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XQA');
DECLARE @xqb SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XQB');
DECLARE @es  SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es');
DECLARE @en  SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');

CREATE TABLE #staging_campanias (
    id_registro   INT            PRIMARY KEY,
    anunciante    NVARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
    id_pais       SMALLINT       NULL,
    nombre        NVARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
    fecha_inicio  DATE           NULL,
    fecha_fin     DATE           NULL,
    errores       NVARCHAR(MAX)  COLLATE DATABASE_DEFAULT NULL,
    accion        VARCHAR(15)    COLLATE DATABASE_DEFAULT NULL
);
CREATE TABLE #staging_piezas (
    id_registro      INT            NOT NULL,
    titulo           NVARCHAR(400)  COLLATE DATABASE_DEFAULT NULL,
    id_idioma        SMALLINT       NULL,
    id_pais_interes  SMALLINT       NULL
);

INSERT INTO #staging_campanias (id_registro, anunciante, id_pais, nombre, fecha_inicio, fecha_fin)
VALUES (1,  N' Anunciante Prueba 66 ', @xqa, N'Campaña Prueba 66 A', '2026-08-01', '2026-08-31'),
       (2,  N'Anunciante Prueba 66',   @xqa, N'Campaña Prueba 66 B', '2026-08-01', '2026-08-31'),
       (3,  N'  ',                     @xqa, N'Sin anunciante 66',   '2026-08-01', '2026-08-31'),
       (4,  REPLICATE(N'x', 151),      @xqa, N'Razón social larga',  '2026-08-01', '2026-08-31'),
       (5,  N'Anunciante País Inexistente 66', 32000, NULL,          '2026-08-31', '2026-08-01'),
       (6,  N'Otro Anunciante 66',     @xqa, N'Sin fechas 66',       NULL, NULL),
       (7,  N'Otro Anunciante 66',     @xqa, N'Piezas inválidas 66', '2026-08-01', '2026-08-31'),
       (8,  N'Otro Anunciante 66',     @xqa, N'Repetida 66',         '2026-08-01', '2026-08-31'),
       (9,  N'Otro Anunciante 66',     @xqa, N'Repetida 66',         '2026-08-01', '2026-08-31'),
       (10, N'Anunciante Dos Países 66', @xqa, N'Uno 66',            '2026-08-01', '2026-08-31'),
       (11, N'Anunciante Dos Países 66', @xqb, N'Dos 66',            '2026-08-01', '2026-08-31');

INSERT INTO #staging_piezas (id_registro, titulo, id_idioma, id_pais_interes)
VALUES (1, N'Pieza A1', @es, @xqa), (1, N'Pieza A1', @es, @xqb), (1, N'Pieza A2', NULL, @xqa),
       (2, N'Pieza B1', @es, NULL),
       (3, N'Pieza', @es, @xqa), (4, N'Pieza', @es, @xqa), (5, N'Pieza', @es, @xqa),
       (7, NULL, @es, @xqa), (7, REPLICATE(N'y', 151), @es, @xqa), (7, N'Idioma inexistente', 32000, @xqa),
       (7, N'País inexistente', @es, 32000), (7, N'Pieza X', @es, @xqa), (7, N'Pieza X', @en, @xqa),
       (8, N'Pieza', @es, @xqa), (9, N'Pieza', @es, @xqa), (10, N'Pieza', @es, @xqa), (11, N'Pieza', @es, @xqb);

EXEC Publicidad.usp_ImportarCampanias;

SELECT 'CP1' AS caso, id_registro, LEFT(anunciante, 30) AS anunciante, nombre, accion,
       REPLACE(STUFF(errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos
FROM #staging_campanias ORDER BY id_registro;

SELECT 'CP1 cargado' AS caso, an.razon_social, pa.codigo_fifa AS pais, c.nombre AS campania, c.fecha_inicio, c.fecha_fin,
       pz.titulo AS pieza, i.codigo_iso AS idioma,
       (SELECT STRING_AGG(p2.codigo_fifa, ', ') WITHIN GROUP (ORDER BY p2.codigo_fifa)
        FROM Publicidad.PIEZA_PAIS_INTERES AS ppi INNER JOIN DatosGenerales.PAIS AS p2 ON p2.id_pais = ppi.id_pais
        WHERE ppi.id_pieza = pz.id_pieza) AS mercados
FROM Publicidad.ANUNCIANTE AS an
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = an.id_pais
INNER JOIN Publicidad.CAMPANIA AS c ON c.id_anunciante = an.id_anunciante
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania
LEFT JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = pz.id_idioma
WHERE an.razon_social LIKE N'%66'
ORDER BY c.nombre, pz.titulo;
GO


/* CP2 (OK) Reimportación de las campañas de CP1.
   Esperado:
     a) las dos iguales: SIN CAMBIOS, sin duplicar nada;
     b) A con una pieza nueva ("Pieza A3") y el mercado XQB en "Pieza A2", y
        B con "Pieza B1" en inglés y del 05/08 al 31/08: las dos ACTUALIZADO;
        quedan 3 piezas en A (A2 con los mercados XQA y XQB) y B con sus
        fechas nuevas;
     c) una pieza de A se exhibe en el partido 226 (25/08/2026) y A vuelve con
        fecha de fin el 20/08: RECHAZADO (quedaría afuera el partido 226), y
        A sigue hasta el 31/08. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DECLARE @xqa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XQA');
DECLARE @xqb SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XQB');
DECLARE @es  SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es');
DECLARE @en  SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Importación 66');
DECLARE @espacio INT = (SELECT id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede AND numero_espacio = 1);
DECLARE @partido INT, @pieza INT;

-- a) Igual que en CP1.
DELETE FROM #staging_campanias;
DELETE FROM #staging_piezas;
INSERT INTO #staging_campanias (id_registro, anunciante, id_pais, nombre, fecha_inicio, fecha_fin)
VALUES (1, N'Anunciante Prueba 66', @xqa, N'Campaña Prueba 66 A', '2026-08-01', '2026-08-31'),
       (2, N'Anunciante Prueba 66', @xqa, N'Campaña Prueba 66 B', '2026-08-01', '2026-08-31');
INSERT INTO #staging_piezas (id_registro, titulo, id_idioma, id_pais_interes)
VALUES (1, N'Pieza A1', @es, @xqa), (1, N'Pieza A1', @es, @xqb), (1, N'Pieza A2', NULL, @xqa), (2, N'Pieza B1', @es, NULL);
EXEC Publicidad.usp_ImportarCampanias;
SELECT 'CP2a' AS caso, id_registro, nombre, accion FROM #staging_campanias ORDER BY id_registro;

-- b) Una pieza y un mercado nuevos en A; otro idioma y otras fechas en B.
UPDATE #staging_campanias SET errores = NULL, accion = NULL;
UPDATE #staging_campanias SET fecha_inicio = '2026-08-05' WHERE id_registro = 2;
UPDATE #staging_piezas SET id_idioma = @en WHERE id_registro = 2;
INSERT INTO #staging_piezas (id_registro, titulo, id_idioma, id_pais_interes)
VALUES (1, N'Pieza A2', NULL, @xqb), (1, N'Pieza A3', @es, @xqa);
EXEC Publicidad.usp_ImportarCampanias;
SELECT 'CP2b' AS caso, id_registro, nombre, accion FROM #staging_campanias ORDER BY id_registro;

SELECT 'CP2b cargado' AS caso, c.nombre AS campania, c.fecha_inicio, c.fecha_fin, pz.titulo AS pieza, i.codigo_iso AS idioma,
       (SELECT STRING_AGG(p2.codigo_fifa, ', ') WITHIN GROUP (ORDER BY p2.codigo_fifa)
        FROM Publicidad.PIEZA_PAIS_INTERES AS ppi INNER JOIN DatosGenerales.PAIS AS p2 ON p2.id_pais = ppi.id_pais
        WHERE ppi.id_pieza = pz.id_pieza) AS mercados
FROM Publicidad.CAMPANIA AS c
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_campania = c.id_campania
LEFT JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = pz.id_idioma
WHERE c.nombre LIKE N'Campaña Prueba 66 _'
ORDER BY c.nombre, pz.titulo;

-- c) Una pieza de A exhibida en un partido del 25/08, y A con fecha de fin el 20/08.
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 226, @id_sede = @sede, @fase = 'FINAL',
     @fecha_hora_local = '2026-08-25 20:00', @id_partido = @partido OUTPUT;
SET @pieza = (SELECT pz.id_pieza FROM Publicidad.PIEZA_PUBLICITARIA AS pz
              INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
              WHERE c.nombre = N'Campaña Prueba 66 A' AND pz.titulo = N'Pieza A1');
EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @partido, @id_espacio = @espacio, @id_pieza = @pieza;

DELETE FROM #staging_campanias WHERE id_registro = 2;
DELETE FROM #staging_piezas WHERE id_registro = 2;
UPDATE #staging_campanias SET errores = NULL, accion = NULL, fecha_fin = '2026-08-20';
EXEC Publicidad.usp_ImportarCampanias;
SELECT 'CP2c' AS caso, st.id_registro, st.nombre, st.accion, REPLACE(STUFF(st.errores, 1, 2, N''), NCHAR(13) + NCHAR(10), N' | ') AS motivos,
       c.fecha_fin AS fecha_fin_guardada
FROM #staging_campanias AS st
INNER JOIN Publicidad.CAMPANIA AS c ON c.nombre = st.nombre;
GO


/* ============================================================================
   REGISTRO DE LAS IMPORTACIONES (usp_RegistrarImportacion, usp_BorrarImportacion)
   ============================================================================ */

/* RI1 (OK) Se registran tres importaciones de prueba (dos del mismo origen) y
   se borran: una por su número y las otras dos por su origen.
   Esperado: las tres quedan registradas con sus totales y la fecha y hora
   actual; después de borrar la primera quedan dos, y después de borrar por
   origen, ninguna. */
IF @@TRANCOUNT = 0 BEGIN PRINT N'FALLÓ: se perdió la transacción del test.'; SET NOEXEC ON; END;

DECLARE @id1 INT, @id2 INT, @id3 INT;
EXEC DatosGenerales.usp_RegistrarImportacion @proceso = 'Prueba 66', @origen = N'C:\prueba66\uno.json',
     @leidos = 10, @insertados = 6, @actualizados = 1, @sin_cambios = 1, @rechazados = 2, @id_importacion = @id1 OUTPUT;
EXEC DatosGenerales.usp_RegistrarImportacion @proceso = 'Prueba 66', @origen = N'C:\prueba66\dos.json',
     @leidos = 5, @insertados = 0, @actualizados = 0, @sin_cambios = 4, @omitidos = 1, @rechazados = 0,
     @id_importacion = @id2 OUTPUT;
EXEC DatosGenerales.usp_RegistrarImportacion @proceso = 'Prueba 66', @origen = N'C:\prueba66\dos.json',
     @leidos = 5, @insertados = 0, @actualizados = 0, @sin_cambios = 5, @rechazados = 0, @id_importacion = @id3 OUTPUT;

SELECT 'RI1 registradas' AS caso, id_importacion - @id1 + 1 AS orden, proceso, origen, leidos, insertados, actualizados,
       sin_cambios, omitidos, rechazados, IIF(ABS(DATEDIFF(MINUTE, fecha_hora, SYSDATETIME())) <= 1, 'ahora', 'FALLÓ') AS fecha_hora
FROM DatosGenerales.IMPORTACION WHERE proceso = 'Prueba 66' ORDER BY id_importacion;

EXEC DatosGenerales.usp_BorrarImportacion @id_importacion = @id1;
SELECT 'RI1 después de borrar la primera' AS caso, COUNT(*) AS importaciones FROM DatosGenerales.IMPORTACION WHERE proceso = 'Prueba 66';

EXEC DatosGenerales.usp_BorrarImportacion @origen = N'C:\prueba66\dos.json';
SELECT 'RI1 después de borrar por origen' AS caso, COUNT(*) AS importaciones FROM DatosGenerales.IMPORTACION WHERE proceso = 'Prueba 66';
GO


-- Se deshace todo lo que cargó el test.
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
DROP TABLE IF EXISTS #staging_sedes, #staging_selecciones, #staging_jugadores, #staging_partidos, #staging_eventos,
                     #jugadores_prueba, #staging_arbitros, #staging_designaciones, #staging_indicadores,
                     #staging_cotizaciones, #staging_feriados, #staging_campanias, #staging_piezas;
GO


/* ============================================================================
   CASOS QUE HACEN FALLAR AL SP (fuera de la transacción del test)
   ============================================================================ */

/* ER1 (ERROR) Los SP de importación sin su tabla de staging.
   Esperado: once errores 50001, uno por SP, sin cargar nada. */
BEGIN TRY EXEC DatosGenerales.usp_ImportarIndicadoresEconomicos; PRINT N'ER1a: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1a', @error_esperado = 50001; END CATCH;
BEGIN TRY EXEC DatosGenerales.usp_ImportarCotizaciones; PRINT N'ER1b: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1b', @error_esperado = 50001; END CATCH;
BEGIN TRY EXEC DatosGenerales.usp_ImportarFeriados; PRINT N'ER1c: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1c', @error_esperado = 50001; END CATCH;
BEGIN TRY EXEC Torneo.usp_ImportarSedes; PRINT N'ER1d: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1d', @error_esperado = 50001; END CATCH;
BEGIN TRY EXEC Torneo.usp_ImportarSelecciones; PRINT N'ER1e: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1e', @error_esperado = 50001; END CATCH;
BEGIN TRY EXEC Torneo.usp_ImportarJugadores; PRINT N'ER1f: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1f', @error_esperado = 50001; END CATCH;
BEGIN TRY EXEC Torneo.usp_ImportarPartidos; PRINT N'ER1g: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1g', @error_esperado = 50001; END CATCH;
BEGIN TRY EXEC DesarrolloPartido.usp_ImportarDesarrolloPartidos; PRINT N'ER1h: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1h', @error_esperado = 50001; END CATCH;
BEGIN TRY EXEC Arbitraje.usp_ImportarArbitros; PRINT N'ER1i: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1i', @error_esperado = 50001; END CATCH;
BEGIN TRY EXEC Arbitraje.usp_ImportarDesignaciones; PRINT N'ER1j: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1j', @error_esperado = 50001; END CATCH;
BEGIN TRY EXEC Publicidad.usp_ImportarCampanias; PRINT N'ER1k: FALLÓ, se esperaba un error.'; END TRY
BEGIN CATCH EXEC #usp_MostrarError @caso = 'ER1k', @error_esperado = 50001; END CATCH;
GO


/* ER2 (ERROR) Una selección nueva sin fecha de presentación de su lista. Se
   hace en su propia transacción: el error del SP la deshace, con el país de
   prueba que crea el caso.
   Esperado: error 50001 ("la fecha de presentación es obligatoria"); no se
   crea la selección ni queda el país. */
SET XACT_ABORT OFF;
BEGIN TRANSACTION;
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XQA', @huso_horario = 'Argentina Standard Time', @codigo_fifa = 'XQA';

CREATE TABLE #staging_selecciones (
    id_registro         INT PRIMARY KEY,
    codigo_fifa         NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
    confederacion       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
    grupo               NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
    nombre_alternativo  NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
    errores             NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    accion              VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
);
INSERT INTO #staging_selecciones (id_registro, codigo_fifa, confederacion) VALUES (1, 'XQA', 'UEFA');

BEGIN TRY
    EXEC Torneo.usp_ImportarSelecciones;
    PRINT N'ER2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ER2', @error_esperado = 50001;
END CATCH;

-- El ROLLBACK también borra la tabla temporal, que se creó dentro de la transacción.
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #staging_selecciones;
GO


/* ER3 (ERROR) Registro de importaciones con datos inválidos:
     a) proceso y origen vacíos y totales negativos;
     b) más omitidos y rechazados que leídos;
     c) borrar sin indicar la importación ni el origen;
     d) borrar indicando las dos cosas.
   Esperado: cuatro errores 50001. */
BEGIN TRY
    EXEC DatosGenerales.usp_RegistrarImportacion @proceso = ' ', @origen = N'', @leidos = -1, @insertados = 0,
         @actualizados = 0, @sin_cambios = 0, @rechazados = 0;
    PRINT N'ER3a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ER3a', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_RegistrarImportacion @proceso = 'Prueba 66', @origen = N'C:\prueba66\tres.json', @leidos = 2,
         @insertados = 0, @actualizados = 0, @sin_cambios = 0, @omitidos = 2, @rechazados = 1;
    PRINT N'ER3b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ER3b', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_BorrarImportacion;
    PRINT N'ER3c: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ER3c', @error_esperado = 50001;
END CATCH;

BEGIN TRY
    EXEC DatosGenerales.usp_BorrarImportacion @id_importacion = 1, @origen = N'C:\prueba66\uno.json';
    PRINT N'ER3d: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ER3d', @error_esperado = 50001;
END CATCH;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas, y SELECCIONES_POR_GRUPO como estaba.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa LIKE 'XQ_')                    AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Importaci%66') AS sedes_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (221, 222, 226))              AS partidos_de_prueba,
       (SELECT COUNT(*) FROM Publicidad.ANUNCIANTE WHERE razon_social LIKE N'%66')                AS anunciantes_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.COTIZACION WHERE codigo_moneda IN ('XTS', 'XXX'))     AS cotizaciones_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.IMPORTACION WHERE proceso = 'Prueba 66')              AS importaciones_de_prueba,
       (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'SELECCIONES_POR_GRUPO') AS selecciones_por_grupo;
GO

SET NOEXEC OFF;
GO
