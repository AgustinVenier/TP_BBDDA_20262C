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
 Archivo: 15_SP_Negocio_Publicidad.sql
 Objetivo: Crear los SP de lógica de negocio para la publicidad:
             Publicidad.usp_RegistrarPiezaPublicitaria  pieza con sus mercados de interés
             Publicidad.usp_AsignarPublicidadPartido     las 4 piezas de un partido, o de todos
                                                         los que no tienen publicidad
           La simulación de prime time es Publicidad.fn_MercadosEnPrimeTime y
           el criterio de prioridad está documentado en
           Publicidad.fn_PrioridadPiezas (04_CrearFuncionesYVistas.sql).
           Siguen las convenciones de 10_SP_Negocio_SedesYPartidos.sql.
           Requiere haber ejecutado 01 a 09. Su script de testing es
           65_Test_SP_Negocio_Publicidad.sql.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_RegistrarPiezaPublicitaria
  Registra una pieza con sus mercados de interés en una sola transacción.
  @mercados es una lista de códigos FIFA de países separados por comas (ej.
  'ARG,URU,PAR') y @codigo_idioma el código ISO 639-1 del idioma de la pieza.
  Valida: al menos un mercado, que todos los códigos de país existan y que el
  idioma exista. Los datos de la pieza los valida
  Publicidad.usp_PIEZA_PUBLICITARIA_Alta. Los mercados se cargan con un solo
  INSERT: la pieza es nueva y los países ya están validados, así que no queda
  nada que controle Publicidad.usp_PIEZA_PAIS_INTERES_Alta.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_RegistrarPiezaPublicitaria
    @id_campania        INT,
    @titulo             NVARCHAR(300),
    @mercados           VARCHAR(400),
    @codigo_idioma      VARCHAR(10) = NULL,
    @duracion_segundos  TINYINT     = NULL,
    @id_pieza           INT         = NULL OUTPUT,
    @mostrar            BIT         = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores     NVARCHAR(2048) = N'';
    DECLARE @nl          NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @id_idioma   SMALLINT;

    DECLARE @paises TABLE (codigo VARCHAR(10) PRIMARY KEY, id_pais SMALLINT);

    INSERT INTO @paises (codigo, id_pais)
    SELECT DISTINCT UPPER(TRIM(m.value)), pa.id_pais
    FROM STRING_SPLIT(@mercados, ',') AS m
    LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = UPPER(TRIM(m.value))
    WHERE TRIM(m.value) <> '';

    SET @codigo_idioma = LOWER(NULLIF(TRIM(@codigo_idioma), ''));
    SELECT @id_idioma = id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = @codigo_idioma;

    IF NOT EXISTS (SELECT 1 FROM @paises)
        SET @errores += @nl + N'- Hay que informar al menos un mercado de interés (códigos FIFA separados por comas).';

    SET @errores += ISNULL((
        SELECT @nl + N'- Códigos de país que no existen: ' + STRING_AGG(codigo, ', ') + N'.'
        FROM @paises
        WHERE id_pais IS NULL), N'');

    IF @codigo_idioma IS NOT NULL AND @id_idioma IS NULL
        SET @errores += @nl + N'- No existe el idioma con código "' + @codigo_idioma + N'".';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_RegistrarPiezaPublicitaria: no se pudo registrar la pieza.' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Alta
            @id_campania = @id_campania, @titulo = @titulo, @id_idioma = @id_idioma,
            @duracion_segundos = @duracion_segundos, @id_pieza = @id_pieza OUTPUT;

        INSERT INTO Publicidad.PIEZA_PAIS_INTERES (id_pieza, id_pais)
        SELECT @id_pieza, id_pais FROM @paises;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @mostrar = 1
        SELECT pz.id_pieza, pz.titulo, c.nombre AS campania, i.nombre AS idioma,
               STRING_AGG(pa.nombre, ', ') WITHIN GROUP (ORDER BY pa.nombre) AS mercados
        FROM Publicidad.PIEZA_PUBLICITARIA AS pz
        INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
        LEFT JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = pz.id_idioma
        INNER JOIN Publicidad.PIEZA_PAIS_INTERES AS ppi ON ppi.id_pieza = pz.id_pieza
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = ppi.id_pais
        WHERE pz.id_pieza = @id_pieza
        GROUP BY pz.id_pieza, pz.titulo, c.nombre, i.nombre;
END;
GO


/*
  usp_AsignarPublicidadPartido
  Propone y registra las cuatro piezas que ocupan los espacios de la sede en
  un partido, según la prioridad de Publicidad.fn_PrioridadPiezas: la pieza
  de mayor prioridad va al espacio de mayor tarifa, y así sucesivamente. El
  costo de cada exhibición es la tarifa del espacio en ese momento.
  Sin @id_partido, la asigna de una vez en todos los partidos que todavía no
  tienen publicidad: los que no cumplen las reglas quedan sin asignar y se
  informan con sus motivos, y los demás se asignan igual.
  Un partido que ya empezó o se jugó recibe su publicidad si no tiene
  ninguna: es el registro histórico de lo que se exhibió, como en la carga
  del torneo real, que trae los partidos ya jugados. La que ya tiene no se
  cambia.
  Valida: partido existente; que la sede tenga sus 4 espacios; que haya al
  menos 4 piezas candidatas; que el partido no tenga ya publicidad asignada,
  salvo que esté PROGRAMADO y se pida reasignar (@reasignar = 1), en cuyo
  caso se reemplaza en la misma transacción. Las demás reglas de
  Publicidad.usp_EXHIBICION_Baja y usp_EXHIBICION_Alta las cumple la
  propuesta (los espacios son de la sede y fn_PrioridadPiezas solo devuelve
  piezas vigentes y sin repetir), así que borra y carga las exhibiciones con
  un DELETE y un INSERT.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_AsignarPublicidadPartido
    @id_partido  INT = NULL,
    @reasignar   BIT = 0,
    @mostrar     BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048);
    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- El partido indicado, o todos los que no tienen publicidad, con lo que validan las reglas.
    DECLARE @partidos TABLE (
        id_partido  INT PRIMARY KEY,
        id_sede     INT,
        estado      VARCHAR(12),
        espacios    INT,
        candidatas  INT,
        asignadas   INT,
        errores     NVARCHAR(2048)
    );

    DECLARE @propuesta TABLE (
        id_partido  INT,
        orden       INT,
        id_espacio  INT,
        id_pieza    INT,
        costo       DECIMAL(9,2),
        PRIMARY KEY (id_partido, orden)
    );

    IF @id_partido IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE id_partido = @id_partido)
    BEGIN
        SET @errores = N'Publicidad.usp_AsignarPublicidadPartido: no se pudo asignar la publicidad.'
                     + @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
        THROW 50001, @errores, 1;
    END;

    INSERT INTO @partidos (id_partido, id_sede, estado, espacios, candidatas, asignadas)
    SELECT p.id_partido, p.id_sede, p.estado,
           (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO AS e WHERE e.id_sede = p.id_sede),
           (SELECT COUNT(*) FROM Publicidad.fn_PrioridadPiezas(p.id_partido)),
           (SELECT COUNT(*) FROM Publicidad.EXHIBICION AS ex WHERE ex.id_partido = p.id_partido)
    FROM Torneo.PARTIDO AS p
    WHERE p.id_partido = @id_partido
       OR (@id_partido IS NULL
           AND NOT EXISTS (SELECT 1 FROM Publicidad.EXHIBICION AS ex WHERE ex.id_partido = p.id_partido));

    UPDATE @partidos
    SET errores = NULLIF(CONCAT(
            IIF(asignadas > 0 AND estado <> 'PROGRAMADO',
                @nl + N'- El partido ya empezó (estado actual: ' + estado
                    + N') y tiene su publicidad: la que se exhibió no se cambia.', NULL),
            IIF(espacios <> 4,
                CONCAT(@nl, N'- La sede tiene ', espacios, N' espacios publicitarios: tienen que ser 4.'), NULL),
            IIF(candidatas < 4,
                CONCAT(@nl, N'- Hay ', candidatas,
                       N' piezas candidatas (de campañas vigentes y con mercados de interés): hacen falta 4.'), NULL),
            IIF(asignadas > 0 AND estado = 'PROGRAMADO' AND ISNULL(@reasignar, 0) = 0,
                @nl + N'- El partido ya tiene publicidad asignada: para reemplazarla, @reasignar = 1.', NULL)), N'');

    -- Un partido indicado que no cumple las reglas: no se asigna nada.
    SELECT @errores = errores FROM @partidos WHERE @id_partido IS NOT NULL;
    IF @errores IS NOT NULL
    BEGIN
        SET @errores = N'Publicidad.usp_AsignarPublicidadPartido: no se pudo asignar la publicidad.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- En cada partido, las 4 piezas de mayor prioridad, en los espacios de mayor a menor tarifa.
    INSERT INTO @propuesta (id_partido, orden, id_espacio, id_pieza, costo)
    SELECT pt.id_partido, e.orden, e.id_espacio, pz.id_pieza, e.tarifa_usd
    FROM @partidos AS pt
    CROSS APPLY (SELECT id_espacio, tarifa_usd, ROW_NUMBER() OVER (ORDER BY tarifa_usd DESC, numero_espacio) AS orden
                 FROM Publicidad.ESPACIO_PUBLICITARIO
                 WHERE id_sede = pt.id_sede) AS e
    CROSS APPLY Publicidad.fn_PrioridadPiezas(pt.id_partido) AS pz
    WHERE pt.errores IS NULL AND pz.prioridad = e.orden;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- Reasignación: se quitan las exhibiciones anteriores.
        DELETE ex
        FROM Publicidad.EXHIBICION AS ex
        INNER JOIN @partidos AS pt ON pt.id_partido = ex.id_partido
        WHERE pt.errores IS NULL;

        -- El costo de cada exhibición es la tarifa del espacio en ese momento.
        INSERT INTO Publicidad.EXHIBICION (id_partido, id_espacio, id_pieza, costo, codigo_moneda)
        SELECT id_partido, id_espacio, id_pieza, costo, 'USD'
        FROM @propuesta;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    -- Todos los que no tenían: cuántos se asignaron y los que no, con sus motivos.
    IF @mostrar = 1 AND @id_partido IS NULL
    BEGIN
        SELECT COUNT(*)                                   AS partidos_sin_publicidad,
               ISNULL(SUM(IIF(errores IS NULL, 1, 0)), 0) AS asignados,
               ISNULL(SUM(IIF(errores IS NULL, 0, 1)), 0) AS sin_asignar
        FROM @partidos;

        SELECT p.numero_partido, STUFF(pt.errores, 1, 2, N'') AS motivos
        FROM @partidos AS pt
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = pt.id_partido
        WHERE pt.errores IS NOT NULL
        ORDER BY p.numero_partido;
    END;

    IF @mostrar = 1 AND @id_partido IS NOT NULL
        SELECT ep.numero_espacio, ex.costo, ex.codigo_moneda, pr.prioridad, pr.anunciante, pr.campania,
               pr.titulo, pr.dirigida_a_seleccion, pr.franja_pbi, pr.mercados_en_prime_time, pr.pbi_per_capita_max
        FROM Publicidad.EXHIBICION AS ex
        INNER JOIN Publicidad.ESPACIO_PUBLICITARIO AS ep ON ep.id_espacio = ex.id_espacio
        INNER JOIN Publicidad.fn_PrioridadPiezas(@id_partido) AS pr ON pr.id_pieza = ex.id_pieza
        WHERE ex.id_partido = @id_partido
        ORDER BY pr.prioridad;
END;
GO


-- Evidencia: SP de negocio creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'Publicidad'
  AND p.name IN (N'usp_RegistrarPiezaPublicitaria', N'usp_AsignarPublicidadPartido')
ORDER BY p.name;
GO
