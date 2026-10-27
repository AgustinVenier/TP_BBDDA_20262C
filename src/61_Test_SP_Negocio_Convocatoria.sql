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
           Requiere haber ejecutado 00 a 20; no depende del juego de datos.
           Usa las selecciones de prueba de Prueba XCA y Prueba XCB (sin grupo),
           la sede "Estadio Prueba Convocatoria" y el partido de prueba 230, y
           los borra al empezar y al terminar, así que se puede ejecutar más
           de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
 Los países de prueba se llaman "Prueba <código>" y usan códigos FIFA que
 empiezan con X, que no tiene ningún miembro de la FIFA: así el test no choca
 con las selecciones reales que se importen.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Torneo.usp_RegistrarConvocatoria', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MIN_CONVOCADOS')
BEGIN
    RAISERROR(N'Faltan los SP de negocio o los datos iniciales: ejecutar los scripts 00 a 20.', 16, 1);
    SET NOEXEC ON;
END;
GO

IF OBJECT_ID(N'tempdb..#usp_MostrarError', N'P') IS NOT NULL
    DROP PROCEDURE #usp_MostrarError;
GO
CREATE PROCEDURE #usp_MostrarError
    @caso VARCHAR(10)
AS
BEGIN
    PRINT CONCAT(@caso, N': ',
                 IIF(ERROR_NUMBER() = 50001, N'OK, falló la validación como se esperaba.',
                     CONCAT(N'FALLÓ, error inesperado ', ERROR_NUMBER(), N'.')),
                 NCHAR(13), NCHAR(10), ERROR_MESSAGE(), NCHAR(13), NCHAR(10));
END;
GO

IF OBJECT_ID(N'tempdb..#usp_LimpiarPruebas', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPruebas;
GO
CREATE PROCEDURE #usp_LimpiarPruebas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT;

    SELECT @id = id_partido FROM Torneo.PARTIDO WHERE numero_partido = 230;
    IF @@ROWCOUNT > 0
        EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;

    DECLARE @pruebas TABLE (id_seleccion INT PRIMARY KEY);
    INSERT INTO @pruebas (id_seleccion)
    SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
    WHERE p.codigo_fifa IN ('XCA', 'XCB');

    WHILE EXISTS (SELECT 1 FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                  WHERE l.id_seleccion IN (SELECT id_seleccion FROM @pruebas))
    BEGIN
        SELECT TOP (1) @id = j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
        WHERE l.id_seleccion IN (SELECT id_seleccion FROM @pruebas);
        EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id, @eliminar_registro = 1;
    END;
    WHILE EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion IN (SELECT id_seleccion FROM @pruebas))
    BEGIN
        SELECT TOP (1) @id = id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion IN (SELECT id_seleccion FROM @pruebas);
        EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Baja @id_persona_ct = @id;
    END;
    WHILE EXISTS (SELECT 1 FROM Torneo.LISTA_CONVOCADOS WHERE id_seleccion IN (SELECT id_seleccion FROM @pruebas))
    BEGIN
        SELECT TOP (1) @id = id_lista FROM Torneo.LISTA_CONVOCADOS WHERE id_seleccion IN (SELECT id_seleccion FROM @pruebas);
        EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id;
    END;
    WHILE EXISTS (SELECT 1 FROM @pruebas)
    BEGIN
        SELECT TOP (1) @id = id_seleccion FROM @pruebas;
        EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id;
        DELETE FROM @pruebas WHERE id_seleccion = @id;
    END;

    SELECT @id = id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Convocatoria';
    IF @@ROWCOUNT > 0
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;

    WHILE EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XCA', 'XCB') AND nombre LIKE 'Prueba XC_')
    BEGIN
        SELECT TOP (1) @id = id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XCA', 'XCB') AND nombre LIKE 'Prueba XC_';
        EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    END;
END;
GO

EXEC #usp_LimpiarPruebas;
GO

-- Preparación: los países de prueba XCA y XCB ("Prueba XCA" y "Prueba XCB"), todavía sin selección.
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XCA', @huso_horario = 'UTC', @codigo_fifa = 'XCA';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XCB', @huso_horario = 'UTC', @codigo_fifa = 'XCB';
GO


/* ============================================================================
   usp_RegistrarSeleccion
   ============================================================================ */

/* SEL1 (OK) Alta de Prueba XCA con su lista y su director técnico.
   Esperado: la consulta del SP muestra la selección (CAF, sin grupo), su lista
   presentada el 01/06/2026 y el director técnico Kofi Prueba DT. */
DECLARE @xca SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XCA');
EXEC Torneo.usp_RegistrarSeleccion
    @id_pais = @xca, @confederacion = 'CAF', @grupo = NULL, @fecha_presentacion = '2026-06-01',
    @dt_nombre = N'Kofi', @dt_apellido = N'Prueba DT', @dt_fecha_nacimiento = '1972-07-12', @dt_id_pais_nacimiento = @xca;
GO

/* SEL2 (ERROR) Sin fecha de presentación ni director técnico.
   Esperado: error 50001 de usp_RegistrarSeleccion con 2 condiciones. */
DECLARE @xcb SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XCB');
BEGIN TRY
    EXEC Torneo.usp_RegistrarSeleccion @id_pais = @xcb, @confederacion = 'CAF', @grupo = NULL,
        @fecha_presentacion = NULL, @dt_nombre = N' ', @dt_apellido = NULL;
    PRINT N'SEL2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'SEL2';
END CATCH;
GO

/* SEL3 (ERROR) Falla el segundo paso: la transacción deshace el primero.
   La selección de Prueba XCB se da de alta, pero la lista falla porque
   la fecha de presentación es futura.
   Esperado: el error 50001 lo informa Torneo.usp_LISTA_CONVOCADOS_Alta, y
   Prueba XCB no queda registrada (0 selecciones). */
DECLARE @xcb SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XCB');
DECLARE @futura DATE = DATEADD(MONTH, 2, GETDATE());
BEGIN TRY
    EXEC Torneo.usp_RegistrarSeleccion @id_pais = @xcb, @confederacion = 'CAF', @grupo = NULL,
        @fecha_presentacion = @futura, @dt_nombre = N'Yao', @dt_apellido = N'Prueba DT', @mostrar = 0;
    PRINT N'SEL3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'SEL3';
END CATCH;
SELECT 'SEL3 después' AS caso, COUNT(*) AS selecciones_de_xcb FROM Torneo.SELECCION WHERE id_pais = @xcb;
GO


/* ============================================================================
   usp_RegistrarConvocatoria
   ============================================================================ */

/* CV1 (ERROR) Lista con todos los problemas posibles.
   22 jugadores con 2 arqueros, un dorsal repetido (21), un jugador repetido,
   una posición LIBERO y una fila sin dorsal.
   Esperado: error 50001 con 6 condiciones en un solo mensaje. Prueba XCA sigue
   sin jugadores. */
DECLARE @xca INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XCA');
DECLARE @lista Torneo.TT_CONVOCADO;
INSERT INTO @lista (nombre, apellido, posicion_habitual, dorsal)
SELECT N'Prueba', CONCAT(N'Prueba XCA ', d.dorsal), d.posicion, d.dorsal
FROM (VALUES (1, 'ARQUERO'), (12, 'ARQUERO'),
             (2, 'DEFENSOR'), (3, 'DEFENSOR'), (4, 'DEFENSOR'), (5, 'DEFENSOR'), (6, 'DEFENSOR'),
             (13, 'DEFENSOR'), (14, 'DEFENSOR'), (15, 'DEFENSOR'),
             (7, 'MEDIOCAMPISTA'), (8, 'MEDIOCAMPISTA'), (10, 'MEDIOCAMPISTA'), (16, 'MEDIOCAMPISTA'),
             (17, 'MEDIOCAMPISTA'), (18, 'MEDIOCAMPISTA'),
             (9, 'DELANTERO'), (11, 'DELANTERO'), (19, 'DELANTERO'), (20, 'DELANTERO'), (21, 'DELANTERO'),
             (22, 'DELANTERO')) AS d (dorsal, posicion);
UPDATE @lista SET dorsal = 21 WHERE dorsal = 22;                        -- dorsal repetido
UPDATE @lista SET apellido = N'Prueba XCA 19' WHERE dorsal = 20;             -- jugador repetido
UPDATE @lista SET posicion_habitual = 'LIBERO' WHERE dorsal = 18;       -- posición no válida
UPDATE @lista SET dorsal = NULL WHERE dorsal = 17;                      -- fila incompleta
BEGIN TRY
    EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = @xca, @jugadores = @lista;
    PRINT N'CV1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CV1';
END CATCH;
SELECT 'CV1 después' AS caso, COUNT(*) AS jugadores_de_ghana FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xca;
GO

/* CV2 (OK) Lista inicial válida de 23 jugadores.
   Esperado: la consulta del SP muestra 3 arqueros, 8 defensores, 6
   mediocampistas y 6 delanteros; todos dados de alta el 01/06/2026 con motivo
   "Lista inicial". */
DECLARE @xca INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XCA');
DECLARE @lista Torneo.TT_CONVOCADO;
INSERT INTO @lista (nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento, club_origen)
SELECT N'Prueba', CONCAT(N'Prueba XCA ', d.dorsal), d.posicion, d.dorsal, DATEADD(DAY, d.dorsal * 211, '1995-01-01'), N'Hearts of Oak'
FROM (VALUES (1, 'ARQUERO'), (12, 'ARQUERO'), (23, 'ARQUERO'),
             (2, 'DEFENSOR'), (3, 'DEFENSOR'), (4, 'DEFENSOR'), (5, 'DEFENSOR'), (6, 'DEFENSOR'),
             (13, 'DEFENSOR'), (14, 'DEFENSOR'), (15, 'DEFENSOR'),
             (7, 'MEDIOCAMPISTA'), (8, 'MEDIOCAMPISTA'), (10, 'MEDIOCAMPISTA'), (16, 'MEDIOCAMPISTA'),
             (17, 'MEDIOCAMPISTA'), (18, 'MEDIOCAMPISTA'),
             (9, 'DELANTERO'), (11, 'DELANTERO'), (19, 'DELANTERO'), (20, 'DELANTERO'), (21, 'DELANTERO'),
             (22, 'DELANTERO')) AS d (dorsal, posicion);
EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = @xca, @jugadores = @lista;
SELECT 'CV2 después' AS caso, COUNT(*) AS jugadores, MIN(j.fecha_alta) AS fecha_alta, MIN(j.motivo_alta) AS motivo_alta
FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xca;
GO

/* CV3 (ERROR) Segunda convocatoria, con más jugadores que el máximo.
   Esperado: error 50001 con 2 condiciones: la lista ya tiene jugadores (los
   cambios son reemplazos) y 27 jugadores superan el máximo de 26. */
DECLARE @xca INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XCA');
DECLARE @lista Torneo.TT_CONVOCADO;
INSERT INTO @lista (nombre, apellido, posicion_habitual, dorsal)
SELECT TOP (27) N'Otro', CONCAT(N'Jugador ', ROW_NUMBER() OVER (ORDER BY object_id)), IIF(ROW_NUMBER() OVER (ORDER BY object_id) <= 3, 'ARQUERO', 'DEFENSOR'),
       ROW_NUMBER() OVER (ORDER BY object_id)
FROM sys.objects;
BEGIN TRY
    EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = @xca, @jugadores = @lista;
    PRINT N'CV3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CV3';
END CATCH;
GO


/* ============================================================================
   usp_ReemplazarJugador
   ============================================================================ */

/* RJ1 (OK) Reemplazo por lesión antes del primer partido.
   Esperado: el dorsal 9 original queda dado de baja el 05/06/2026 con su
   motivo, y el reemplazante entra ese día con el mismo dorsal 9 y el motivo
   "Reemplazo de Prueba XCA 9, Prueba: ...". */
DECLARE @xca INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XCA');
DECLARE @j9 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                   WHERE l.id_seleccion = @xca AND j.dorsal = 9 AND j.fecha_baja IS NULL);
EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @j9, @motivo = 'Fractura de clavícula', @fecha_cambio = '2026-06-05',
    @nombre = N'Kwame', @apellido = N'Prueba Reemplazo', @posicion_habitual = 'DELANTERO';
GO

/* RJ2 (ERROR) Reemplazo de un jugador dado de baja y sin motivo.
   Esperado: error 50001 con 2 condiciones: el jugador ya estaba dado de baja
   y el motivo del cambio es obligatorio. */
DECLARE @j9 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba XCA 9');
BEGIN TRY
    EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @j9, @motivo = ' ', @fecha_cambio = '2026-06-06',
        @nombre = N'Otro', @apellido = N'Prueba', @posicion_habitual = 'DELANTERO';
    PRINT N'RJ2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RJ2';
END CATCH;
GO

/* RJ3 (ERROR) Falla el alta del reemplazante: la transacción deshace la baja.
   El reemplazante tiene el mismo nombre que otro convocado.
   Esperado: el error 50001 lo informa Torneo.usp_JUGADOR_Alta; el dorsal 5
   sigue activo (sin fecha de baja). */
DECLARE @j5 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba XCA 5');
BEGIN TRY
    EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @j5, @motivo = 'Lesión muscular', @fecha_cambio = '2026-06-10',
        @nombre = N'Prueba', @apellido = N'Prueba XCA 6', @posicion_habitual = 'DEFENSOR', @mostrar = 0;
    PRINT N'RJ3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RJ3';
END CATCH;
SELECT 'RJ3 después' AS caso, dorsal, apellido, fecha_baja, motivo_baja FROM Torneo.JUGADOR WHERE id_jugador = @j5;
GO

-- Partido de prueba 230: primer partido de Prueba XCA, el 25/08/2026, contra
-- Prueba XCB (que se da de alta acá, sin lista) en la sede "Estadio Prueba Convocatoria".
DECLARE @usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @xcb_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XCB');
DECLARE @xca INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XCA');
DECLARE @sede INT, @xcb INT;
EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Convocatoria', @ciudad = 'Kansas City', @id_pais = @usa,
    @capacidad = 76000, @huso_horario = 'Central Standard Time', @id_sede = @sede OUTPUT;
EXEC Torneo.usp_SELECCION_Alta @id_pais = @xcb_pais, @confederacion = 'CAF', @grupo = NULL, @id_seleccion = @xcb OUTPUT;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 230, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2026-08-25 20:00',
    @id_seleccion_local = @xca, @id_seleccion_visitante = @xcb;
GO

/* RJ4 (ERROR) Reemplazo de un jugador de campo después del primer partido.
   Esperado: error 50001 con 1 condición: la selección ya jugó su primer
   partido (25/08/2026) y desde entonces solo se puede reemplazar a un arquero. */
DECLARE @j2 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba XCA 2');
BEGIN TRY
    EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @j2, @motivo = 'Lesión', @fecha_cambio = '2026-08-26',
        @nombre = N'Nuevo', @apellido = N'Prueba Defensor', @posicion_habitual = 'DEFENSOR';
    PRINT N'RJ4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RJ4';
END CATCH;
GO

/* RJ5 (ERROR) Reemplazo de un arquero por un jugador de campo después del primer partido.
   Esperado: error 50001 con 1 condición: un arquero reemplazado después del
   primer partido se reemplaza por otro arquero. */
DECLARE @j23 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba XCA 23');
BEGIN TRY
    EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @j23, @motivo = 'Lesión en la mano', @fecha_cambio = '2026-08-26',
        @nombre = N'Nuevo', @apellido = N'Prueba Delantero', @posicion_habitual = 'DELANTERO';
    PRINT N'RJ5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RJ5';
END CATCH;
GO

/* RJ6 (OK) Reemplazo de un arquero lesionado después del primer partido.
   Esperado: el dorsal 23 queda dado de baja el 26/08/2026 y entra otro
   arquero con el dorsal 23. */
DECLARE @j23 INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba XCA 23');
EXEC Torneo.usp_ReemplazarJugador @id_jugador_baja = @j23, @motivo = 'Fractura en la mano', @fecha_cambio = '2026-08-26',
    @nombre = N'Richard', @apellido = N'Prueba Arquero', @posicion_habitual = 'ARQUERO';
GO

-- Evidencia: altas y bajas de último momento de la lista de Prueba XCA.
DECLARE @xca INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XCA');
SELECT 'Altas y bajas' AS caso, j.dorsal, j.apellido, j.nombre, j.posicion_habitual, j.fecha_alta, j.motivo_alta, j.fecha_baja, j.motivo_baja
FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
WHERE l.id_seleccion = @xca AND (j.fecha_baja IS NOT NULL OR j.motivo_alta <> 'Lista inicial')
ORDER BY j.dorsal, j.fecha_alta;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('XCA', 'XCB'))                                AS selecciones_de_prueba,
       (SELECT COUNT(*) FROM Torneo.JUGADOR WHERE apellido LIKE N'Prueba XCA%' OR apellido LIKE N'Prueba%') AS jugadores_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido = 230)        AS partidos_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Convocatoria') AS sedes_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XCA', 'XCB') AND nombre LIKE 'Prueba XC_') AS paises_de_prueba;
GO

SET NOEXEC OFF;
GO
