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
 Archivo: 12_SP_Negocio_FormacionesYCambios.sql
 Objetivo: Crear los SP de lógica de negocio para el registro de formaciones,
           alineaciones y cambios durante el partido:
             DesarrolloPartido.usp_RegistrarFormacion  esquema, titulares y banco
             DesarrolloPartido.usp_RegistrarCambio     sustitución según el reglamento
           y el tipo de tabla DesarrolloPartido.TT_ALINEACION, con el que se
           pasan los jugadores de la formación. El equipo en cancha en
           cualquier minuto lo reconstruye DesarrolloPartido.fn_EquipoEnCancha
           (03_CrearFuncionesYVistas.sql). Siguen las convenciones de
           10_SP_Negocio_SedesYPartidos.sql. Requiere haber ejecutado 00 a 08.
           Su script de testing es 62_Test_SP_Negocio_FormacionesYCambios.sql.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  TT_ALINEACION
  Una fila por jugador de la formación: titular (1) o suplente (0) y, para
  los titulares, la posición en cancha. Se crea igual que Torneo.TT_CONVOCADO.
*/
DROP PROCEDURE IF EXISTS DesarrolloPartido.usp_RegistrarFormacion;
DROP TYPE IF EXISTS DesarrolloPartido.TT_ALINEACION;
GO

CREATE TYPE DesarrolloPartido.TT_ALINEACION AS TABLE (
    id_jugador          INT          NULL,
    es_titular          BIT          NULL,
    posicion_en_cancha  VARCHAR(30)  NULL
);
GO


/*
  usp_RegistrarFormacion
  Registra la formación de una selección para un partido: el esquema táctico,
  los 11 titulares con su posición y el banco de suplentes, en una sola
  transacción. Valida, sobre los jugadores recibidos: exactamente 11
  titulares, uno de ellos en la posición ARQUERO; titulares con posición; sin
  jugadores repetidos ni filas sin jugador; que todos sean convocados de la
  selección a la fecha del partido; que ninguno esté suspendido para ese
  partido (fn_JugadoresSuspendidos), con el detalle de cada suspensión. El
  partido, la selección y el esquema los valida
  DesarrolloPartido.usp_FORMACION_Alta. Con eso cubre las reglas de
  DesarrolloPartido.usp_ALINEACION_Alta y carga a todos los jugadores con un
  solo INSERT, sin recorrer la lista fila por fila.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_RegistrarFormacion
    @id_partido       INT,
    @id_seleccion     INT,
    @esquema_tactico  VARCHAR(20),
    @jugadores        DesarrolloPartido.TT_ALINEACION READONLY,
    @id_formacion     INT = NULL OUTPUT,
    @mostrar          BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia   BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @fecha_partido DATE;
    DECLARE @titulares     INT;
    DECLARE @arqueros      INT;
    DECLARE @sin_posicion  INT;
    DECLARE @sin_jugador   INT;

    DECLARE @lista TABLE (
        id_jugador          INT,
        es_titular          BIT,
        posicion_en_cancha  VARCHAR(30)
    );

    INSERT INTO @lista
    SELECT id_jugador, es_titular, UPPER(NULLIF(TRIM(posicion_en_cancha), ''))
    FROM @jugadores;

    SELECT @fecha_partido = CAST(fecha_hora_local AS DATE) FROM Torneo.PARTIDO WHERE id_partido = @id_partido;

    SELECT @titulares    = COUNT(*),
           @arqueros     = SUM(IIF(posicion_en_cancha = 'ARQUERO', 1, 0)),
           @sin_posicion = SUM(IIF(posicion_en_cancha IS NULL, 1, 0))
    FROM @lista
    WHERE es_titular = 1;

    SELECT @sin_jugador = COUNT(*) FROM @lista WHERE id_jugador IS NULL OR es_titular IS NULL;

    IF @titulares <> 11
        SET @errores += @nl + N'- La formación tiene ' + CAST(@titulares AS NVARCHAR(3)) + N' titulares: tienen que ser 11.';

    IF ISNULL(@arqueros, 0) <> 1
        SET @errores += @nl + N'- Tiene que haber exactamente un titular en la posición ARQUERO (hay '
                      + CAST(ISNULL(@arqueros, 0) AS NVARCHAR(3)) + N').';

    IF @sin_posicion > 0
        SET @errores += @nl + N'- Hay ' + CAST(@sin_posicion AS NVARCHAR(3)) + N' titular(es) sin posición en cancha.';

    IF @sin_jugador > 0
        SET @errores += @nl + N'- Hay ' + CAST(@sin_jugador AS NVARCHAR(3))
                      + N' fila(s) sin jugador o sin indicar si es titular.';

    SET @errores += ISNULL((
        SELECT @nl + N'- Jugadores repetidos (id): ' + STRING_AGG(CAST(id_jugador AS NVARCHAR(10)), ', ') + N'.'
        FROM (SELECT id_jugador FROM @lista WHERE id_jugador IS NOT NULL
              GROUP BY id_jugador HAVING COUNT(*) > 1) AS x), N'');

    -- Jugadores que no son de la selección o que no estaban convocados en la fecha del partido.
    SET @errores += ISNULL((
        SELECT @nl + N'- No son convocados de la selección en la fecha del partido (id): '
               + STRING_AGG(CAST(x.id_jugador AS NVARCHAR(10)), ', ') + N'.'
        FROM (SELECT DISTINCT li.id_jugador
              FROM @lista AS li
              LEFT JOIN Torneo.JUGADOR AS j ON j.id_jugador = li.id_jugador
              LEFT JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
              WHERE li.id_jugador IS NOT NULL
                AND (l.id_seleccion IS NULL OR l.id_seleccion <> @id_seleccion
                     OR j.fecha_alta > @fecha_partido OR j.fecha_baja <= @fecha_partido)) AS x), N'');

    -- Suspendidos, con el motivo y el partido en que se originó la sanción.
    SET @errores += ISNULL((
        SELECT STRING_AGG(@nl + N'- Suspendido: ' + CAST(j.dorsal AS NVARCHAR(3)) + N' ' + j.apellido + N', '
                          + j.nombre + N' (' + s.motivo + N' en el partido '
                          + CAST(s.numero_partido_origen AS NVARCHAR(3)) + N').', N'')
        FROM DesarrolloPartido.fn_JugadoresSuspendidos(@id_partido) AS s
        INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
        WHERE s.id_jugador IN (SELECT id_jugador FROM @lista)), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_RegistrarFormacion: no se pudo registrar la formación.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC DesarrolloPartido.usp_FORMACION_Alta
            @id_partido = @id_partido, @id_seleccion = @id_seleccion,
            @esquema_tactico = @esquema_tactico, @id_formacion = @id_formacion OUTPUT;

        INSERT INTO DesarrolloPartido.ALINEACION (id_formacion, id_jugador, es_titular, posicion_en_cancha)
        SELECT @id_formacion, id_jugador, es_titular, posicion_en_cancha
        FROM @lista;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @mostrar = 1
        SELECT f.id_formacion, f.esquema_tactico, IIF(a.es_titular = 1, 'TITULAR', 'SUPLENTE') AS condicion,
               j.dorsal, j.apellido, j.nombre, a.posicion_en_cancha
        FROM DesarrolloPartido.FORMACION AS f
        INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
        INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = a.id_jugador
        WHERE f.id_formacion = @id_formacion
        ORDER BY a.es_titular DESC, j.dorsal;
END;
GO


/*
  usp_RegistrarCambio
  Registra una sustitución con el partido EN_JUEGO. Valida, según el
  reglamento (PARAMETRO_REGLAMENTO):
    - que el jugador que sale esté en cancha en ese momento y que el que
      entra esté en el banco: suplente, sin haber entrado ni sido expulsado;
    - que los cambios se registren en orden: no antes del último cambio de
      la selección;
    - el máximo de cambios (MAX_CAMBIOS) y de ventanas (MAX_VENTANAS) por
      selección. En tiempo suplementario (minuto mayor que 90, o entretiempo
      antes del alargue o en su descanso) se suman CAMBIOS_EXTRA_ALARGUE y
      VENTANAS_EXTRA_ALARGUE. Cada momento distinto con cambios es una
      ventana, salvo los entretiempos, que no consumen ventana.
  Los datos del cambio los valida además DesarrolloPartido.usp_CAMBIO_Alta.
*/
CREATE OR ALTER PROCEDURE DesarrolloPartido.usp_RegistrarCambio
    @id_partido        INT,
    @id_jugador_sale   INT,
    @id_jugador_entra  INT,
    @minuto            TINYINT,
    @motivo            VARCHAR(30),
    @minuto_adicional  TINYINT = 0,
    @en_entretiempo    BIT     = 0,
    @id_cambio         INT     = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores         NVARCHAR(2048) = N'';
    DECLARE @nl              NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia     BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @estado          VARCHAR(12);
    DECLARE @id_seleccion    INT;
    DECLARE @instante        INT;
    DECLARE @ultimo_cambio   INT;
    DECLARE @en_alargue      BIT;
    DECLARE @max_cambios     INT;
    DECLARE @max_ventanas    INT;
    DECLARE @cambios_hechos  INT;
    DECLARE @ventanas_usadas INT;
    DECLARE @ventana_nueva   INT;

    SET @minuto_adicional = ISNULL(@minuto_adicional, 0);
    SET @en_entretiempo   = ISNULL(@en_entretiempo, 0);
    SET @instante         = @minuto * 100 + @minuto_adicional;
    SET @en_alargue       = IIF(@minuto > 90 OR (@en_entretiempo = 1 AND @minuto IN (91, 106)), 1, 0);

    SELECT @estado = estado FROM Torneo.PARTIDO WHERE id_partido = @id_partido;

    SELECT @id_seleccion = f.id_seleccion
    FROM DesarrolloPartido.ALINEACION AS a
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
    WHERE f.id_partido = @id_partido AND a.id_jugador = @id_jugador_sale;

    SET @max_cambios  = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CAMBIOS')
                      + IIF(@en_alargue = 1, (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                                              WHERE codigo = 'CAMBIOS_EXTRA_ALARGUE'), 0);
    SET @max_ventanas = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_VENTANAS')
                      + IIF(@en_alargue = 1, (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO
                                              WHERE codigo = 'VENTANAS_EXTRA_ALARGUE'), 0);

    -- Cambios ya hechos por la selección (se identifica por el que salió).
    DECLARE @cambios_seleccion TABLE (instante INT, en_entretiempo BIT);
    INSERT INTO @cambios_seleccion (instante, en_entretiempo)
    SELECT c.minuto * 100 + c.minuto_adicional, c.en_entretiempo
    FROM DesarrolloPartido.CAMBIO AS c
    INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_jugador = c.id_jugador_sale
    INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion AND f.id_partido = c.id_partido
    WHERE c.id_partido = @id_partido AND f.id_seleccion = @id_seleccion;

    SELECT @cambios_hechos = COUNT(*), @ultimo_cambio = MAX(instante) FROM @cambios_seleccion;
    SELECT @ventanas_usadas = COUNT(DISTINCT instante) FROM @cambios_seleccion WHERE en_entretiempo = 0;
    -- Un cambio en el mismo momento que otro (fuera del entretiempo) es parte de la misma ventana.
    SET @ventana_nueva = IIF(@en_entretiempo = 1
                             OR EXISTS (SELECT 1 FROM @cambios_seleccion
                                        WHERE en_entretiempo = 0 AND instante = @instante), 0, 1);

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE IF @estado <> 'EN_JUEGO'
        SET @errores += @nl + N'- Los cambios se registran con el partido EN_JUEGO (estado actual: ' + @estado + N').';

    IF @minuto IS NULL
        SET @errores += @nl + N'- El minuto es obligatorio.';
    ELSE IF @id_seleccion IS NOT NULL AND @estado = 'EN_JUEGO'
    BEGIN
        IF NOT EXISTS (SELECT 1
                       FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion, @minuto, @minuto_adicional)
                       WHERE id_jugador = @id_jugador_sale)
            SET @errores += @nl + N'- El jugador que sale no está en cancha en ese minuto.';

        IF NOT EXISTS (SELECT 1
                       FROM DesarrolloPartido.ALINEACION AS a
                       INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
                       WHERE f.id_partido = @id_partido AND f.id_seleccion = @id_seleccion
                         AND a.id_jugador = @id_jugador_entra AND a.es_titular = 0)
           OR EXISTS (SELECT 1 FROM DesarrolloPartido.CAMBIO
                      WHERE id_partido = @id_partido AND id_jugador_entra = @id_jugador_entra)
           OR EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION
                      WHERE id_partido = @id_partido AND id_jugador = @id_jugador_entra AND tipo_tarjeta = 'ROJA')
            SET @errores += @nl + N'- El jugador que entra no está en el banco: tiene que ser un suplente de la '
                          + N'selección que no haya entrado ni haya sido expulsado.';

        IF @instante < @ultimo_cambio
            SET @errores += @nl + N'- La selección ya tiene un cambio registrado después de ese minuto: '
                          + N'los cambios se registran en orden.';

        IF @cambios_hechos + 1 > @max_cambios
            SET @errores += @nl + N'- La selección ya hizo sus ' + CAST(@max_cambios AS NVARCHAR(3))
                          + N' cambios permitidos' + IIF(@en_alargue = 1, N' con el tiempo suplementario.', N' (MAX_CAMBIOS).');

        IF @ventanas_usadas + @ventana_nueva > @max_ventanas
            SET @errores += @nl + N'- La selección ya usó sus ' + CAST(@max_ventanas AS NVARCHAR(3))
                          + N' ventanas de cambio' + IIF(@en_alargue = 1, N' con el tiempo suplementario.', N' (MAX_VENTANAS).');
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'DesarrolloPartido.usp_RegistrarCambio: no se pudo registrar el cambio.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC DesarrolloPartido.usp_CAMBIO_Alta
            @id_partido = @id_partido, @id_jugador_sale = @id_jugador_sale,
            @id_jugador_entra = @id_jugador_entra, @minuto = @minuto, @motivo = @motivo,
            @minuto_adicional = @minuto_adicional, @en_entretiempo = @en_entretiempo,
            @id_cambio = @id_cambio OUTPUT;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- Evidencia: SP de negocio y tipo de tabla creados.
SELECT s.name AS esquema, p.name AS objeto, 'PROCEDIMIENTO' AS tipo
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'DesarrolloPartido'
  AND p.name IN (N'usp_RegistrarFormacion', N'usp_RegistrarCambio')
UNION ALL
SELECT s.name, t.name, 'TIPO DE TABLA'
FROM sys.table_types AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = N'DesarrolloPartido'
ORDER BY tipo, objeto;
GO
