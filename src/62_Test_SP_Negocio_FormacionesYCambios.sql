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
 Archivo: 62_Test_SP_Negocio_FormacionesYCambios.sql
 Objetivo: Probar los SP de 12_SP_Negocio_FormacionesYCambios.sql
           (usp_RegistrarFormacion y usp_RegistrarCambio) y la reconstrucción
           del equipo en cancha con fn_EquipoEnCancha: casos exitosos con su
           evidencia y casos que no cumplen el reglamento (titulares, arquero,
           suspendidos, jugador en cancha, máximo de cambios y ventanas, cambio
           extra del alargue). Requiere haber ejecutado 00 a 20; no depende del
           juego de datos.
           Usa sus propios datos de prueba: la sede "Estadio Prueba
           Formaciones", dos selecciones de prueba (XFA y XFB, con 23
           jugadores cada una), el partido 236 (XFA - XFB, ya jugado, con una
           roja directa al dorsal 3 de XFA, que queda suspendido) y el partido
           de prueba 235 (XFA - XFB, de octavos). Todo se borra al empezar y al
           terminar.
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

IF OBJECT_ID(N'DesarrolloPartido.usp_RegistrarFormacion', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo IN ('MAX_CAMBIOS', 'MAX_VENTANAS') HAVING COUNT(*) = 2)
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
    DECLARE @id INT;
    EXEC #usp_LimpiarPartido @numero_partido = 235;
    EXEC #usp_LimpiarPartido @numero_partido = 236;
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XFA';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XFB';
    SET @id = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Formaciones');
    IF @id IS NOT NULL
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;
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

EXEC #usp_LimpiarPruebas;
GO

-- Preparación: la sede y las selecciones de prueba, el partido 236 (dieciseisavos,
-- 22/08/2026) ya jugado, con una roja directa al dorsal 3 de XFA, que queda
-- suspendido para su partido siguiente, y el partido de prueba 235 (octavos).
DECLARE @usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT, @xfa INT, @xfb INT, @id_236 INT, @id_formacion INT, @xfa_3 INT;
EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Formaciones', @ciudad = 'Seattle', @id_pais = @usa,
    @capacidad = 68000, @huso_horario = 'Pacific Standard Time', @id_sede = @sede OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XFA', @id_seleccion = @xfa OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XFB', @id_seleccion = @xfb OUTPUT;
EXEC #usp_Jugador @codigo_fifa = 'XFA', @dorsal = 3, @id_jugador = @xfa_3 OUTPUT;

EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 236, @id_sede = @sede, @fase = 'DIECISEISAVOS', @fecha_hora_utc = '2026-08-22 03:00',
    @id_seleccion_local = @xfa, @id_seleccion_visitante = @xfb, @id_partido = @id_236 OUTPUT;
EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_236, @id_seleccion = @xfa,
    @esquema_tactico = '4-3-3', @id_formacion = @id_formacion OUTPUT;
EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @xfa_3,
    @es_titular = 1, @posicion_en_cancha = 'DEFENSOR';
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_236, @estado = 'EN_JUEGO';
EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_236, @tipo_tarjeta = 'ROJA', @minuto = 88,
    @motivo = 'Juego brusco grave', @id_jugador = @xfa_3;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_236, @estado = 'FINALIZADO', @goles_local = 1, @goles_visitante = 0;

EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 235, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2026-08-28 03:00',
    @id_seleccion_local = @xfa, @id_seleccion_visitante = @xfb;

SELECT 'Preparación' AS caso, s.motivo, s.numero_partido_origen, j.dorsal, j.apellido
FROM DesarrolloPartido.fn_JugadoresSuspendidos((SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235)) AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador;
GO


/* ============================================================================
   usp_RegistrarFormacion
   ============================================================================ */

/* RF1 (ERROR) Formación con todos los problemas posibles.
   10 titulares (dos como ARQUERO, uno sin posición y uno repetido), un
   jugador de XFB, el dorsal 3 de XFA (suspendido) en el banco y una
   fila sin jugador.
   Esperado: error 50001 con 7 condiciones en un solo mensaje, entre ellas
   "Suspendido: 3 ... (ROJA DIRECTA en el partido 236)". No se crea la
   formación. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @xfa INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @alineacion DesarrolloPartido.TT_ALINEACION;
DECLARE @j1 INT, @j12 INT, @j4 INT, @j5 INT, @j6 INT, @j7 INT, @j8 INT, @j9 INT, @j3 INT, @xfb9 INT;
EXEC #usp_Jugador 'XFA', 1, @j1 OUTPUT;   EXEC #usp_Jugador 'XFA', 12, @j12 OUTPUT;
EXEC #usp_Jugador 'XFA', 4, @j4 OUTPUT;   EXEC #usp_Jugador 'XFA', 5, @j5 OUTPUT;
EXEC #usp_Jugador 'XFA', 6, @j6 OUTPUT;   EXEC #usp_Jugador 'XFA', 7, @j7 OUTPUT;
EXEC #usp_Jugador 'XFA', 8, @j8 OUTPUT;   EXEC #usp_Jugador 'XFA', 9, @j9 OUTPUT;
EXEC #usp_Jugador 'XFA', 3, @j3 OUTPUT;   EXEC #usp_Jugador 'XFB', 9, @xfb9 OUTPUT;
INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
VALUES (@j1, 1, 'ARQUERO'), (@j12, 1, 'ARQUERO'), (@j4, 1, NULL), (@j5, 1, 'DEFENSOR'), (@j5, 1, 'DEFENSOR'),
       (@j6, 1, 'DEFENSOR'), (@j7, 1, 'MEDIOCAMPISTA'), (@j8, 1, 'MEDIOCAMPISTA'), (@j9, 1, 'DELANTERO'),
       (@xfb9, 1, 'DELANTERO'), (@j3, 0, NULL), (NULL, 0, NULL);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @xfa,
        @esquema_tactico = '4-3-3', @jugadores = @alineacion;
    PRINT N'RF1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RF1';
END CATCH;
SELECT 'RF1 después' AS caso, COUNT(*) AS formaciones FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido;
GO

/* RF2 (OK) Formaciones válidas de las dos selecciones.
   Esperado: la consulta del SP muestra, para XFA, 11 titulares (dorsales 1,
   2, 4 a 11 y el 13, que juega por el 3) y un banco de 10 sin el dorsal 3,
   que está suspendido. XFB queda con 11 titulares y 11 suplentes. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @alineacion DesarrolloPartido.TT_ALINEACION;
DECLARE @lado INT = 0, @id_sel INT, @esquema VARCHAR(10);

WHILE @lado <= 1
BEGIN
    SELECT @id_sel = IIF(@lado = 0, id_seleccion_local, id_seleccion_visitante) FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
    DELETE FROM @alineacion;
    INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
    SELECT j.id_jugador, IIF(j.dorsal <= 11, 1, 0), IIF(j.dorsal <= 11, j.posicion_habitual, NULL)
    FROM Torneo.JUGADOR AS j
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    WHERE l.id_seleccion = @id_sel AND j.fecha_baja IS NULL AND j.dorsal <= 22
      AND NOT EXISTS (SELECT 1 FROM DesarrolloPartido.fn_JugadoresSuspendidos(@id_partido) AS s WHERE s.id_jugador = j.id_jugador);
    -- XFA reemplaza al dorsal 3 suspendido por el 13 entre los titulares.
    UPDATE @alineacion SET es_titular = 1, posicion_en_cancha = 'DEFENSOR'
    WHERE @lado = 0 AND id_jugador = (SELECT j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l
                                      ON l.id_lista = j.id_lista WHERE l.id_seleccion = @id_sel AND j.dorsal = 13);
    SET @esquema = IIF(@lado = 0, '4-3-3', '4-4-2');
    IF @lado = 0
        EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @id_sel,
            @esquema_tactico = @esquema, @jugadores = @alineacion;
    ELSE
        EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @id_sel,
            @esquema_tactico = @esquema, @jugadores = @alineacion, @mostrar = 0;
    SET @lado += 1;
END;

SELECT 'RF2 después' AS caso, pa.nombre AS seleccion, f.esquema_tactico,
       SUM(IIF(a.es_titular = 1, 1, 0)) AS titulares, SUM(IIF(a.es_titular = 0, 1, 0)) AS suplentes
FROM DesarrolloPartido.FORMACION AS f
INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = f.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
WHERE f.id_partido = @id_partido
GROUP BY pa.nombre, f.esquema_tactico;
GO

/* RF3 (ERROR) Segunda formación para la misma selección.
   Esperado: el error 50001 lo informa DesarrolloPartido.usp_FORMACION_Alta
   (la selección ya tiene formación para ese partido) y no se agrega ninguna
   alineación. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @xfa INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @antes INT = (SELECT COUNT(*) FROM DesarrolloPartido.ALINEACION AS a INNER JOIN DesarrolloPartido.FORMACION AS f
                      ON f.id_formacion = a.id_formacion WHERE f.id_partido = @id_partido);
DECLARE @alineacion DesarrolloPartido.TT_ALINEACION;
INSERT INTO @alineacion (id_jugador, es_titular, posicion_en_cancha)
SELECT j.id_jugador, 1, IIF(j.dorsal = 1, 'ARQUERO', j.posicion_habitual)
FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
WHERE l.id_seleccion = @xfa AND j.dorsal IN (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13);
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = @id_partido, @id_seleccion = @xfa,
        @esquema_tactico = '4-3-3', @jugadores = @alineacion;
    PRINT N'RF3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RF3';
END CATCH;
SELECT 'RF3 después' AS caso, @antes AS alineados_antes, COUNT(*) AS alineados_despues
FROM DesarrolloPartido.ALINEACION AS a INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
WHERE f.id_partido = @id_partido;
GO

-- El partido empieza (con el ABM: este test no necesita la terna arbitral).
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';
GO


/* ============================================================================
   usp_RegistrarCambio (XFA)
   ============================================================================ */

/* RC1 (OK) Caso obligatorio: cambio por lesión dentro de los primeros 20 minutos.
   Esperado: en el minuto 15 sale el dorsal 4 por LESION y entra el 14. Con
   fn_EquipoEnCancha, en el minuto 14 está el 4 y en el 16 está el 14. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @xfa INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFA', 4, @sale OUTPUT;
EXEC #usp_Jugador 'XFA', 14, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 15, @motivo = 'LESION';
SELECT 'RC1 después' AS caso, m.minuto, STRING_AGG(CAST(e.dorsal AS VARCHAR(3)), ', ') WITHIN GROUP (ORDER BY e.dorsal) AS en_cancha
FROM (VALUES (CAST(14 AS TINYINT)), (CAST(16 AS TINYINT))) AS m (minuto)
CROSS APPLY DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @xfa, m.minuto, 0) AS e
GROUP BY m.minuto;
GO

/* RC2 (ERROR) El que sale ya no está en cancha y el que entra es titular.
   Esperado: error 50001 con 2 condiciones: el dorsal 4 no está en cancha en
   ese minuto y el dorsal 5 no está en el banco. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFA', 4, @sale OUTPUT;
EXEC #usp_Jugador 'XFA', 5, @entra OUTPUT;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
        @id_jugador_entra = @entra, @minuto = 30, @motivo = 'TACTICO';
    PRINT N'RC2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RC2';
END CATCH;
GO

/* RC3 (OK) Dos cambios en la misma ventana (minuto 60).
   Esperado: salen el 9 y el 7, entran el 19 y el 16. XFA lleva 3 cambios
   en 2 ventanas (15 y 60). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFA', 9, @sale OUTPUT;
EXEC #usp_Jugador 'XFA', 19, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 60, @motivo = 'TACTICO';
EXEC #usp_Jugador 'XFA', 7, @sale OUTPUT;
EXEC #usp_Jugador 'XFA', 16, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 60, @motivo = 'TACTICO';
SELECT 'RC3 después' AS caso, COUNT(*) AS cambios, COUNT(DISTINCT c.minuto * 100 + c.minuto_adicional) AS ventanas
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
WHERE c.id_partido = @id_partido AND l.id_seleccion = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
GO

/* RC4 (ERROR) Un cambio anterior al último registrado.
   Esperado: error 50001 con 1 condición: la selección ya tiene un cambio
   registrado después de ese minuto. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFA', 10, @sale OUTPUT;
EXEC #usp_Jugador 'XFA', 17, @entra OUTPUT;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
        @id_jugador_entra = @entra, @minuto = 50, @motivo = 'TACTICO';
    PRINT N'RC4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RC4';
END CATCH;
GO

/* RC5 (OK) Tercera ventana con dos cambios (minuto 75).
   Esperado: salen el 11 y el 8, entran el 21 y el 17. XFA llega a 5
   cambios en 3 ventanas, el máximo del tiempo reglamentario. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFA', 11, @sale OUTPUT;
EXEC #usp_Jugador 'XFA', 21, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 75, @motivo = 'TACTICO';
EXEC #usp_Jugador 'XFA', 8, @sale OUTPUT;
EXEC #usp_Jugador 'XFA', 17, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 75, @motivo = 'PRECAUCION';
SELECT 'RC5 después' AS caso, COUNT(*) AS cambios, COUNT(DISTINCT c.minuto * 100 + c.minuto_adicional) AS ventanas
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
WHERE c.id_partido = @id_partido AND l.id_seleccion = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
GO

/* RC6 (ERROR) Sexto cambio en el tiempo reglamentario.
   Esperado: error 50001 con 2 condiciones: XFA ya hizo sus 5 cambios
   permitidos (MAX_CAMBIOS) y ya usó sus 3 ventanas (MAX_VENTANAS). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFA', 10, @sale OUTPUT;
EXEC #usp_Jugador 'XFA', 18, @entra OUTPUT;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
        @id_jugador_entra = @entra, @minuto = 85, @motivo = 'TACTICO';
    PRINT N'RC6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RC6';
END CATCH;
GO

/* RC7 (OK) Cambio adicional del tiempo suplementario.
   Esperado: en el minuto 95 (alargue) se permite un sexto cambio y una
   cuarta ventana (CAMBIOS_EXTRA_ALARGUE y VENTANAS_EXTRA_ALARGUE): sale el
   10 y entra el 18. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFA', 10, @sale OUTPUT;
EXEC #usp_Jugador 'XFA', 18, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 95, @motivo = 'TACTICO';
SELECT 'RC7 después' AS caso, COUNT(*) AS cambios, COUNT(DISTINCT c.minuto * 100 + c.minuto_adicional) AS ventanas
FROM DesarrolloPartido.CAMBIO AS c
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
WHERE c.id_partido = @id_partido AND l.id_seleccion = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
GO

/* RC8 (ERROR) Séptimo cambio, ya en el alargue.
   Esperado: error 50001 con 2 condiciones: XFA ya hizo sus 6 cambios y
   usó sus 4 ventanas permitidos con el tiempo suplementario. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFA', 13, @sale OUTPUT;
EXEC #usp_Jugador 'XFA', 15, @entra OUTPUT;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
        @id_jugador_entra = @entra, @minuto = 100, @motivo = 'TACTICO';
    PRINT N'RC8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RC8';
END CATCH;
GO


/* ============================================================================
   usp_RegistrarCambio (XFB): entretiempo y jugador expulsado
   ============================================================================ */

/* RC9 (OK) Cambio en el entretiempo, que no consume ventana.
   Esperado: en el minuto 46 (entretiempo) sale el 9 y entra el 19; XFB queda con 1 cambio y 0 ventanas usadas. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFB', 9, @sale OUTPUT;
EXEC #usp_Jugador 'XFB', 19, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
    @id_jugador_entra = @entra, @minuto = 46, @motivo = 'TACTICO', @en_entretiempo = 1;
WITH cambios AS (
    SELECT c.minuto * 100 + c.minuto_adicional AS instante, c.en_entretiempo
    FROM DesarrolloPartido.CAMBIO AS c
    INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    WHERE c.id_partido = @id_partido
      AND l.id_seleccion = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido)
)
SELECT 'RC9 después' AS caso, (SELECT COUNT(*) FROM cambios) AS cambios,
       (SELECT COUNT(DISTINCT instante) FROM cambios WHERE en_entretiempo = 0) AS ventanas;
GO

/* RC10 (ERROR) Un suplente expulsado no puede entrar.
   El dorsal 20 de XFB ve una roja en el banco en el minuto 50.
   Esperado: error 50001 con 1 condición: el jugador que entra no está en el
   banco (fue expulsado). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFB', 11, @sale OUTPUT;
EXEC #usp_Jugador 'XFB', 20, @entra OUTPUT;
EXEC DesarrolloPartido.usp_AMONESTACION_Alta @id_partido = @id_partido, @tipo_tarjeta = 'ROJA', @minuto = 50,
    @motivo = 'Insultos al árbitro desde el banco', @id_jugador = @entra;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale,
        @id_jugador_entra = @entra, @minuto = 55, @motivo = 'TACTICO';
    PRINT N'RC10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RC10';
END CATCH;
GO

/* RC11 (OK) Tres ventanas más después del cambio del entretiempo.
   Esperado: XFB hace cambios en los minutos 55, 65 y 75: queda con
   4 cambios y 3 ventanas, dentro del reglamento. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @sale INT, @entra INT;
EXEC #usp_Jugador 'XFB', 11, @sale OUTPUT;
EXEC #usp_Jugador 'XFB', 21, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra, @minuto = 55, @motivo = 'TACTICO';
EXEC #usp_Jugador 'XFB', 10, @sale OUTPUT;
EXEC #usp_Jugador 'XFB', 16, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra, @minuto = 65, @motivo = 'TACTICO';
EXEC #usp_Jugador 'XFB', 8, @sale OUTPUT;
EXEC #usp_Jugador 'XFB', 17, @entra OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id_partido, @id_jugador_sale = @sale, @id_jugador_entra = @entra, @minuto = 75, @motivo = 'TACTICO';
WITH cambios AS (
    SELECT c.minuto * 100 + c.minuto_adicional AS instante, c.en_entretiempo
    FROM DesarrolloPartido.CAMBIO AS c
    INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = c.id_jugador_sale
    INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
    WHERE c.id_partido = @id_partido
      AND l.id_seleccion = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido)
)
SELECT 'RC11 después' AS caso, (SELECT COUNT(*) FROM cambios) AS cambios,
       (SELECT COUNT(DISTINCT instante) FROM cambios WHERE en_entretiempo = 0) AS ventanas;
GO


/* ============================================================================
   fn_EquipoEnCancha: el equipo de XFA a lo largo del partido de prueba
   Esperado: 11 jugadores en cada minuto, con los cambios aplicados (en el
   10 juega el 4; en el 70, el 14, el 19 y el 16; en el 100, el 21, el 17 y
   el 18).
   ============================================================================ */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 235);
DECLARE @xfa INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);
SELECT 'Equipo en cancha' AS caso, m.minuto, COUNT(*) AS jugadores,
       STRING_AGG(CAST(e.dorsal AS VARCHAR(3)), ', ') WITHIN GROUP (ORDER BY e.dorsal) AS dorsales
FROM (VALUES (CAST(10 AS TINYINT)), (CAST(70 AS TINYINT)), (CAST(100 AS TINYINT))) AS m (minuto)
CROSS APPLY DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @xfa, m.minuto, 0) AS e
GROUP BY m.minuto
ORDER BY m.minuto;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (235, 236))                AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XFA', 'XFB'))           AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.JUGADOR WHERE apellido LIKE N'Prueba XF%')                 AS jugadores_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Formaciones')  AS sedes_de_prueba;
GO

SET NOEXEC OFF;
GO
