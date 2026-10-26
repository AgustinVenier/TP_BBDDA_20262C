/*
================================================================================
 Universidad Nacional de La Matanza
 Materia: 3641 - Bases de Datos Aplicada
 Comisión: 01    Grupo: 2
 Integrantes:
   Caruso Dellisanti, Carolina Belen - COMPLETAR
   D'Ambrosio, Rodrigo - rodrigoDambrosio
   Tavella, Tomás - TomasTavella
   Venier, Agustin - AgustinVenier

 Fecha: 25/10/2026
 Archivo: 10_SP_Negocio_SedesYPartidos.sql
 Objetivo: Crear los SP de lógica de negocio para el registro de sedes,
           partidos y resultados:
             Torneo.usp_RegistrarSede      sede y sus 4 espacios publicitarios
             Torneo.usp_IniciarPartido     controles previos y paso a EN_JUEGO
             Torneo.usp_FinalizarPartido   resultado, asistencia y paso a FINALIZADO
           El alta de un partido (con el cálculo de la hora local a partir de
           la UTC) es Torneo.usp_PARTIDO_Alta (05_SP_ABM_Torneo.sql).
           Requiere haber ejecutado 00 a 08. Su script de testing es
           60_Test_SP_Negocio_SedesYPartidos.sql.
================================================================================

 Convenciones de los SP de negocio (las siguen los scripts 10 a 16):
   - Primero validan las reglas propias del proceso y, si alguna no se
     cumple, lanzan un único THROW 50001 con todas juntas, antes de abrir la
     transacción. Después llaman a los SP de ABM, que validan cada fila.
   - Todo lo que escriben va en una sola transacción, con SET XACT_ABORT ON
     y TRY/CATCH: si falla cualquier paso se deshace todo y se relanza el
     error original con THROW.
   - Si el SP se llama desde otro que ya abrió una transacción, usa la del
     que lo llamó (@tran_propia = 0): no la confirma ni la deshace él, para
     que la decisión quede en un solo lugar.
   - @mostrar = 1 devuelve una consulta con el resultado de la operación,
     como evidencia. Los procesos de carga masiva lo llaman con 0.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_RegistrarSede
  Registra una sede con sus cuatro espacios publicitarios (numerados del 1 al
  4) en una sola transacción, así ninguna sede queda con menos de cuatro.
  Valida: que se informen las cuatro tarifas y que no sean negativas. Los
  datos de la sede los valida Torneo.usp_SEDE_Alta.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_RegistrarSede
    @nombre_estadio    VARCHAR(200),
    @ciudad            VARCHAR(200),
    @id_pais           SMALLINT,
    @capacidad         INT,
    @huso_horario      VARCHAR(100),
    @tarifa_espacio_1  DECIMAL(9,2),
    @tarifa_espacio_2  DECIMAL(9,2),
    @tarifa_espacio_3  DECIMAL(9,2),
    @tarifa_espacio_4  DECIMAL(9,2),
    @latitud           DECIMAL(9,6) = NULL,
    @longitud          DECIMAL(9,6) = NULL,
    @id_sede           INT          = NULL OUTPUT,
    @mostrar           BIT          = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @nl          NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT            = IIF(@@TRANCOUNT = 0, 1, 0);

    IF @tarifa_espacio_1 IS NULL OR @tarifa_espacio_2 IS NULL
       OR @tarifa_espacio_3 IS NULL OR @tarifa_espacio_4 IS NULL
        SET @errores += @nl + N'- Las tarifas de los 4 espacios publicitarios son obligatorias.';

    IF @tarifa_espacio_1 < 0 OR @tarifa_espacio_2 < 0 OR @tarifa_espacio_3 < 0 OR @tarifa_espacio_4 < 0
        SET @errores += @nl + N'- Las tarifas de los espacios no pueden ser negativas.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_RegistrarSede: no se pudo registrar la sede.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Torneo.usp_SEDE_Alta
            @nombre_estadio = @nombre_estadio, @ciudad = @ciudad, @id_pais = @id_pais,
            @capacidad = @capacidad, @huso_horario = @huso_horario,
            @latitud = @latitud, @longitud = @longitud, @id_sede = @id_sede OUTPUT;

        EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @id_sede, @numero_espacio = 1,
            @tarifa_usd = @tarifa_espacio_1, @descripcion = 'Panel perimetral 1';
        EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @id_sede, @numero_espacio = 2,
            @tarifa_usd = @tarifa_espacio_2, @descripcion = 'Panel perimetral 2';
        EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @id_sede, @numero_espacio = 3,
            @tarifa_usd = @tarifa_espacio_3, @descripcion = 'Panel perimetral 3';
        EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @id_sede, @numero_espacio = 4,
            @tarifa_usd = @tarifa_espacio_4, @descripcion = 'Panel perimetral 4';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @mostrar = 1
        SELECT s.id_sede, s.nombre_estadio, s.ciudad, s.huso_horario, s.capacidad,
               e.numero_espacio, e.descripcion, e.tarifa_usd
        FROM Torneo.SEDE AS s
        INNER JOIN Publicidad.ESPACIO_PUBLICITARIO AS e ON e.id_sede = s.id_sede
        WHERE s.id_sede = @id_sede
        ORDER BY e.numero_espacio;
END;
GO


/*
  usp_IniciarPartido
  Pasa un partido a EN_JUEGO, que es el estado en que se registran goles,
  cambios y tarjetas. Valida: partido existente y PROGRAMADO; las dos
  selecciones definidas; cada una con su formación de 11 titulares; la
  designación arbitral completa (principal, dos asistentes, cuarto árbitro y
  VAR); que ningún jugador de las formaciones esté suspendido. Si el partido
  no tiene asignados sus 4 espacios publicitarios, avisa pero no lo impide.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_IniciarPartido
    @id_partido INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado       VARCHAR(12);
    DECLARE @local        INT;
    DECLARE @visitante    INT;
    DECLARE @exhibiciones INT;

    SELECT @estado = estado, @local = id_seleccion_local, @visitante = id_seleccion_visitante
    FROM Torneo.PARTIDO
    WHERE id_partido = @id_partido;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        IF @estado <> 'PROGRAMADO'
            SET @errores += @nl + N'- El partido está ' + @estado + N': solo empieza un partido PROGRAMADO.';

        IF @local IS NULL OR @visitante IS NULL
            SET @errores += @nl + N'- Las dos selecciones tienen que estar definidas.';
        ELSE
            -- Selecciones sin formación o sin sus 11 titulares.
            SET @errores += ISNULL((
                SELECT STRING_AGG(@nl + N'- ' + pa.nombre + N' tiene ' + CAST(t.titulares AS NVARCHAR(3))
                                  + N' titulares cargados (tienen que ser 11).', N'')
                FROM (VALUES (@local), (@visitante)) AS v (id_seleccion)
                INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = v.id_seleccion
                INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
                CROSS APPLY (SELECT COUNT(a.id_jugador) AS titulares
                             FROM DesarrolloPartido.FORMACION AS f
                             LEFT JOIN DesarrolloPartido.ALINEACION AS a
                                    ON a.id_formacion = f.id_formacion AND a.es_titular = 1
                             WHERE f.id_partido = @id_partido AND f.id_seleccion = v.id_seleccion) AS t
                WHERE t.titulares <> 11), N'');

        -- Roles sin designar.
        SET @errores += ISNULL((
            SELECT @nl + N'- Falta designar: ' + STRING_AGG(r.rol, ', ') + N'.'
            FROM (VALUES ('PRINCIPAL'), ('ASISTENTE_1'), ('ASISTENTE_2'), ('CUARTO'), ('VAR')) AS r (rol)
            WHERE NOT EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL AS d
                              WHERE d.id_partido = @id_partido AND d.rol = r.rol)), N'');

        -- Jugadores alineados que están suspendidos.
        SET @errores += ISNULL((
            SELECT STRING_AGG(@nl + N'- ' + j.apellido + N', ' + j.nombre + N' está suspendido ('
                              + s.motivo + N' en el partido ' + CAST(s.numero_partido_origen AS NVARCHAR(3)) + N').', N'')
            FROM DesarrolloPartido.fn_JugadoresSuspendidos(@id_partido) AS s
            INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
            WHERE EXISTS (SELECT 1
                          FROM DesarrolloPartido.ALINEACION AS a
                          INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
                          WHERE f.id_partido = @id_partido AND a.id_jugador = s.id_jugador)), N'');
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_IniciarPartido: no se pudo iniciar el partido.' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT @exhibiciones = COUNT(*) FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido;
    IF @exhibiciones < 4
        PRINT CONCAT(N'Advertencia: el partido empieza con ', @exhibiciones,
                     N' de sus 4 espacios publicitarios asignados.');

    -- Una sola sentencia: no hace falta abrir una transacción.
    EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';
END;
GO


/*
  usp_FinalizarPartido
  Cierra un partido EN_JUEGO: registra el resultado y la asistencia y lo pasa
  a FINALIZADO. Si no se informan los goles, se toman los registrados en GOL
  (sin goles registrados, el partido terminó 0 a 0); lo mismo con los
  penales. Valida: partido existente y EN_JUEGO; que el resultado informado
  coincida con los goles registrados; que un partido de eliminación directa
  empatado tenga definición por penales y que un partido de grupos no la
  tenga. La asistencia y la coherencia del resultado las valida también
  Torneo.usp_PARTIDO_Modificacion.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_FinalizarPartido
    @id_partido         INT,
    @asistencia         INT     = NULL,
    @goles_local        TINYINT = NULL,
    @goles_visitante    TINYINT = NULL,
    @penales_local      TINYINT = NULL,
    @penales_visitante  TINYINT = NULL,
    @mostrar            BIT     = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores             NVARCHAR(2048) = N'';
    DECLARE @nl                  NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado              VARCHAR(12);
    DECLARE @fase                VARCHAR(15);
    DECLARE @goles_registrados   INT;
    DECLARE @penales_registrados INT;
    DECLARE @gl                  INT;
    DECLARE @gv                  INT;
    DECLARE @pl                  INT;
    DECLARE @pv                  INT;

    SELECT @estado = estado, @fase = fase FROM Torneo.PARTIDO WHERE id_partido = @id_partido;

    SELECT @goles_registrados   = goles_registrados - penales_registrados,
           @penales_registrados = penales_registrados,
           @gl = goles_local, @gv = goles_visitante,
           @pl = penales_local, @pv = penales_visitante
    FROM DesarrolloPartido.fn_MarcadorSegunGoles(@id_partido);

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        IF @estado <> 'EN_JUEGO'
            SET @errores += @nl + N'- El partido está ' + @estado + N': solo se finaliza un partido EN_JUEGO.';

        IF (@goles_local IS NULL AND @goles_visitante IS NOT NULL)
           OR (@goles_local IS NOT NULL AND @goles_visitante IS NULL)
            SET @errores += @nl + N'- Los goles se informan para las dos selecciones (o ninguno, para tomar los registrados).';
        ELSE IF @goles_local IS NOT NULL AND @goles_registrados > 0
                AND (@goles_local <> @gl OR @goles_visitante <> @gv)
            SET @errores += @nl + N'- El resultado informado no coincide con los goles registrados ('
                          + CAST(@gl AS NVARCHAR(3)) + N' - ' + CAST(@gv AS NVARCHAR(3)) + N').';

        IF @penales_local IS NOT NULL AND @penales_registrados > 0
           AND (@penales_local <> @pl OR ISNULL(@penales_visitante, 255) <> @pv)
            SET @errores += @nl + N'- Los penales informados no coinciden con los registrados ('
                          + CAST(@pl AS NVARCHAR(3)) + N' - ' + CAST(@pv AS NVARCHAR(3)) + N').';
    END;

    -- Resultado final: el informado o, si no se informó, el de los goles registrados.
    IF @goles_local IS NULL
        SELECT @goles_local = @gl, @goles_visitante = @gv;
    IF @penales_local IS NULL AND @penales_registrados > 0
        SELECT @penales_local = @pl, @penales_visitante = @pv;

    IF @estado = 'EN_JUEGO' AND @errores = N''
    BEGIN
        IF @fase = 'GRUPOS' AND @penales_local IS NOT NULL
            SET @errores += @nl + N'- En la fase de grupos no hay definición por penales.';
        ELSE IF @fase <> 'GRUPOS' AND @goles_local = @goles_visitante AND @penales_local IS NULL
            SET @errores += @nl + N'- El partido de eliminación directa terminó empatado: falta la definición por penales.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Torneo.usp_FinalizarPartido: no se pudo finalizar el partido.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Una sola sentencia: no hace falta abrir una transacción.
    EXEC Torneo.usp_PARTIDO_Modificacion
        @id_partido = @id_partido,
        @goles_local = @goles_local, @goles_visitante = @goles_visitante,
        @penales_local = @penales_local, @penales_visitante = @penales_visitante,
        @asistencia = @asistencia, @estado = 'FINALIZADO';

    IF @mostrar = 1
        SELECT numero_partido, fase, seleccion_local, seleccion_visitante, resultado, asistencia, estado
        FROM Torneo.vw_Fixture
        WHERE id_partido = @id_partido;
END;
GO


-- Evidencia: SP de negocio creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Torneo'
  AND p.name IN (N'usp_RegistrarSede', N'usp_IniciarPartido', N'usp_FinalizarPartido')
ORDER BY p.name;
GO
