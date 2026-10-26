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
 Archivo: 56_Test_SP_ABM_DesarrolloPartido.sql
 Objetivo: Probar los SP de 06_SP_ABM_DesarrolloPartido.sql (TIPO_GOL,
           FORMACION, ALINEACION, CAMBIO, GOL y AMONESTACION), con casos
           exitosos y su evidencia y casos que no cumplen las validaciones.
           Requiere haber ejecutado 00 a 20; no depende del juego de datos.
           Crea sus propios datos de prueba con los SP: tres selecciones de
           prueba (XDA y XDB con 23 jugadores, XDC sin jugadores), la sede
           "Estadio Prueba DesarrolloPartido", el partido 211 (XDA - XDB, ya
           jugado, con un gol y una roja directa al dorsal 2 de XDA) y el
           partido 210 (XDA - XDB, de octavos), sobre el que se prueban los
           SP. Todo se borra al empezar y al terminar con los SP de baja, así
           que se puede ejecutar más de una vez.
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

IF OBJECT_ID(N'DesarrolloPartido.usp_GOL_Alta', N'P') IS NULL
   OR OBJECT_ID(N'DesarrolloPartido.usp_RegistrarFormacion', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE descripcion IN ('JUGADA', 'EN CONTRA', 'PENAL', 'CABEZAZO')
                  HAVING COUNT(*) = 4)
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

-- Da de alta con los SP una selección de prueba: el país "Prueba <código>", la
-- selección con su lista presentada el 01/06/2026, su director técnico
-- ("Prueba DT <código>") y, si @con_jugadores = 1, 23 jugadores ("Prueba
-- <código> <dorsal>"): arqueros 1, 12 y 23; defensores 2 a 6 y 13 a 15;
-- mediocampistas 7, 8, 10 y 16 a 18; delanteros 9, 11 y 19 a 22.
-- Los procedimientos temporales se crean en tempdb, que puede tener otra
-- intercalación que la base: por eso el código se usa con COLLATE DATABASE_DEFAULT.
IF OBJECT_ID(N'tempdb..#usp_CrearSeleccionPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_CrearSeleccionPrueba;
GO
CREATE PROCEDURE #usp_CrearSeleccionPrueba
    @codigo_fifa    CHAR(3),
    @con_jugadores  BIT = 1,
    @id_seleccion   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @nombre      VARCHAR(60)  = CONCAT('Prueba ', @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @dt_apellido NVARCHAR(60) = CONCAT(N'Prueba DT ', @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @id_pais SMALLINT, @id_lista INT, @i INT = 1, @dorsal TINYINT, @posicion VARCHAR(15), @apellido NVARCHAR(60);
    DECLARE @plantel TABLE (orden INT IDENTITY(1,1), dorsal TINYINT, posicion VARCHAR(15));

    EXEC DatosGenerales.usp_PAIS_Alta @nombre = @nombre, @huso_horario = 'UTC', @codigo_fifa = @codigo_fifa,
        @id_pais = @id_pais OUTPUT;
    EXEC Torneo.usp_RegistrarSeleccion
        @id_pais = @id_pais, @confederacion = 'UEFA', @grupo = NULL, @fecha_presentacion = '2026-06-01',
        @dt_nombre = N'Director', @dt_apellido = @dt_apellido, @id_seleccion = @id_seleccion OUTPUT, @mostrar = 0;

    IF @con_jugadores = 0 RETURN;

    SET @id_lista = (SELECT id_lista FROM Torneo.LISTA_CONVOCADOS WHERE id_seleccion = @id_seleccion);
    INSERT INTO @plantel (dorsal, posicion)
    VALUES (1, 'ARQUERO'), (12, 'ARQUERO'), (23, 'ARQUERO'),
           (2, 'DEFENSOR'), (3, 'DEFENSOR'), (4, 'DEFENSOR'), (5, 'DEFENSOR'), (6, 'DEFENSOR'),
           (13, 'DEFENSOR'), (14, 'DEFENSOR'), (15, 'DEFENSOR'),
           (7, 'MEDIOCAMPISTA'), (8, 'MEDIOCAMPISTA'), (10, 'MEDIOCAMPISTA'),
           (16, 'MEDIOCAMPISTA'), (17, 'MEDIOCAMPISTA'), (18, 'MEDIOCAMPISTA'),
           (9, 'DELANTERO'), (11, 'DELANTERO'), (19, 'DELANTERO'), (20, 'DELANTERO'),
           (21, 'DELANTERO'), (22, 'DELANTERO');
    WHILE @i <= 23
    BEGIN
        SELECT @dorsal = dorsal, @posicion = posicion FROM @plantel WHERE orden = @i;
        SET @apellido = CONCAT(N'Prueba ', @codigo_fifa COLLATE DATABASE_DEFAULT, N' ', @dorsal);
        EXEC Torneo.usp_JUGADOR_Alta
            @id_lista = @id_lista, @nombre = N'Jugador', @apellido = @apellido,
            @posicion_habitual = @posicion, @dorsal = @dorsal, @fecha_alta = '2026-06-01';
        SET @i += 1;
    END;
END;
GO

-- Borra con los SP de baja una selección de prueba (jugadores, cuerpo técnico,
-- lista y selección) y su país. Sus partidos tienen que estar borrados antes.
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
        WHILE EXISTS (SELECT 1 FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                      WHERE l.id_seleccion = @id_sel)
        BEGIN
            SELECT TOP (1) @id = j.id_jugador FROM Torneo.JUGADOR AS j
            INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_sel;
            EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id, @eliminar_registro = 1;
        END;
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

-- Borra un partido de prueba y todo lo que tenga, en el orden que exigen los SP de baja.
IF OBJECT_ID(N'tempdb..#usp_LimpiarPartido', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPartido;
GO
CREATE PROCEDURE #usp_LimpiarPartido
    @numero_partido TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = @numero_partido);
    DECLARE @id INT, @id2 INT;
    IF @id_partido IS NULL RETURN;

    IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido) = 'FINALIZADO'
        EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';

    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.GOL WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_gol FROM DesarrolloPartido.GOL WHERE id_partido = @id_partido;
        EXEC DesarrolloPartido.usp_GOL_Baja @id_gol = @id;
    END;
    -- Primero las rojas: una roja por doble amarilla impide borrar sus amarillas.
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_amonestacion FROM DesarrolloPartido.AMONESTACION
        WHERE id_partido = @id_partido ORDER BY IIF(tipo_tarjeta = 'ROJA', 0, 1);
        EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id;
    END;
    -- Del último cambio al primero: el que entró puede haber salido en un cambio posterior.
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.CAMBIO WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_cambio FROM DesarrolloPartido.CAMBIO
        WHERE id_partido = @id_partido ORDER BY minuto DESC, minuto_adicional DESC, id_cambio DESC;
        EXEC DesarrolloPartido.usp_CAMBIO_Baja @id_cambio = @id;
    END;

    IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido) IN ('EN_JUEGO', 'SUSPENDIDO')
        EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'PROGRAMADO';

    WHILE EXISTS (SELECT 1 FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_espacio FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido;
        EXEC Publicidad.usp_EXHIBICION_Baja @id_partido = @id_partido, @id_espacio = @id;
    END;
    WHILE EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_arbitro FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido;
        EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id_partido, @id_arbitro = @id;
    END;
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS a
                  INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
                  WHERE f.id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = a.id_formacion, @id2 = a.id_jugador
        FROM DesarrolloPartido.ALINEACION AS a
        INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
        WHERE f.id_partido = @id_partido;
        EXEC DesarrolloPartido.usp_ALINEACION_Baja @id_formacion = @id, @id_jugador = @id2;
    END;
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_formacion FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido;
        EXEC DesarrolloPartido.usp_FORMACION_Baja @id_formacion = @id;
    END;

    EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id_partido;
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

    EXEC #usp_LimpiarPartido @numero_partido = 210;
    EXEC #usp_LimpiarPartido @numero_partido = 211;

    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XDA';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XDB';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XDC';

    SET @id = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba DesarrolloPartido');
    IF @id IS NOT NULL
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;

    SET @id = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion LIKE 'PRUEBA%');
    IF @id IS NOT NULL
        EXEC DesarrolloPartido.usp_TIPO_GOL_Baja @id_tipo_gol = @id;
END;
GO

EXEC #usp_LimpiarPruebas;
GO


/* ============================================================================
   TIPO_GOL
   ============================================================================ */

/* TG1 (OK) Alta de un tipo de gol.
   Esperado: una fila nueva con la descripción en mayúsculas ("PRUEBA OLÍMPICO")
   y es_en_contra en 0. */
DECLARE @id TINYINT;
EXEC DesarrolloPartido.usp_TIPO_GOL_Alta @descripcion = 'Prueba olímpico', @id_tipo_gol = @id OUTPUT;
SELECT 'TG1 después' AS caso, id_tipo_gol, descripcion, es_en_contra FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @id;
GO

/* TG2 (ERROR) Alta repetida y sin indicar si es en contra.
   Esperado: error 50001 con 2 condiciones: ya existe el tipo PENAL y hay que
   indicar si es un gol en contra. */
BEGIN TRY
    EXEC DesarrolloPartido.usp_TIPO_GOL_Alta @descripcion = 'penal', @es_en_contra = NULL;
    PRINT N'TG2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'TG2';
END CATCH;
GO

/* TG3 (OK) Modificación de la descripción.
   Esperado: pasa a "PRUEBA GOL OLÍMPICO". */
DECLARE @id TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PRUEBA OLÍMPICO');
SELECT 'TG3 antes' AS caso, id_tipo_gol, descripcion FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @id;
EXEC DesarrolloPartido.usp_TIPO_GOL_Modificacion @id_tipo_gol = @id, @descripcion = 'Prueba gol olímpico';
SELECT 'TG3 después' AS caso, id_tipo_gol, descripcion FROM DesarrolloPartido.TIPO_GOL WHERE id_tipo_gol = @id;
GO


/* ============================================================================
   PREPARACIÓN: selecciones, sede, partido 211 ya jugado y partido 210
   Esperado: el partido 211 FINALIZADO 1 - 0 (gol olímpico del dorsal 9 de
   XDA) con una roja directa al dorsal 2 de XDA, que queda suspendido para el
   partido 210 (ROJA DIRECTA, origen en el partido 211).
   ============================================================================ */
DECLARE @can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PRUEBA GOL OLÍMPICO');
DECLARE @sede INT, @xda INT, @xdb INT, @id_211 INT, @id_formacion INT, @xda_2 INT, @xda_9 INT;

EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba DesarrolloPartido', @ciudad = 'Vancouver', @id_pais = @can,
    @capacidad = 54000, @huso_horario = 'Pacific Standard Time', @id_sede = @sede OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XDA', @id_seleccion = @xda OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XDB', @id_seleccion = @xdb OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XDC', @con_jugadores = 0;

SET @xda_2 = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
              WHERE l.id_seleccion = @xda AND j.dorsal = 2);
SET @xda_9 = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
              WHERE l.id_seleccion = @xda AND j.dorsal = 9);

-- Partido 211 (dieciseisavos, 05/08/2026): formación de XDA con los dorsales 2 y 9,
-- gol del 9, roja directa al 2 y resultado final 1 - 0.
EXEC Torneo.usp_PARTIDO_Alta
    @numero_partido = 211, @id_sede = @sede, @fase = 'DIECISEISAVOS', @fecha_hora_utc = '2026-08-05 02:00',
    @id_seleccion_local = @xda, @id_seleccion_visitante = @xdb, @id_partido = @id_211 OUTPUT;
EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_211, @id_seleccion = @xda,
    @esquema_tactico = '4-4-2', @id_formacion = @id_formacion OUTPUT;
EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @xda_2,
    @es_titular = 1, @posicion_en_cancha = 'DEFENSOR';
EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @xda_9,
    @es_titular = 1, @posicion_en_cancha = 'DELANTERO';
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_211, @estado = 'EN_JUEGO';
EXEC DesarrolloPartido.usp_GOL_Alta @id_partido = @id_211, @id_jugador_autor = @xda_9, @id_tipo_gol = @tipo,
    @periodo = 'PRIMER_TIEMPO', @minuto = 20;
EXEC DesarrolloPartido.usp_AMONESTACION_Alta
    @id_partido = @id_211, @tipo_tarjeta = 'ROJA', @minuto = 89, @motivo = 'Juego brusco grave', @id_jugador = @xda_2;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_211, @estado = 'FINALIZADO', @goles_local = 1, @goles_visitante = 0;

-- Partido 210 (octavos, 10/08/2026), sobre el que se prueban los SP.
EXEC Torneo.usp_PARTIDO_Alta
    @numero_partido = 210, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2026-08-10 02:00',
    @id_seleccion_local = @xda, @id_seleccion_visitante = @xdb;

SELECT 'Preparación' AS caso, numero_partido, seleccion_local, resultado, seleccion_visitante, estado
FROM Torneo.vw_Fixture WHERE numero_partido IN (210, 211) ORDER BY numero_partido;

SELECT 'Preparación' AS caso, s.motivo, s.numero_partido_origen, j.dorsal, j.apellido
FROM DesarrolloPartido.fn_JugadoresSuspendidos((SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210)) AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador;
GO


/* ============================================================================
   TIPO_GOL (casos que necesitan goles registrados)
   ============================================================================ */

/* TG4 (ERROR) Cambiar la marca de "en contra" de un tipo con goles.
   Esperado: error 50001 con 1 condición: hay goles de este tipo (el gol del
   partido 211) y cambiar si es en contra alteraría sus resultados. */
DECLARE @id TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PRUEBA GOL OLÍMPICO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_TIPO_GOL_Modificacion @id_tipo_gol = @id, @es_en_contra = 1;
    PRINT N'TG4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'TG4';
END CATCH;
GO

/* TG5 (ERROR) Baja de un tipo con goles.
   Esperado: error 50001 con 1 condición: lo referencia 1 registro de
   DesarrolloPartido.GOL (el gol del partido 211). */
DECLARE @id TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PRUEBA GOL OLÍMPICO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_TIPO_GOL_Baja @id_tipo_gol = @id;
    PRINT N'TG5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'TG5';
END CATCH;
GO

-- TG6 (baja del tipo de prueba) se prueba al final, después de borrar el partido 211.


/* ============================================================================
   FORMACION
   ============================================================================ */

/* F1 (OK) Alta de la formación de XDA.
   Esperado: una formación 4-2-3-1 de XDA para el partido 210. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id INT;
EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_partido, @id_seleccion = @xda,
    @esquema_tactico = '4-2-3-1', @id_formacion = @id OUTPUT;
SELECT 'F1 después' AS caso, id_formacion, id_partido, id_seleccion, esquema_tactico FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id;
GO

/* F2 (ERROR) Selección que no juega el partido y esquema que no suma 10.
   Esperado: error 50001 con 2 condiciones: XDC no juega ese partido y el
   esquema 4-4-3 no suma 10 jugadores de campo. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xdc INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XDC');
BEGIN TRY
    EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_partido, @id_seleccion = @xdc, @esquema_tactico = '4-4-3';
    PRINT N'F2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'F2';
END CATCH;
GO

/* F3 (ERROR) Formación para un partido ya jugado, repetida y con esquema mal escrito.
   Esperado: error 50001 con 3 condiciones: el partido 211 está FINALIZADO,
   XDA ya tiene formación para ese partido y el esquema 4-x-3 no es válido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 211);
DECLARE @xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
BEGIN TRY
    EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_partido, @id_seleccion = @xda, @esquema_tactico = '4-x-3';
    PRINT N'F3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'F3';
END CATCH;
GO

/* F4 (OK) Modificación del esquema.
   Esperado: XDA pasa de 4-2-3-1 a 4-3-3. */
DECLARE @id INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                   WHERE p.numero_partido = 210);
SELECT 'F4 antes' AS caso, id_formacion, esquema_tactico FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id;
EXEC DesarrolloPartido.usp_FORMACION_Modificacion @id_formacion = @id, @esquema_tactico = '4-3-3';
SELECT 'F4 después' AS caso, id_formacion, esquema_tactico FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id;
GO

/* F5 (ERROR) Modificación de la formación de un partido terminado, con esquema incompleto.
   Esperado: error 50001 con 2 condiciones: el partido 211 ya terminó y el
   esquema 3-3 no suma 10. */
DECLARE @id INT = (SELECT TOP (1) f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                   WHERE p.numero_partido = 211);
BEGIN TRY
    EXEC DesarrolloPartido.usp_FORMACION_Modificacion @id_formacion = @id, @esquema_tactico = '3-3';
    PRINT N'F5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'F5';
END CATCH;
GO

/* F6 (OK) Baja de una formación sin alineaciones.
   Preparación: una formación 4-4-2 de XDB para el partido 210 (la que se usa
   después la carga usp_RegistrarFormacion).
   Esperado: 2 formaciones del partido 210 antes y 1 después (queda la de XDA).
   F7 (ERROR) Baja de la misma formación otra vez.
   Esperado: error 50001 con 1 condición: no existe una formación con ese id. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @id INT;
EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_partido, @id_seleccion = @xdb,
    @esquema_tactico = '4-4-2', @id_formacion = @id OUTPUT;

SELECT 'F6 antes' AS caso, COUNT(*) AS formaciones_del_partido FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido;
EXEC DesarrolloPartido.usp_FORMACION_Baja @id_formacion = @id;
SELECT 'F6 después' AS caso, COUNT(*) AS formaciones_del_partido FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido;

BEGIN TRY
    EXEC DesarrolloPartido.usp_FORMACION_Baja @id_formacion = @id;
    PRINT N'F7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'F7';
END CATCH;
GO


/* ============================================================================
   ALINEACION (formación de XDA)
   ============================================================================ */

/* A1 (OK) Alta de 11 titulares y 5 suplentes.
   Esperado: 0 antes; después, 11 titulares (dorsales 1, 3 a 11 y 19) y 5
   suplentes (12, 13, 15, 16 y 17). El dorsal 2, suspendido, no se incluye. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @xda INT = (SELECT id_seleccion FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion);
DECLARE @lista TABLE (orden INT IDENTITY(1,1), dorsal TINYINT, es_titular BIT, posicion VARCHAR(30));
INSERT INTO @lista (dorsal, es_titular, posicion)
VALUES (1, 1, 'ARQUERO'), (3, 1, 'DEFENSOR'), (4, 1, 'DEFENSOR'), (5, 1, 'DEFENSOR'), (6, 1, 'DEFENSOR'),
       (7, 1, 'MEDIOCAMPISTA'), (8, 1, 'MEDIOCAMPISTA'), (10, 1, 'MEDIOCAMPISTA'),
       (9, 1, 'DELANTERO'), (11, 1, 'DELANTERO'), (19, 1, 'DELANTERO'),
       (12, 0, NULL), (13, 0, NULL), (15, 0, NULL), (16, 0, NULL), (17, 0, NULL);
DECLARE @i INT = 1, @id_jugador INT, @es_titular BIT, @posicion VARCHAR(30);

SELECT 'A1 antes' AS caso, COUNT(*) AS alineados FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion;

WHILE @i <= 16
BEGIN
    SELECT @id_jugador = j.id_jugador, @es_titular = li.es_titular, @posicion = li.posicion
    FROM @lista AS li
    INNER JOIN Torneo.JUGADOR AS j ON j.dorsal = li.dorsal
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista AND l.id_seleccion = @xda
    WHERE li.orden = @i;
    EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @id_jugador,
        @es_titular = @es_titular, @posicion_en_cancha = @posicion;
    SET @i += 1;
END;

SELECT 'A1 después' AS caso, IIF(a.es_titular = 1, 'TITULAR', 'SUPLENTE') AS condicion, COUNT(*) AS jugadores,
       STRING_AGG(CAST(j.dorsal AS VARCHAR(3)), ', ') WITHIN GROUP (ORDER BY j.dorsal) AS dorsales
FROM DesarrolloPartido.ALINEACION AS a
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
WHERE a.id_formacion = @id_formacion
GROUP BY a.es_titular;
GO

/* A2 (ERROR) Un jugador suspendido en el banco.
   Esperado: error 50001 con 1 condición: el dorsal 2 de XDA está suspendido
   para este partido (ROJA DIRECTA en el partido 211). */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @xda_2 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                      INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_seleccion = l.id_seleccion
                      WHERE f.id_formacion = @id_formacion AND j.dorsal = 2);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @xda_2, @es_titular = 0;
    PRINT N'A2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'A2';
END CATCH;
GO

/* A3 (ERROR) Un jugador de otra selección como duodécimo titular y sin posición.
   Esperado: error 50001 con 3 condiciones: el jugador (dorsal 9 de XDB) no
   es de la selección de la formación, un titular necesita su posición en
   cancha y la formación ya tiene sus 11 titulares. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @xdb_9 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                      INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                      INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XDB' AND j.dorsal = 9);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @xdb_9, @es_titular = 1;
    PRINT N'A3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'A3';
END CATCH;
GO

/* A4 (ERROR) Un jugador que ya figura en la formación.
   Esperado: error 50001 con 1 condición: el jugador ya figura en la formación. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @xda_12 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                       INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_seleccion = l.id_seleccion
                       WHERE f.id_formacion = @id_formacion AND j.dorsal = 12);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @xda_12, @es_titular = 0;
    PRINT N'A4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'A4';
END CATCH;
GO

/* A5 (OK) El dorsal 11 pasa al banco y el 15 entra de titular.
   Esperado: siguen 11 titulares; el 11 queda SUPLENTE y el 15 TITULAR como
   DEFENSOR. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @j11 INT = (SELECT j.id_jugador FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
                    WHERE a.id_formacion = @id_formacion AND j.dorsal = 11);
DECLARE @j15 INT = (SELECT j.id_jugador FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
                    WHERE a.id_formacion = @id_formacion AND j.dorsal = 15);

SELECT 'A5 antes' AS caso, j.dorsal, a.es_titular, a.posicion_en_cancha
FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
WHERE a.id_formacion = @id_formacion AND j.dorsal IN (11, 15);

EXEC DesarrolloPartido.usp_ALINEACION_Modificacion @id_formacion = @id_formacion, @id_jugador = @j11, @es_titular = 0;
EXEC DesarrolloPartido.usp_ALINEACION_Modificacion @id_formacion = @id_formacion, @id_jugador = @j15,
    @es_titular = 1, @posicion_en_cancha = 'defensor';

SELECT 'A5 después' AS caso, j.dorsal, a.es_titular, a.posicion_en_cancha,
       (SELECT COUNT(*) FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion AND es_titular = 1) AS titulares
FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
WHERE a.id_formacion = @id_formacion AND j.dorsal IN (11, 15);
GO

/* A6 (ERROR) Un duodécimo titular con una posición demasiado larga.
   Esperado: error 50001 con 2 condiciones: la posición supera los 30
   caracteres y la formación ya tiene sus 11 titulares. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @j13 INT = (SELECT j.id_jugador FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
                    WHERE a.id_formacion = @id_formacion AND j.dorsal = 13);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Modificacion @id_formacion = @id_formacion, @id_jugador = @j13,
        @es_titular = 1, @posicion_en_cancha = 'Defensor central por la izquierda con salida';
    PRINT N'A6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'A6';
END CATCH;
GO

/* A7 (OK) Baja de un suplente sin eventos.
   Esperado: 16 alineados antes y 15 después (sale el dorsal 13). */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @j13 INT = (SELECT j.id_jugador FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
                    WHERE a.id_formacion = @id_formacion AND j.dorsal = 13);
SELECT 'A7 antes' AS caso, COUNT(*) AS alineados FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion;
EXEC DesarrolloPartido.usp_ALINEACION_Baja @id_formacion = @id_formacion, @id_jugador = @j13;
SELECT 'A7 después' AS caso, COUNT(*) AS alineados FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion;
GO

/* A8 (ERROR) Baja del mismo suplente otra vez.
   Esperado: error 50001 con 1 condición: el jugador (dorsal 13) no figura en
   esa formación. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
DECLARE @xda_13 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                       INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_seleccion = l.id_seleccion
                       WHERE f.id_formacion = @id_formacion AND j.dorsal = 13);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Baja @id_formacion = @id_formacion, @id_jugador = @xda_13;
    PRINT N'A8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'A8';
END CATCH;
GO

/* F8 (ERROR) Baja de una formación con jugadores alineados.
   Esperado: error 50001 con 1 condición: a la formación de XDA la referencian
   15 registros de DesarrolloPartido.ALINEACION. La formación sigue existiendo. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210);
BEGIN TRY
    EXEC DesarrolloPartido.usp_FORMACION_Baja @id_formacion = @id_formacion;
    PRINT N'F8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'F8';
END CATCH;
SELECT 'F8 después' AS caso, COUNT(*) AS formaciones FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion;
GO


/* ============================================================================
   PREPARACIÓN: formación de XDB e inicio del partido
   (con el SP de negocio de formaciones y el ABM de partidos)
   ============================================================================ */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @alineacion DesarrolloPartido.TT_ALINEACION;

INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
SELECT j.id_jugador,
       IIF(j.dorsal IN (1, 2, 3, 4, 5, 7, 8, 10, 9, 11, 19), 1, 0),
       CASE WHEN j.dorsal NOT IN (1, 2, 3, 4, 5, 7, 8, 10, 9, 11, 19) THEN NULL ELSE j.posicion_habitual END
FROM Torneo.JUGADOR AS j
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
WHERE l.id_seleccion = @xdb AND j.fecha_baja IS NULL AND j.dorsal <= 20;

EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @xdb,
    @esquema_tactico = '4-3-3', @jugadores = @alineacion, @mostrar = 0;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';

SELECT 'Preparación' AS caso, numero_partido, estado,
       (SELECT COUNT(*) FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido) AS formaciones
FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
GO


/* ============================================================================
   CAMBIO (XDA)
   ============================================================================ */

/* CA1 (OK) Alta de un cambio.
   Esperado: en el minuto 60 sale el dorsal 19 y entra el 16, por motivo TACTICO. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @sale INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xda AND j.dorsal = 19);
DECLARE @entra INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xda AND j.dorsal = 16);
DECLARE @id INT;
EXEC DesarrolloPartido.usp_CAMBIO_Alta @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra,
    @minuto = 60, @motivo = 'tactico', @id_cambio = @id OUTPUT;
SELECT 'CA1 después' AS caso, c.id_cambio, js.dorsal AS sale, je.dorsal AS entra, c.minuto, c.motivo
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.JUGADOR AS js ON js.id_jugador = c.id_jugador_sale
INNER JOIN Torneo.JUGADOR AS je ON je.id_jugador = c.id_jugador_entra
WHERE c.id_cambio = @id;
GO

/* CA2 (ERROR) Cambio con todos los datos mal.
   Esperado: error 50001 con 4 condiciones: el que entra (dorsal 3) es
   titular, el que sale (dorsal 19) ya había salido, el minuto 121 está fuera
   de rango y el motivo CANSANCIO no es válido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @sale INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xda AND j.dorsal = 19);
DECLARE @entra INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xda AND j.dorsal = 3);
BEGIN TRY
    EXEC DesarrolloPartido.usp_CAMBIO_Alta @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra,
        @minuto = 121, @motivo = 'CANSANCIO';
    PRINT N'CA2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CA2';
END CATCH;
GO

/* CA3 (ERROR) Jugadores de selecciones distintas y entretiempo en un minuto que no corresponde.
   Esperado: error 50001 con 2 condiciones: los dos jugadores tienen que ser
   de la misma selección y un cambio en el entretiempo va en el minuto 46, 91
   o 106. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @sale INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xda AND j.dorsal = 9);
DECLARE @entra INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xdb AND j.dorsal = 12);
BEGIN TRY
    EXEC DesarrolloPartido.usp_CAMBIO_Alta @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra,
        @minuto = 50, @motivo = 'TACTICO', @en_entretiempo = 1;
    PRINT N'CA3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CA3';
END CATCH;
GO

/* CA4 (OK) Modificación del minuto y del motivo.
   Esperado: el cambio pasa del minuto 60 al 62 y el motivo a LESION. */
DECLARE @id INT = (SELECT TOP (1) c.id_cambio FROM DesarrolloPartido.CAMBIO AS c INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
                   WHERE p.numero_partido = 210 ORDER BY c.id_cambio);
SELECT 'CA4 antes' AS caso, id_cambio, minuto, motivo FROM DesarrolloPartido.CAMBIO WHERE id_cambio = @id;
EXEC DesarrolloPartido.usp_CAMBIO_Modificacion @id_cambio = @id, @minuto = 62, @motivo = 'LESION';
SELECT 'CA4 después' AS caso, id_cambio, minuto, motivo FROM DesarrolloPartido.CAMBIO WHERE id_cambio = @id;
GO

/* CA5 (ERROR) Modificación a entretiempo en el minuto 62 con adicional fuera de rango.
   Esperado: error 50001 con 2 condiciones: el adicional no puede superar los
   30 minutos y un cambio en el entretiempo va en el minuto 46, 91 o 106. */
DECLARE @id INT = (SELECT TOP (1) c.id_cambio FROM DesarrolloPartido.CAMBIO AS c INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
                   WHERE p.numero_partido = 210 ORDER BY c.id_cambio);
BEGIN TRY
    EXEC DesarrolloPartido.usp_CAMBIO_Modificacion @id_cambio = @id, @en_entretiempo = 1, @minuto_adicional = 31;
    PRINT N'CA5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CA5';
END CATCH;
GO


/* ============================================================================
   GOL
   ============================================================================ */

/* G1 (OK) Gol del dorsal 16 de XDA (entró en el 62) con asistencia del 7.
   Esperado: un gol en el minuto 70, SEGUNDO_TIEMPO, tipo JUGADA; el marcador
   según los goles queda 1 - 0. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @autor INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xda AND j.dorsal = 16);
DECLARE @asiste INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xda AND j.dorsal = 7);
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @id INT;
EXEC DesarrolloPartido.usp_GOL_Alta @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
    @periodo = 'segundo_tiempo', @minuto = 70, @id_jugador_asistencia = @asiste, @id_gol = @id OUTPUT;
SELECT 'G1 después' AS caso, g.id_gol, ja.dorsal AS autor, js.dorsal AS asistencia, g.periodo, g.minuto, m.goles_local, m.goles_visitante
FROM DesarrolloPartido.GOL AS g
INNER JOIN Torneo.JUGADOR AS ja ON ja.id_jugador = g.id_jugador_autor
LEFT JOIN Torneo.JUGADOR AS js ON js.id_jugador = g.id_jugador_asistencia
CROSS APPLY DesarrolloPartido.fn_MarcadorSegunGoles(g.id_partido) AS m
WHERE g.id_gol = @id;
GO

/* G2 (ERROR) Gol de un jugador que no juega el partido, tipo inexistente y penal con minuto.
   Esperado: error 50001 con 3 condiciones: el autor (dorsal 23 de XDB, que
   no está en su formación) no figura en la formación, no existe el tipo de
   gol 99 y el minuto no corresponde al período PENALES. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @xdb_23 INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xdb AND j.dorsal = 23);
BEGIN TRY
    EXEC DesarrolloPartido.usp_GOL_Alta @id_partido = @id_partido, @id_jugador_autor = @xdb_23, @id_tipo_gol = 99,
        @periodo = 'PENALES', @minuto = 50;
    PRINT N'G2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'G2';
END CATCH;
GO

/* G3 (ERROR) Adicional sin minutos agregados y asistencia del rival.
   Esperado: error 50001 con 2 condiciones: el minuto no corresponde al
   período ADICIONALES (falta el adicional) y el que asiste tiene que ser de
   la misma selección que el autor. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xda INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @autor INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xda AND j.dorsal = 9);
DECLARE @asiste INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xdb AND j.dorsal = 9);
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_GOL_Alta @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
        @periodo = 'ADICIONALES', @minuto = 90, @minuto_adicional = 0, @id_jugador_asistencia = @asiste;
    PRINT N'G3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'G3';
END CATCH;
GO

/* G4 (ERROR) Gol en contra con asistencia.
   Esperado: error 50001 con 1 condición: un gol en contra no tiene asistencia. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @autor INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xdb AND j.dorsal = 3);
DECLARE @asiste INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xdb AND j.dorsal = 4);
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'EN CONTRA');
BEGIN TRY
    EXEC DesarrolloPartido.usp_GOL_Alta @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
        @periodo = 'PRIMER_TIEMPO', @minuto = 20, @id_jugador_asistencia = @asiste;
    PRINT N'G4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'G4';
END CATCH;
GO

/* G5 (OK) Modificación del minuto.
   Esperado: el gol pasa del minuto 70 al 75. */
DECLARE @id INT = (SELECT TOP (1) g.id_gol FROM DesarrolloPartido.GOL AS g INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
                   WHERE p.numero_partido = 210 ORDER BY g.id_gol);
SELECT 'G5 antes' AS caso, id_gol, periodo, minuto FROM DesarrolloPartido.GOL WHERE id_gol = @id;
EXEC DesarrolloPartido.usp_GOL_Modificacion @id_gol = @id, @minuto = 75;
SELECT 'G5 después' AS caso, id_gol, periodo, minuto FROM DesarrolloPartido.GOL WHERE id_gol = @id;
GO

/* G6 (ERROR) Período de alargue con un minuto del segundo tiempo.
   Esperado: error 50001 con 1 condición: el minuto no corresponde al período. */
DECLARE @id INT = (SELECT TOP (1) g.id_gol FROM DesarrolloPartido.GOL AS g INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
                   WHERE p.numero_partido = 210 ORDER BY g.id_gol);
BEGIN TRY
    EXEC DesarrolloPartido.usp_GOL_Modificacion @id_gol = @id, @periodo = 'ALARGUE';
    PRINT N'G6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'G6';
END CATCH;
GO

/* CA6 (ERROR) Baja de un cambio cuyo jugador ya hizo un gol.
   Esperado: error 50001 con 1 condición: el jugador que entró (dorsal 16)
   tiene 1 registro de DesarrolloPartido.GOL en el partido. */
DECLARE @id INT = (SELECT TOP (1) c.id_cambio FROM DesarrolloPartido.CAMBIO AS c INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
                   WHERE p.numero_partido = 210 ORDER BY c.id_cambio);
BEGIN TRY
    EXEC DesarrolloPartido.usp_CAMBIO_Baja @id_cambio = @id;
    PRINT N'CA6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CA6';
END CATCH;
GO

/* A9 (ERROR) Baja de un jugador con eventos en el partido.
   Esperado: error 50001 con 2 condiciones: el dorsal 16 de XDA tiene 1
   registro de DesarrolloPartido.CAMBIO (entró en el 62) y 1 de
   DesarrolloPartido.GOL (el de G1) en el partido. */
DECLARE @id_formacion INT = (SELECT f.id_formacion FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                             WHERE p.numero_partido = 210 AND f.id_seleccion = p.id_seleccion_local);
DECLARE @j16 INT = (SELECT j.id_jugador FROM DesarrolloPartido.ALINEACION AS a INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
                    WHERE a.id_formacion = @id_formacion AND j.dorsal = 16);
BEGIN TRY
    EXEC DesarrolloPartido.usp_ALINEACION_Baja @id_formacion = @id_formacion, @id_jugador = @j16;
    PRINT N'A9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'A9';
END CATCH;
GO

/* G7 (OK) Baja de un gol con el partido EN_JUEGO.
   Esperado: 1 gol antes y 0 después; el marcador según los goles vuelve a 0 - 0. */
DECLARE @id INT = (SELECT TOP (1) g.id_gol FROM DesarrolloPartido.GOL AS g INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
                   WHERE p.numero_partido = 210 ORDER BY g.id_gol);
DECLARE @id_partido INT = (SELECT id_partido FROM DesarrolloPartido.GOL WHERE id_gol = @id);
SELECT 'G7 antes' AS caso, goles_registrados, goles_local, goles_visitante FROM DesarrolloPartido.fn_MarcadorSegunGoles(@id_partido);
EXEC DesarrolloPartido.usp_GOL_Baja @id_gol = @id;
SELECT 'G7 después' AS caso, goles_registrados, goles_local, goles_visitante FROM DesarrolloPartido.fn_MarcadorSegunGoles(@id_partido);
GO

/* CA7 (OK) Baja de un cambio cuyo jugador ya no tiene eventos.
   Esperado: después de G7 el dorsal 16 ya no tiene goles, así que el cambio
   del minuto 62 se puede borrar: 1 cambio del partido 210 antes y 0 después. */
DECLARE @id INT = (SELECT TOP (1) c.id_cambio FROM DesarrolloPartido.CAMBIO AS c INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = c.id_partido
                   WHERE p.numero_partido = 210 ORDER BY c.id_cambio);
DECLARE @id_partido INT = (SELECT id_partido FROM DesarrolloPartido.CAMBIO WHERE id_cambio = @id);
SELECT 'CA7 antes' AS caso, COUNT(*) AS cambios FROM DesarrolloPartido.CAMBIO WHERE id_partido = @id_partido;
EXEC DesarrolloPartido.usp_CAMBIO_Baja @id_cambio = @id;
SELECT 'CA7 después' AS caso, COUNT(*) AS cambios FROM DesarrolloPartido.CAMBIO WHERE id_partido = @id_partido;
GO

/* G8 (ERROR) Baja de un gol de un partido finalizado.
   Esperado: error 50001 con 1 condición: el partido 211 está FINALIZADO y un
   gol solo se quita con el partido EN_JUEGO. */
DECLARE @id INT = (SELECT TOP (1) g.id_gol FROM DesarrolloPartido.GOL AS g INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
                   WHERE p.numero_partido = 211);
BEGIN TRY
    EXEC DesarrolloPartido.usp_GOL_Baja @id_gol = @id;
    PRINT N'G8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'G8';
END CATCH;
GO


/* ============================================================================
   AMONESTACION (XDB)
   ============================================================================ */

/* AM1 (OK) Amarilla al dorsal 5 de XDB.
   Esperado: una tarjeta AMARILLA en el minuto 30, sin doble amarilla. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @j INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xdb AND j.dorsal = 5);
DECLARE @id INT;
EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'amarilla', @minuto = 30,
    @motivo = 'Falta táctica', @id_jugador = @j, @id_amonestacion = @id OUTPUT;
SELECT 'AM1 después' AS caso, id_amonestacion, tipo_tarjeta, es_doble_amarilla, minuto, motivo FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id;
GO

/* AM2 (ERROR) Tarjeta con todos los datos mal.
   Esperado: error 50001 con 4 condiciones: la tarjeta la recibe exactamente
   un jugador o una persona del cuerpo técnico, el tipo AZUL no es válido, el
   minuto 125 está fuera de rango y el motivo es obligatorio. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @j INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xdb AND j.dorsal = 5);
DECLARE @ct INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @xdb AND rol = 'DIRECTOR_TECNICO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'AZUL', @minuto = 125,
        @motivo = ' ', @id_jugador = @j, @id_persona_ct = @ct;
    PRINT N'AM2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AM2';
END CATCH;
GO

/* AM3 (ERROR) Roja por doble amarilla con una sola amarilla.
   Esperado: error 50001 con 1 condición: una roja por doble amarilla
   necesita las dos amarillas registradas antes. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @j INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xdb AND j.dorsal = 5);
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'ROJA', @minuto = 35,
        @motivo = 'Doble amarilla', @id_jugador = @j, @es_doble_amarilla = 1;
    PRINT N'AM3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AM3';
END CATCH;
GO

/* AM4 (OK) Segunda amarilla y roja por doble amarilla, cargadas con el ABM.
   Esperado: el dorsal 5 queda con dos amarillas (30 y 40) y una roja con
   es_doble_amarilla = 1 en el minuto 40. (La roja automática la agrega el SP
   de negocio usp_RegistrarAmonestacion; acá se carga a mano.) */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @j INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xdb AND j.dorsal = 5);
EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 40,
    @motivo = 'Mano intencional', @id_jugador = @j;
EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'ROJA', @minuto = 40,
    @motivo = 'Doble amarilla', @id_jugador = @j, @es_doble_amarilla = 1;
SELECT 'AM4 después' AS caso, id_amonestacion, tipo_tarjeta, es_doble_amarilla, minuto, motivo
FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido AND id_jugador = @j ORDER BY id_amonestacion;
GO

/* AM5 (ERROR) Tarjeta a un jugador ya expulsado.
   Esperado: error 50001 con 1 condición: el receptor ya había sido
   expulsado en este partido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @xdb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @j INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista WHERE l.id_seleccion = @xdb AND j.dorsal = 5);
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'ROJA', @minuto = 50,
        @motivo = 'Insultos', @id_jugador = @j;
    PRINT N'AM5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AM5';
END CATCH;
GO

/* AM6 (ERROR) Baja de una amarilla que forma parte de la doble amarilla.
   Esperado: error 50001 con 1 condición: primero hay que dar de baja la roja. */
DECLARE @id INT = (SELECT TOP (1) a.id_amonestacion FROM DesarrolloPartido.AMONESTACION AS a INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
                   WHERE p.numero_partido = 210 AND a.tipo_tarjeta = 'AMARILLA' ORDER BY a.id_amonestacion);
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id;
    PRINT N'AM6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AM6';
END CATCH;
GO

/* AM7 (OK) Modificación del motivo de la primera amarilla.
   Esperado: el motivo pasa a "Falta táctica para cortar un contraataque". */
DECLARE @id INT = (SELECT TOP (1) a.id_amonestacion FROM DesarrolloPartido.AMONESTACION AS a INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
                   WHERE p.numero_partido = 210 AND a.tipo_tarjeta = 'AMARILLA' ORDER BY a.id_amonestacion);
SELECT 'AM7 antes' AS caso, id_amonestacion, motivo FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id;
EXEC DesarrolloPartido.usp_AMONESTACION_Modificacion @id_amonestacion = @id, @motivo = 'Falta táctica para cortar un contraataque';
SELECT 'AM7 después' AS caso, id_amonestacion, motivo FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id;
GO

/* AM8 (ERROR) Tarjeta al cuerpo técnico de una selección que no juega.
   Esperado: error 50001 con 1 condición: el director técnico de XDC no es
   del cuerpo técnico de una de las selecciones del partido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @ct INT = (SELECT ct.id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                   WHERE p.codigo_fifa = 'XDC' AND ct.rol = 'DIRECTOR_TECNICO');
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 55,
        @motivo = 'Protestar', @id_persona_ct = @ct;
    PRINT N'AM8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AM8';
END CATCH;
GO

/* AM9 (OK) Baja de la roja y después de una amarilla.
   Esperado: 3 tarjetas antes y 1 después. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id INT;
SELECT 'AM9 antes' AS caso, COUNT(*) AS tarjetas FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido;
SET @id = (SELECT id_amonestacion FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido AND tipo_tarjeta = 'ROJA');
EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id;
SET @id = (SELECT MAX(id_amonestacion) FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido);
EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id;
SELECT 'AM9 después' AS caso, COUNT(*) AS tarjetas FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido;
GO

/* AM10 (ERROR) Modificación con minuto, adicional y motivo fuera de rango.
   Esperado: error 50001 con 3 condiciones: el minuto 125 está fuera de rango,
   el adicional no puede superar los 30 minutos y el motivo supera los 200
   caracteres. La tarjeta que quedó (la amarilla del minuto 30) no cambia. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 210);
DECLARE @id INT = (SELECT MIN(id_amonestacion) FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido);
DECLARE @motivo_largo VARCHAR(400) = REPLICATE('Motivo demasiado largo. ', 10);
BEGIN TRY
    EXEC DesarrolloPartido.usp_AMONESTACION_Modificacion @id_amonestacion = @id, @minuto = 125,
        @minuto_adicional = 31, @motivo = @motivo_largo;
    PRINT N'AM10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AM10';
END CATCH;
SELECT 'AM10 después' AS caso, id_amonestacion, minuto, minuto_adicional, motivo
FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id;
GO


/* ============================================================================
   TIPO_GOL (baja del tipo de prueba)
   ============================================================================ */

/* TG6 (OK) Baja del tipo de prueba, una vez borrado el partido 211 (con su gol)
   con los SP de baja.
   Esperado: 1 tipo de prueba antes y 0 después. */
EXEC #usp_LimpiarPartido @numero_partido = 211;
DECLARE @id TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion LIKE 'PRUEBA%');
SELECT 'TG6 antes' AS caso, COUNT(*) AS tipos_de_prueba FROM DesarrolloPartido.TIPO_GOL WHERE descripcion LIKE 'PRUEBA%';
EXEC DesarrolloPartido.usp_TIPO_GOL_Baja @id_tipo_gol = @id;
SELECT 'TG6 después' AS caso, COUNT(*) AS tipos_de_prueba FROM DesarrolloPartido.TIPO_GOL WHERE descripcion LIKE 'PRUEBA%';
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (210, 211))                    AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DesarrolloPartido.TIPO_GOL WHERE descripcion LIKE 'PRUEBA%')         AS tipos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XDA', 'XDB', 'XDC'))        AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.JUGADOR WHERE apellido LIKE N'Prueba XD%')                     AS jugadores_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba DesarrolloPartido') AS sedes_de_prueba;
GO

SET NOEXEC OFF;
GO
