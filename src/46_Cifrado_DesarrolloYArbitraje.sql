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

 Fecha: 08/11/2026
 Archivo: 46_Cifrado_DesarrolloYArbitraje.sql
 Objetivo: Modificar las funciones, vistas y SP de DesarrolloPartido y
           Arbitraje que leen o escriben el nombre, el apellido o la fecha de
           nacimiento de jugadores y árbitros, para que los lean descifrados y
           los guarden cifrados.
           Su script de testing es 96_Test_Cifrado_DesarrolloYArbitraje.sql.
================================================================================

 Orden: lo ejecuta 40_Ejecutar_Cifrado.sql, después de 42 a 44 (Cifrado_Tabla_).

 Cada objeto es el de su script original (indicado arriba de cada uno), con
 estos cambios:
   - Lectura: las consultas que usan esos datos leen las vistas descifradas de
     42 y 44 (Seguridad.vw_Jugador, Seguridad.vw_Arbitro) en lugar de las tablas.
     Tienen las mismas columnas, así que el resto de la consulta no cambia.
   - Búsquedas y controles de duplicados: comparan sobre las vistas
     descifradas. El control de árbitro repetido reemplaza a
     UQ_ARBITRO_pais_apellido_nombre, que se eliminó porque el mismo nombre
     cifrado dos veces da bytes distintos.
   - Escritura: el INSERT o UPDATE sigue sobre la tabla. El SP abre la clave
     (Seguridad.usp_AbrirClave), cifra con Seguridad.fn_CifrarTexto y
     Seguridad.fn_CifrarFecha, y la cierra (Seguridad.usp_CerrarClave), también
     si hay un error.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO


-- Original en 04_CrearFuncionesYVistas.sql. Cambio: lee los jugadores de Seguridad.vw_Jugador.
/*
  fn_EquipoEnCancha
  Reconstruye los jugadores de una selección que estaban en cancha en un
  instante del partido: los titulares que no salieron, más los suplentes que
  entraron y no salieron, menos los expulsados.
  Ej.: SELECT * FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion, 90, 3);
  Para el final del partido (definición por penales) se usa minuto 120 y
  adicional 99.
*/
CREATE OR ALTER FUNCTION DesarrolloPartido.fn_EquipoEnCancha
(
    @id_partido       INT,
    @id_seleccion     INT,
    @minuto           TINYINT,
    @minuto_adicional TINYINT
)
RETURNS TABLE
AS
RETURN
    SELECT j.id_jugador,
           j.dorsal,
           j.apellido,
           j.nombre,
           a.es_titular,
           a.posicion_en_cancha,
           ingreso.minuto           AS minuto_ingreso,
           ingreso.minuto_adicional AS adicional_ingreso
    FROM DesarrolloPartido.FORMACION AS f
    INNER JOIN DesarrolloPartido.ALINEACION AS a ON a.id_formacion = f.id_formacion
    INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = a.id_jugador
    OUTER APPLY (SELECT c.minuto, c.minuto_adicional
                 FROM DesarrolloPartido.CAMBIO AS c
                 WHERE c.id_partido = f.id_partido
                   AND c.id_jugador_entra = a.id_jugador) AS ingreso
    WHERE f.id_partido = @id_partido
      AND f.id_seleccion = @id_seleccion
      AND (a.es_titular = 1
           OR ingreso.minuto * 100 + ingreso.minuto_adicional <= @minuto * 100 + @minuto_adicional)
      AND NOT EXISTS (SELECT 1
                      FROM DesarrolloPartido.CAMBIO AS c
                      WHERE c.id_partido = f.id_partido
                        AND c.id_jugador_sale = a.id_jugador
                        AND c.minuto * 100 + c.minuto_adicional <= @minuto * 100 + @minuto_adicional)
      AND NOT EXISTS (SELECT 1
                      FROM DesarrolloPartido.AMONESTACION AS r
                      WHERE r.id_partido = f.id_partido
                        AND r.id_jugador = a.id_jugador
                        AND r.tipo_tarjeta = 'ROJA'
                        AND r.minuto * 100 + r.minuto_adicional <= @minuto * 100 + @minuto_adicional);
GO


-- Original en 04_CrearFuncionesYVistas.sql. Cambio: lee los jugadores de Seguridad.vw_Jugador.
/*
  vw_HistorialTitularidad
  Una fila por jugador y partido en el que figuró en la formación: si fue
  titular o suplente, en qué minuto entró o salió y si fue expulsado.
*/
CREATE OR ALTER VIEW DesarrolloPartido.vw_HistorialTitularidad
AS
SELECT j.id_jugador,
       j.apellido,
       j.nombre,
       j.dorsal,
       ps.nombre                                              AS seleccion,
       p.id_partido,
       p.numero_partido,
       p.fase,
       p.fecha_hora_local,
       ISNULL(pr.nombre, 'A definir')                         AS rival,
       IIF(a.es_titular = 1, 'TITULAR', 'SUPLENTE')           AS condicion,
       a.posicion_en_cancha,
       IIF(a.es_titular = 1 OR ce.id_cambio IS NOT NULL, 1, 0) AS jugo,
       CASE WHEN ce.id_cambio IS NULL THEN NULL
            ELSE CONCAT(ce.minuto, IIF(ce.minuto_adicional > 0, CONCAT('+', ce.minuto_adicional), ''))
       END                                                    AS minuto_ingreso,
       CASE WHEN cs.id_cambio IS NULL THEN NULL
            ELSE CONCAT(cs.minuto, IIF(cs.minuto_adicional > 0, CONCAT('+', cs.minuto_adicional), ''))
       END                                                    AS minuto_salida,
       CASE WHEN roja.minuto IS NULL THEN NULL
            ELSE CONCAT(roja.minuto, IIF(roja.minuto_adicional > 0, CONCAT('+', roja.minuto_adicional), ''))
       END                                                    AS minuto_expulsion
FROM DesarrolloPartido.ALINEACION AS a
INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = a.id_jugador
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = f.id_seleccion
INNER JOIN DatosGenerales.PAIS AS ps ON ps.id_pais = s.id_pais
LEFT JOIN Torneo.SELECCION AS sr
       ON sr.id_seleccion = IIF(p.id_seleccion_local = f.id_seleccion, p.id_seleccion_visitante, p.id_seleccion_local)
LEFT JOIN DatosGenerales.PAIS AS pr ON pr.id_pais = sr.id_pais
LEFT JOIN DesarrolloPartido.CAMBIO AS ce ON ce.id_partido = p.id_partido AND ce.id_jugador_entra = a.id_jugador
LEFT JOIN DesarrolloPartido.CAMBIO AS cs ON cs.id_partido = p.id_partido AND cs.id_jugador_sale = a.id_jugador
OUTER APPLY (SELECT TOP (1) r.minuto, r.minuto_adicional
             FROM DesarrolloPartido.AMONESTACION AS r
             WHERE r.id_partido = p.id_partido
               AND r.id_jugador = a.id_jugador
               AND r.tipo_tarjeta = 'ROJA') AS roja;
GO


-- Original en 04_CrearFuncionesYVistas.sql. Cambio: lee los jugadores de Seguridad.vw_Jugador.
/*
  vw_Goleadores
  Goles por jugador. No cuentan los goles en contra ni los penales de la
  definición por penales. Para la tabla del torneo se ordena por goles; para
  la de una selección se filtra por id_seleccion.
*/
CREATE OR ALTER VIEW DesarrolloPartido.vw_Goleadores
AS
SELECT j.id_jugador,
       j.apellido,
       j.nombre,
       s.id_seleccion,
       ps.nombre                    AS seleccion,
       COUNT(*)                     AS goles,
       COUNT(DISTINCT g.id_partido) AS partidos_con_gol
FROM DesarrolloPartido.GOL AS g
INNER JOIN DesarrolloPartido.TIPO_GOL AS tg ON tg.id_tipo_gol = g.id_tipo_gol
INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = g.id_jugador_autor
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
INNER JOIN DatosGenerales.PAIS AS ps ON ps.id_pais = s.id_pais
WHERE tg.es_en_contra = 0
  AND g.periodo <> 'PENALES'
GROUP BY j.id_jugador, j.apellido, j.nombre, s.id_seleccion, ps.nombre;
GO


-- Original en 04_CrearFuncionesYVistas.sql. Cambio: lee los árbitros de Seguridad.vw_Arbitro.
/*
  vw_HistorialArbitro
  Partidos de cada árbitro con su rol, el resultado, las tarjetas del partido
  y el informe y la sanción post-partido que haya recibido.
*/
CREATE OR ALTER VIEW Arbitraje.vw_HistorialArbitro
AS
SELECT ar.id_arbitro,
       ar.apellido,
       ar.nombre,
       pa.nombre                           AS pais,
       ar.categoria,
       d.rol,
       f.id_partido,
       f.numero_partido,
       f.fase,
       f.fecha_hora_local,
       f.seleccion_local,
       f.seleccion_visitante,
       f.resultado,
       f.estado,
       ISNULL(t.amarillas, 0)              AS amarillas_del_partido,
       ISNULL(t.rojas, 0)                  AS rojas_del_partido,
       d.informe_postpartido,
       d.sancion
FROM Arbitraje.DESIGNACION_ARBITRAL AS d
INNER JOIN Seguridad.vw_Arbitro AS ar ON ar.id_arbitro = d.id_arbitro
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = ar.id_pais
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = d.id_partido
OUTER APPLY (SELECT SUM(IIF(am.tipo_tarjeta = 'AMARILLA', 1, 0)) AS amarillas,
                    SUM(IIF(am.tipo_tarjeta = 'ROJA', 1, 0))     AS rojas
             FROM DesarrolloPartido.AMONESTACION AS am
             WHERE am.id_partido = d.id_partido) AS t;
GO


-- Original en 08_SP_ABM_Arbitraje.sql. Cambio: el control de árbitro repetido lee Seguridad.vw_Arbitro (reemplaza a
-- UQ_ARBITRO_pais_apellido_nombre); el INSERT cifra nombre, apellido y fecha de nacimiento.
/*
  usp_ARBITRO_Alta
  Valida: país existente; nombre y apellido obligatorios, de hasta 60
  caracteres, y que no haya otro árbitro con el mismo nombre del mismo país;
  categoría FIFA o CONFEDERACION; fecha de nacimiento no futura.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ARBITRO_Alta
    @id_pais           SMALLINT,
    @nombre            NVARCHAR(120),
    @apellido          NVARCHAR(120),
    @categoria         VARCHAR(30),
    @fecha_nacimiento  DATE = NULL,
    @id_arbitro        INT  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);

    SET @nombre    = NULLIF(TRIM(@nombre), N'');
    SET @apellido  = NULLIF(TRIM(@apellido), N'');
    SET @categoria = UPPER(NULLIF(TRIM(@categoria), ''));

    IF @id_pais IS NULL
        SET @errores += @nl + N'- El país es obligatorio.';
    ELSE IF NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';

    IF @nombre IS NULL
        SET @errores += @nl + N'- El nombre es obligatorio.';
    ELSE IF LEN(@nombre) > 60
        SET @errores += @nl + N'- El nombre no puede superar los 60 caracteres.';

    IF @apellido IS NULL
        SET @errores += @nl + N'- El apellido es obligatorio.';
    ELSE IF LEN(@apellido) > 60
        SET @errores += @nl + N'- El apellido no puede superar los 60 caracteres.';

    IF EXISTS (SELECT 1 FROM Seguridad.vw_Arbitro
               WHERE id_pais = @id_pais AND apellido = @apellido AND nombre = @nombre)
        SET @errores += @nl + N'- Ya hay un árbitro ' + @nombre + N' ' + @apellido + N' de ese país.';

    IF @categoria IS NULL
        SET @errores += @nl + N'- La categoría es obligatoria.';
    ELSE IF @categoria NOT IN ('FIFA', 'CONFEDERACION')
        SET @errores += @nl + N'- La categoría debe ser FIFA o CONFEDERACION.';

    IF @fecha_nacimiento > CONVERT(DATE, GETDATE())
        SET @errores += @nl + N'- La fecha de nacimiento no puede ser futura.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ARBITRO_Alta: no se pudo dar de alta el árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    DECLARE @abierta_aca BIT;
    BEGIN TRY
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, fecha_nacimiento, categoria)
        VALUES (@id_pais, Seguridad.fn_CifrarTexto(@nombre), Seguridad.fn_CifrarTexto(@apellido),
                Seguridad.fn_CifrarFecha(@fecha_nacimiento), @categoria);

        SET @id_arbitro = SCOPE_IDENTITY();
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;
END;
GO


-- Original en 08_SP_ABM_Arbitraje.sql. Cambio: lee los datos actuales y controla el árbitro repetido sobre Seguridad.vw_Arbitro;
-- el UPDATE cifra los datos informados.
/*
  usp_ARBITRO_Modificacion
  Valida: que el árbitro exista y que se informe al menos un dato; para cada
  dato informado, las mismas reglas del alta; que con el país nuevo no quede
  designado en un partido de una selección de ese país; que no se desactive a
  un árbitro designado en un partido que todavía no se jugó.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ARBITRO_Modificacion
    @id_arbitro        INT,
    @id_pais           SMALLINT      = NULL,
    @nombre            NVARCHAR(120) = NULL,
    @apellido          NVARCHAR(120) = NULL,
    @categoria         VARCHAR(30)   = NULL,
    @fecha_nacimiento  DATE          = NULL,
    @activo            BIT           = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @pais_final     SMALLINT;
    DECLARE @nombre_final   NVARCHAR(60);
    DECLARE @apellido_final NVARCHAR(60);
    DECLARE @partido        TINYINT;

    SET @nombre    = NULLIF(TRIM(@nombre), N'');
    SET @apellido  = NULLIF(TRIM(@apellido), N'');
    SET @categoria = UPPER(NULLIF(TRIM(@categoria), ''));

    SELECT @pais_final     = ISNULL(@id_pais, id_pais),
           @nombre_final   = ISNULL(@nombre, nombre),
           @apellido_final = ISNULL(@apellido, apellido)
    FROM Seguridad.vw_Arbitro
    WHERE id_arbitro = @id_arbitro;

    IF @id_arbitro IS NULL
        SET @errores += @nl + N'- El id del árbitro es obligatorio.';
    ELSE IF @pais_final IS NULL
        SET @errores += @nl + N'- No existe un árbitro con id ' + CAST(@id_arbitro AS NVARCHAR(10)) + N'.';

    IF @id_pais IS NULL AND @nombre IS NULL AND @apellido IS NULL AND @categoria IS NULL
       AND @fecha_nacimiento IS NULL AND @activo IS NULL
        SET @errores += @nl + N'- No se indicó ningún dato para modificar.';

    IF @id_pais IS NOT NULL AND NOT EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE id_pais = @id_pais)
        SET @errores += @nl + N'- No existe un país con id ' + CAST(@id_pais AS NVARCHAR(10)) + N'.';
    ELSE IF @id_pais IS NOT NULL
    BEGIN
        SELECT TOP (1) @partido = p.numero_partido
        FROM Arbitraje.DESIGNACION_ARBITRAL AS d
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
        INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion IN (p.id_seleccion_local, p.id_seleccion_visitante)
        WHERE d.id_arbitro = @id_arbitro AND s.id_pais = @id_pais;
        IF @partido IS NOT NULL
            SET @errores += @nl + N'- Con ese país quedaría en conflicto de nacionalidad en el partido '
                          + CAST(@partido AS NVARCHAR(3)) + N', que tiene designado.';
    END;

    IF LEN(@nombre) > 60
        SET @errores += @nl + N'- El nombre no puede superar los 60 caracteres.';
    IF LEN(@apellido) > 60
        SET @errores += @nl + N'- El apellido no puede superar los 60 caracteres.';
    IF (@id_pais IS NOT NULL OR @nombre IS NOT NULL OR @apellido IS NOT NULL)
       AND EXISTS (SELECT 1 FROM Seguridad.vw_Arbitro
                   WHERE id_pais = @pais_final AND apellido = @apellido_final AND nombre = @nombre_final
                     AND id_arbitro <> @id_arbitro)
        SET @errores += @nl + N'- Ya hay otro árbitro ' + @nombre_final + N' ' + @apellido_final + N' de ese país.';

    IF @categoria NOT IN ('FIFA', 'CONFEDERACION')
        SET @errores += @nl + N'- La categoría debe ser FIFA o CONFEDERACION.';

    IF @fecha_nacimiento > CONVERT(DATE, GETDATE())
        SET @errores += @nl + N'- La fecha de nacimiento no puede ser futura.';

    IF @activo = 0
       AND EXISTS (SELECT 1
                   FROM Arbitraje.DESIGNACION_ARBITRAL AS d
                   INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = d.id_partido
                   WHERE d.id_arbitro = @id_arbitro AND p.estado IN ('PROGRAMADO', 'EN_JUEGO'))
        SET @errores += @nl + N'- El árbitro está designado en un partido que todavía no se jugó: no se puede desactivar.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ARBITRO_Modificacion: no se pudo modificar el árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Un dato que no se informa conserva el valor guardado (ya cifrado); el informado se cifra.
    DECLARE @abierta_aca BIT;
    BEGIN TRY
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        UPDATE Arbitraje.ARBITRO
        SET id_pais          = ISNULL(@id_pais, id_pais),
            nombre           = IIF(@nombre IS NULL, nombre, Seguridad.fn_CifrarTexto(@nombre)),
            apellido         = IIF(@apellido IS NULL, apellido, Seguridad.fn_CifrarTexto(@apellido)),
            categoria        = ISNULL(@categoria, categoria),
            fecha_nacimiento = IIF(@fecha_nacimiento IS NULL, fecha_nacimiento, Seguridad.fn_CifrarFecha(@fecha_nacimiento)),
            activo           = ISNULL(@activo, activo)
        WHERE id_arbitro = @id_arbitro;

        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;
END;
GO


-- Original en 08_SP_ABM_Arbitraje.sql. Cambio: lee el árbitro (y su nombre para los mensajes) de Seguridad.vw_Arbitro.
/*
  usp_DESIGNACION_ARBITRAL_Alta
  Valida: partido existente y PROGRAMADO; árbitro existente y activo; rol
  válido (PRINCIPAL, ASISTENTE_1, ASISTENTE_2, CUARTO, VAR, ASISTENTE_RESERVA,
  AVAR o VAR_APOYO) y libre en el partido; que el árbitro no esté ya
  designado en el partido; que su país no sea el de ninguna de las dos
  selecciones (conflicto de nacionalidad).
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_DESIGNACION_ARBITRAL_Alta
    @id_partido  INT,
    @id_arbitro  INT,
    @rol         VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        NVARCHAR(2048) = N'';
    DECLARE @nl             NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @estado         VARCHAR(12);
    DECLARE @local          INT;
    DECLARE @visitante      INT;
    DECLARE @activo         BIT;
    DECLARE @id_pais        SMALLINT;
    DECLARE @arbitro        NVARCHAR(130);
    DECLARE @pais_conflicto VARCHAR(60);

    SET @rol = UPPER(NULLIF(TRIM(@rol), ''));

    SELECT @estado = estado, @local = id_seleccion_local, @visitante = id_seleccion_visitante
    FROM Torneo.PARTIDO
    WHERE id_partido = @id_partido;

    SELECT @activo = activo, @id_pais = id_pais, @arbitro = nombre + N' ' + apellido
    FROM Seguridad.vw_Arbitro
    WHERE id_arbitro = @id_arbitro;

    IF @id_partido IS NULL
        SET @errores += @nl + N'- El partido es obligatorio.';
    ELSE IF @estado IS NULL
        SET @errores += @nl + N'- No existe un partido con id ' + CAST(@id_partido AS NVARCHAR(10)) + N'.';
    ELSE IF @estado <> 'PROGRAMADO'
        SET @errores += @nl + N'- Las designaciones se hacen antes de que empiece el partido (estado actual: '
                      + @estado + N').';

    IF @id_arbitro IS NULL
        SET @errores += @nl + N'- El árbitro es obligatorio.';
    ELSE IF @activo IS NULL
        SET @errores += @nl + N'- No existe un árbitro con id ' + CAST(@id_arbitro AS NVARCHAR(10)) + N'.';
    ELSE IF @activo = 0
        SET @errores += @nl + N'- El árbitro ' + @arbitro + N' no está activo.';

    IF @rol IS NULL
        SET @errores += @nl + N'- El rol es obligatorio.';
    ELSE IF @rol NOT IN ('PRINCIPAL', 'ASISTENTE_1', 'ASISTENTE_2', 'CUARTO', 'VAR', 'ASISTENTE_RESERVA', 'AVAR', 'VAR_APOYO')
        SET @errores += @nl + N'- El rol debe ser PRINCIPAL, ASISTENTE_1, ASISTENTE_2, CUARTO, VAR, ASISTENTE_RESERVA, '
                      + N'AVAR o VAR_APOYO.';
    ELSE IF EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND rol = @rol)
        SET @errores += @nl + N'- El rol ' + @rol + N' ya está cubierto en ese partido.';

    IF EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido AND id_arbitro = @id_arbitro)
        SET @errores += @nl + N'- El árbitro ya está designado en ese partido.';

    IF @id_pais IS NOT NULL
    BEGIN
        SELECT TOP (1) @pais_conflicto = pa.nombre
        FROM Torneo.SELECCION AS s
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = s.id_pais
        WHERE s.id_seleccion IN (@local, @visitante) AND s.id_pais = @id_pais;
        IF @pais_conflicto IS NOT NULL
            SET @errores += @nl + N'- Conflicto de nacionalidad: ' + @arbitro + N' es de ' + @pais_conflicto
                          + N', que juega este partido.';
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_DESIGNACION_ARBITRAL_Alta: no se pudo designar al árbitro.' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Arbitraje.DESIGNACION_ARBITRAL (id_partido, id_arbitro, rol)
    VALUES (@id_partido, @id_arbitro, @rol);
END;
GO


-- Original en 12_SP_Negocio_FormacionesYCambios.sql. Cambio: lee los jugadores de los suspendidos y de la formación de Seguridad.vw_Jugador.
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
        INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = s.id_jugador
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
        INNER JOIN Seguridad.vw_Jugador AS j ON j.id_jugador = a.id_jugador
        WHERE f.id_formacion = @id_formacion
        ORDER BY a.es_titular DESC, j.dorsal;
END;
GO


-- Original en 13_SP_Negocio_GolesYTarjetas.sql. Cambio: lee el jugador de los avisos y del resultado de Seguridad.vw_Jugador.
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

        SELECT @receptor = apellido + N', ' + nombre FROM Seguridad.vw_Jugador WHERE id_jugador = @id_jugador;

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
        FROM Seguridad.vw_Jugador AS j
        LEFT JOIN DesarrolloPartido.AMONESTACION AS a
               ON a.id_jugador = j.id_jugador AND a.id_partido = @id_partido
        WHERE j.id_jugador = @id_jugador
        GROUP BY j.dorsal, j.apellido, j.nombre;
END;
GO


-- Original en 14_SP_Negocio_Arbitraje.sql. Cambio: lee el árbitro del resultado de Seguridad.vw_Arbitro (el alta la hace usp_ARBITRO_Alta).
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
        FROM Seguridad.vw_Arbitro AS a
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        INNER JOIN Arbitraje.ARBITRO_IDIOMA AS ai ON ai.id_arbitro = a.id_arbitro
        INNER JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = ai.id_idioma
        WHERE a.id_arbitro = @id_arbitro
        GROUP BY a.id_arbitro, a.apellido, a.nombre, pa.nombre, a.categoria;
END;
GO


-- Original en 14_SP_Negocio_Arbitraje.sql. Cambio: lee los árbitros de los controles, las advertencias y el resultado de Seguridad.vw_Arbitro.
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
        INNER JOIN Seguridad.vw_Arbitro AS a ON a.id_arbitro = t.id_arbitro
        WHERE a.activo = 0), N'');

    -- Conflicto de nacionalidad.
    SET @errores += ISNULL((
        SELECT STRING_AGG(@nl + N'- Conflicto de nacionalidad: ' + a.apellido + N', ' + a.nombre + N' ('
                          + t.rol + N') es de ' + pa.nombre + N', que juega este partido.', N'')
        FROM @terna AS t
        INNER JOIN Seguridad.vw_Arbitro AS a ON a.id_arbitro = t.id_arbitro
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        INNER JOIN Torneo.SELECCION AS s ON s.id_pais = a.id_pais
        WHERE s.id_seleccion IN (@local, @visitante)), N'');

    SET @errores += ISNULL((
        SELECT STRING_AGG(@nl + N'- ' + a.apellido + N', ' + a.nombre + N' no puede ser ' + t.rol
                          + N': tiene que ser de categoría FIFA.', N'')
        FROM @terna AS t
        INNER JOIN Seguridad.vw_Arbitro AS a ON a.id_arbitro = t.id_arbitro
        WHERE t.rol IN ('PRINCIPAL', 'VAR') AND a.categoria <> 'FIFA'), N'');

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
            INNER JOIN Seguridad.vw_Arbitro AS a ON a.id_arbitro = t.id_arbitro
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
        INNER JOIN Seguridad.vw_Arbitro AS a ON a.id_arbitro = d.id_arbitro
        INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = a.id_pais
        LEFT JOIN Torneo.fn_SeleccionesEnCompetencia() AS sc ON sc.id_pais = a.id_pais
        WHERE d.id_partido = @id_partido
        ORDER BY CHARINDEX(d.rol, 'PRINCIPAL ASISTENTE_1 ASISTENTE_2 CUARTO VAR');
END;
GO


-- Original en 16_SP_CargaMasiva.sql. Cambio: reconoce a los árbitros ya cargados sobre Seguridad.vw_Arbitro (país, apellido
-- y nombre) y compara su fecha de nacimiento descifrada; cifra lo que carga.
/*
  usp_CargarArbitros
  Upsert de árbitros por país (código FIFA), apellido y nombre, desde
  #staging_arbitros. Columnas que usa: id_registro (distinto en cada fila),
  codigo_fifa, nombre, apellido, categoria, fecha_nacimiento, idiomas,
  errores y accion. Acepta la categoría CONFEDERATION, en inglés. idiomas es
  una lista de códigos ISO 639-1 separados por comas (ej. 'es,en'), como en
  usp_RegistrarArbitro, y puede no venir: se agregan los que el árbitro no
  tiene, y los que tiene y no vienen no se borran. En uno existente, la
  fecha de nacimiento que no viene no se borra, y si está activo o no queda
  como está.
  Valida cada árbitro pendiente: país registrado; nombre y apellido
  obligatorios y de hasta 60 caracteres; categoría FIFA o CONFEDERACION;
  fecha de nacimiento no futura; idiomas registrados; que no venga dos
  veces. Con eso cubre las reglas de usp_ARBITRO_Alta y
  usp_ARBITRO_IDIOMA_Alta.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_CargarArbitros
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nl           NCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @tran_propia  BIT      = IIF(@@TRANCOUNT = 0, 1, 0);

    -- El país y el árbitro ya registrados de cada fila pendiente.
    DECLARE @registrados TABLE (
        id_registro  INT PRIMARY KEY,
        id_pais      SMALLINT,
        id_arbitro   INT
    );

    -- Los idiomas de cada fila pendiente, uno por fila (id_idioma NULL: el código no existe).
    DECLARE @idiomas TABLE (
        id_registro  INT,
        codigo       VARCHAR(10),
        id_idioma    SMALLINT,
        PRIMARY KEY (id_registro, codigo)
    );

    IF OBJECT_ID(N'tempdb..#staging_arbitros') IS NULL
        THROW 50001, N'Arbitraje.usp_CargarArbitros: no se importó nada, falta la tabla #staging_arbitros con los árbitros.', 1;

    UPDATE #staging_arbitros
    SET codigo_fifa = UPPER(NULLIF(TRIM(codigo_fifa), '')),
        nombre      = NULLIF(TRIM(nombre), N''),
        apellido    = NULLIF(TRIM(apellido), N''),
        categoria   = IIF(UPPER(TRIM(categoria)) = 'CONFEDERATION', 'CONFEDERACION', UPPER(NULLIF(TRIM(categoria), '')))
    WHERE accion IS NULL;

    INSERT INTO @registrados (id_registro, id_pais, id_arbitro)
    SELECT st.id_registro, pa.id_pais, a.id_arbitro
    FROM #staging_arbitros AS st
    LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = st.codigo_fifa
    LEFT JOIN Seguridad.vw_Arbitro AS a ON a.id_pais = pa.id_pais AND a.apellido = st.apellido AND a.nombre = st.nombre
    WHERE st.accion IS NULL;

    INSERT INTO @idiomas (id_registro, codigo, id_idioma)
    SELECT DISTINCT st.id_registro, LEFT(LOWER(TRIM(c.value)), 10), i.id_idioma
    FROM #staging_arbitros AS st
    CROSS APPLY STRING_SPLIT(st.idiomas, ',') AS c
    LEFT JOIN DatosGenerales.IDIOMA AS i ON i.codigo_iso = LOWER(TRIM(c.value))
    WHERE st.accion IS NULL AND TRIM(c.value) <> '';

    /* 1. Las reglas de cada árbitro. */
    UPDATE st
    SET errores = NULLIF(CONCAT(st.errores,
            CASE WHEN st.codigo_fifa IS NULL THEN @nl + N'- El código FIFA del país es obligatorio.'
                 WHEN r.id_pais IS NULL     THEN @nl + N'- No hay un país registrado con código FIFA "' + st.codigo_fifa + N'".'
            END,
            CASE WHEN st.nombre IS NULL OR st.apellido IS NULL
                     THEN @nl + N'- El nombre y el apellido son obligatorios.'
                 WHEN LEN(st.nombre) > 60 OR LEN(st.apellido) > 60
                     THEN @nl + N'- El nombre y el apellido no pueden superar los 60 caracteres.'
            END,
            CASE WHEN st.categoria IS NULL THEN @nl + N'- La categoría es obligatoria.'
                 WHEN st.categoria NOT IN ('FIFA', 'CONFEDERACION')
                     THEN @nl + N'- La categoría "' + st.categoria + N'" no es FIFA ni CONFEDERACION.'
            END,
            IIF(st.fecha_nacimiento > CONVERT(DATE, GETDATE()), @nl + N'- La fecha de nacimiento no puede ser futura.', NULL),
            (SELECT @nl + N'- Idiomas que no existen: ' + STRING_AGG(i.codigo, ', ') + N'.'
             FROM @idiomas AS i
             WHERE i.id_registro = st.id_registro AND i.id_idioma IS NULL)), N'')
    FROM #staging_arbitros AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro;

    UPDATE st
    SET errores = CONCAT(st.errores, @nl, N'- Este árbitro viene ', r.veces, N' veces.')
    FROM #staging_arbitros AS st
    INNER JOIN (SELECT codigo_fifa, nombre, apellido, COUNT(*) AS veces FROM #staging_arbitros
                WHERE codigo_fifa IS NOT NULL AND nombre IS NOT NULL AND apellido IS NOT NULL
                GROUP BY codigo_fifa, nombre, apellido HAVING COUNT(*) > 1) AS r
            ON r.codigo_fifa = st.codigo_fifa AND r.nombre = st.nombre AND r.apellido = st.apellido
    WHERE st.accion IS NULL;

    UPDATE #staging_arbitros SET accion = 'RECHAZADO' WHERE accion IS NULL AND errores IS NOT NULL;

    /* 2. Lo que le pasa a cada árbitro válido, antes de cargar. */
    UPDATE st
    SET accion = CASE WHEN r.id_arbitro IS NULL THEN 'INSERTADO'
                      WHEN st.categoria <> a.categoria OR st.fecha_nacimiento <> ISNULL(a.fecha_nacimiento, '19000101')
                        OR EXISTS (SELECT 1 FROM @idiomas AS i
                                   WHERE i.id_registro = st.id_registro
                                     AND NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA AS ai
                                                     WHERE ai.id_arbitro = a.id_arbitro AND ai.id_idioma = i.id_idioma))
                          THEN 'ACTUALIZADO'
                      ELSE 'SIN CAMBIOS'
                 END
    FROM #staging_arbitros AS st
    INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
    LEFT JOIN Seguridad.vw_Arbitro AS a ON a.id_arbitro = r.id_arbitro
    WHERE st.accion IS NULL;

    /* 3. Carga, todos juntos. */
    DECLARE @abierta_aca BIT;
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        -- La fecha que no viene conserva la guardada (ya cifrada); la que viene se cifra.
        UPDATE a
        SET categoria        = st.categoria,
            fecha_nacimiento = IIF(st.fecha_nacimiento IS NULL, a.fecha_nacimiento, Seguridad.fn_CifrarFecha(st.fecha_nacimiento))
        FROM Arbitraje.ARBITRO AS a
        INNER JOIN @registrados AS r ON r.id_arbitro = a.id_arbitro
        INNER JOIN #staging_arbitros AS st ON st.id_registro = r.id_registro
        WHERE st.accion = 'ACTUALIZADO';

        INSERT INTO Arbitraje.ARBITRO (id_pais, nombre, apellido, fecha_nacimiento, categoria)
        SELECT r.id_pais, Seguridad.fn_CifrarTexto(st.nombre), Seguridad.fn_CifrarTexto(st.apellido),
               Seguridad.fn_CifrarFecha(st.fecha_nacimiento), st.categoria
        FROM #staging_arbitros AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        WHERE st.accion = 'INSERTADO'
        ORDER BY st.id_registro;

        -- Los idiomas que cada árbitro todavía no tiene (el árbitro nuevo ya tiene su id).
        INSERT INTO Arbitraje.ARBITRO_IDIOMA (id_arbitro, id_idioma)
        SELECT a.id_arbitro, i.id_idioma
        FROM #staging_arbitros AS st
        INNER JOIN @registrados AS r ON r.id_registro = st.id_registro
        INNER JOIN Seguridad.vw_Arbitro AS a ON a.id_pais = r.id_pais AND a.apellido = st.apellido AND a.nombre = st.nombre
        INNER JOIN @idiomas AS i ON i.id_registro = st.id_registro
        WHERE st.accion IN ('INSERTADO', 'ACTUALIZADO')
          AND NOT EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA AS ai
                          WHERE ai.id_arbitro = a.id_arbitro AND ai.id_idioma = i.id_idioma);

        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;
END;
GO


-- Original en 18_SP_Importar_Mundial2026.sql. Cambio: busca el árbitro de cada designación en Seguridad.vw_Arbitro.
/*
  usp_ImportarDesignacionesCSV
  Importa el equipo arbitral de cada partido desde el CSV que genera el
  scraping de Wikipedia (designaciones_arbitrales.csv, ver
  scraping/README.md), con una fila por árbitro designado y esta primera fila
  con los nombres de las columnas:
    fecha,local,visitante,rol,nombre,apellido,pais
  fecha es la del partido (AAAA-MM-DD, en la hora local de la sede), local y
  visitante los códigos FIFA de sus selecciones (en cualquier orden), rol el
  que publica la FIFA en inglés (lo traduce usp_CargarDesignaciones) y pais
  el código FIFA del país del árbitro. Los partidos tienen que estar
  cargados antes (usp_ImportarPartidosJSON).
  Primero carga los árbitros con usp_CargarArbitros: uno por cada país,
  nombre y apellido distintos del archivo, con la categoría @categoria (el
  archivo no la trae; los árbitros del Mundial son de la lista de la FIFA).
  Después, las designaciones con usp_CargarDesignaciones.
  Valida: ruta obligatoria y terminada en .csv; categoría FIFA o
  CONFEDERACION. Si el archivo no se puede leer, no tiene las columnas
  esperadas o alguna fila no es CSV válido, no se importa nada (THROW 50002).
  Rechaza las filas con una fecha que no es fecha, las de un partido que no
  encuentra y las de un árbitro rechazado; las reglas las aplican los SP de
  la Entrega 5. Registra la importación (los totales cuentan las filas del
  archivo, es decir, las designaciones; su número queda en @id_importacion)
  y las filas rechazadas en Arbitraje.ERRORES_DESIGNACION. Devuelve el
  resumen de designaciones y de árbitros, los rechazados con sus motivos y
  los partidos del archivo a los que les falta alguno de los cinco roles que
  pide la consigna.
*/
CREATE OR ALTER PROCEDURE Arbitraje.usp_ImportarDesignacionesCSV
    @ruta_archivo    NVARCHAR(400),
    @categoria       VARCHAR(15) = 'FIFA',
    @id_importacion  INT         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores       NVARCHAR(2048) = N'';
    DECLARE @nl            NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @contenido     NVARCHAR(MAX);
    DECLARE @encabezado    NVARCHAR(400);
    DECLARE @mensaje       NVARCHAR(2048);
    DECLARE @sql           NVARCHAR(MAX);
    DECLARE @tran_propia   BIT            = IIF(@@TRANCOUNT = 0, 1, 0);
    DECLARE @proceso       VARCHAR(100)   = CONCAT(OBJECT_SCHEMA_NAME(@@PROCID), '.', OBJECT_NAME(@@PROCID));
    DECLARE @leidos        INT;
    DECLARE @insertados    INT;
    DECLARE @actualizados  INT;
    DECLARE @sin_cambios   INT;
    DECLARE @rechazados    INT;

    SET @ruta_archivo = NULLIF(TRIM(@ruta_archivo), N'');
    SET @categoria    = UPPER(NULLIF(TRIM(@categoria), ''));
    SET @id_importacion = NULL;

    IF @ruta_archivo IS NULL
        SET @errores += @nl + N'- La ruta del archivo es obligatoria.';
    ELSE IF @ruta_archivo NOT LIKE N'%.csv'
        SET @errores += @nl + N'- El archivo tiene que ser un .csv (el designaciones_arbitrales.csv del scraping).';

    IF @categoria IS NULL OR @categoria NOT IN ('FIFA', 'CONFEDERACION')
        SET @errores += @nl + N'- La categoría de los árbitros tiene que ser FIFA o CONFEDERACION.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Arbitraje.usp_ImportarDesignacionesCSV: no se pudo importar el archivo.' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* 1. El archivo: la primera fila tiene que tener las columnas esperadas. */
    EXEC DatosGenerales.usp_LeerArchivoUTF8 @ruta_archivo = @ruta_archivo, @contenido = @contenido OUTPUT;

    SET @encabezado = REPLACE(REPLACE(LEFT(@contenido, CHARINDEX(NCHAR(10), @contenido + NCHAR(10)) - 1),
                                      NCHAR(13), N''), N' ', N'');
    IF @encabezado <> N'fecha,local,visitante,rol,nombre,apellido,pais'
    BEGIN
        SET @mensaje = N'Arbitraje.usp_ImportarDesignacionesCSV: no se importó nada, la primera fila del archivo tiene que ser '
                     + N'"fecha,local,visitante,rol,nombre,apellido,pais" y es "' + LEFT(@encabezado, 200) + N'".';
        THROW 50002, @mensaje, 1;
    END;

    /* 2. Las filas, como vienen. FORMAT = 'CSV' respeta las comillas. El fin de
          línea es el del archivo: CRLF (Windows) o LF. */
    CREATE TABLE #crudo (
        fecha_txt      NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        local_txt      NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        visitante_txt  NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        rol_txt        NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
        nombre         NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido       NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        pais_txt       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL
    );

    BEGIN TRY
        SET @sql = N'BULK INSERT #crudo FROM N''' + REPLACE(@ruta_archivo, N'''', N'''''')
                 + N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', FIELDTERMINATOR = '','', '
                 + N'ROWTERMINATOR = ''' + IIF(CHARINDEX(NCHAR(13) + NCHAR(10), @contenido) > 0, N'0x0d0a', N'0x0a')
                 + N''', FIELDQUOTE = ''"'', MAXERRORS = 0);';
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @mensaje = N'Arbitraje.usp_ImportarDesignacionesCSV: no se importó nada, hay filas que no son CSV válido '
                     + N'(tienen que tener 7 columnas): ' + ERROR_MESSAGE();
        THROW 50002, @mensaje, 1;
    END CATCH;

    -- usp_CargarDesignaciones lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_designaciones (
        id_registro     INT PRIMARY KEY,   -- línea del archivo
        -- Tal como vienen en el archivo
        fecha_txt       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        local_txt       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        visitante_txt   NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        rol_txt         NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
        nombre          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido        NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        pais_txt        NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        -- Para convertir
        fecha           DATE          NULL,
        -- Lo que lee usp_CargarDesignaciones, ya convertido
        numero_partido  TINYINT       NULL,
        id_arbitro      INT           NULL,
        rol             VARCHAR(100)  COLLATE DATABASE_DEFAULT NULL,
        -- Lo que le pasa a cada registro: lo completan este SP y usp_CargarDesignaciones
        errores         NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion          VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    -- usp_CargarArbitros lee y completa esta tabla: no cambiar su nombre ni el de las columnas que usa.
    CREATE TABLE #staging_arbitros (
        id_registro       INT PRIMARY KEY,   -- primera línea del archivo en la que aparece
        codigo_fifa       NVARCHAR(50)  COLLATE DATABASE_DEFAULT NULL,
        nombre            NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        apellido          NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL,
        categoria         VARCHAR(30)   COLLATE DATABASE_DEFAULT NULL,
        fecha_nacimiento  DATE          NULL,
        idiomas           VARCHAR(200)  COLLATE DATABASE_DEFAULT NULL,   -- el archivo no los trae
        errores           NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
        accion            VARCHAR(15)   COLLATE DATABASE_DEFAULT NULL
    );

    INSERT INTO #staging_designaciones (id_registro, fecha_txt, local_txt, visitante_txt, rol_txt, nombre, apellido, pais_txt)
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) + 1,
           NULLIF(TRIM(fecha_txt), N''), UPPER(NULLIF(TRIM(local_txt), N'')), UPPER(NULLIF(TRIM(visitante_txt), N'')),
           NULLIF(TRIM(rol_txt), N''), NULLIF(TRIM(nombre), N''), NULLIF(TRIM(apellido), N''),
           UPPER(NULLIF(TRIM(REPLACE(pais_txt, NCHAR(13), N'')), N''))
    FROM #crudo
    WHERE CONCAT(fecha_txt, local_txt, visitante_txt, rol_txt, nombre, apellido, REPLACE(pais_txt, NCHAR(13), N'')) <> N'';

    -- El rol pasa como viene ("Referee", "Fourth official"): lo traduce usp_CargarDesignaciones.
    UPDATE #staging_designaciones
    SET fecha = TRY_CONVERT(DATE, fecha_txt, 23),
        rol   = LEFT(rol_txt, 100);

    -- El partido: el de esa fecha (hora local de la sede) entre esas dos selecciones, en cualquier orden.
    UPDATE st
    SET numero_partido = (SELECT MAX(p.numero_partido)
                          FROM Torneo.PARTIDO AS p
                          INNER JOIN Torneo.SELECCION AS sl ON sl.id_seleccion = p.id_seleccion_local
                          INNER JOIN DatosGenerales.PAIS AS pl ON pl.id_pais = sl.id_pais
                          INNER JOIN Torneo.SELECCION AS sv ON sv.id_seleccion = p.id_seleccion_visitante
                          INNER JOIN DatosGenerales.PAIS AS pv ON pv.id_pais = sv.id_pais
                          WHERE CAST(p.fecha_hora_local AS DATE) = st.fecha
                            AND ((pl.codigo_fifa = st.local_txt AND pv.codigo_fifa = st.visitante_txt)
                              OR (pl.codigo_fifa = st.visitante_txt AND pv.codigo_fifa = st.local_txt)))
    FROM #staging_designaciones AS st
    WHERE st.fecha IS NOT NULL;

    -- Un árbitro por cada país, nombre y apellido distintos del archivo.
    INSERT INTO #staging_arbitros (id_registro, codigo_fifa, nombre, apellido, categoria)
    SELECT MIN(id_registro), pais_txt, nombre, apellido, @categoria
    FROM #staging_designaciones
    GROUP BY pais_txt, nombre, apellido;

    /* 3. Lo que no se pudo convertir. Las reglas de los árbitros y de las designaciones las
          aplican usp_CargarArbitros y usp_CargarDesignaciones. */
    UPDATE #staging_designaciones
    SET errores = NULLIF(CONCAT(
            CASE WHEN fecha_txt IS NULL THEN @nl + N'- La fecha del partido es obligatoria.'
                 WHEN fecha IS NULL     THEN @nl + N'- La fecha "' + fecha_txt + N'" no es una fecha AAAA-MM-DD.'
            END,
            CASE WHEN local_txt IS NULL OR visitante_txt IS NULL
                     THEN @nl + N'- Faltan las selecciones del partido.'
                 WHEN fecha IS NOT NULL AND numero_partido IS NULL
                     THEN @nl + N'- No hay un partido entre ' + local_txt + N' y ' + visitante_txt + N' el '
                              + CONVERT(NVARCHAR(10), fecha, 103) + N'.'
            END), N'');

    /* 4. Los SP de la Entrega 5 cargan los árbitros y, con ellos, las designaciones; después se
          registran la importación y sus rechazados. Todo en una transacción. */
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        EXEC Arbitraje.usp_CargarArbitros;

        -- Cada fila con su árbitro, o con los motivos por los que se rechazó.
        UPDATE st
        SET id_arbitro = a.id_arbitro,
            errores    = NULLIF(CONCAT(st.errores,
                             IIF(sa.accion = 'RECHAZADO', @nl + N'- El árbitro se rechazó:' + REPLACE(sa.errores, @nl + N'- ', @nl + N'  - '), NULL)), N'')
        FROM #staging_designaciones AS st
        INNER JOIN #staging_arbitros AS sa
                ON EXISTS (SELECT st.pais_txt, st.nombre, st.apellido INTERSECT SELECT sa.codigo_fifa, sa.nombre, sa.apellido)
        LEFT JOIN DatosGenerales.PAIS AS pa ON pa.codigo_fifa = sa.codigo_fifa
        LEFT JOIN Seguridad.vw_Arbitro AS a ON a.id_pais = pa.id_pais AND a.apellido = sa.apellido AND a.nombre = sa.nombre
                                        AND sa.accion <> 'RECHAZADO';

        UPDATE #staging_designaciones SET accion = 'RECHAZADO' WHERE errores IS NOT NULL;

        EXEC Arbitraje.usp_CargarDesignaciones;

        SELECT @leidos       = COUNT(*),
               @insertados   = ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
               @actualizados = ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
               @sin_cambios  = ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
               @rechazados   = ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
        FROM #staging_designaciones;

        EXEC DatosGenerales.usp_RegistrarImportacion
            @proceso = @proceso, @origen = @ruta_archivo, @leidos = @leidos, @insertados = @insertados,
            @actualizados = @actualizados, @sin_cambios = @sin_cambios, @rechazados = @rechazados,
            @id_importacion = @id_importacion OUTPUT;

        INSERT INTO Arbitraje.ERRORES_DESIGNACION (id_importacion, registro, fecha, local, visitante, rol, nombre, apellido,
                                                   pais, motivos)
        SELECT @id_importacion, id_registro, fecha_txt, local_txt, visitante_txt, rol_txt, nombre, apellido, pais_txt,
               STUFF(errores, 1, 2, N'')
        FROM #staging_designaciones
        WHERE accion = 'RECHAZADO';

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    /* 5. Resultado. */
    SELECT @id_importacion AS id_importacion, N'Designaciones' AS registros, @leidos AS leidos, @insertados AS insertados,
           @actualizados AS actualizados, @sin_cambios AS sin_cambios, @rechazados AS rechazados
    UNION ALL
    SELECT @id_importacion, N'Árbitros', COUNT(*),
           ISNULL(SUM(IIF(accion = 'INSERTADO', 1, 0)), 0),
           ISNULL(SUM(IIF(accion = 'ACTUALIZADO', 1, 0)), 0),
           ISNULL(SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)), 0),
           ISNULL(SUM(IIF(accion = 'RECHAZADO', 1, 0)), 0)
    FROM #staging_arbitros;

    SELECT CONCAT(N'Línea ', registro, N': ', ISNULL(fecha, N'(sin fecha)'), N' ', ISNULL(local, N'?'), N' - ',
                  ISNULL(visitante, N'?'), N', ', ISNULL(rol, N'(sin rol)'), N': ', ISNULL(nombre, N''), N' ',
                  ISNULL(apellido, N''), N' (', ISNULL(pais, N'?'), N')') AS rechazado,
           motivos
    FROM Arbitraje.ERRORES_DESIGNACION
    WHERE id_importacion = @id_importacion
    ORDER BY registro;

    -- Partidos del archivo a los que les falta alguno de los cinco roles que pide la consigna.
    SELECT p.numero_partido, f.seleccion_local, f.seleccion_visitante,
           STRING_AGG(r.rol, ', ') WITHIN GROUP (ORDER BY r.orden) AS roles_sin_designar
    FROM Torneo.PARTIDO AS p
    INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = p.id_partido
    CROSS JOIN (VALUES (1, 'PRINCIPAL'), (2, 'ASISTENTE_1'), (3, 'ASISTENTE_2'), (4, 'CUARTO'), (5, 'VAR')) AS r (orden, rol)
    WHERE p.numero_partido IN (SELECT numero_partido FROM #staging_designaciones)
      AND NOT EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL AS d WHERE d.id_partido = p.id_partido AND d.rol = r.rol)
    GROUP BY p.numero_partido, f.seleccion_local, f.seleccion_visitante
    ORDER BY p.numero_partido;
END;
GO
