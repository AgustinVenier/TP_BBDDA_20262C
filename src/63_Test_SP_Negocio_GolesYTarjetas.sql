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
 Archivo: 63_Test_SP_Negocio_GolesYTarjetas.sql
 Objetivo: Probar los SP de 13_SP_Negocio_GolesYTarjetas.sql
           (usp_RegistrarGol y usp_RegistrarAmonestacion): goles con autor y
           asistente en cancha, gol en contra, alargue y penales solo con
           empate; tarjetas, roja automática por doble amarilla y cálculo de
           la suspensión (doble amarilla, roja directa y acumulación de
           amarillas en partidos distintos).
           Requiere haber ejecutado 00 a 20; no depende del juego de datos.
           Usa sus propios datos de prueba: la sede "Estadio Prueba Goles",
           dos selecciones de prueba (XGA y XGB, con 23 jugadores cada una),
           el partido 241 (XGA - XGB, de dieciseisavos, ya jugado, con una
           amarilla al dorsal 6 de XGA) y el partido de prueba 240 (XGA - XGB,
           de octavos). Todo se borra al empezar y al terminar, así que se
           puede ejecutar más de una vez.
           Los casos obligatorios se prueban acá con datos propios.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
     Las suspensiones que genera una tarjeta se informan en Mensajes
     ("Suspensión: ...") y en la consulta del SP.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'DesarrolloPartido.usp_RegistrarAmonestacion', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE descripcion IN ('JUGADA', 'EN CONTRA', 'PENAL', 'CABEZAZO')
                  HAVING COUNT(*) = 4)
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

-- Devuelve el id de un jugador por selección (código FIFA) y dorsal, entre los convocados activos.
IF OBJECT_ID(N'tempdb..#usp_Jugador', N'P') IS NOT NULL
    DROP PROCEDURE #usp_Jugador;
GO
CREATE PROCEDURE #usp_Jugador
    @codigo_fifa CHAR(3),
    @dorsal      TINYINT,
    @id_jugador  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @id_jugador = j.id_jugador
    FROM Torneo.JUGADOR AS j
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
    WHERE p.codigo_fifa = @codigo_fifa AND j.dorsal = @dorsal AND j.fecha_baja IS NULL;
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
    EXEC #usp_LimpiarPartido @numero_partido = 240;
    EXEC #usp_LimpiarPartido @numero_partido = 241;
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XGA';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XGB';
    SET @id = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Goles');
    IF @id IS NOT NULL
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;
END;
GO

EXEC #usp_LimpiarPruebas;
GO

-- Preparación: la sede y las selecciones de prueba, y el partido 241
-- (dieciseisavos, 25/08/2026) ya jugado, con una amarilla al dorsal 6 de XGA
-- cargada con el ABM (para el caso de acumulación de amarillas).
DECLARE @usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @xga INT, @xgb INT, @id_241 INT, @id_formacion INT, @xga_6 INT;
EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Goles', @ciudad = 'Kansas City', @id_pais = @usa,
    @capacidad = 76000, @huso_horario = 'Central Standard Time', @id_sede = @sede OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XGA', @id_seleccion = @xga OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XGB', @id_seleccion = @xgb OUTPUT;
EXEC #usp_Jugador @codigo_fifa = 'XGA', @dorsal = 6, @id_jugador = @xga_6 OUTPUT;

EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 241, @id_sede = @sede, @fase = 'DIECISEISAVOS', @fecha_hora_utc = '2026-08-25 20:00',
    @id_seleccion_local = @xga, @id_seleccion_visitante = @xgb, @id_partido = @id_241 OUTPUT;
EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_241, @id_seleccion = @xga,
    @esquema_tactico = '4-3-3', @id_formacion = @id_formacion OUTPUT;
EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @xga_6,
    @es_titular = 1, @posicion_en_cancha = 'DEFENSOR';
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_241, @estado = 'EN_JUEGO';
EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_241, @tipo_tarjeta = 'AMARILLA', @minuto = 40,
    @motivo = 'Falta táctica', @id_jugador = @xga_6;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_241, @estado = 'FINALIZADO', @goles_local = 1, @goles_visitante = 0;
GO

-- Preparación: partido de prueba 240 con las dos formaciones (dorsales 1 a 11 titulares, 12 a 22 suplentes).
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Goles');
DECLARE @xga INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XGA');
DECLARE @xgb INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XGB');
DECLARE @id_partido INT;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 240, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2026-08-30 20:00',
    @id_seleccion_local = @xga, @id_seleccion_visitante = @xgb, @id_partido = @id_partido OUTPUT;

DECLARE @alineacion DesarrolloPartido.TT_ALINEACION;
DECLARE @lado INT = 0, @id_sel INT;
WHILE @lado <= 1
BEGIN
    SET @id_sel = IIF(@lado = 0, @xga, @xgb);
    DELETE FROM @alineacion;
    INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
    SELECT j.id_jugador, IIF(j.dorsal <= 11, 1, 0), IIF(j.dorsal <= 11, j.posicion_habitual, NULL)
    FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    WHERE l.id_seleccion = @id_sel AND j.fecha_baja IS NULL AND j.dorsal <= 22;
    EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @id_sel,
        @esquema_tactico = '4-3-3', @jugadores = @alineacion, @mostrar = 0;
    SET @lado += 1;
END;

-- El partido empieza (con el ABM: este test no necesita la terna arbitral).
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';
GO


/* ============================================================================
   usp_RegistrarGol
   ============================================================================ */

/* GO1 (OK) Gol de XGA con asistencia.
   Esperado: gol del dorsal 9 en el minuto 20 con asistencia del 10; la
   consulta del SP muestra el marcador 1 - 0. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @autor INT, @asiste INT;
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
EXEC #usp_Jugador 'XGA', 9, @autor OUTPUT;
EXEC #usp_Jugador 'XGA', 10, @asiste OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
    @periodo = 'PRIMER_TIEMPO', @minuto = 20, @id_jugador_asistencia = @asiste;
GO

/* GO2 (ERROR) Autor y asistente que están en el banco.
   Esperado: error 50001 con 2 condiciones: el autor (dorsal 15 de XGB) y el que asiste (16) no estaban en cancha en ese minuto. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @autor INT, @asiste INT;
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
EXEC #usp_Jugador 'XGB', 15, @autor OUTPUT;
EXEC #usp_Jugador 'XGB', 16, @asiste OUTPUT;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
        @periodo = 'PRIMER_TIEMPO', @minuto = 30, @id_jugador_asistencia = @asiste;
    PRINT N'GO2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'GO2';
END CATCH;
GO

/* GO3 (OK) Gol en contra.
   Esperado: el dorsal 2 de XGB hace un gol en contra en el minuto
   35, que suma para XGA: el marcador pasa a 2 - 0. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @autor INT;
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'EN CONTRA');
EXEC #usp_Jugador 'XGB', 2, @autor OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
    @periodo = 'PRIMER_TIEMPO', @minuto = 35;
GO

/* GO4 (ERROR) Gol de alargue sin empate en los 90 minutos.
   Esperado: error 50001 con 1 condición: el partido no terminó empatado el
   tiempo reglamentario (2 - 0) y no hay alargue. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @autor INT;
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
EXEC #usp_Jugador 'XGB', 9, @autor OUTPUT;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
        @periodo = 'ALARGUE', @minuto = 100;
    PRINT N'GO4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'GO4';
END CATCH;
GO

/* GO5 (ERROR) Penal de definición sin empate.
   Esperado: error 50001 con 1 condición: el partido no está empatado (2 - 0)
   y no hay definición por penales. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @autor INT;
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
EXEC #usp_Jugador 'XGB', 9, @autor OUTPUT;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
        @periodo = 'PENALES';
    PRINT N'GO5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'GO5';
END CATCH;
GO

/* GO6 (OK) Empate de XGB y gol de XGA en el alargue.
   Esperado: goles de XGB en los minutos 60 y 90+3 (2 - 2 al terminar los 90
   minutos) y, ya con el empate, gol de XGA en el alargue (minuto 100): el
   marcador final es 3 - 2. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @autor INT;
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
EXEC #usp_Jugador 'XGB', 9, @autor OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
    @periodo = 'SEGUNDO_TIEMPO', @minuto = 60, @mostrar = 0;
EXEC #usp_Jugador 'XGB', 11, @autor OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
    @periodo = 'ADICIONALES', @minuto = 90, @minuto_adicional = 3, @mostrar = 0;
EXEC #usp_Jugador 'XGA', 10, @autor OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @autor, @id_tipo_gol = @tipo,
    @periodo = 'ALARGUE', @minuto = 100;
SELECT 'GO6 después' AS caso, goles_local, goles_visitante, goles_local_90, goles_visitante_90
FROM DesarrolloPartido.fn_MarcadorSegunGoles(@id_partido);
GO

/* GO7 (ERROR) Gol de un jugador que ya había salido.
   El dorsal 9 de XGA sale en el minuto 70 (con usp_RegistrarCambio).
   Esperado: error 50001 con 1 condición: el autor no estaba en cancha en el
   minuto 80. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @sale INT, @entra INT;
DECLARE @tipo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
EXEC #usp_Jugador 'XGA', 9, @sale OUTPUT;
EXEC #usp_Jugador 'XGA', 19, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra,
    @minuto = 70, @motivo = 'TACTICO';
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id_partido, @id_jugador_autor = @sale, @id_tipo_gol = @tipo,
        @periodo = 'SEGUNDO_TIEMPO', @minuto = 80;
    PRINT N'GO7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'GO7';
END CATCH;
GO


/* ============================================================================
   usp_RegistrarAmonestacion
   ============================================================================ */

/* TA1 (OK) Primera amarilla de un jugador sin tarjetas en el torneo.
   Esperado: la consulta del SP muestra 1 amarilla en el partido y
   "SIN SUSPENSION". */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @xgb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @j INT = (SELECT TOP (1) j.id_jugador
                  FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                  WHERE l.id_seleccion = @xgb AND j.dorsal BETWEEN 3 AND 8
                    AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION AS a WHERE a.id_jugador = j.id_jugador)
                  ORDER BY j.dorsal);
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 25,
    @motivo = 'Falta imprudente', @id_jugador = @j;
GO

/* TA2 (OK) Caso obligatorio: expulsión por doble amarilla.
   Esperado: la segunda amarilla del mismo jugador registra, en la misma
   transacción, la ROJA con es_doble_amarilla = 1 en el minuto 50. En
   Mensajes aparece la suspensión por DOBLE AMARILLA (1 partido). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @j INT = (SELECT id_jugador FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido AND minuto = 25);
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 50,
    @motivo = 'Sujetar a un rival', @id_jugador = @j;
SELECT 'TA2 después' AS caso, id_amonestacion, tipo_tarjeta, es_doble_amarilla, minuto, motivo
FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido AND id_jugador = @j ORDER BY id_amonestacion;
GO

/* TA3 (ERROR) Tarjeta a un jugador ya expulsado.
   Esperado: el error 50001 lo informa DesarrolloPartido.usp_AMONESTACION_Alta:
   el receptor ya había sido expulsado en este partido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @j INT = (SELECT id_jugador FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido AND minuto = 25);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 60,
        @motivo = 'Protestar', @id_jugador = @j;
    PRINT N'TA3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'TA3';
END CATCH;
GO

/* TA4 (OK) Caso obligatorio: suspensión por acumulación de amarillas.
   El dorsal 6 de XGA, que ya vio una amarilla en el partido 241
   (dieciseisavos), ve otra en este partido (octavos): dieciseisavos, octavos
   y cuartos son el mismo tramo, así que las amarillas se acumulan.
   Esperado: en Mensajes, "Suspensión: ... no puede jugar los próximos 1
   partido(s) de su selección (ACUMULACION DE AMARILLAS)", y la consulta del
   SP muestra esa suspensión. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @xga INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @j INT = (SELECT TOP (1) j.id_jugador
                  FROM Torneo.JUGADOR AS j
                  INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                  WHERE l.id_seleccion = @xga AND j.dorsal <= 22 AND j.fecha_baja IS NULL
                    AND (SELECT COUNT(DISTINCT a.id_partido) FROM DesarrolloPartido.AMONESTACION AS a
                         WHERE a.id_jugador = j.id_jugador AND a.tipo_tarjeta = 'AMARILLA') = 1
                    AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION AS r
                                    WHERE r.id_jugador = j.id_jugador AND r.tipo_tarjeta = 'ROJA')
                  ORDER BY j.dorsal);
SELECT 'TA4 antes' AS caso, j.dorsal, j.apellido, p.numero_partido AS partido_con_amarilla_previa
FROM Torneo.JUGADOR AS j
INNER JOIN DesarrolloPartido.AMONESTACION AS a ON a.id_jugador = j.id_jugador
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
WHERE j.id_jugador = @j;
IF @j IS NULL
    PRINT N'TA4: FALLÓ, no hay un jugador de XGA con una sola amarilla (falta la preparación del partido 241).';
ELSE
    EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 75,
        @motivo = 'Demorar la reanudación', @id_jugador = @j;
GO

/* TA5 (OK) Caso obligatorio: roja directa.
   Esperado: ROJA sin doble amarilla en el minuto 85 a un titular de XGA sin
   tarjetas en el torneo; en Mensajes, la suspensión por ROJA DIRECTA (1
   partido). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @xga INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @j INT = (SELECT TOP (1) j.id_jugador
                  FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                  WHERE l.id_seleccion = @xga AND j.dorsal BETWEEN 2 AND 8
                    AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION AS a WHERE a.id_jugador = j.id_jugador)
                  ORDER BY j.dorsal);
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'ROJA', @minuto = 85,
    @motivo = 'Agresión a un rival', @id_jugador = @j;
GO

/* TA6 (OK) Amarilla al director técnico de XGB.
   Esperado: una AMARILLA para una persona del cuerpo técnico (las
   suspensiones se calculan solo para jugadores). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @xgb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @dt INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @xgb AND rol = 'DIRECTOR_TECNICO');
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 88,
    @motivo = 'Salir del área técnica', @id_persona_ct = @dt;
SELECT 'TA6 después' AS caso, ct.apellido, ct.rol, a.tipo_tarjeta, a.minuto, a.motivo
FROM DesarrolloPartido.AMONESTACION AS a INNER JOIN Torneo.PERSONA_CUERPO_TECNICO AS ct ON ct.id_persona_ct = a.id_persona_ct
WHERE a.id_partido = @id_partido;
GO

/* TA7 (ERROR) Tarjeta en un partido que no existe y a un jugador que no juega.
   Esperado: dos errores 50001. TA7a, de usp_RegistrarAmonestacion: no existe
   el partido -1. TA7b, de usp_AMONESTACION_Alta: el jugador (dorsal 23 de
   XGB, que no está en su formación) no figura en la formación del partido. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 240);
DECLARE @arg9 INT;
EXEC #usp_Jugador 'XGB', 23, @arg9 OUTPUT;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = -1, @tipo_tarjeta = 'AMARILLA', @minuto = 10,
        @motivo = 'Falta', @id_jugador = @arg9;
    PRINT N'TA7a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'TA7a';
END CATCH;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 10,
        @motivo = 'Falta', @id_jugador = @arg9;
    PRINT N'TA7b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'TA7b';
END CATCH;
GO

-- Evidencia: sanciones que generó el partido de prueba (fn_Sanciones).
SELECT 'Sanciones del partido 240' AS caso, j.dorsal, j.apellido, s.motivo, s.partidos_de_suspension
FROM DesarrolloPartido.fn_Sanciones() AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = s.id_partido_origen
WHERE p.numero_partido = 240
ORDER BY s.motivo;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (240, 241))         AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XGA', 'XGB'))    AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.JUGADOR WHERE apellido LIKE N'Prueba XG%')          AS jugadores_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Goles') AS sedes_de_prueba;
GO

SET NOEXEC OFF;
GO
