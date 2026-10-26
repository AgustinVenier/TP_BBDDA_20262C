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
 Archivo: 13_SP_Negocio_GolesYTarjetas.sql
 Objetivo: Crear los SP de lógica de negocio para el registro de goles,
           amonestaciones y expulsiones, con el cálculo de la suspensión por
           acumulación:
             DesarrolloPartido.usp_RegistrarGol           gol con autor y asistente en cancha
             DesarrolloPartido.usp_RegistrarAmonestacion  tarjeta, roja por doble amarilla
                                                          y suspensión resultante
           Las sanciones y suspensiones las calculan fn_Sanciones y
           fn_JugadoresSuspendidos (03_CrearFuncionesYVistas.sql) con los
           criterios de PARAMETRO_REGLAMENTO. Siguen las convenciones de
           10_SP_Negocio_SedesYPartidos.sql. Requiere haber ejecutado 00 a 08.
           Su script de testing es 63_Test_SP_Negocio_GolesYTarjetas.sql.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_RegistrarGol
  Registra un gol con el partido EN_JUEGO. Valida:
    - que el autor esté en cancha en ese minuto (para la definición por
      penales, en cancha al final del partido), y lo mismo el que asiste;
    - que solo haya goles de alargue si el partido estaba empatado al
      terminar el tiempo reglamentario;
    - que solo haya definición por penales si el partido sigue empatado
      después del alargue.
  Los datos del gol (período, minuto, tipo, asistencia de la misma
  selección) los valida además DesarrolloPartido.usp_GOL_Alta.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_RegistrarGol
    @id_partido             INT,
    @id_jugador_autor       INT,
    @id_tipo_gol            TINYINT,
    @periodo                VARCHAR(30),
    @minuto                 TINYINT = NULL,
    @minuto_adicional       TINYINT = 0,
    @id_jugador_asistencia  INT     = NULL,
    @id_gol                 INT     = NULL OUTPUT,
    @mostrar                BIT     = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia    BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @estado         VARCHAR(12);
    DECLARE @sel_autor      INT;
    DECLARE @sel_asistencia INT;
    DECLARE @minuto_cancha  TINYINT;
    DECLARE @adic_cancha    TINYINT;
    DECLARE @gl             INT;
    DECLARE @gv             INT;
    DECLARE @gl_90          INT;
    DECLARE @gv_90          INT;

    SET @periodo          = UPPER(NULLIF(TRIM(@periodo), ''));
    SET @minuto_adicional = ISNULL(@minuto_adicional, 0);

    -- Para la definición por penales se mira quién estaba en cancha al final.
    SELECT @minuto_cancha = IIF(@periodo = 'PENALES', 120, @minuto),
           @adic_cancha   = IIF(@periodo = 'PENALES', 99, @minuto_adicional);

    SELECT @estado = estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;

    SELECT @sel_autor = f.id_seleccion
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    WHERE f.id_partido = @id_partido AND a.id_jugador = @id_jugador_autor;

    SELECT @sel_asistencia = f.id_seleccion
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    WHERE f.id_partido = @id_partido AND a.id_jugador = @id_jugador_asistencia;

    SELECT @gl = goles_local, @gv = goles_visitante, @gl_90 = goles_local_90, @gv_90 = goles_visitante_90
    FROM DesarrolloPartido.fn_MarcadorSegunGoles(@id_partido);

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE IF @estado <> 'EN_JUEGO'
        SET @errores += @nl + N'- Los goles se registran con el partido EN_JUEGO (estado actual: ' + @estado + N').';
    ELSE
    BEGIN
        IF @sel_autor IS NOT NULL AND @minuto_cancha IS NOT NULL
           AND NOT EXISTS (SELECT 1
                           FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @sel_autor, @minuto_cancha, @adic_cancha)
                           WHERE id_jugador = @id_jugador_autor)
            SET @errores += @nl + N'- El autor no estaba en cancha en ese minuto.';

        IF @sel_asistencia IS NOT NULL AND @minuto_cancha IS NOT NULL
           AND NOT EXISTS (SELECT 1
                           FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @sel_asistencia, @minuto_cancha, @adic_cancha)
                           WHERE id_jugador = @id_jugador_asistencia)
            SET @errores += @nl + N'- El jugador que asiste no estaba en cancha en ese minuto.';

        IF (@periodo = 'ALARGUE' OR (@periodo = 'ADICIONALES' AND @minuto IN (105, 120)))
           AND @gl_90 <> @gv_90
            SET @errores += @nl + N'- El partido no terminó empatado el tiempo reglamentario ('
                          + CAST(@gl_90 AS NVARCHAR(3)) + N' - ' + CAST(@gv_90 AS NVARCHAR(3))
                          + N'): no hay alargue.';

        IF @periodo = 'PENALES' AND @gl <> @gv
            SET @errores += @nl + N'- El partido no está empatado (' + CAST(@gl AS NVARCHAR(3)) + N' - '
                          + CAST(@gv AS NVARCHAR(3)) + N'): no hay definición por penales.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_RegistrarGol: no se pudo registrar el gol.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC DesarrolloPartido.usp_GOL_Alta
            @id_partido = @id_partido, @id_jugador_autor = @id_jugador_autor, @id_tipo_gol = @id_tipo_gol,
            @periodo = @periodo, @minuto = @minuto, @minuto_adicional = @minuto_adicional,
            @id_jugador_asistencia = @id_jugador_asistencia, @id_gol = @id_gol OUTPUT;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @mostrar = 1
        SELECT f.seleccion_local, m.goles_local, m.goles_visitante, f.seleccion_visitante,
               m.penales_local, m.penales_visitante
        FROM Torneo.vw_Fixture AS f
        CROSS APPLY DesarrolloPartido.fn_MarcadorSegunGoles(f.id_partido) AS m
        WHERE f.id_partido = @id_partido;
END;
GO


/*
  usp_RegistrarAmonestacion
  Registra una tarjeta a un jugador o a una persona del cuerpo técnico. Si es
  la segunda amarilla del receptor en el partido, registra además en la misma
  transacción la roja por doble amarilla (es_doble_amarilla = 1), en el mismo
  minuto. Después informa si la tarjeta genera una suspensión para los
  próximos partidos (acumulación de amarillas en partidos distintos, doble
  amarilla o roja directa), según los criterios de PARAMETRO_REGLAMENTO.
  Valida: partido existente, EN_JUEGO o FINALIZADO (las tarjetas pueden
  cargarse después, desde el informe del árbitro). El resto lo valida
  DesarrolloPartido.usp_AMONESTACION_Alta.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_RegistrarAmonestacion
    @id_partido        INT,
    @tipo_tarjeta      VARCHAR(20),
    @minuto            TINYINT,
    @motivo            VARCHAR(400),
    @id_jugador        INT     = NULL,
    @id_persona_ct     INT     = NULL,
    @minuto_adicional  TINYINT = 0,
    @id_amonestacion   INT     = NULL OUTPUT,
    @mostrar           BIT     = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores           NVARCHAR(2048) = N'';
    DECLARE @nl                NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia       BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @estado            VARCHAR(12);
    DECLARE @amarillas_previas INT;
    DECLARE @es_segunda        BIT            = 0;
    DECLARE @motivo_sancion    VARCHAR(100);
    DECLARE @partidos_sancion  INT;
    DECLARE @receptor          NVARCHAR(130);

    SET @tipo_tarjeta = UPPER(NULLIF(TRIM(@tipo_tarjeta), ''));

    SELECT @estado = estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;

    SELECT @amarillas_previas = COUNT(*)
    FROM DesarrolloPartido.AMONESTACION
    WHERE id_partido = @id_partido
      AND tipo_tarjeta = 'AMARILLA'
      AND (id_jugador = @id_jugador OR id_persona_ct = @id_persona_ct);

    IF @tipo_tarjeta = 'AMARILLA' AND @amarillas_previas = 1
        SET @es_segunda = 1;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE IF @estado NOT IN ('EN_JUEGO', 'FINALIZADO')
        SET @errores += @nl + N'- Las tarjetas se registran con el partido EN_JUEGO o FINALIZADO (estado actual: '
                      + @estado + N').';

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_RegistrarAmonestacion: no se pudo registrar la tarjeta.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC DesarrolloPartido.usp_AMONESTACION_Alta
            @id_partido = @id_partido, @tipo_tarjeta = @tipo_tarjeta, @minuto = @minuto,
            @motivo = @motivo, @id_jugador = @id_jugador, @id_persona_ct = @id_persona_ct,
            @minuto_adicional = @minuto_adicional, @id_amonestacion = @id_amonestacion OUTPUT;

        IF @es_segunda = 1
            EXEC DesarrolloPartido.usp_AMONESTACION_Alta
                @id_partido = @id_partido, @tipo_tarjeta = 'ROJA', @minuto = @minuto,
                @motivo = 'Doble amarilla', @id_jugador = @id_jugador, @id_persona_ct = @id_persona_ct,
                @minuto_adicional = @minuto_adicional, @es_doble_amarilla = 1;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    -- Suspensión que genera esta tarjeta (solo para jugadores).
    IF @id_jugador IS NOT NULL
    BEGIN
        SELECT @motivo_sancion = s.motivo, @partidos_sancion = s.partidos_de_suspension
        FROM DesarrolloPartido.fn_Sanciones() AS s
        WHERE s.id_jugador = @id_jugador AND s.id_partido_origen = @id_partido;

        SELECT @receptor = apellido + N', ' + nombre FROM Torneo.JUGADOR WHERE id_jugador = @id_jugador;

        IF @es_segunda = 1
            PRINT N'Segunda amarilla de ' + @receptor + N' en el partido: se registró la roja por doble amarilla.';
        IF @motivo_sancion IS NOT NULL
            PRINT N'Suspensión: ' + @receptor + N' no puede jugar los próximos '
                  + CAST(@partidos_sancion AS NVARCHAR(3)) + N' partido(s) de su selección (' + @motivo_sancion + N').';
    END;

    IF @mostrar = 1 AND @id_jugador IS NOT NULL
        SELECT j.dorsal, j.apellido, j.nombre,
               SUM(IIF(a.tipo_tarjeta = 'AMARILLA', 1, 0))                        AS amarillas_en_el_partido,
               SUM(IIF(a.tipo_tarjeta = 'ROJA', 1, 0))                            AS rojas_en_el_partido,
               ISNULL(@motivo_sancion, 'SIN SUSPENSION')                          AS suspension,
               ISNULL(@partidos_sancion, 0)                                       AS partidos_de_suspension
        FROM Torneo.JUGADOR AS j
        LEFT JOIN DesarrolloPartido.AMONESTACION AS a
               ON a.id_jugador = j.id_jugador AND a.id_partido = @id_partido
        WHERE j.id_jugador = @id_jugador
        GROUP BY j.dorsal, j.apellido, j.nombre;
END;
GO


-- Evidencia: SP de negocio creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'DesarrolloPartido'
  AND p.name IN (N'usp_RegistrarGol', N'usp_RegistrarAmonestacion')
ORDER BY p.name;
GO
