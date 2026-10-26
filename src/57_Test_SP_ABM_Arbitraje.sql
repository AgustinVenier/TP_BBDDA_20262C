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
 Archivo: 57_Test_SP_ABM_Arbitraje.sql
 Objetivo: Probar los SP de 07_SP_ABM_Arbitraje.sql (ARBITRO, ARBITRO_IDIOMA y
           DESIGNACION_ARBITRAL), con casos exitosos y su evidencia y casos
           que no cumplen las validaciones, entre ellos el conflicto de
           nacionalidad. Requiere haber ejecutado 00 a 20; no depende del juego de
           datos.
           Usa sus propios datos de prueba: cuatro selecciones de prueba (XAA
           a XAD, sin jugadores), las sedes "Estadio Prueba Arbitraje" y
           "Estadio Prueba Arbitraje 2", dos partidos (215, XAA - XAB, y 216,
           XAC - XAD, 18 horas después), dos árbitros de Ghana ("Prueba
           Mensah" y "Prueba Owusu") y un árbitro del país de prueba XAA
           ("Prueba Conflicto"). Todo se borra al empezar y al terminar con
           los SP de baja, así que se puede ejecutar más de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Arbitraje.usp_DESIGNACION_ARBITRAL_Alta', N'P') IS NULL
   OR OBJECT_ID(N'Torneo.usp_RegistrarSeleccion', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE codigo_iso IN ('en', 'fr') HAVING COUNT(*) = 2)
BEGIN
    RAISERROR(N'Faltan los SP o los datos iniciales: ejecutar los scripts 00 a 20.', 16, 1);
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

-- Da de alta con los SP una selección de prueba (sin jugadores): el país
-- "Prueba <código>", la selección con su lista presentada el 01/06/2026 y su
-- director técnico ("Prueba DT <código>").
-- Los procedimientos temporales se crean en tempdb, que puede tener otra
-- intercalación que la base: por eso el código se usa con COLLATE DATABASE_DEFAULT.
IF OBJECT_ID(N'tempdb..#usp_CrearSeleccionPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_CrearSeleccionPrueba;
GO
CREATE PROCEDURE #usp_CrearSeleccionPrueba
    @codigo_fifa    CHAR(3),
    @id_seleccion   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @nombre      VARCHAR(60)  = CONCAT('Prueba ', @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @dt_apellido NVARCHAR(60) = CONCAT(N'Prueba DT ', @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @id_pais SMALLINT;

    EXEC DatosGenerales.usp_PAIS_Alta @nombre = @nombre, @huso_horario = 'UTC', @codigo_fifa = @codigo_fifa,
        @id_pais = @id_pais OUTPUT;
    EXEC Torneo.usp_RegistrarSeleccion
        @id_pais = @id_pais, @confederacion = 'UEFA', @grupo = NULL, @fecha_presentacion = '2026-06-01',
        @dt_nombre = N'Director', @dt_apellido = @dt_apellido, @id_seleccion = @id_seleccion OUTPUT, @mostrar = 0;
END;
GO

-- Borra con los SP de baja una selección de prueba (cuerpo técnico, lista y
-- selección) y su país. Sus partidos y sus árbitros tienen que estar borrados antes.
IF OBJECT_ID(N'tempdb..#usp_BorrarSeleccionPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_BorrarSeleccionPrueba;
GO
CREATE PROCEDURE #usp_BorrarSeleccionPrueba
    @codigo_fifa CHAR(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS
                                 WHERE codigo_fifa = @codigo_fifa COLLATE DATABASE_DEFAULT
                                   AND nombre = CONCAT('Prueba ', @codigo_fifa COLLATE DATABASE_DEFAULT));
    DECLARE @id_sel INT, @id INT;
    IF @id_pais IS NULL RETURN;
    SET @id_sel = (SELECT id_seleccion FROM Torneo.SELECCION WHERE id_pais = @id_pais);

    IF @id_sel IS NOT NULL
    BEGIN
        WHILE EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_sel)
        BEGIN
            SELECT TOP (1) @id = id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_sel;
            EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Baja @id_persona_ct = @id;
        END;
        SET @id = (SELECT id_lista FROM Torneo.LISTA_CONVOCADOS WHERE id_seleccion = @id_sel);
        IF @id IS NOT NULL
            EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id;
        EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id_sel;
    END;
    EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id_pais;
END;
GO

-- Borra los partidos de prueba (con sus designaciones), los árbitros de
-- prueba, las selecciones de prueba y las sedes de prueba.
IF OBJECT_ID(N'tempdb..#usp_LimpiarPruebas', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPruebas;
GO
CREATE PROCEDURE #usp_LimpiarPruebas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @id_arbitro INT;

    WHILE EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE numero_partido IN (215, 216))
    BEGIN
        SELECT TOP (1) @id = id_partido FROM Torneo.PARTIDO WHERE numero_partido IN (215, 216);
        IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id) = 'FINALIZADO'
            EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'EN_JUEGO';
        IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id) IN ('EN_JUEGO', 'SUSPENDIDO')
            EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'PROGRAMADO';
        WHILE EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id)
        BEGIN
            SELECT TOP (1) @id_arbitro = id_arbitro FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id;
            EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id, @id_arbitro = @id_arbitro;
        END;
        EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;
    END;

    WHILE EXISTS (SELECT 1 FROM Arbitraje.ARBITRO WHERE apellido IN (N'Prueba Mensah', N'Prueba Owusu', N'Prueba Conflicto'))
    BEGIN
        SELECT TOP (1) @id_arbitro = id_arbitro FROM Arbitraje.ARBITRO
        WHERE apellido IN (N'Prueba Mensah', N'Prueba Owusu', N'Prueba Conflicto');
        WHILE EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id_arbitro)
        BEGIN
            SELECT TOP (1) @id = id_idioma FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id_arbitro;
            EXEC Arbitraje.usp_ARBITRO_IDIOMA_Baja @id_arbitro = @id_arbitro, @id_idioma = @id;
        END;
        EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id_arbitro, @eliminar_registro = 1;
    END;

    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XAA';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XAB';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XAC';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XAD';

    WHILE EXISTS (SELECT 1 FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Arbitraje%')
    BEGIN
        SELECT TOP (1) @id = id_sede FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Arbitraje%';
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;
    END;
END;
GO

EXEC #usp_LimpiarPruebas;
GO

-- Preparación: dos sedes de prueba, cuatro selecciones de prueba, los partidos
-- 215 (XAA - XAB) y, 18 horas después, 216 (XAC - XAD), y el árbitro "Prueba
-- Conflicto", del país de prueba XAA (para el conflicto de nacionalidad).
DECLARE @can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
DECLARE @usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede1 INT, @sede2 INT, @xaa INT, @xab INT, @xac INT, @xad INT;
EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Arbitraje', @ciudad = 'Vancouver', @id_pais = @can,
    @capacidad = 54000, @huso_horario = 'Pacific Standard Time', @id_sede = @sede1 OUTPUT;
EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Arbitraje 2', @ciudad = 'Seattle', @id_pais = @usa,
    @capacidad = 68000, @huso_horario = 'Pacific Standard Time', @id_sede = @sede2 OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XAA', @id_seleccion = @xaa OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XAB', @id_seleccion = @xab OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XAC', @id_seleccion = @xac OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XAD', @id_seleccion = @xad OUTPUT;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 215, @id_sede = @sede1, @fase = 'OCTAVOS',
    @fecha_hora_utc = '2026-08-12 02:00', @id_seleccion_local = @xaa, @id_seleccion_visitante = @xab;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 216, @id_sede = @sede2, @fase = 'OCTAVOS',
    @fecha_hora_utc = '2026-08-12 20:00', @id_seleccion_local = @xac, @id_seleccion_visitante = @xad;

DECLARE @pais_xaa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XAA');
EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @pais_xaa, @nombre = N'Árbitro', @apellido = N'Prueba Conflicto', @categoria = 'FIFA';

SELECT 'Preparación' AS caso, numero_partido, seleccion_local, seleccion_visitante, nombre_estadio, fecha_hora_utc, estado
FROM Torneo.vw_Fixture WHERE numero_partido IN (215, 216) ORDER BY numero_partido;
GO


/* ============================================================================
   ARBITRO
   ============================================================================ */

/* AR1 (OK) Alta de un árbitro.
   Esperado: 0 árbitros "Prueba Mensah" antes y 1 después, con categoría FIFA y activo. */
DECLARE @gha SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'GHA');
DECLARE @id INT;
SELECT 'AR1 antes' AS caso, COUNT(*) AS arbitros_de_prueba FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah';
EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @gha, @nombre = N'Kwame', @apellido = N'Prueba Mensah',
    @categoria = 'fifa', @fecha_nacimiento = '1988-03-03', @id_arbitro = @id OUTPUT;
SELECT 'AR1 después' AS caso, id_arbitro, apellido, nombre, categoria, fecha_nacimiento, activo FROM Arbitraje.ARBITRO WHERE id_arbitro = @id;
GO

/* AR2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 4 condiciones: no existe el país -1, el nombre
   es obligatorio, la categoría NACIONAL no es válida y la fecha de
   nacimiento es futura. */
DECLARE @futura DATE = DATEADD(YEAR, 1, GETDATE());
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = -1, @nombre = N'', @apellido = N'Prueba Sin Nombre',
        @categoria = 'NACIONAL', @fecha_nacimiento = @futura;
    PRINT N'AR2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AR2';
END CATCH;
GO

/* AR3 (ERROR) Alta repetida.
   Esperado: error 50001 con 1 condición: ya hay un árbitro Kwame Prueba
   Mensah de ese país. */
DECLARE @gha SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'GHA');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @gha, @nombre = N'Kwame', @apellido = N'Prueba Mensah', @categoria = 'FIFA';
    PRINT N'AR3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AR3';
END CATCH;
GO

/* AR4 (OK) Modificación de categoría y fecha de nacimiento.
   Esperado: pasa a CONFEDERACION y nacido el 03/04/1988. */
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
SELECT 'AR4 antes' AS caso, id_arbitro, categoria, fecha_nacimiento FROM Arbitraje.ARBITRO WHERE id_arbitro = @id;
EXEC Arbitraje.usp_ARBITRO_Modificacion @id_arbitro = @id, @categoria = 'CONFEDERACION', @fecha_nacimiento = '1988-04-03';
SELECT 'AR4 después' AS caso, id_arbitro, categoria, fecha_nacimiento FROM Arbitraje.ARBITRO WHERE id_arbitro = @id;
GO

/* AR5 (ERROR) Modificación con nombre demasiado largo y categoría no válida.
   Esperado: error 50001 con 2 condiciones. */
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Modificacion @id_arbitro = @id,
        @nombre = N'Un nombre de árbitro tan largo que supera el máximo de sesenta caracteres',
        @categoria = 'REGIONAL';
    PRINT N'AR5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AR5';
END CATCH;
GO


/* ============================================================================
   ARBITRO_IDIOMA
   ============================================================================ */

/* AI1 (OK) Alta de dos idiomas.
   Esperado: el árbitro queda con inglés y francés. */
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
DECLARE @en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
DECLARE @fr SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'fr');
EXEC Arbitraje.usp_ARBITRO_IDIOMA_Alta @id_arbitro = @id, @id_idioma = @en;
EXEC Arbitraje.usp_ARBITRO_IDIOMA_Alta @id_arbitro = @id, @id_idioma = @fr;
SELECT 'AI1 después' AS caso, i.nombre AS idioma FROM Arbitraje.ARBITRO_IDIOMA AS ai
INNER JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = ai.id_idioma WHERE ai.id_arbitro = @id;
GO

/* AI2 (ERROR) Árbitro e idioma que no existen.
   Esperado: error 50001 con 2 condiciones. */
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_IDIOMA_Alta @id_arbitro = -1, @id_idioma = -1;
    PRINT N'AI2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AI2';
END CATCH;
GO

/* AI3 (ERROR) Idioma repetido.
   Esperado: error 50001 con 1 condición: el árbitro ya tiene registrado ese idioma. */
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
DECLARE @en SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'en');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_IDIOMA_Alta @id_arbitro = @id, @id_idioma = @en;
    PRINT N'AI3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AI3';
END CATCH;
GO

/* AI4 (OK) Baja del francés.
   AI5 (ERROR) Baja del francés otra vez.
   Esperado: AI4 deja solo el inglés; AI5 falla con 1 condición: el árbitro
   no tiene registrado ese idioma. */
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
DECLARE @fr SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'fr');
EXEC Arbitraje.usp_ARBITRO_IDIOMA_Baja @id_arbitro = @id, @id_idioma = @fr;
SELECT 'AI4 después' AS caso, i.nombre AS idioma FROM Arbitraje.ARBITRO_IDIOMA AS ai
INNER JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = ai.id_idioma WHERE ai.id_arbitro = @id;
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_IDIOMA_Baja @id_arbitro = @id, @id_idioma = @fr;
    PRINT N'AI5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AI5';
END CATCH;
GO


/* ============================================================================
   DESIGNACION_ARBITRAL
   ============================================================================ */

/* D1 (OK) Designación del árbitro de prueba como cuarto árbitro del partido 215.
   Esperado: 0 designaciones antes y 1 después. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
SELECT 'D1 antes' AS caso, COUNT(*) AS designaciones FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido;
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id, @rol = 'cuarto';
SELECT 'D1 después' AS caso, d.rol, a.apellido, a.nombre, d.fecha_designacion
FROM Arbitraje.DESIGNACION_ARBITRAL AS d INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = d.id_arbitro
WHERE d.id_partido = @id_partido;
GO

/* D2 (ERROR) Caso obligatorio: designación descartada por conflicto de nacionalidad.
   Esperado: error 50001 con 1 condición: el árbitro "Prueba Conflicto" es
   del país de prueba XAA, que juega este partido. No queda designado. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @conflicto INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Conflicto');
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @conflicto, @rol = 'PRINCIPAL';
    PRINT N'D2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'D2';
END CATCH;
SELECT 'D2 después' AS caso, COUNT(*) AS designaciones_del_arbitro_en_215
FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND id_arbitro = @conflicto;
GO

/* D3 (ERROR) El mismo árbitro otra vez y en un rol ya cubierto.
   Esperado: error 50001 con 2 condiciones: el rol CUARTO ya está cubierto y
   el árbitro ya está designado en ese partido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id, @rol = 'CUARTO';
    PRINT N'D3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'D3';
END CATCH;
GO

-- D4 necesita un partido jugado: se prueba después de D8, cuando el partido 215 termina.

/* D5 (ERROR) Dos partidos a menos de 24 horas.
   Esperado: error 50001 con 1 condición: el árbitro ya está designado en el
   partido 215, a menos de 24 horas del 216. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 216);
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id, @rol = 'VAR';
    PRINT N'D5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'D5';
END CATCH;
GO

/* AR6 (ERROR) Cambio de país que crea un conflicto de nacionalidad.
   Esperado: error 50001 con 1 condición: con el país de prueba XAB quedaría
   en conflicto de nacionalidad en el partido 215, que tiene designado. */
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
DECLARE @xab SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XAB');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Modificacion @id_arbitro = @id, @id_pais = @xab;
    PRINT N'AR6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AR6';
END CATCH;
GO

/* AR7 (ERROR) Baja lógica de un árbitro con un partido por jugar.
   Esperado: error 50001 con 1 condición: el árbitro está designado en un
   partido que todavía no se jugó. */
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id;
    PRINT N'AR7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AR7';
END CATCH;
GO

/* D6 (OK) Cambio de rol.
   Esperado: el árbitro de prueba pasa de CUARTO a VAR. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
SELECT 'D6 antes' AS caso, rol FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND id_arbitro = @id;
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Modificacion @id_partido = @id_partido, @id_arbitro = @id, @rol = 'VAR';
SELECT 'D6 después' AS caso, rol FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND id_arbitro = @id;
GO

/* D7 (ERROR) Informe de un partido que no se jugó y sanción demasiado larga.
   Esperado: error 50001 con 2 condiciones: el informe y la sanción se
   registran con el partido FINALIZADO, y la sanción supera los 500 caracteres. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
DECLARE @larga VARCHAR(600) = REPLICATE('Sanción muy extensa. ', 28);
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Modificacion @id_partido = @id_partido, @id_arbitro = @id,
        @informe_postpartido = 'Buen partido', @sancion = @larga;
    PRINT N'D7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'D7';
END CATCH;
GO

/* D8 (OK) Informe y sanción post-partido.
   Esperado: con el partido 215 cargado como FINALIZADO (1 a 0), la
   designación queda con su informe y su sanción. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @goles_local = 1, @goles_visitante = 0, @estado = 'FINALIZADO';
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Modificacion @id_partido = @id_partido, @id_arbitro = @id,
    @informe_postpartido = 'Revisiones del VAR correctas y rápidas.', @sancion = 'Apercibimiento por llegar tarde a la reunión previa.';
SELECT 'D8 después' AS caso, h.numero_partido, h.rol, h.apellido, h.resultado, h.informe_postpartido, h.sancion
FROM Arbitraje.vw_HistorialArbitro AS h WHERE h.id_arbitro = @id;
GO

/* D4 (ERROR) Designación en un partido jugado y con un rol que no existe.
   Preparación: el árbitro "Prueba Owusu", de Ghana, sin designaciones.
   Esperado: error 50001 con 2 condiciones: el partido 215 está FINALIZADO y
   el rol JUEZ no es válido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @gha SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'GHA');
DECLARE @id INT;
EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @gha, @nombre = N'Kofi', @apellido = N'Prueba Owusu', @categoria = 'FIFA',
    @id_arbitro = @id OUTPUT;
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id, @rol = 'JUEZ';
    PRINT N'D4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'D4';
END CATCH;
GO

/* D9 (ERROR) Baja de la designación de un partido jugado.
   Esperado: error 50001 con 1 condición: el partido está FINALIZADO y la
   designación queda en el historial del árbitro. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 215);
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id_partido, @id_arbitro = @id;
    PRINT N'D9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'D9';
END CATCH;
GO

/* AR8 (ERROR) Borrado físico de un árbitro con idiomas y designaciones.
   Esperado: error 50001 con 2 condiciones: lo referencian 1 registro de
   ARBITRO_IDIOMA y 1 de DESIGNACION_ARBITRAL. */
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id, @eliminar_registro = 1;
    PRINT N'AR8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AR8';
END CATCH;
GO

/* AR9 (OK) Baja lógica de un árbitro cuyos partidos ya se jugaron.
   Esperado: activo pasa de 1 a 0 y el árbitro conserva su historial.
   AR10 (ERROR) Segunda baja lógica del mismo árbitro.
   Esperado: error 50001 con 1 condición: el árbitro ya está inactivo. */
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
SELECT 'AR9 antes' AS caso, id_arbitro, activo FROM Arbitraje.ARBITRO WHERE id_arbitro = @id;
EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id;
SELECT 'AR9 después' AS caso, id_arbitro, activo,
       (SELECT COUNT(*) FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_arbitro = @id) AS designaciones
FROM Arbitraje.ARBITRO WHERE id_arbitro = @id;
BEGIN TRY
    EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id;
    PRINT N'AR10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AR10';
END CATCH;
GO

/* D10 (ERROR) Designación de un árbitro inactivo.
   Esperado: error 50001 con 2 condiciones: el árbitro no está activo y ya
   está designado en el partido 215, a menos de 24 horas del 216. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 216);
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Mensah');
BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id, @rol = 'ASISTENTE_1';
    PRINT N'D10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'D10';
END CATCH;
GO

/* D11 (OK) Baja de la designación de un partido por jugar.
   Preparación: "Prueba Owusu" (el árbitro de D4) designado como ASISTENTE_1
   del partido 216, que sigue PROGRAMADO.
   Esperado: 1 designación de Prueba Owusu antes y 0 después.
   D12 (ERROR) Baja de la misma designación otra vez.
   Esperado: error 50001 con 1 condición: el árbitro no está designado en ese
   partido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 216);
DECLARE @id INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Owusu');
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Alta @id_partido = @id_partido, @id_arbitro = @id, @rol = 'ASISTENTE_1';

SELECT 'D11 antes' AS caso, COUNT(*) AS designaciones FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_arbitro = @id;
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id_partido, @id_arbitro = @id;
SELECT 'D11 después' AS caso, COUNT(*) AS designaciones FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_arbitro = @id;

BEGIN TRY
    EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id_partido, @id_arbitro = @id;
    PRINT N'D12: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'D12';
END CATCH;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO
        WHERE apellido IN (N'Prueba Mensah', N'Prueba Owusu', N'Prueba Conflicto'))        AS arbitros_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (215, 216))            AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XAA', 'XAB', 'XAC', 'XAD')) AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Arbitraje%') AS sedes_de_prueba;
GO

SET NOEXEC OFF;
GO
