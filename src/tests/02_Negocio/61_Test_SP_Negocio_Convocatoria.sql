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
 Archivo: 61_Test_SP_Negocio_Convocatoria.sql
 Objetivo: Probar los SP de 11_SP_Negocio_Convocatoria.sql
           (usp_RegistrarSeleccion, usp_RegistrarConvocatoria y
           usp_ReemplazarJugador), con casos exitosos y su evidencia, casos
           que no cumplen las validaciones y casos en que falla un paso
           intermedio y la transacción deshace los anteriores.
           Requiere haber ejecutado 01 a 28; no depende del juego de datos.
           Cada caso arma sus propios datos con INSERT directos a las tablas
           (los países Argentina1 y Brasil1, la selección, su lista, el
           plantel, la sede "Arrowhead Stadium1" y el partido 230) y los
           deshace al terminar, así que se puede ejecutar más de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso")
     o la consulta que devuelve el SP.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.

 Cada caso corre en su propia transacción (BEGIN TRANSACTION ... ROLLBACK)
 y en un solo lote: estos SP usan SET XACT_ABORT ON, así que un error deja
 la transacción sin poder confirmarse y SQL Server la deshace al terminar el
 lote. Por eso no hay una sola transacción para todo el test.
 SEL3 y RJ3 son la excepción: prueban que el SP deshaga su propia
 transacción, y el SP solo abre la suya si no hay otra abierta. Corren sin
 transacción del test y borran sus datos con DELETE al final.
 Los países de prueba se llaman como uno real con un 1 al final: así no
 chocan con las selecciones reales que se importen.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Torneo.usp_RegistrarConvocatoria', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_CONVOCADOS')
BEGIN
    RAISERROR(N'Faltan los SP de negocio o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Plantel de 23 jugadores de Argentina1 que usan los casos: 3 arqueros,
-- 8 defensores, 6 mediocampistas y 6 delanteros. Es una tabla temporal, no
-- una tabla de la base: la transacción de cada caso no la borra.
DROP TABLE IF EXISTS #plantel_argentina;
CREATE TABLE #plantel_argentina (
    dorsal            TINYINT,
    nombre            NVARCHAR(60),
    apellido          NVARCHAR(60),
    posicion          VARCHAR(15),
    fecha_nacimiento  DATE,
    club_origen       NVARCHAR(100)
);
INSERT INTO #plantel_argentina (dorsal, nombre, apellido, posicion, fecha_nacimiento, club_origen) VALUES
    ( 1, N'Emiliano',  N'Martínez',  'ARQUERO',       '1992-09-02', N'Aston Villa'),
    (12, N'Gerónimo',  N'Rulli',     'ARQUERO',       '1992-05-20', N'Olympique de Marsella'),
    (23, N'Walter',    N'Benítez',   'ARQUERO',       '1993-01-19', N'Crystal Palace'),
    ( 2, N'Juan',      N'Foyth',     'DEFENSOR',      '1998-01-12', N'Villarreal'),
    ( 3, N'Nicolás',   N'Tagliafico','DEFENSOR',      '1992-08-31', N'Olympique de Lyon'),
    ( 4, N'Gonzalo',   N'Montiel',   'DEFENSOR',      '1997-01-01', N'River Plate'),
    ( 5, N'Leonardo',  N'Balerdi',   'DEFENSOR',      '1999-01-26', N'Olympique de Marsella'),
    ( 6, N'Germán',    N'Pezzella',  'DEFENSOR',      '1991-06-27', N'River Plate'),
    (13, N'Cristian',  N'Romero',    'DEFENSOR',      '1998-04-27', N'Tottenham Hotspur'),
    (14, N'Lisandro',  N'Martínez',  'DEFENSOR',      '1998-01-18', N'Manchester United'),
    (15, N'Nicolás',   N'Otamendi',  'DEFENSOR',      '1988-02-12', N'Benfica'),
    ( 7, N'Rodrigo',   N'De Paul',   'MEDIOCAMPISTA', '1994-05-24', N'Inter Miami'),
    ( 8, N'Enzo',      N'Fernández', 'MEDIOCAMPISTA', '2001-01-17', N'Chelsea'),
    (10, N'Lionel',    N'Messi',     'MEDIOCAMPISTA', '1987-06-24', N'Inter Miami'),
    (16, N'Thiago',    N'Almada',    'MEDIOCAMPISTA', '2001-04-26', N'Atlético de Madrid'),
    (17, N'Leandro',   N'Paredes',   'MEDIOCAMPISTA', '1994-06-29', N'Boca Juniors'),
    (18, N'Alexis',    N'Mac Allister','MEDIOCAMPISTA','1998-12-24', N'Liverpool'),
    ( 9, N'Julián',    N'Álvarez',   'DELANTERO',     '2000-01-31', N'Atlético de Madrid'),
    (11, N'Ángel',     N'Di María',  'DELANTERO',     '1988-02-14', N'Rosario Central'),
    (19, N'Nicolás',   N'González',  'DELANTERO',     '1998-04-06', N'Juventus'),
    (20, N'Giuliano',  N'Simeone',   'DELANTERO',     '2002-12-18', N'Atlético de Madrid'),
    (21, N'Paulo',     N'Dybala',    'DELANTERO',     '1993-11-15', N'Roma'),
    (22, N'Lautaro',   N'Martínez',  'DELANTERO',     '1997-08-22', N'Inter de Milán');
GO


/* ============================================================================
   usp_RegistrarSeleccion
   ============================================================================ */

/* SEL1 (OK) Alta de Argentina1 con su lista y su director técnico.
   Preparación: el país Argentina1, todavía sin selección.
   Esperado: la consulta del SP muestra la selección (CONMEBOL, sin grupo), su
   lista presentada el 01/06/2026 y el director técnico Scaloni, Lionel. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();

EXEC Torneo.usp_RegistrarSeleccion
    @id_pais = @id_pais_arg, @confederacion = 'CONMEBOL', @grupo = NULL, @fecha_presentacion = '2026-06-01',
    @dt_nombre = N'Lionel', @dt_apellido = N'Scaloni', @dt_fecha_nacimiento = '1978-05-16', @dt_id_pais_nacimiento = @id_pais_arg;
ROLLBACK TRANSACTION;
GO

/* SEL2 (ERROR) Sin fecha de presentación ni director técnico.
   Preparación: el país Argentina1, todavía sin selección.
   Esperado: error 50001 de usp_RegistrarSeleccion con 2 condiciones. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();

BEGIN TRY
    EXEC Torneo.usp_RegistrarSeleccion @id_pais = @id_pais_arg, @confederacion = 'CONMEBOL', @grupo = NULL,
        @fecha_presentacion = NULL, @dt_nombre = N' ', @dt_apellido = NULL;
    PRINT N'SEL2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SEL2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SEL2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* SEL3 (ERROR) Falla el segundo paso: la transacción deshace el primero.
   La selección de Brasil1 se da de alta, pero la lista falla porque la
   fecha de presentación es futura.
   Sin transacción del test (ver el encabezado): el país se borra al final.
   Esperado: el error 50001 lo informa Torneo.usp_LISTA_CONVOCADOS_Alta, y
   Brasil1 no queda registrada (0 selecciones). */
DECLARE @id_pais_bra SMALLINT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();

DECLARE @futura DATE = DATEADD(MONTH, 2, GETDATE());
BEGIN TRY
    EXEC Torneo.usp_RegistrarSeleccion @id_pais = @id_pais_bra, @confederacion = 'CONMEBOL', @grupo = NULL,
        @fecha_presentacion = @futura, @dt_nombre = N'Carlo', @dt_apellido = N'Ancelotti', @mostrar_resultados = 0;
    PRINT N'SEL3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'SEL3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'SEL3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'SEL3 después' AS caso, COUNT(*) AS selecciones_de_brasil1 FROM Torneo.SELECCION WHERE id_pais = @id_pais_bra;

DELETE FROM DatosGenerales.PAIS WHERE id_pais = @id_pais_bra;
GO


/* ============================================================================
   usp_RegistrarConvocatoria
   ============================================================================ */

/* CV1 (ERROR) Lista con todos los problemas posibles.
   Preparación: Argentina1 con su selección y su lista vacía.
   El plantel sin el dorsal 23 (22 jugadores y 2 arqueros), con un dorsal
   repetido (21), un jugador repetido (Nicolás González), una posición
   LIBERO y una fila sin dorsal.
   Esperado: error 50001 con 6 condiciones en un solo mensaje. Argentina1
   sigue sin jugadores. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_seleccion_arg INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_arg, 'CONMEBOL', NULL);
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');

DECLARE @lista Torneo.TT_CONVOCADO;
INSERT INTO @lista (nombre, apellido, posicion_habitual, dorsal)
SELECT nombre, apellido, posicion, dorsal FROM #plantel_argentina WHERE dorsal <> 23;
UPDATE @lista SET dorsal = 21 WHERE dorsal = 22;                                      -- dorsal repetido
UPDATE @lista SET nombre = N'Nicolás', apellido = N'González' WHERE dorsal = 20;      -- jugador repetido
UPDATE @lista SET posicion_habitual = 'LIBERO' WHERE dorsal = 18;                     -- posición no válida
UPDATE @lista SET dorsal = NULL WHERE dorsal = 17;                                    -- fila incompleta
BEGIN TRY
    EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = @id_seleccion_arg, @jugadores = @lista;
    PRINT N'CV1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CV1: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CV1: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'CV1 después' AS caso, COUNT(*) AS jugadores_de_argentina1 FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_arg;
ROLLBACK TRANSACTION;
GO

/* CV2 (ERROR) Lista completa con datos que el alta de jugador no acepta.
   Preparación: Argentina1 con su selección y su lista vacía.
   El plantel de 23 jugadores con 3 arqueros, pero con un dorsal 100, una
   fecha de nacimiento futura y un país de nacimiento inexistente (id 32767).
   Esperado: error 50001 con 3 condiciones en un solo mensaje. Argentina1
   sigue sin jugadores (no entra ninguno de los 20 jugadores correctos). */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_seleccion_arg INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_arg, 'CONMEBOL', NULL);
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');

DECLARE @lista Torneo.TT_CONVOCADO;
INSERT INTO @lista (nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento)
SELECT nombre, apellido, posicion, dorsal, fecha_nacimiento FROM #plantel_argentina;
UPDATE @lista SET dorsal = 100 WHERE dorsal = 22;                                    -- dorsal fuera de rango
UPDATE @lista SET fecha_nacimiento = DATEADD(YEAR, 1, GETDATE()) WHERE dorsal = 21;  -- nacimiento futuro
UPDATE @lista SET id_pais_nacimiento = 32767 WHERE dorsal = 20;                      -- país inexistente
BEGIN TRY
    EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = @id_seleccion_arg, @jugadores = @lista;
    PRINT N'CV2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CV2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CV2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'CV2 después' AS caso, COUNT(*) AS jugadores_de_argentina1 FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_arg;
ROLLBACK TRANSACTION;
GO

/* CV3 (OK) Lista inicial válida de 23 jugadores.
   Preparación: Argentina1 con su selección y su lista vacía.
   Esperado: la consulta del SP muestra 3 arqueros, 8 defensores, 6
   mediocampistas y 6 delanteros; todos dados de alta el 01/06/2026 con motivo
   "Lista inicial". */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_seleccion_arg INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_arg, 'CONMEBOL', NULL);
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');

DECLARE @lista Torneo.TT_CONVOCADO;
INSERT INTO @lista (nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento, club_origen)
SELECT nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen FROM #plantel_argentina;
EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = @id_seleccion_arg, @jugadores = @lista;
SELECT 'CV3 después' AS caso, COUNT(*) AS jugadores, MIN(j.fecha_alta) AS fecha_alta, MIN(j.motivo_alta) AS motivo_alta
FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_seleccion_arg;
ROLLBACK TRANSACTION;
GO

/* CV4 (ERROR) Segunda convocatoria, con más jugadores que el máximo.
   Preparación: Argentina1 con su lista y un jugador ya cargado (Messi).
   Esperado: error 50001 con 2 condiciones: la lista ya tiene jugadores (los
   cambios son reemplazos) y 27 jugadores superan el máximo de 26. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_seleccion_arg INT, @id_lista INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_arg, 'CONMEBOL', NULL);
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @id_lista = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_alta, motivo_alta)
VALUES (@id_lista, N'Lionel', N'Messi', 'MEDIOCAMPISTA', 10, '2026-06-01', 'Lista inicial');

-- 27 jugadores: el plantel de 23 más 4.
DECLARE @lista Torneo.TT_CONVOCADO;
INSERT INTO @lista (nombre, apellido, posicion_habitual, dorsal)
SELECT nombre, apellido, posicion, dorsal FROM #plantel_argentina;
INSERT INTO @lista (nombre, apellido, posicion_habitual, dorsal) VALUES
    (N'Franco',   N'Armani',    'ARQUERO',       24),
    (N'Marcos',   N'Acuña',     'DEFENSOR',      25),
    (N'Exequiel', N'Palacios',  'MEDIOCAMPISTA', 26),
    (N'Ángel',    N'Correa',    'DELANTERO',     27);
BEGIN TRY
    EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = @id_seleccion_arg, @jugadores = @lista;
    PRINT N'CV4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CV4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CV4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   usp_ReemplazarJugador
   La preparación de estos casos es Argentina1 con su lista del 01/06/2026 y
   el plantel de 23 jugadores ya cargado.
   ============================================================================ */

/* RJ1 (OK) Reemplazo por lesión antes del primer partido.
   Esperado: Julián Álvarez (dorsal 9) queda dado de baja el 05/06/2026 con
   su motivo, y Valentín Castellanos entra ese día con el mismo dorsal 9 y el
   motivo "Reemplazo de Álvarez, Julián: Fractura de clavícula". */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_seleccion_arg INT, @id_lista INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_arg, 'CONMEBOL', NULL);
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @id_lista = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento, club_origen, fecha_alta, motivo_alta)
SELECT @id_lista, nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen, '2026-06-01', 'Lista inicial'
FROM #plantel_argentina;

DECLARE @id_jugador_dorsal_9 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND dorsal = 9);
EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @id_jugador_dorsal_9, @motivo = 'Fractura de clavícula', @fecha_cambio = '2026-06-05',
    @nombre = N'Valentín', @apellido = N'Castellanos', @posicion_habitual = 'DELANTERO';
ROLLBACK TRANSACTION;
GO

/* RJ2 (ERROR) Reemplazo de un jugador dado de baja y sin motivo.
   Preparación: además, Julián Álvarez ya dado de baja el 05/06/2026.
   Esperado: error 50001 con 2 condiciones: el jugador ya estaba dado de baja
   y el motivo del cambio es obligatorio. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_seleccion_arg INT, @id_lista INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_arg, 'CONMEBOL', NULL);
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @id_lista = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento, club_origen, fecha_alta, motivo_alta)
SELECT @id_lista, nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen, '2026-06-01', 'Lista inicial'
FROM #plantel_argentina;
UPDATE Torneo.JUGADOR SET fecha_baja = '2026-06-05', motivo_baja = 'Fractura de clavícula'
WHERE id_lista = @id_lista AND dorsal = 9;

DECLARE @id_jugador_dorsal_9 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND dorsal = 9);
BEGIN TRY
    EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @id_jugador_dorsal_9, @motivo = ' ', @fecha_cambio = '2026-06-06',
        @nombre = N'Valentín', @apellido = N'Castellanos', @posicion_habitual = 'DELANTERO';
    PRINT N'RJ2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RJ2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RJ2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* RJ3 (ERROR) Falla el alta del reemplazante: la transacción deshace la baja.
   El reemplazante de Leonardo Balerdi (dorsal 5) se llama igual que otro
   convocado (Germán Pezzella).
   Sin transacción del test (ver el encabezado): los datos se borran al final.
   Esperado: el error 50001 lo informa Torneo.usp_JUGADOR_Alta; el dorsal 5
   sigue activo (sin fecha de baja). */
DECLARE @id_pais_arg SMALLINT, @id_seleccion_arg INT, @id_lista INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_arg, 'CONMEBOL', NULL);
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @id_lista = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento, club_origen, fecha_alta, motivo_alta)
SELECT @id_lista, nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen, '2026-06-01', 'Lista inicial'
FROM #plantel_argentina;

DECLARE @id_jugador_dorsal_5 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND dorsal = 5);
BEGIN TRY
    EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @id_jugador_dorsal_5, @motivo = 'Lesión muscular', @fecha_cambio = '2026-06-10',
        @nombre = N'Germán', @apellido = N'Pezzella', @posicion_habitual = 'DEFENSOR', @mostrar_resultados = 0;
    PRINT N'RJ3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RJ3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RJ3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'RJ3 después' AS caso, dorsal, apellido, fecha_baja, motivo_baja FROM Torneo.JUGADOR WHERE id_jugador = @id_jugador_dorsal_5;

DELETE FROM Torneo.JUGADOR WHERE id_lista = @id_lista;
DELETE FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id_lista;
DELETE FROM Torneo.SELECCION WHERE id_seleccion = @id_seleccion_arg;
DELETE FROM DatosGenerales.PAIS WHERE id_pais = @id_pais_arg;
GO

/* RJ4 (ERROR) Reemplazo de un jugador de campo después del primer partido.
   Preparación: además, el partido 230, Argentina1 - Brasil1, el 16/06/2026
   en "Arrowhead Stadium1".
   Esperado: error 50001 con 1 condición: la selección ya jugó su primer
   partido (16/06/2026) y desde entonces solo se puede reemplazar a un arquero. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @id_lista INT, @sede INT;
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_arg, 'CONMEBOL', NULL);
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_bra, 'CONMEBOL', NULL);
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @id_lista = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento, club_origen, fecha_alta, motivo_alta)
SELECT @id_lista, nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen, '2026-06-01', 'Lista inicial'
FROM #plantel_argentina;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Arrowhead Stadium1', 'Kansas City', @id_pais_usa, 76000, 'Central Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (230, @sede, 'GRUPOS', '2026-06-16 15:00', '2026-06-16 20:00', @id_seleccion_arg, @id_seleccion_bra);

DECLARE @id_jugador_dorsal_2 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND dorsal = 2);
BEGIN TRY
    EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @id_jugador_dorsal_2, @motivo = 'Lesión', @fecha_cambio = '2026-06-17',
        @nombre = N'Marcos', @apellido = N'Acuña', @posicion_habitual = 'DEFENSOR';
    PRINT N'RJ4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RJ4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RJ4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* RJ5 (ERROR) Reemplazo de un arquero por un jugador de campo después del primer partido.
   Preparación: la misma de RJ4.
   Esperado: error 50001 con 1 condición: un arquero reemplazado después del
   primer partido se reemplaza por otro arquero. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @id_lista INT, @sede INT;
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_arg, 'CONMEBOL', NULL);
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_bra, 'CONMEBOL', NULL);
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @id_lista = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento, club_origen, fecha_alta, motivo_alta)
SELECT @id_lista, nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen, '2026-06-01', 'Lista inicial'
FROM #plantel_argentina;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Arrowhead Stadium1', 'Kansas City', @id_pais_usa, 76000, 'Central Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (230, @sede, 'GRUPOS', '2026-06-16 15:00', '2026-06-16 20:00', @id_seleccion_arg, @id_seleccion_bra);

DECLARE @id_jugador_dorsal_23 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND dorsal = 23);
BEGIN TRY
    EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @id_jugador_dorsal_23, @motivo = 'Lesión en la mano', @fecha_cambio = '2026-06-17',
        @nombre = N'Ángel', @apellido = N'Correa', @posicion_habitual = 'DELANTERO';
    PRINT N'RJ5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'RJ5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'RJ5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
GO

/* RJ6 (OK) Reemplazo de un arquero lesionado después del primer partido.
   Preparación: la misma de RJ4.
   Esperado: Walter Benítez (dorsal 23) queda dado de baja el 17/06/2026 y
   entra Franco Armani, arquero, con el dorsal 23. */
BEGIN TRANSACTION;
DECLARE @id_pais_arg SMALLINT, @id_pais_bra SMALLINT, @id_seleccion_arg INT, @id_seleccion_bra INT, @id_lista INT, @sede INT;
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Argentina1', 'Argentina Standard Time');
SET @id_pais_arg = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Brasil1', 'E. South America Standard Time');
SET @id_pais_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_arg, 'CONMEBOL', NULL);
SET @id_seleccion_arg = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais_bra, 'CONMEBOL', NULL);
SET @id_seleccion_bra = SCOPE_IDENTITY();
INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion_arg, '2026-06-01');
SET @id_lista = SCOPE_IDENTITY();
INSERT INTO Torneo.JUGADOR (id_lista, nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento, club_origen, fecha_alta, motivo_alta)
SELECT @id_lista, nombre, apellido, posicion, dorsal, fecha_nacimiento, club_origen, '2026-06-01', 'Lista inicial'
FROM #plantel_argentina;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Arrowhead Stadium1', 'Kansas City', @id_pais_usa, 76000, 'Central Standard Time');
SET @sede = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc, id_seleccion_local, id_seleccion_visitante)
VALUES (230, @sede, 'GRUPOS', '2026-06-16 15:00', '2026-06-16 20:00', @id_seleccion_arg, @id_seleccion_bra);

DECLARE @id_jugador_dorsal_23 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND dorsal = 23);
EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @id_jugador_dorsal_23, @motivo = 'Fractura en la mano', @fecha_cambio = '2026-06-17',
    @nombre = N'Franco', @apellido = N'Armani', @posicion_habitual = 'ARQUERO';
ROLLBACK TRANSACTION;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE nombre IN ('Argentina1', 'Brasil1')) AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido = 230)                     AS partidos_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Arrowhead Stadium1')       AS sedes_de_prueba,
       @@TRANCOUNT                                                                          AS transacciones_abiertas;
GO

SET NOEXEC OFF;
GO
