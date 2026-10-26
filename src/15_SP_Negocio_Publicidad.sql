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
             Publicidad.usp_AsignarPublicidadPartido     las 4 piezas de un partido
           La simulación de prime time es Publicidad.fn_MercadosEnPrimeTime y
           el criterio de prioridad está documentado en
           Publicidad.fn_PrioridadPiezas (03_CrearFuncionesYVistas.sql).
           Siguen las convenciones de 10_SP_Negocio_SedesYPartidos.sql.
           Requiere haber ejecutado 00 a 08. Su script de testing es
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
  Publicidad.usp_PIEZA_PUBLICITARIA_Alta.
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
    DECLARE @id_pais     SMALLINT;

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

        WHILE EXISTS (SELECT 1 FROM @paises)
        BEGIN
            SELECT TOP (1) @id_pais = id_pais FROM @paises ORDER BY codigo;
            EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Alta @id_pieza = @id_pieza, @id_pais = @id_pais;
            DELETE FROM @paises WHERE id_pais = @id_pais;
        END;

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
  Valida: partido existente y PROGRAMADO; que la sede tenga sus 4 espacios;
  que haya al menos 4 piezas candidatas; que el partido no tenga ya
  publicidad asignada, salvo que se pida reasignar (@reasignar = 1), en cuyo
  caso se reemplaza en la misma transacción.
*/
CREATE OR ALTER PROCEDURE Publicidad.usp_AsignarPublicidadPartido
    @id_partido  INT,
    @reasignar   BIT = 0,
    @mostrar     BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores      NVARCHAR(2048) = N'';
    DECLARE @nl           NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @estado       VARCHAR(12);
    DECLARE @id_sede      INT;
    DECLARE @espacios     INT;
    DECLARE @candidatas   INT;
    DECLARE @asignadas    INT;
    DECLARE @id_espacio   INT;
    DECLARE @id_pieza     INT;
    DECLARE @orden        INT;

    DECLARE @propuesta TABLE (orden INT PRIMARY KEY, id_espacio INT, id_pieza INT);

    SELECT @estado = estado, @id_sede = id_sede FROM Torneo.PARTIDO WHERE id_partido = @id_partido;
    SELECT @espacios = COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id_sede;
    SELECT @candidatas = COUNT(*) FROM Publicidad.fn_PrioridadPiezas(@id_partido);
    SELECT @asignadas = COUNT(*) FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE
    BEGIN
        IF @estado <> 'PROGRAMADO'
            SET @errores += @nl + N'- La publicidad se asigna antes de que empiece el partido (estado actual: '
                          + @estado + N').';
        IF @espacios <> 4
            SET @errores += @nl + N'- La sede tiene ' + CAST(@espacios AS NVARCHAR(3))
                          + N' espacios publicitarios: tienen que ser 4.';
        IF @candidatas < 4
            SET @errores += @nl + N'- Hay ' + CAST(@candidatas AS NVARCHAR(3))
                          + N' piezas candidatas (de campañas vigentes y con mercados de interés): hacen falta 4.';
        IF @asignadas > 0 AND ISNULL(@reasignar, 0) = 0
            SET @errores += @nl + N'- El partido ya tiene publicidad asignada: para reemplazarla, @reasignar = 1.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Publicidad.usp_AsignarPublicidadPartido: no se pudo asignar la publicidad.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Las 4 piezas de mayor prioridad, en los espacios de mayor a menor tarifa.
    INSERT INTO @propuesta (orden, id_espacio, id_pieza)
    SELECT e.orden, e.id_espacio, pz.id_pieza
    FROM (SELECT id_espacio, ROW_NUMBER() OVER (ORDER BY tarifa_usd DESC, numero_espacio) AS orden
          FROM Publicidad.ESPACIO_PUBLICITARIO
          WHERE id_sede = @id_sede) AS e
    INNER JOIN Publicidad.fn_PrioridadPiezas(@id_partido) AS pz ON pz.prioridad = e.orden;

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- Reasignación: se quitan las exhibiciones anteriores.
        WHILE EXISTS (SELECT 1 FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido)
        BEGIN
            SELECT TOP (1) @id_espacio = id_espacio FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido;
            EXEC Publicidad.usp_EXHIBICION_Baja @id_partido = @id_partido, @id_espacio = @id_espacio;
        END;

        SET @orden = 1;
        WHILE @orden <= 4
        BEGIN
            SELECT @id_espacio = id_espacio, @id_pieza = id_pieza FROM @propuesta WHERE orden = @orden;
            EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @id_partido, @id_espacio = @id_espacio, @id_pieza = @id_pieza;
            SET @orden += 1;
        END;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    IF @mostrar = 1
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
