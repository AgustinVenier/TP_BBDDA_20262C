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
             Arbitraje.usp_CargarInformesArbitrales  informes y sanciones, todos juntos (lo usa el 33)
           Siguen las convenciones de 10_SP_Negocio_SedesYPartidos.sql.
           Requiere haber ejecutado 01 a 09. Su script de testing es
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
    @mostrar_resultados           BIT  = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @salto_linea NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT            = IIF(@@TRANCOUNT = 0, 1, 0);

    DECLARE @codigos TABLE (codigo VARCHAR(10) PRIMARY KEY, id_idioma SMALLINT);

    INSERT INTO @codigos (codigo, id_idioma)
    SELECT DISTINCT LOWER(TRIM(c.value)), i.id_idioma
    FROM STRING_SPLIT(@idiomas, ',') AS c
    LEFT JOIN DatosGenerales.IDIOMA AS i ON i.codigo_iso = LOWER(TRIM(c.value))
    WHERE TRIM(c.value) <> '';

    IF NOT EXISTS (SELECT 1 FROM @codigos)
        SET @errores += @salto_linea + N'- Hay que informar al menos un idioma (códigos ISO 639-1 separados por comas).';

    SET @errores += ISNULL((
        SELECT @salto_linea + N'- Idiomas que no existen: ' + STRING_AGG(codigo, ', ') + N'.'
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

    IF @mostrar_resultados = 1
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
    - el principal y el VAR tienen que ser de categoría FIFA.
  Desde dieciseisavos, advierte (sin impedir la designación) cuando un
  árbitro es de un país que puede cruzarse con los que juegan el partido.
  Los roles opcionales (ASISTENTE_RESERVA, AVAR y VAR_APOYO) se designan
  después, con usp_DESIGNACION_ARBITRAL_Alta.
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
    @mostrar_resultados         BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @advertencias NVARCHAR(2048) = N'';
    DECLARE @salto_linea  NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @estado       VARCHAR(12);
    DECLARE @fase         VARCHAR(15);
    DECLARE @local        INT;
    DECLARE @visitante    INT;

    DECLARE @terna TABLE (rol VARCHAR(17) PRIMARY KEY, id_arbitro INT);
    INSERT INTO @terna (rol, id_arbitro)
    VALUES ('PRINCIPAL', @id_principal), ('ASISTENTE_1', @id_asistente_1),
           ('ASISTENTE_2', @id_asistente_2), ('CUARTO', @id_cuarto), ('VAR', @id_var);

    SELECT @estado = estado, @fase = fase,
           @local = id_seleccion_local, @visitante = id_seleccion_visitante
    FROM Torneo.PARTIDO
    WHERE id_partido = @id_partido;

    IF @id_partido IS NULL
        SET @errores += @salto_linea + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @salto_linea + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        IF @estado <> 'PROGRAMADO'
            SET @errores += @salto_linea + N'- Las designaciones se hacen antes de que empiece el partido (estado actual: '
                          + @estado + N').';
        IF @local IS NULL OR @visitante IS NULL
            SET @errores += @salto_linea + N'- Las dos selecciones del partido tienen que estar definidas para controlar la nacionalidad.';
        IF EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido)
            SET @errores += @salto_linea + N'- El partido ya tiene árbitros designados: los cambios se hacen con '
                          + N'usp_DESIGNACION_ARBITRAL_Baja y usp_DESIGNACION_ARBITRAL_Alta.';
    END;

    SET @errores += ISNULL((
        SELECT @salto_linea + N'- Faltan árbitros para: ' + STRING_AGG(rol, ', ') + N'.'
        FROM @terna WHERE id_arbitro IS NULL), N'');

    IF EXISTS (SELECT id_arbitro FROM @terna WHERE id_arbitro IS NOT NULL GROUP BY id_arbitro HAVING COUNT(*) > 1)
        SET @errores += @salto_linea + N'- Un mismo árbitro no puede cumplir dos roles en el partido.';

    SET @errores += ISNULL((
        SELECT @salto_linea + N'- No existen árbitros con id: ' + STRING_AGG(CAST(t.id_arbitro AS NVARCHAR(10)), ', ') + N'.'
        FROM @terna AS t
        WHERE t.id_arbitro IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO AS a WHERE a.id_arbitro = t.id_arbitro)), N'');

    SET @errores += ISNULL((
        SELECT STRING_AGG(@salto_linea + N'- ' + a.apellido + N', ' + a.nombre + N' (' + t.rol + N') no está activo.', N'')
        FROM @terna AS t
        INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = t.id_arbitro
        WHERE a.activo = 0), N'');

    -- Conflicto de nacionalidad.
    SET @errores += ISNULL((
        SELECT STRING_AGG(@salto_linea + N'- Conflicto de nacionalidad: ' + a.apellido + N', ' + a.nombre + N' ('
                          + t.rol + N') es de ' + pa.nombre + N', que juega este partido.', N'')
        FROM @terna AS t
        INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = t.id_arbitro
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        INNER JOIN Torneo.SELECCION AS s ON s.id_pais = a.id_pais
        WHERE s.id_seleccion IN (@local, @visitante)), N'');

    SET @errores += ISNULL((
        SELECT STRING_AGG(@salto_linea + N'- ' + a.apellido + N', ' + a.nombre + N' no puede ser ' + t.rol
                          + N': tiene que ser de categoría FIFA.', N'')
        FROM @terna AS t
        INNER JOIN Arbitraje.ARBITRO AS a ON a.id_arbitro = t.id_arbitro
        WHERE t.rol IN ('PRINCIPAL', 'VAR') AND a.categoria <> 'FIFA'), N'');

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_DesignarTernaArbitral: no se pudo designar a los árbitros.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Advertencias por posible cruce, desde dieciseisavos.
    IF @fase <> 'GRUPOS'
        SET @advertencias = ISNULL((
            SELECT STRING_AGG(@salto_linea + N'- ' + a.apellido + N', ' + a.nombre + N' (' + t.rol + N') es de '
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

    IF @mostrar_resultados = 1
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


/*
  usp_CargarInformesArbitrales
  Informes post-partido y sanciones de los árbitros, por partido (número) y
  rol, desde #staging_informes. Columnas que usa: id_registro (distinto en
  cada fila), numero_partido, rol, informe_postpartido, sancion, errores y
  accion. Completa las designaciones ya cargadas (usp_CargarDesignaciones
  no toca el informe ni la sanción): un dato que no viene (NULL) no borra el
  guardado.
  Valida cada fila pendiente: partido existente; rol válido y designado en
  ese partido; que traiga el informe o la sanción; sanción de hasta 500
  caracteres; que no venga dos veces el mismo partido y rol.
  Una fila queda ACTUALIZADO si cambió el informe o la sanción; si no, SIN
  CAMBIOS.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_CargarInformesArbitrales
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @salto_linea NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- El partido y la designación ya registrados de cada fila pendiente.
    DECLARE @registradas TABLE (
        id_registro  INT PRIMARY KEY,
        id_partido   INT,
        id_arbitro   INT,
        informe      VARCHAR(MAX),
        sancion      VARCHAR(500)
    );

    IF OBJECT_ID(N'tempdb..#staging_informes') IS NULL
        THROW 50001, N'Arbitraje.usp_CargarInformesArbitrales: no se importó nada, falta la tabla #staging_informes con los informes.', 1;

    UPDATE #staging_informes
    SET rol                 = UPPER(NULLIF(TRIM(rol), '')),
        informe_postpartido = NULLIF(TRIM(informe_postpartido), ''),
        sancion             = NULLIF(TRIM(sancion), '')
    WHERE accion IS NULL;

    INSERT INTO @registradas (id_registro, id_partido, id_arbitro, informe, sancion)
    SELECT st.id_registro, p.id_partido, d.id_arbitro, d.informe_postpartido, d.sancion
    FROM #staging_informes AS st
    LEFT JOIN Torneo.PARTIDO AS p ON p.numero_partido = st.numero_partido
    LEFT JOIN Arbitraje.DESIGNACION_ARBITRAL AS d ON d.id_partido = p.id_partido AND d.rol = st.rol
    WHERE st.accion IS NULL;

    /* 1. Las reglas de cada fila. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.numero_partido IS NULL THEN @salto_linea + N'- El número de partido es obligatorio.'
                 WHEN r.id_partido IS NULL     THEN @salto_linea + N'- No hay un partido con el número '
                                                         + CAST(st.numero_partido AS NVARCHAR(3)) + N'.'
            END,
            CASE WHEN st.rol IS NULL THEN @salto_linea + N'- El rol es obligatorio.'
                 WHEN r.id_partido IS NOT NULL AND r.id_arbitro IS NULL
                     THEN @salto_linea + N'- El partido no tiene un árbitro designado con el rol ' + st.rol + N'.'
            END,
            IIF(st.informe_postpartido IS NULL AND st.sancion IS NULL,
                @salto_linea + N'- Hay que informar el informe post-partido o la sanción.', NULL),
            IIF(LEN(st.sancion) > 500, @salto_linea + N'- La sanción no puede superar los 500 caracteres.', NULL)), N'')
    FROM #staging_informes AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro;

    WITH validas AS (
        SELECT st.errores, ROW_NUMBER() OVER (PARTITION BY r.id_partido, st.rol ORDER BY st.id_registro) AS n
        FROM #staging_informes AS st
        INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
        WHERE st.errores IS NULL
    )
    UPDATE validas
    SET errores = @salto_linea + N'- El partido y el rol vienen más de una vez (se toma el primero).'
    WHERE n > 1;

    UPDATE #staging_informes SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 2. Lo que le pasa a cada fila válida, antes de cargar. */
    UPDATE st
    SET accion = IIF(ISNULL(st.informe_postpartido, ISNULL(r.informe, '')) = ISNULL(r.informe, '')
                     AND ISNULL(st.sancion, ISNULL(r.sancion, '')) = ISNULL(r.sancion, ''),
                     'SIN CAMBIOS', 'ACTUALIZADO')
    FROM #staging_informes AS st
    INNER JOIN @registradas AS r ON r.id_registro = st.id_registro
    WHERE st.accion IS NULL;

    /* 3. Carga, todos juntos. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        UPDATE d
        SET informe_postpartido = ISNULL(st.informe_postpartido, d.informe_postpartido),
            sancion             = ISNULL(st.sancion, d.sancion)
        FROM Arbitraje.DESIGNACION_ARBITRAL AS d
        INNER JOIN @registradas AS r ON r.id_partido = d.id_partido AND r.id_arbitro = d.id_arbitro
        INNER JOIN #staging_informes AS st ON st.id_registro = r.id_registro
        WHERE st.accion = 'ACTUALIZADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- Evidencia: SP de negocio creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Arbitraje'
  AND p.name IN (N'usp_RegistrarArbitro', N'usp_DesignarTernaArbitral', N'usp_CargarInformesArbitrales')
ORDER BY p.name;
GO
