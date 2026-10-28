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
 Archivo: 14_SP_Negocio_Arbitraje.sql
 Objetivo: Crear los SP de lógica de negocio para el registro de árbitros y
           su designación por partido, con la validación del conflicto de
           nacionalidad:
             Arbitraje.usp_RegistrarArbitro        árbitro con sus idiomas
             Arbitraje.usp_DesignarTernaArbitral   los cinco roles de un partido
           Siguen las convenciones de 10_SP_Negocio_SedesYPartidos.sql.
           Requiere haber ejecutado 00 a 08. Su script de testing es
           64_Test_SP_Negocio_Arbitraje.sql.
================================================================================

 Criterio de "país que puede cruzarse" (advertencia desde dieciseisavos):
   el cuadro de eliminatorias no está modelado, así que se advierte cuando el
   país del árbitro tiene una selección que sigue en competencia
   (Torneo.fn_SeleccionesEnCompetencia): llegó a la eliminación directa y no
   perdió ningún partido de esa etapa. Esa selección podría cruzarse más
   adelante con las que juegan el partido. Es una advertencia: la
   designación se hace igual.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_RegistrarArbitro
  Registra un árbitro con los idiomas que habla, en una sola transacción.
  @idiomas es una lista de códigos ISO 639-1 separados por comas (ej.
  'es,en'). Valida: al menos un idioma y que todos los códigos existan. Los
  datos del árbitro los valida Arbitraje.usp_ARBITRO_Alta. Los idiomas se
  cargan con un solo INSERT: el árbitro es nuevo y los códigos ya están
  validados, así que no queda nada que controle Arbitraje.usp_ARBITRO_IDIOMA_Alta.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_RegistrarArbitro
    @id_pais           SMALLINT,
    @nombre            NVARCHAR(120),
    @apellido          NVARCHAR(120),
    @categoria         VARCHAR(30),
    @idiomas           VARCHAR(200),
    @fecha_nacimiento  DATE = NULL,
    @id_arbitro        INT  = NULL OUTPUT,
    @mostrar           BIT  = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @nl          NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT            = IIF(@@TRANCOUNT = 0, 1, 0);

    DECLARE @codigos TABLE (codigo VARCHAR(10) PRIMARY KEY, id_idioma SMALLINT);

    INSERT INTO @codigos (codigo, id_idioma)
    SELECT DISTINCT LOWER(TRIM(c.value)), i.id_idioma
    FROM STRING_SPLIT(@idiomas, ',') AS c
    LEFT JOIN DatosGenerales.IDIOMA AS i ON i.codigo_iso = LOWER(TRIM(c.value))
    WHERE TRIM(c.value) <> '';

    IF NOT EXISTS (SELECT 1 FROM @codigos)
        SET @errores += @nl + N'- Hay que informar al menos un idioma (códigos ISO 639-1 separados por comas).';

    SET @errores += ISNULL((
        SELECT @nl + N'- Idiomas que no existen: ' + STRING_AGG(codigo, ', ') + N'.'
        FROM @codigos
        WHERE id_idioma IS NULL), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_RegistrarArbitro: no se pudo registrar el árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Arbitraje.usp_ARBITRO_Alta
            @id_pais = @id_pais, @nombre = @nombre, @apellido = @apellido,
            @categoria = @categoria, @fecha_nacimiento = @fecha_nacimiento,
            @id_arbitro = @id_arbitro OUTPUT;

        INSERT INTO Arbitraje.ARBITRO_IDIOMA (id_arbitro, id_idioma)
        SELECT @id_arbitro, id_idioma FROM @codigos;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @mostrar = 1
        SELECT a.id_arbitro, a.apellido, a.nombre, pa.nombre AS pais, a.categoria,
               STRING_AGG(i.nombre, ', ') WITHIN GROUP (ORDER BY i.nombre) AS idiomas
        FROM Arbitraje.ARBITRO AS a
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        INNER JOIN Arbitraje.ARBITRO_IDIOMA AS ai ON ai.id_arbitro = a.id_arbitro
        INNER JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = ai.id_idioma
        WHERE a.id_arbitro = @id_arbitro
        GROUP BY a.id_arbitro, a.apellido, a.nombre, pa.nombre, a.categoria;
END;
GO


/*
  usp_DesignarTernaArbitral
  Designa en una sola transacción a los cinco árbitros de un partido:
  principal, asistente 1, asistente 2, cuarto árbitro y VAR. Valida:
    - partido existente, PROGRAMADO, con las dos selecciones definidas y sin
      árbitros designados todavía;
    - los cinco árbitros informados, distintos, existentes y activos;
    - conflicto de nacionalidad: ninguno puede ser del país de una de las
      dos selecciones (lo rechaza con el detalle de cada caso);
    - el principal y el VAR tienen que ser de categoría FIFA;
    - ninguno puede tener otro partido a menos de 24 horas.
  Desde dieciseisavos, advierte (sin impedir la designación) cuando un
  árbitro es de un país que puede cruzarse con los que juegan el partido.
  Con esas validaciones cubre las reglas de Arbitraje.usp_DESIGNACION_ARBITRAL_Alta
  y designa a los cinco con un solo INSERT.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_DesignarTernaArbitral
    @id_partido      INT,
    @id_principal    INT,
    @id_asistente_1  INT,
    @id_asistente_2  INT,
    @id_cuarto       INT,
    @id_var          INT,
    @mostrar         BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @advertencias NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @estado       VARCHAR(12);
    DECLARE @fase         VARCHAR(15);
    DECLARE @utc          DATETIME2(0);
    DECLARE @local        INT;
    DECLARE @visitante    INT;

    DECLARE @terna TABLE (rol VARCHAR(12) PRIMARY KEY, id_arbitro INT);
    INSERT INTO @terna (rol, id_arbitro)
    VALUES ('PRINCIPAL', @id_principal), ('ASISTENTE_1', @id_asistente_1),
           ('ASISTENTE_2', @id_asistente_2), ('CUARTO', @id_cuarto), ('VAR', @id_var);

    SELECT @estado = estado, @fase = fase, @utc = fecha_hora_utc,
           @local = id_seleccion_local, @visitante = id_seleccion_visitante
    FROM Torneo.PARTIDO
    WHERE id_partido = @id_partido;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        IF @estado <> 'PROGRAMADO'
            SET @errores += @nl + N'- Las designaciones se hacen antes de que empiece el partido (estado actual: '
                          + @estado + N').';
        IF @local IS NULL OR @visitante IS NULL
            SET @errores += @nl + N'- Las dos selecciones del partido tienen que estar definidas para controlar la nacionalidad.';
        IF EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido)
            SET @errores += @nl + N'- El partido ya tiene árbitros designados: los cambios se hacen con '
                          + N'usp_DESIGNACION_ARBITRAL_Baja y usp_DESIGNACION_ARBITRAL_Alta.';
    END;

    SET @errores += ISNULL((
        SELECT @nl + N'- Faltan árbitros para: ' + STRING_AGG(rol, ', ') + N'.'
        FROM @terna WHERE id_arbitro IS NULL), N'');

    IF EXISTS (SELECT id_arbitro FROM @terna WHERE id_arbitro IS NOT NULL GROUP BY id_arbitro HAVING COUNT(*) > 1)
        SET @errores += @nl + N'- Un mismo árbitro no puede cumplir dos roles en el partido.';

    SET @errores += ISNULL((
        SELECT @nl + N'- No existen árbitros con id: ' + STRING_AGG(CAST(t.id_arbitro AS NVARCHAR(10)), ', ') + N'.'
        FROM @terna AS t
        WHERE t.id_arbitro IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO AS a WHERE a.id_arbitro = t.id_arbitro)), N'');

    SET @errores += ISNULL((
        SELECT STRING_AGG(@nl + N'- ' + a.apellido + N', ' + a.nombre + N' (' + t.rol + N') no está activo.', N'')
        FROM @terna AS t
        INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = t.id_arbitro
        WHERE a.activo = 0), N'');

    -- Conflicto de nacionalidad.
    SET @errores += ISNULL((
        SELECT STRING_AGG(@nl + N'- Conflicto de nacionalidad: ' + a.apellido + N', ' + a.nombre + N' ('
                          + t.rol + N') es de ' + pa.nombre + N', que juega este partido.', N'')
        FROM @terna AS t
        INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = t.id_arbitro
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        INNER JOIN Torneo.SELECCION AS s ON s.id_pais = a.id_pais
        WHERE s.id_seleccion IN (@local, @visitante)), N'');

    SET @errores += ISNULL((
        SELECT STRING_AGG(@nl + N'- ' + a.apellido + N', ' + a.nombre + N' no puede ser ' + t.rol
                          + N': tiene que ser de categoría FIFA.', N'')
        FROM @terna AS t
        INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = t.id_arbitro
        WHERE t.rol IN ('PRINCIPAL', 'VAR') AND a.categoria <> 'FIFA'), N'');

    SET @errores += ISNULL((
        SELECT STRING_AGG(@nl + N'- ' + a.apellido + N', ' + a.nombre + N' ya dirige el partido '
                          + CAST(p.numero_partido AS NVARCHAR(3)) + N', a menos de 24 horas.', N'')
        FROM @terna AS t
        INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = t.id_arbitro
        INNER JOIN Arbitraje.DESIGNACION_ARBITRAL AS d ON d.id_arbitro = t.id_arbitro
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
        WHERE d.id_partido <> @id_partido
          AND ABS(DATEDIFF(MINUTE, p.fecha_hora_utc, @utc)) < 1440), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_DesignarTernaArbitral: no se pudo designar a los árbitros.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Advertencias por posible cruce, desde dieciseisavos.
    IF @fase <> 'GRUPOS'
        SET @advertencias = ISNULL((
            SELECT STRING_AGG(@nl + N'- ' + a.apellido + N', ' + a.nombre + N' (' + t.rol + N') es de '
                              + pa.nombre + N', que sigue en competencia y puede cruzarse con las selecciones de este partido.', N'')
            FROM @terna AS t
            INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = t.id_arbitro
            INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
            INNER JOIN Torneo.fn_SeleccionesEnCompetencia() AS sc ON sc.id_pais = a.id_pais
            WHERE sc.id_seleccion NOT IN (@local, @visitante)), N'');

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol)
        SELECT @id_partido, id_arbitro, rol FROM @terna;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @advertencias <> N''
        PRINT N'Advertencia de Arbitraje.usp_DesignarTernaArbitral (la designación se hizo igual):' + @advertencias;

    IF @mostrar = 1
        SELECT d.rol, a.apellido, a.nombre, pa.nombre AS pais, a.categoria,
               IIF(@fase <> 'GRUPOS' AND sc.id_seleccion IS NOT NULL AND sc.id_seleccion NOT IN (@local, @visitante),
                   'PUEDE CRUZARSE', '') AS advertencia
        FROM Arbitraje.DESIGNACION_ARBITRAL AS d
        INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = d.id_arbitro
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        LEFT JOIN Torneo.fn_SeleccionesEnCompetencia() AS sc ON sc.id_pais = a.id_pais
        WHERE d.id_partido = @id_partido
        ORDER BY CHARINDEX(d.rol, 'PRINCIPAL ASISTENTE_1 ASISTENTE_2 CUARTO VAR');
END;
GO


-- Evidencia: SP de negocio creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Arbitraje'
  AND p.name IN (N'usp_RegistrarArbitro', N'usp_DesignarTernaArbitral')
ORDER BY p.name;
GO
