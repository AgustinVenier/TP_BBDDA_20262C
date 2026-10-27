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
 Archivo: 60_Test_SP_Negocio_SedesYPartidos.sql
 Objetivo: Probar los SP de 10_SP_Negocio_SedesYPartidos.sql
           (usp_RegistrarSede, usp_IniciarPartido y usp_FinalizarPartido),
           con casos exitosos y su evidencia y casos que no cumplen las
           validaciones. Requiere haber ejecutado 00 a 20; no depende del juego de
           datos.
           Usa una sede de prueba ("Estadio Prueba Negocio"), dos selecciones
           de prueba (XNA y XNB, con 23 jugadores cada una), cinco árbitros de
           prueba ("Prueba Negocio 1" a "5", del país de prueba XNN, sin
           selección) y un partido de prueba (225,
           XNA - XNB, de octavos), con formaciones, árbitros y goles cargados
           con los SP de negocio. Todo se borra al empezar y al terminar, así
           que se puede ejecutar más de una vez.
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

IF OBJECT_ID(N'Torneo.usp_RegistrarSede', N'P') IS NULL
   OR OBJECT_ID(N'Arbitraje.usp_DesignarTernaArbitral', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE descripcion IN ('JUGADA', 'CABEZAZO', 'PENAL') HAVING COUNT(*) = 3)
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

-- Da de alta con los SP una selección de prueba: el país "Prueba <código>", la
-- selección con su lista presentada el 01/06/2026, su director técnico
-- ("Prueba DT <código>") y 23 jugadores ("Prueba <código> <dorsal>"):
-- arqueros 1, 12 y 23; defensores 2 a 6 y 13 a 15; mediocampistas 7, 8, 10 y
-- 16 a 18; delanteros 9, 11 y 19 a 22.
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
    DECLARE @id_pais SMALLINT, @id_lista INT, @i INT = 1, @dorsal TINYINT, @posicion VARCHAR(15), @apellido NVARCHAR(60);
    DECLARE @plantel TABLE (orden INT IDENTITY(1,1), dorsal TINYINT, posicion VARCHAR(15));

    EXEC DatosGenerales.usp_PAIS_Alta @nombre = @nombre, @huso_horario = 'UTC', @codigo_fifa = @codigo_fifa,
        @id_pais = @id_pais OUTPUT;
    EXEC Torneo.usp_RegistrarSeleccion
        @id_pais = @id_pais, @confederacion = 'UEFA', @grupo = NULL, @fecha_presentacion = '2026-06-01',
        @dt_nombre = N'Director', @dt_apellido = @dt_apellido, @id_seleccion = @id_seleccion OUTPUT, @mostrar = 0;

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
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_amonestacion FROM DesarrolloPartido.AMONESTACION
        WHERE id_partido = @id_partido ORDER BY IIF(tipo_tarjeta = 'ROJA', 0, 1);
        EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id;
    END;
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
    DECLARE @id INT, @id2 INT;

    EXEC #usp_LimpiarPartido @numero_partido = 225;

    WHILE EXISTS (SELECT 1 FROM Arbitraje.ARBITRO WHERE apellido LIKE N'Prueba Negocio%')
    BEGIN
        SELECT TOP (1) @id = id_arbitro FROM Arbitraje.ARBITRO WHERE apellido LIKE N'Prueba Negocio%';
        EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id, @eliminar_registro = 1;
    END;

    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XNA';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XNB';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XNN';  -- el país de los árbitros, sin selección

    WHILE EXISTS (SELECT 1 FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Negocio%')
    BEGIN
        SELECT TOP (1) @id = id_sede FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Negocio%';
        WHILE EXISTS (SELECT 1 FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id)
        BEGIN
            SELECT TOP (1) @id2 = id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id;
            EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Baja @id_espacio = @id2;
        END;
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;
    END;
END;
GO

EXEC #usp_LimpiarPruebas;
GO


/* ============================================================================
   usp_RegistrarSede
   ============================================================================ */

/* RS1 (OK) Alta de una sede con sus cuatro espacios en una sola transacción.
   Esperado: la consulta del SP muestra la sede con los espacios 1 a 4 y sus
   tarifas; en la tabla quedan 4 espacios para la sede nueva. */
DECLARE @per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @id INT;
EXEC Torneo.usp_RegistrarSede
    @nombre_estadio = 'Estadio Prueba Negocio', @ciudad = 'Lima', @id_pais = @per, @capacidad = 50000,
    @huso_horario = 'SA Pacific Standard Time', @tarifa_espacio_1 = 70000, @tarifa_espacio_2 = 60000,
    @tarifa_espacio_3 = 50000, @tarifa_espacio_4 = 40000, @latitud = -12.067800, @longitud = -77.033600,
    @id_sede = @id OUTPUT;
SELECT 'RS1 después' AS caso, COUNT(*) AS espacios_de_la_sede FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id;
GO

/* RS2 (ERROR) Tarifas faltantes y negativas.
   Esperado: error 50001 de Torneo.usp_RegistrarSede con 2 condiciones: las
   tarifas de los 4 espacios son obligatorias y no pueden ser negativas. No
   se crea la sede. */
DECLARE @per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
BEGIN TRY
    EXEC Torneo.usp_RegistrarSede
        @nombre_estadio = 'Estadio Prueba Negocio 2', @ciudad = 'Cusco', @id_pais = @per, @capacidad = 20000,
        @huso_horario = 'SA Pacific Standard Time', @tarifa_espacio_1 = 1000, @tarifa_espacio_2 = -5,
        @tarifa_espacio_3 = NULL, @tarifa_espacio_4 = 1000;
    PRINT N'RS2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RS2';
END CATCH;
SELECT 'RS2 después' AS caso, COUNT(*) AS sedes FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Negocio 2';
GO

/* RS3 (ERROR) Datos de la sede que no pasan las validaciones del ABM.
   Esperado: el error 50001 lo informa Torneo.usp_SEDE_Alta, con 2
   condiciones (ya existe la sede "Estadio Prueba Negocio", dada de alta en
   RS1, y el huso no existe); la transacción se deshace y la cantidad de
   espacios publicitarios no cambia. */
DECLARE @per SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'PER');
DECLARE @espacios_antes INT = (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO);
BEGIN TRY
    EXEC Torneo.usp_RegistrarSede
        @nombre_estadio = 'Estadio Prueba Negocio', @ciudad = 'Arequipa', @id_pais = @per, @capacidad = 40000,
        @huso_horario = 'Hora del Pacífico Sur', @tarifa_espacio_1 = 1, @tarifa_espacio_2 = 1,
        @tarifa_espacio_3 = 1, @tarifa_espacio_4 = 1;
    PRINT N'RS3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RS3';
END CATCH;
SELECT 'RS3 después' AS caso, @espacios_antes AS espacios_antes, COUNT(*) AS espacios_despues FROM Publicidad.ESPACIO_PUBLICITARIO;
GO


/* ============================================================================
   usp_IniciarPartido
   ============================================================================ */

-- Preparación: las selecciones de prueba XNA y XNB, cinco árbitros de prueba
-- (categoría FIFA) del país de prueba XNN, que no tiene selección, y el partido
-- de prueba 225 en la sede nueva, todavía sin formaciones ni árbitros. Como XNN
-- no tiene selección, la designación no da conflicto de nacionalidad ni
-- advertencias de posible cruce, haya o no otras selecciones cargadas.
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Negocio');
DECLARE @xna INT, @xnb INT, @xnn SMALLINT, @i INT = 1, @apellido NVARCHAR(60);

EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XNA', @id_seleccion = @xna OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XNB', @id_seleccion = @xnb OUTPUT;
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XNN', @huso_horario = 'UTC', @codigo_fifa = 'XNN', @id_pais = @xnn OUTPUT;
WHILE @i <= 5
BEGIN
    SET @apellido = CONCAT(N'Prueba Negocio ', @i);
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @xnn, @nombre = N'Árbitro', @apellido = @apellido, @categoria = 'FIFA';
    SET @i += 1;
END;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 225, @id_sede = @sede, @fase = 'OCTAVOS',
    @fecha_hora_utc = '2026-08-20 20:00', @id_seleccion_local = @xna, @id_seleccion_visitante = @xnb;
GO

/* IP1 (ERROR) Partido sin formaciones ni árbitros.
   Esperado: error 50001 con 3 condiciones: XNA y XNB tienen 0 titulares
   cargados, y falta designar PRINCIPAL, ASISTENTE_1, ASISTENTE_2, CUARTO y
   VAR. El partido sigue PROGRAMADO. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
BEGIN TRY
    EXEC Torneo.usp_IniciarPartido @id_partido = @id_partido;
    PRINT N'IP1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IP1';
END CATCH;
SELECT 'IP1 después' AS caso, numero_partido, estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
GO

-- Preparación: formaciones de las dos selecciones y terna arbitral, con los SP de negocio.
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
DECLARE @alineacion DesarrolloPartido.TT_ALINEACION;
DECLARE @lado INT = 0, @id_sel INT;

WHILE @lado <= 1
BEGIN
    SELECT @id_sel = IIF(@lado = 0, id_seleccion_local, id_seleccion_visitante) FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
    DELETE FROM @alineacion;
    INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
    SELECT j.id_jugador, IIF(j.dorsal <= 11, 1, 0), IIF(j.dorsal <= 11, j.posicion_habitual, NULL)
    FROM Torneo.JUGADOR AS j
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    WHERE l.id_seleccion = @id_sel AND j.fecha_baja IS NULL AND j.dorsal <= 18;
    EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @id_sel,
        @esquema_tactico = '4-3-3', @jugadores = @alineacion, @mostrar = 0;
    SET @lado += 1;
END;

DECLARE @principal INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Negocio 1');
DECLARE @asis1 INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Negocio 2');
DECLARE @asis2 INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Negocio 3');
DECLARE @cuarto INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Negocio 4');
DECLARE @var INT = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Negocio 5');
EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido, @id_principal = @principal,
    @id_asistente_1 = @asis1, @id_asistente_2 = @asis2, @id_cuarto = @cuarto, @id_var = @var, @mostrar = 0;
GO

-- IP2 (iniciar un partido que ya se jugó) se prueba al final, con el partido 225 terminado.

/* IP3 (OK) Inicio del partido con formaciones y terna completas.
   Esperado: el partido 225 pasa de PROGRAMADO a EN_JUEGO. Como no tiene
   publicidad asignada, en Mensajes aparece la advertencia "el partido
   empieza con 0 de sus 4 espacios publicitarios asignados". */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
SELECT 'IP3 antes' AS caso, numero_partido, estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
EXEC Torneo.usp_IniciarPartido @id_partido = @id_partido;
SELECT 'IP3 después' AS caso, numero_partido, estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
GO


/* ============================================================================
   usp_FinalizarPartido
   ============================================================================ */

-- Gol de XNA en el minuto 30, con el SP de negocio.
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
DECLARE @xna INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @autor INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                      WHERE l.id_seleccion = @xna AND j.dorsal = 9);
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
    @periodo = 'PRIMER_TIEMPO', @minuto = 30, @mostrar = 0;
GO

/* FP1 (ERROR) Resultado informado que no coincide con los goles registrados.
   Esperado: error 50001 con 1 condición: el resultado no coincide con los
   goles registrados (1 - 0). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
BEGIN TRY
    EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido, @goles_local = 2, @goles_visitante = 0;
    PRINT N'FP1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'FP1';
END CATCH;
GO

-- Empata XNB en el minuto 80.
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
DECLARE @xnb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @autor INT = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                      WHERE l.id_seleccion = @xnb AND j.dorsal = 10);
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
    @periodo = 'SEGUNDO_TIEMPO', @minuto = 80, @mostrar = 0;
GO

/* FP2 (ERROR) Empate en eliminación directa sin definición por penales.
   Esperado: error 50001 con 1 condición: el partido de eliminación directa
   terminó empatado y falta la definición por penales. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
BEGIN TRY
    EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido;
    PRINT N'FP2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'FP2';
END CATCH;
GO

-- Definición por penales: XNA convierte 3 y XNB 2.
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
DECLARE @penal TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
DECLARE @pateadores TABLE (orden INT IDENTITY(1,1), id_jugador INT);
INSERT INTO @pateadores (id_jugador)
SELECT j.id_jugador
FROM Torneo.PARTIDO AS p
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)
INNER JOIN Torneo.JUGADOR AS j ON j.id_lista = l.id_lista
WHERE p.id_partido = @id_partido
  AND ((l.id_seleccion = p.id_seleccion_local AND j.dorsal IN (9, 10, 11))
       OR (l.id_seleccion = p.id_seleccion_visitante AND j.dorsal IN (9, 11)));
DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @pateadores), @j INT;
WHILE @i <= @n
BEGIN
    SELECT @j = id_jugador FROM @pateadores WHERE orden = @i;
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @j, @id_tipo_gol = @penal,
        @periodo = 'PENALES', @mostrar = 0;
    SET @i += 1;
END;
GO

/* FP3 (ERROR) Asistencia mayor que la capacidad de la sede.
   Esperado: el error 50001 lo informa Torneo.usp_PARTIDO_Modificacion, con
   1 condición: la asistencia (60000) supera la capacidad de la sede (50000).
   El partido sigue EN_JUEGO. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
BEGIN TRY
    EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido, @asistencia = 60000;
    PRINT N'FP3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'FP3';
END CATCH;
SELECT 'FP3 después' AS caso, numero_partido, estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
GO

/* FP4 (OK) Cierre del partido con el resultado de los goles registrados.
   Esperado: sin informar goles, el partido queda FINALIZADO 1 - 1 y 3 - 2
   por penales, con 45000 espectadores. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
SELECT 'FP4 antes' AS caso, numero_partido, resultado, estado FROM Torneo.vw_Fixture WHERE id_partido = @id_partido;
EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido, @asistencia = 45000;
GO

/* FP5 (ERROR) Finalizar un partido ya finalizado.
   Esperado: error 50001 con 1 condición: solo se finaliza un partido EN_JUEGO. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
BEGIN TRY
    EXEC Torneo.usp_FinalizarPartido @id_partido = @id_partido;
    PRINT N'FP5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'FP5';
END CATCH;
GO

/* IP2 (ERROR) Iniciar un partido que ya se jugó.
   Esperado: error 50001 con 1 condición: el partido 225 está FINALIZADO y
   solo empieza un partido PROGRAMADO. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 225);
BEGIN TRY
    EXEC Torneo.usp_IniciarPartido @id_partido = @id_partido;
    PRINT N'IP2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IP2';
END CATCH;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Negocio%') AS sedes_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido = 225)                     AS partidos_de_prueba,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO WHERE apellido LIKE N'Prueba Negocio%')       AS arbitros_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XNA', 'XNB', 'XNN'))  AS paises_de_prueba;
GO

SET NOEXEC OFF;
GO
