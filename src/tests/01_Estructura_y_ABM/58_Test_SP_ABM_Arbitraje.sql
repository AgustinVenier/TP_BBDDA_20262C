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
 Archivo: 58_Test_SP_ABM_Arbitraje.sql
 Objetivo: Probar los SP de 08_SP_ABM_Arbitraje.sql (ARBITRO, ARBITRO_IDIOMA y
           DESIGNACION_ARBITRAL), con casos exitosos y su evidencia y casos
           que no cumplen las validaciones, entre ellos el conflicto de
           nacionalidad. Requiere haber ejecutado 01 a 28; no depende del juego de
           datos.
           Usa sus propios datos de prueba, cargados con INSERT directos a las
           tablas: los países Argentina1, Brasil1, Francia1 e Inglaterra1 con
           su selección, las sedes "BC Place1" y "Lumen Field1", dos partidos
           (215, Argentina1 - Brasil1, y 216, Francia1 - Inglaterra1, 18 horas
           después), dos árbitros de Ghana (Kwame Mensah, que se da de alta en
           AR1, y Kofi Owusu) y un árbitro de Argentina1 (Facundo Tello1, para
           el conflicto de nacionalidad). Corre dentro de una transacción que
           se deshace al final, así que no deja datos y se puede ejecutar más
           de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba. Si no da
     0, quedó algo sin deshacer.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Arbitraje.usp_DESIGNACION_ARBITRAL_Alta', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE codigo_iso IN ('en', 'fr') HAVING COUNT(*) = 2)
BEGIN
    RAISERROR(N'Faltan los SP o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Todo el test corre en una transacción que se deshace al final: no deja datos de prueba.
-- Se puede porque los SP de ABM no usan XACT_ABORT: un error de validación no
-- arruina la transacción.
BEGIN TRANSACTION;
GO

-- Preparación, con INSERT directos (no se usan los SP de otros scripts):
-- cuatro países con su selección, dos sedes, los partidos 215 (Argentina1 -
-- Brasil1) y, 18 horas después, 216 (Francia1 - Inglaterra1), el árbitro
-- Facundo Tello1, de Argentina1 (para el conflicto de nacionalidad), y el
-- árbitro Kofi Owusu, de Ghana, sin designaciones (para D4 y D11).
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES
    ('Argentina1',  'Argentina Standard Time'),
    ('Brasil1',     'E. South America Standard Time'),
    ('Francia1',    'Romance Standard Time'),
    ('Inglaterra1', 'GMT Standard Time');

INSERT INTO Torneo.SELECCION (id_pais, confederacion)
SELECT id_pais, 'CONMEBOL' FROM DatosGenerales.PAIS WHERE nombre IN ('Argentina1', 'Brasil1');
INSERT INTO Torneo.SELECCION (id_pais, confederacion)
SELECT id_pais, 'UEFA' FROM DatosGenerales.PAIS WHERE nombre IN ('Francia1', 'Inglaterra1');

DECLARE @id_pais_can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario) VALUES
    ('BC Place1',    'Vancouver', @id_pais_can, 54000, 'Pacific Standard Time'),
    ('Lumen Field1', 'Seattle',   @id_pais_usa, 68000, 'Pacific Standard Time');

DECLARE @id_seleccion_arg INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais WHERE pa.nombre = 'Argentina1');
DECLARE @id_seleccion_bra INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais WHERE pa.nombre = 'Brasil1');
DECLARE @id_seleccion_fra INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais WHERE pa.nombre = 'Francia1');
DECLARE @id_seleccion_ing INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais WHERE pa.nombre = 'Inglaterra1');
DECLARE @sede1 INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'BC Place1');
DECLARE @sede2 INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Lumen Field1');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante) VALUES
    (215, @sede1, 'OCTAVOS', '2026-08-11 19:00', '2026-08-12 02:00', @id_seleccion_arg, @id_seleccion_bra),
    (216, @sede2, 'OCTAVOS', '2026-08-12 13:00', '2026-08-12 20:00', @id_seleccion_fra, @id_seleccion_ing);

DECLARE @id_pais_arg SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Argentina1');
DECLARE @id_pais_gha      SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'GHA');
INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, categoria) VALUES
    (@id_pais_arg, N'Facundo', N'Tello1', 'FIFA'),
    (@id_pais_gha,      N'Kofi',    N'Owusu',  'FIFA');

SELECT 'Preparación' AS caso, numero_partido, seleccion_local, seleccion_visitante, nombre_estadio, fecha_hora_utc, estado
FROM Torneo.vw_Fixture WHERE numero_partido IN (215, 216) ORDER BY numero_partido;
GO


/* ============================================================================
   ARBITRO
   ============================================================================ */

/* AR1 (OK) Alta de un árbitro.
   Esperado: 0 árbitros Kwame Mensah antes y 1 después, con categoría FIFA y activo. */
DECLARE @id_pais_gha SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'GHA');
DECLARE @id_arbitro INT;
SELECT 'AR1 antes' AS caso, COUNT(*) AS arbitros_kwame_mensah FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah';
EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais_gha, @nombre = N'Kwame', @apellido = N'Mensah',
    @categoria = 'fifa', @fecha_nacimiento = '1988-03-03', @id_arbitro = @id_arbitro OUTPUT;
SELECT 'AR1 después' AS caso, id_arbitro, apellido, nombre, categoria, fecha_nacimiento, activo FROM Arbitraje.ARBITRO WHERE id_arbitro = @id_arbitro;
GO

/* AR2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 4 condiciones: no existe el país -1, el nombre
   es obligatorio, la categoría NACIONAL no es válida y la fecha de
   nacimiento es futura. */
DECLARE @futura DATE = DATEADD(YEAR, 1, GETDATE());
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = -1, @nombre = N'', @apellido = N'Sin Nombre',
        @categoria = 'NACIONAL', @fecha_nacimiento = @futura;
    PRINT N'AR2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AR2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AR2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AR3 (ERROR) Alta repetida.
   Esperado: error 50001 con 1 condición: ya hay un árbitro Kwame Mensah
   de ese país. */
DECLARE @id_pais_gha SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'GHA');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais_gha, @nombre = N'Kwame', @apellido = N'Mensah', @categoria = 'FIFA';
    PRINT N'AR3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AR3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AR3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AR4 (OK) Modificación de categoría y fecha de nacimiento.
   Esperado: pasa a CONFEDERACION y nacido el 03/04/1988. */
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
SELECT 'AR4 antes' AS caso, id_arbitro, categoria, fecha_nacimiento FROM Arbitraje.ARBITRO WHERE id_arbitro = @id_arbitro;
EXEC Arbitraje.usp_ARBITRO_Modificacion @id_arbitro = @id_arbitro, @categoria = 'CONFEDERACION', @fecha_nacimiento = '1988-04-03';
SELECT 'AR4 después' AS caso, id_arbitro, categoria, fecha_nacimiento FROM Arbitraje.ARBITRO WHERE id_arbitro = @id_arbitro;
GO

/* AR5 (ERROR) Modificación con nombre demasiado largo y categoría no válida.
   Esperado: error 50001 con 2 condiciones. */
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Modificacion @id_arbitro = @id_arbitro,
        @nombre = N'Un nombre de árbitro tan largo que supera el máximo de sesenta caracteres',
        @categoria = 'REGIONAL';
    PRINT N'AR5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AR5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AR5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   ARBITRO_IDIOMA
   ============================================================================ */

/* AI1 (OK) Alta de dos idiomas.
   Esperado: el árbitro queda con inglés y francés. */
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
DECLARE @id_idioma_en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
DECLARE @id_idioma_fr SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'fr');
EXEC Arbitraje.usp_ARBITRO_IDIOMA_Alta @id_arbitro = @id_arbitro, @id_idioma = @id_idioma_en;
EXEC Arbitraje.usp_ARBITRO_IDIOMA_Alta @id_arbitro = @id_arbitro, @id_idioma = @id_idioma_fr;
SELECT 'AI1 después' AS caso, i.nombre AS idioma FROM Arbitraje.ARBITRO_IDIOMA AS ai
INNER JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = ai.id_idioma WHERE ai.id_arbitro = @id_arbitro;
GO

/* AI2 (ERROR) Árbitro e idioma que no existen.
   Esperado: error 50001 con 2 condiciones. */
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_IDIOMA_Alta @id_arbitro = -1, @id_idioma = -1;
    PRINT N'AI2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AI2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AI2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AI3 (ERROR) Idioma repetido.
   Esperado: error 50001 con 1 condición: el árbitro ya tiene registrado ese idioma. */
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
DECLARE @id_idioma_en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_IDIOMA_Alta @id_arbitro = @id_arbitro, @id_idioma = @id_idioma_en;
    PRINT N'AI3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AI3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AI3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AI4 (OK) Baja del francés.
   AI5 (ERROR) Baja del francés otra vez.
   Esperado: AI4 deja solo el inglés; AI5 falla con 1 condición: el árbitro
   no tiene registrado ese idioma. */
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
DECLARE @id_idioma_fr SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'fr');
EXEC Arbitraje.usp_ARBITRO_IDIOMA_Baja @id_arbitro = @id_arbitro, @id_idioma = @id_idioma_fr;
SELECT 'AI4 después' AS caso, i.nombre AS idioma FROM Arbitraje.ARBITRO_IDIOMA AS ai
INNER JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = ai.id_idioma WHERE ai.id_arbitro = @id_arbitro;
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_IDIOMA_Baja @id_arbitro = @id_arbitro, @id_idioma = @id_idioma_fr;
    PRINT N'AI5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AI5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AI5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   DESIGNACION_ARBITRAL
   ============================================================================ */

/* D1 (OK) Designación de Kwame Mensah como cuarto árbitro del partido 215.
   Esperado: 0 designaciones antes y 1 después. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
SELECT 'D1 antes' AS caso, COUNT(*) AS designaciones FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido;
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id_arbitro, @rol = 'cuarto';
SELECT 'D1 después' AS caso, d.rol, a.apellido, a.nombre, d.fecha_designacion
FROM Arbitraje.DESIGNACION_ARBITRAL AS d INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = d.id_arbitro
WHERE d.id_partido = @id_partido;
GO

/* D2 (ERROR) Caso obligatorio: designación descartada por conflicto de nacionalidad.
   Esperado: error 50001 con 1 condición: el árbitro Facundo Tello1 es
   de Argentina1, que juega este partido. No queda designado. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @conflicto INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Facundo' AND apellido = N'Tello1');
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @conflicto, @rol = 'PRINCIPAL';
    PRINT N'D2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'D2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'D2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'D2 después' AS caso, COUNT(*) AS designaciones_del_arbitro_en_215
FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND id_arbitro = @conflicto;
GO

/* D3 (ERROR) El mismo árbitro otra vez y en un rol ya cubierto.
   Esperado: error 50001 con 2 condiciones: el rol CUARTO ya está cubierto y
   el árbitro ya está designado en ese partido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id_arbitro, @rol = 'CUARTO';
    PRINT N'D3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'D3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'D3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

-- D4 necesita un partido jugado: se prueba después de D8, cuando el partido 215 termina.

/* D5 (OK) Uno de los roles opcionales, en un partido 18 horas después de otro
   del mismo árbitro: no hay un descanso mínimo entre partidos (la consigna
   no lo pide).
   Kwame Mensah, designado en el 215, se designa como AVAR del 216.
   Para que los casos siguientes lo encuentren solo en el 215, después se da
   de baja esa designación (el 216 sigue PROGRAMADO).
   Esperado: 1 designación en el 216, con rol AVAR, y 0 después de la baja. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 216);
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id_arbitro, @rol = 'avar';
SELECT 'D5 designado' AS caso, d.rol, a.apellido FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = d.id_arbitro WHERE d.id_partido = @id_partido;
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id_partido, @id_arbitro = @id_arbitro;
SELECT 'D5 después' AS caso, COUNT(*) AS designaciones_en_216 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido;
GO

/* AR6 (ERROR) Cambio de país que crea un conflicto de nacionalidad.
   Esperado: error 50001 con 1 condición: con el país Brasil1 quedaría
   en conflicto de nacionalidad en el partido 215, que tiene designado. */
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
DECLARE @id_pais_bra SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE nombre = 'Brasil1');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Modificacion @id_arbitro = @id_arbitro, @id_pais = @id_pais_bra;
    PRINT N'AR6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AR6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AR6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AR7 (ERROR) Baja lógica de un árbitro con un partido por jugar.
   Esperado: error 50001 con 1 condición: el árbitro está designado en un
   partido que todavía no se jugó. */
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id_arbitro;
    PRINT N'AR7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AR7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AR7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* D6 (OK) Cambio de rol.
   Esperado: Kwame Mensah pasa de CUARTO a VAR. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
SELECT 'D6 antes' AS caso, rol FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND id_arbitro = @id_arbitro;
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Modificacion @id_partido = @id_partido, @id_arbitro = @id_arbitro, @rol = 'VAR';
SELECT 'D6 después' AS caso, rol FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND id_arbitro = @id_arbitro;
GO

/* D7 (ERROR) Informe de un partido que no se jugó y sanción demasiado larga.
   Esperado: error 50001 con 2 condiciones: el informe y la sanción se
   registran con el partido FINALIZADO, y la sanción supera los 500 caracteres. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
DECLARE @larga VARCHAR(600) = REPLICATE('Sanción muy extensa. ', 28);
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Modificacion @id_partido = @id_partido, @id_arbitro = @id_arbitro,
        @informe_postpartido = 'Buen partido', @sancion = @larga;
    PRINT N'D7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'D7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'D7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* D8 (OK) Informe y sanción post-partido.
   Preparación: el partido 215 pasa a FINALIZADO (1 a 0) con un UPDATE.
   Esperado: la designación queda con su informe y su sanción. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
UPDATE Torneo.PARTIDO SET goles_local = 1, goles_visitante = 0, estado = 'FINALIZADO' WHERE id_partido = @id_partido;
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Modificacion @id_partido = @id_partido, @id_arbitro = @id_arbitro,
    @informe_postpartido = 'Revisiones del VAR correctas y rápidas.', @sancion = 'Apercibimiento por llegar tarde a la reunión previa.';
SELECT 'D8 después' AS caso, h.numero_partido, h.rol, h.apellido, h.resultado, h.informe_postpartido, h.sancion
FROM Arbitraje.vw_HistorialArbitro AS h WHERE h.id_arbitro = @id_arbitro;
GO

/* D4 (ERROR) Designación en un partido jugado y con un rol que no existe.
   Se usa Kofi Owusu, de Ghana, que no tiene designaciones.
   Esperado: error 50001 con 2 condiciones: el partido 215 está FINALIZADO y
   el rol JUEZ no es válido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kofi' AND apellido = N'Owusu');
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id_arbitro, @rol = 'JUEZ';
    PRINT N'D4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'D4: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'D4: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* D9 (ERROR) Baja de la designación de un partido jugado.
   Esperado: error 50001 con 1 condición: el partido está FINALIZADO y la
   designación queda en el historial del árbitro. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id_partido, @id_arbitro = @id_arbitro;
    PRINT N'D9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'D9: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'D9: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AR8 (ERROR) Borrado físico de un árbitro con idiomas y designaciones.
   Esperado: error 50001 con 2 condiciones: lo referencian 1 registro de
   ARBITRO_IDIOMA y 1 de DESIGNACION_ARBITRAL. */
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id_arbitro, @eliminar_registro = 1;
    PRINT N'AR8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AR8: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AR8: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AR9 (OK) Baja lógica de un árbitro cuyos partidos ya se jugaron.
   Esperado: activo pasa de 1 a 0 y el árbitro conserva su historial.
   AR10 (ERROR) Segunda baja lógica del mismo árbitro.
   Esperado: error 50001 con 1 condición: el árbitro ya está inactivo. */
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
SELECT 'AR9 antes' AS caso, id_arbitro, activo FROM Arbitraje.ARBITRO WHERE id_arbitro = @id_arbitro;
EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id_arbitro;
SELECT 'AR9 después' AS caso, id_arbitro, activo,
       (SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_arbitro = @id_arbitro) AS designaciones
FROM Arbitraje.ARBITRO WHERE id_arbitro = @id_arbitro;
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id_arbitro;
    PRINT N'AR10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AR10: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AR10: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* D10 (ERROR) Designación de un árbitro inactivo.
   Esperado: error 50001 con 1 condición: el árbitro no está activo. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 216);
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kwame' AND apellido = N'Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id_arbitro, @rol = 'ASISTENTE_1';
    PRINT N'D10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'D10: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'D10: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* D11 (OK) Baja de la designación de un partido por jugar.
   Preparación: Kofi Owusu designado con un INSERT como ASISTENTE_1
   del partido 216, que sigue PROGRAMADO.
   Esperado: 1 designación de Kofi Owusu antes y 0 después.
   D12 (ERROR) Baja de la misma designación otra vez.
   Esperado: error 50001 con 1 condición: el árbitro no está designado en ese
   partido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 216);
DECLARE @id_arbitro INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE nombre = N'Kofi' AND apellido = N'Owusu');
INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol) VALUES (@id_partido, @id_arbitro, 'ASISTENTE_1');

SELECT 'D11 antes' AS caso, COUNT(*) AS designaciones FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_arbitro = @id_arbitro;
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id_partido, @id_arbitro = @id_arbitro;
SELECT 'D11 después' AS caso, COUNT(*) AS designaciones FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_arbitro = @id_arbitro;

BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id_partido, @id_arbitro = @id_arbitro;
    PRINT N'D12: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'D12: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'D12: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
ROLLBACK TRANSACTION;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO
        WHERE (nombre = N'Kwame' AND apellido = N'Mensah') OR (nombre = N'Kofi' AND apellido = N'Owusu')
           OR apellido = N'Tello1')                                                         AS arbitros_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (215, 216))            AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS
        WHERE nombre IN ('Argentina1', 'Brasil1', 'Francia1', 'Inglaterra1'))              AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio IN ('BC Place1', 'Lumen Field1')) AS sedes_de_prueba;
GO

SET NOEXEC OFF;
GO
