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
 Archivo: 53_Test_FuncionesYVistas.sql
 Objetivo: Probar las funciones y vistas de 03_CrearFuncionesYVistas.sql:
           fixture filtrable, equipo en cancha en distintos minutos, marcador
           según los goles, sanciones y suspensiones (también cambiando sus
           parámetros), selecciones en competencia, simulación de prime time,
           prioridad de piezas, historial de titularidad, goleadores e
           historial de árbitros.
           Requiere haber ejecutado 00 a 20 y no depende del juego de datos.
           Arma su propio mini torneo con los SP de ABM y de negocio y lo borra
           al empezar y al terminar, así que se puede ejecutar más de una vez:
             - Países de prueba XVA a XVD (con selección del grupo I y 23
               jugadores), XVM y XVJ (mercados) y XVN (de los árbitros).
             - Sedes "Estadio Prueba Vistas 1" y "Estadio Prueba Vistas 2".
             - Partidos 226 a 229 (febrero de 2027):
                 226 XVA - XVB (grupos): cambio por lesión en el 17, gol en
                     contra y expulsión por doble amarilla. Termina 2 - 0.
                 227 XVC - XVD (grupos): roja directa; con terna arbitral,
                     informe y sanción del principal. Termina 0 - 1.
                 228 XVA - XVC (grupos): segunda amarilla del dorsal 8 de XVA
                     (suspensión por acumulación). Termina 1 - 1.
                 229 XVA - XVD (cuartos): sin el dorsal 8 de XVA, suspendido;
                     1 - 1 en los 90, 2 - 2 en el alargue y 4 - 3 por penales.
             - Cinco árbitros de prueba y un anunciante con dos campañas.
           Las consultas se filtran a los datos de prueba, así que dan lo
           mismo con o sin el juego de datos cargado. Los cambios de
           parámetros (FV8 y FV10) se hacen dentro de una transacción que se
           deshace al final del caso. Si el grupo I no tiene lugar para las
           cuatro selecciones de prueba (por ejemplo, con las 48 del Mundial
           cargadas), la preparación amplía SELECCIONES_POR_GRUPO mientras
           dura el test y la limpieza lo restaura (solo queda cambiada su
           fecha_modificacion).
================================================================================

 Cómo leer los resultados: cada consulta tiene una columna "caso" y, en el
 comentario de arriba, el resultado esperado. Si algo falla inesperadamente se
 imprime "FALLÓ" en Mensajes.
 Los países de prueba se llaman "Prueba <código>" y usan códigos FIFA que
 empiezan con X, que no tiene ningún miembro de la FIFA.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'DesarrolloPartido.fn_EquipoEnCancha', N'IF') IS NULL
   OR OBJECT_ID(N'DesarrolloPartido.usp_RegistrarGol', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DesarrolloPartido.TIPO_GOL WHERE descripcion IN ('JUGADA', 'EN CONTRA', 'PENAL', 'CABEZAZO')
                  HAVING COUNT(*) = 4)
BEGIN
    RAISERROR(N'Faltan las funciones, los SP o los datos iniciales: ejecutar los scripts 00 a 20.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Da de alta con los SP un país de prueba ("Prueba <código>") con su huso y,
-- si se informa, su PBI per cápita 2024; si @con_seleccion = 1, también su
-- selección del grupo indicado, con su lista presentada el 01/06/2026, su
-- director técnico y 23 jugadores ("Prueba <código> <dorsal>"): arqueros 1,
-- 12 y 23; defensores 2 a 6 y 13 a 15; mediocampistas 7, 8, 10 y 16 a 18;
-- delanteros 9, 11 y 19 a 22.
-- Los procedimientos temporales se crean en tempdb, que puede tener otra
-- intercalación que la base: por eso el código se usa con COLLATE DATABASE_DEFAULT.
IF OBJECT_ID(N'tempdb..#usp_CrearPaisPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_CrearPaisPrueba;
GO
CREATE PROCEDURE #usp_CrearPaisPrueba
    @codigo_fifa    CHAR(3),
    @huso_horario   VARCHAR(50)   = 'UTC',
    @pbi            DECIMAL(18,4) = NULL,
    @con_seleccion  BIT           = 0,
    @grupo          CHAR(1)       = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @nombre      VARCHAR(60)  = CONCAT('Prueba ', @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @dt_apellido NVARCHAR(60) = CONCAT(N'Prueba DT ', @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @id_pais SMALLINT, @id_seleccion INT, @id_lista INT, @i INT = 1, @dorsal TINYINT,
            @posicion VARCHAR(15), @apellido NVARCHAR(60);
    DECLARE @plantel TABLE (orden INT IDENTITY(1,1), dorsal TINYINT, posicion VARCHAR(15));

    EXEC DatosGenerales.usp_PAIS_Alta @nombre = @nombre, @huso_horario = @huso_horario, @codigo_fifa = @codigo_fifa,
        @id_pais = @id_pais OUTPUT;
    IF @pbi IS NOT NULL
        EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Alta @id_pais = @id_pais, @codigo_indicador = 'NY.GDP.PCAP.CD',
            @anio = 2024, @valor = @pbi;
    IF @con_seleccion = 0 RETURN;

    EXEC Torneo.usp_RegistrarSeleccion
        @id_pais = @id_pais, @confederacion = 'UEFA', @grupo = @grupo, @fecha_presentacion = '2026-06-01',
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

-- Borra con los SP de baja un país de prueba: sus indicadores, su selección
-- (jugadores, cuerpo técnico, lista y selección) y el país. Sus partidos,
-- árbitros, anunciantes y mercados de interés tienen que estar borrados antes.
IF OBJECT_ID(N'tempdb..#usp_BorrarPaisPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_BorrarPaisPrueba;
GO
CREATE PROCEDURE #usp_BorrarPaisPrueba
    @codigo_fifa CHAR(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS
                                 WHERE codigo_fifa = @codigo_fifa COLLATE DATABASE_DEFAULT
                                   AND nombre = CONCAT('Prueba ', @codigo_fifa COLLATE DATABASE_DEFAULT));
    DECLARE @id_sel INT, @id INT;
    IF @id_pais IS NULL RETURN;

    WHILE EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO WHERE id_pais = @id_pais)
    BEGIN
        SELECT TOP (1) @id = id_indicador FROM DatosGenerales.INDICADOR_ECONOMICO WHERE id_pais = @id_pais;
        EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id;
    END;

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
    WHERE p.codigo_fifa = @codigo_fifa COLLATE DATABASE_DEFAULT AND j.dorsal = @dorsal AND j.fecha_baja IS NULL;
END;
GO

-- Registra con los SP de ABM la formación 4-3-3 de una selección de prueba
-- para un partido: titulares los dorsales 1 a 11 y suplentes del 12 al 20.
-- @excluido no figura (por ejemplo, porque está suspendido) y @reemplazo pasa
-- del banco a titular en su lugar.
IF OBJECT_ID(N'tempdb..#usp_FormacionPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_FormacionPrueba;
GO
CREATE PROCEDURE #usp_FormacionPrueba
    @numero_partido TINYINT,
    @codigo_fifa    CHAR(3),
    @excluido       TINYINT = NULL,
    @reemplazo      TINYINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = @numero_partido);
    DECLARE @id_sel INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                           WHERE p.codigo_fifa = @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @id_formacion INT, @dorsal TINYINT = 1, @id_jugador INT, @titular BIT, @posicion VARCHAR(15), @en_cancha VARCHAR(15);

    EXEC DesarrolloPartido.usp_FORMACION_Alta @id_partido = @id_partido, @id_seleccion = @id_sel,
        @esquema_tactico = '4-3-3', @id_formacion = @id_formacion OUTPUT;
    WHILE @dorsal <= 20
    BEGIN
        IF @dorsal <> ISNULL(@excluido, 0)
        BEGIN
            SELECT @id_jugador = j.id_jugador, @posicion = j.posicion_habitual
            FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
            WHERE l.id_seleccion = @id_sel AND j.dorsal = @dorsal AND j.fecha_baja IS NULL;
            SET @titular = IIF(@dorsal <= 11 OR @dorsal = ISNULL(@reemplazo, 0), 1, 0);
            SET @en_cancha = IIF(@titular = 1, @posicion, NULL);
            EXEC DesarrolloPartido.usp_ALINEACION_Alta @id_formacion = @id_formacion, @id_jugador = @id_jugador,
                @es_titular = @titular, @posicion_en_cancha = @en_cancha;
        END;
        SET @dorsal += 1;
    END;
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
    -- Primero las rojas: una roja por doble amarilla impide borrar sus amarillas.
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido)
    BEGIN
        SELECT TOP (1) @id = id_amonestacion FROM DesarrolloPartido.AMONESTACION
        WHERE id_partido = @id_partido ORDER BY IIF(tipo_tarjeta = 'ROJA', 0, 1);
        EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id;
    END;
    -- Del último cambio al primero: el que entró puede haber salido en un cambio posterior.
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
    DECLARE @id INT, @id2 INT, @cupo TINYINT;

    EXEC #usp_LimpiarPartido @numero_partido = 226;
    EXEC #usp_LimpiarPartido @numero_partido = 227;
    EXEC #usp_LimpiarPartido @numero_partido = 228;
    EXEC #usp_LimpiarPartido @numero_partido = 229;

    -- Árbitros de prueba (del país XVN).
    WHILE EXISTS (SELECT 1 FROM Arbitraje.ARBITRO AS a INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais
                  WHERE p.codigo_fifa = 'XVN' AND p.nombre = 'Prueba XVN')
    BEGIN
        SELECT TOP (1) @id = a.id_arbitro FROM Arbitraje.ARBITRO AS a INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais
        WHERE p.codigo_fifa = 'XVN' AND p.nombre = 'Prueba XVN';
        EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id, @eliminar_registro = 1;
    END;

    -- Anunciante de prueba con sus campañas, piezas y mercados.
    WHILE EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
                  INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = ppi.id_pieza
                  INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
                  INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
                  WHERE a.razon_social = N'Anunciante Prueba Vistas')
    BEGIN
        SELECT TOP (1) @id = ppi.id_pieza, @id2 = ppi.id_pais
        FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
        INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = ppi.id_pieza
        INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
        INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
        WHERE a.razon_social = N'Anunciante Prueba Vistas';
        EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Baja @id_pieza = @id, @id_pais = @id2;
    END;
    WHILE EXISTS (SELECT 1 FROM Publicidad.PIEZA_PUBLICITARIA AS pz
                  INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
                  INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
                  WHERE a.razon_social = N'Anunciante Prueba Vistas')
    BEGIN
        SELECT TOP (1) @id = pz.id_pieza FROM Publicidad.PIEZA_PUBLICITARIA AS pz
        INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
        INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
        WHERE a.razon_social = N'Anunciante Prueba Vistas';
        EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Baja @id_pieza = @id;
    END;
    WHILE EXISTS (SELECT 1 FROM Publicidad.CAMPANIA AS c INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
                  WHERE a.razon_social = N'Anunciante Prueba Vistas')
    BEGIN
        SELECT TOP (1) @id = c.id_campania FROM Publicidad.CAMPANIA AS c
        INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
        WHERE a.razon_social = N'Anunciante Prueba Vistas';
        EXEC Publicidad.usp_CAMPANIA_Baja @id_campania = @id;
    END;
    SET @id = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba Vistas');
    IF @id IS NOT NULL
        EXEC Publicidad.usp_ANUNCIANTE_Baja @id_anunciante = @id;

    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XVA';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XVB';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XVC';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XVD';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XVM';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XVJ';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XVN';

    WHILE EXISTS (SELECT 1 FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Vistas%')
    BEGIN
        SELECT TOP (1) @id = id_sede FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Vistas%';
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;
    END;

    -- Cupo de los grupos: si la preparación lo amplió, vuelve a su valor
    -- original, que quedó guardado en el parámetro de prueba PRUEBA_53_CUPO_GRUPO.
    IF EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'PRUEBA_53_CUPO_GRUPO')
    BEGIN
        SET @cupo = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'PRUEBA_53_CUPO_GRUPO');
        EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'SELECCIONES_POR_GRUPO', @valor = @cupo;
        EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Baja @codigo = 'PRUEBA_53_CUPO_GRUPO';
    END;
END;
GO

EXEC #usp_LimpiarPruebas;
GO


/* ============================================================================
   PREPARACIÓN DEL MINI TORNEO
   ============================================================================ */

-- Cupo de los grupos: las cuatro selecciones de prueba van al grupo I, porque
-- los partidos 226 a 228 son de la fase de grupos. Si el grupo no tiene lugar
-- (por ejemplo, con las 48 selecciones del Mundial cargadas), se amplía
-- SELECCIONES_POR_GRUPO mientras dura el test. El valor original queda en el
-- parámetro de prueba PRUEBA_53_CUPO_GRUPO, y #usp_LimpiarPruebas lo restaura.
DECLARE @cupo TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'SELECCIONES_POR_GRUPO');
DECLARE @necesario TINYINT = (SELECT COUNT(*) FROM Torneo.SELECCION WHERE grupo = 'I') + 4;
IF @necesario > @cupo
BEGIN
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta @codigo = 'PRUEBA_53_CUPO_GRUPO',
        @descripcion = 'SELECCIONES_POR_GRUPO antes de ejecutar 53_Test_FuncionesYVistas.sql', @valor = @cupo;
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'SELECCIONES_POR_GRUPO', @valor = @necesario;
    PRINT CONCAT(N'El grupo I ya tiene ', @necesario - 4, N' selecciones: SELECCIONES_POR_GRUPO pasa de ',
                 @cupo, N' a ', @necesario, N' mientras dura el test.');
END;
GO

-- Países, selecciones, sedes, árbitros, publicidad y fixture.
DECLARE @usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede1 INT, @sede2 INT, @xva INT, @xvb INT, @xvc INT, @xvd INT, @xvn SMALLINT, @xvm SMALLINT;
DECLARE @id_anunciante INT, @c1 INT, @c2 INT, @i INT = 1, @apellido NVARCHAR(60);
DECLARE @a INT, @b INT, @c INT, @d INT, @e INT, @id_227 INT;

EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XVA', @con_seleccion = 1, @grupo = 'I';
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XVB', @con_seleccion = 1, @grupo = 'I';
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XVC', @con_seleccion = 1, @grupo = 'I';
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XVD', @con_seleccion = 1, @grupo = 'I';
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XVM', @huso_horario = 'E. Europe Standard Time', @pbi = 60000;
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XVJ', @huso_horario = 'Tokyo Standard Time',     @pbi = 90000;
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XVN';

SELECT @xva = s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XVA';
SELECT @xvb = s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XVB';
SELECT @xvc = s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XVC';
SELECT @xvd = s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XVD';
SET @xvn = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XVN');
SET @xvm = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XVM');

EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Vistas 1', @ciudad = 'Atlanta', @id_pais = @usa,
    @capacidad = 65000, @huso_horario = 'Eastern Standard Time', @id_sede = @sede1 OUTPUT;
EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Vistas 2', @ciudad = 'Houston', @id_pais = @usa,
    @capacidad = 70000, @huso_horario = 'Central Standard Time', @id_sede = @sede2 OUTPUT;

-- Cinco árbitros de prueba, de categoría FIFA, del país XVN (sin selección).
WHILE @i <= 5
BEGIN
    SET @apellido = CONCAT(N'Prueba Vistas ', @i);
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @xvn, @nombre = N'Árbitro', @apellido = @apellido, @categoria = 'FIFA';
    SET @i += 1;
END;

-- Anunciante con dos campañas de febrero de 2027: la pieza 1 apunta a XVA (que
-- juega el partido 226) y la pieza 2, a XVM y XVJ (franja de PBI 9).
EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = N'Anunciante Prueba Vistas', @id_pais = @xvm, @id_anunciante = @id_anunciante OUTPUT;
EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @id_anunciante, @nombre = N'Campaña Prueba Vistas 1',
    @fecha_inicio = '2027-02-01', @fecha_fin = '2027-02-28', @id_campania = @c1 OUTPUT;
EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @id_anunciante, @nombre = N'Campaña Prueba Vistas 2',
    @fecha_inicio = '2027-02-01', @fecha_fin = '2027-02-28', @id_campania = @c2 OUTPUT;
EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @c1, @titulo = N'Pieza Prueba Vistas 1',
    @mercados = 'XVA', @codigo_idioma = 'es', @mostrar = 0;
EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @c2, @titulo = N'Pieza Prueba Vistas 2',
    @mercados = 'XVM,XVJ', @codigo_idioma = 'en', @mostrar = 0;

-- Fixture: tres partidos de grupos y uno de cuartos.
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 226, @id_sede = @sede1, @fase = 'GRUPOS', @fecha_hora_utc = '2027-02-10 19:00',
    @id_seleccion_local = @xva, @id_seleccion_visitante = @xvb;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 227, @id_sede = @sede2, @fase = 'GRUPOS', @fecha_hora_utc = '2027-02-11 19:00',
    @id_seleccion_local = @xvc, @id_seleccion_visitante = @xvd, @id_partido = @id_227 OUTPUT;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 228, @id_sede = @sede1, @fase = 'GRUPOS', @fecha_hora_utc = '2027-02-15 19:00',
    @id_seleccion_local = @xva, @id_seleccion_visitante = @xvc;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 229, @id_sede = @sede2, @fase = 'CUARTOS', @fecha_hora_utc = '2027-02-20 19:00',
    @id_seleccion_local = @xva, @id_seleccion_visitante = @xvd;

-- Terna del partido 227.
SELECT @a = id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Vistas 1';
SELECT @b = id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Vistas 2';
SELECT @c = id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Vistas 3';
SELECT @d = id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Vistas 4';
SELECT @e = id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Vistas 5';
EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_227, @id_principal = @a, @id_asistente_1 = @b,
    @id_asistente_2 = @c, @id_cuarto = @d, @id_var = @e, @mostrar = 0;
GO

-- Partido 226 (XVA - XVB, grupos): cambio por lesión del 4 de XVA en el 17,
-- amarilla al 8 de XVA, gol del 9 de XVA, gol en contra del 3 de XVB, cambio
-- táctico del 11 de XVA en el 60 y doble amarilla al 5 de XVB (40 y 70).
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);
DECLARE @j1 INT, @j2 INT;
DECLARE @jugada TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @en_contra TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'EN CONTRA');
EXEC #usp_FormacionPrueba @numero_partido = 226, @codigo_fifa = 'XVA';
EXEC #usp_FormacionPrueba @numero_partido = 226, @codigo_fifa = 'XVB';
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'EN_JUEGO';
EXEC #usp_Jugador 'XVA', 4, @j1 OUTPUT;  EXEC #usp_Jugador 'XVA', 13, @j2 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id, @id_jugador_sale = @j1, @id_jugador_entra = @j2, @minuto = 17, @motivo = 'LESION';
EXEC #usp_Jugador 'XVA', 8, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id, @tipo_tarjeta = 'AMARILLA', @minuto = 25,
    @motivo = 'Falta imprudente', @id_jugador = @j1, @mostrar = 0;
EXEC #usp_Jugador 'XVA', 9, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id, @id_jugador_autor = @j1, @id_tipo_gol = @jugada,
    @periodo = 'PRIMER_TIEMPO', @minuto = 30, @mostrar = 0;
EXEC #usp_Jugador 'XVB', 5, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id, @tipo_tarjeta = 'AMARILLA', @minuto = 40,
    @motivo = 'Sujetar a un rival', @id_jugador = @j1, @mostrar = 0;
EXEC #usp_Jugador 'XVB', 3, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id, @id_jugador_autor = @j1, @id_tipo_gol = @en_contra,
    @periodo = 'SEGUNDO_TIEMPO', @minuto = 60, @mostrar = 0;
EXEC #usp_Jugador 'XVA', 11, @j1 OUTPUT;  EXEC #usp_Jugador 'XVA', 19, @j2 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = @id, @id_jugador_sale = @j1, @id_jugador_entra = @j2, @minuto = 60, @motivo = 'TACTICO';
EXEC #usp_Jugador 'XVB', 5, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id, @tipo_tarjeta = 'AMARILLA', @minuto = 70,
    @motivo = 'Demorar la reanudación', @id_jugador = @j1, @mostrar = 0;
EXEC Torneo.usp_FinalizarPartido @id_partido = @id, @asistencia = 50000, @mostrar = 0;
GO

-- Partido 227 (XVC - XVD, grupos): gol del 9 de XVD y roja directa al 3 de XVC;
-- después, informe y sanción del árbitro principal.
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 227);
DECLARE @j1 INT, @principal INT;
DECLARE @jugada TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
EXEC #usp_FormacionPrueba @numero_partido = 227, @codigo_fifa = 'XVC';
EXEC #usp_FormacionPrueba @numero_partido = 227, @codigo_fifa = 'XVD';
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'EN_JUEGO';
EXEC #usp_Jugador 'XVD', 9, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id, @id_jugador_autor = @j1, @id_tipo_gol = @jugada,
    @periodo = 'SEGUNDO_TIEMPO', @minuto = 50, @mostrar = 0;
EXEC #usp_Jugador 'XVC', 3, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id, @tipo_tarjeta = 'ROJA', @minuto = 58,
    @motivo = 'Agresión a un rival', @id_jugador = @j1, @mostrar = 0;
EXEC Torneo.usp_FinalizarPartido @id_partido = @id, @asistencia = 40000, @mostrar = 0;
SET @principal = (SELECT id_arbitro FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id AND rol = 'PRINCIPAL');
EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Modificacion @id_partido = @id, @id_arbitro = @principal,
    @informe_postpartido = 'Buen manejo del partido; la expulsión fue correcta.',
    @sancion = 'Apercibimiento por demorar el informe.';
GO

-- Partido 228 (XVA - XVC, grupos): XVC juega sin el 3 (suspendido por la roja
-- del 227; entra el 13). Gol del 9 de XVA, segunda amarilla del torneo al 8 de
-- XVA (suspensión por acumulación) y gol de cabeza del 9 de XVC.
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 228);
DECLARE @j1 INT;
DECLARE @jugada TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @cabezazo TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'CABEZAZO');
EXEC #usp_FormacionPrueba @numero_partido = 228, @codigo_fifa = 'XVA';
EXEC #usp_FormacionPrueba @numero_partido = 228, @codigo_fifa = 'XVC', @excluido = 3, @reemplazo = 13;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'EN_JUEGO';
EXEC #usp_Jugador 'XVA', 9, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id, @id_jugador_autor = @j1, @id_tipo_gol = @jugada,
    @periodo = 'PRIMER_TIEMPO', @minuto = 20, @mostrar = 0;
EXEC #usp_Jugador 'XVA', 8, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = @id, @tipo_tarjeta = 'AMARILLA', @minuto = 50,
    @motivo = 'Protestar', @id_jugador = @j1, @mostrar = 0;
EXEC #usp_Jugador 'XVC', 9, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id, @id_jugador_autor = @j1, @id_tipo_gol = @cabezazo,
    @periodo = 'SEGUNDO_TIEMPO', @minuto = 70, @mostrar = 0;
EXEC Torneo.usp_FinalizarPartido @id_partido = @id, @asistencia = 55000, @mostrar = 0;
GO

-- Partido 229 (XVA - XVD, cuartos): XVA juega sin el 8 (suspendido; entra el
-- 16). 1 - 1 en los 90 (9 de XVA y 9 de XVD), 2 - 2 en el alargue (10 de cada
-- uno) y penales: convierten el 9, 10, 11 y 7 de XVA y el 9, 10 y 11 de XVD.
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 229);
DECLARE @j1 INT, @k INT = 1, @codigo CHAR(3), @dorsal TINYINT;
DECLARE @jugada TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'JUGADA');
DECLARE @penal TINYINT = (SELECT id_tipo_gol FROM DesarrolloPartido.TIPO_GOL WHERE descripcion = 'PENAL');
DECLARE @penales TABLE (orden INT IDENTITY(1,1), codigo_fifa CHAR(3), dorsal TINYINT);
INSERT INTO @penales (codigo_fifa, dorsal)
VALUES ('XVA', 9), ('XVD', 9), ('XVA', 10), ('XVD', 10), ('XVA', 11), ('XVD', 11), ('XVA', 7);
EXEC #usp_FormacionPrueba @numero_partido = 229, @codigo_fifa = 'XVA', @excluido = 8, @reemplazo = 16;
EXEC #usp_FormacionPrueba @numero_partido = 229, @codigo_fifa = 'XVD';
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'EN_JUEGO';
EXEC #usp_Jugador 'XVA', 9, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id, @id_jugador_autor = @j1, @id_tipo_gol = @jugada,
    @periodo = 'PRIMER_TIEMPO', @minuto = 30, @mostrar = 0;
EXEC #usp_Jugador 'XVD', 9, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id, @id_jugador_autor = @j1, @id_tipo_gol = @jugada,
    @periodo = 'SEGUNDO_TIEMPO', @minuto = 80, @mostrar = 0;
EXEC #usp_Jugador 'XVA', 10, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id, @id_jugador_autor = @j1, @id_tipo_gol = @jugada,
    @periodo = 'ALARGUE', @minuto = 100, @mostrar = 0;
EXEC #usp_Jugador 'XVD', 10, @j1 OUTPUT;
EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id, @id_jugador_autor = @j1, @id_tipo_gol = @jugada,
    @periodo = 'ALARGUE', @minuto = 115, @mostrar = 0;
WHILE @k <= 7
BEGIN
    SELECT @codigo = codigo_fifa, @dorsal = dorsal FROM @penales WHERE orden = @k;
    EXEC #usp_Jugador @codigo, @dorsal, @j1 OUTPUT;
    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = @id, @id_jugador_autor = @j1, @id_tipo_gol = @penal,
        @periodo = 'PENALES', @mostrar = 0;
    SET @k += 1;
END;
EXEC Torneo.usp_FinalizarPartido @id_partido = @id, @asistencia = 60000, @mostrar = 0;
GO

SELECT 'Mini torneo' AS caso, numero_partido, fase, seleccion_local, resultado, seleccion_visitante, estado
FROM Torneo.vw_Fixture WHERE numero_partido BETWEEN 226 AND 229 ORDER BY numero_partido;
GO


/* ============================================================================
   CASOS
   ============================================================================ */

/* FV1 fn_ParametrosDelSistema
   Esperado: los 17 parámetros del sistema están cargados y dentro de su rango
   (columna dentro_de_rango = 1 en todas las filas). */
SELECT 'FV1' AS caso, ps.codigo, pr.valor, ps.valor_minimo, ps.valor_maximo,
       IIF(pr.valor BETWEEN ps.valor_minimo AND ps.valor_maximo, 1, 0) AS dentro_de_rango
FROM DatosGenerales.fn_ParametrosDelSistema() AS ps
LEFT JOIN DatosGenerales.PARAMETRO_REGLAMENTO AS pr ON pr.codigo = ps.codigo
ORDER BY ps.codigo;
GO

/* FV2 vw_Fixture y fn_Fixture con cada filtro (contando solo los partidos de prueba)
   Esperado: 4 partidos en total; 3 de GRUPOS; 3 de XVA; 2 en "Estadio Prueba
   Vistas 1"; 1 el 11/02/2027 en hora local (el 227). El detalle de XVA muestra
   el grupo I en los partidos de grupos. */
DECLARE @xva INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XVA');
DECLARE @sede1 INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Vistas 1');

SELECT 'FV2' AS caso, filtro, partidos
FROM (VALUES ('Fixture completo', (SELECT COUNT(*) FROM Torneo.fn_Fixture(NULL, NULL, NULL, NULL) WHERE numero_partido BETWEEN 226 AND 229)),
             ('Fase GRUPOS',      (SELECT COUNT(*) FROM Torneo.fn_Fixture(NULL, 'GRUPOS', NULL, NULL) WHERE numero_partido BETWEEN 226 AND 229)),
             ('Selección XVA',    (SELECT COUNT(*) FROM Torneo.fn_Fixture(NULL, NULL, @xva, NULL))),
             ('Sede Vistas 1',    (SELECT COUNT(*) FROM Torneo.fn_Fixture(@sede1, NULL, NULL, NULL))),
             ('Fecha 11/02/2027', (SELECT COUNT(*) FROM Torneo.fn_Fixture(NULL, NULL, NULL, '2027-02-11') WHERE numero_partido BETWEEN 226 AND 229))
     ) AS f (filtro, partidos);

SELECT 'FV2 XVA' AS caso, numero_partido, fase, grupo, fecha_hora_local, nombre_estadio,
       seleccion_local, resultado, seleccion_visitante
FROM Torneo.fn_Fixture(NULL, NULL, @xva, NULL)
ORDER BY fecha_hora_utc;
GO

/* FV3 fn_EquipoEnCancha: el cambio por lesión del partido 226
   Esperado: XVA tiene 11 jugadores en cancha en los tres minutos. En el 10
   está el dorsal 4; en el 20 ya no, y está el 13, que entró en el 17 por
   lesión. En el 90 ya entró el 19 por el 11 (cambio del 60). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);
DECLARE @xva INT = (SELECT id_seleccion_local FROM Torneo.PARTIDO WHERE id_partido = @id_partido);

SELECT 'FV3' AS caso, m.minuto, COUNT(*) AS en_cancha,
       STRING_AGG(CAST(e.dorsal AS VARCHAR(3)), ', ') WITHIN GROUP (ORDER BY e.dorsal) AS dorsales
FROM (VALUES (CAST(10 AS TINYINT)), (CAST(20 AS TINYINT)), (CAST(90 AS TINYINT))) AS m (minuto)
CROSS APPLY DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @xva, m.minuto, 0) AS e
GROUP BY m.minuto
ORDER BY m.minuto;
GO

/* FV4 fn_EquipoEnCancha: la expulsión por doble amarilla del partido 226
   Esperado: XVB tiene 11 jugadores en el minuto 60 y 10 en el 80, sin el
   dorsal 5, expulsado en el 70. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);
DECLARE @xvb INT = (SELECT id_seleccion_visitante FROM Torneo.PARTIDO WHERE id_partido = @id_partido);

SELECT 'FV4' AS caso, m.minuto, COUNT(*) AS en_cancha,
       MAX(IIF(e.dorsal = 5, 1, 0)) AS esta_el_dorsal_5
FROM (VALUES (CAST(60 AS TINYINT)), (CAST(80 AS TINYINT))) AS m (minuto)
CROSS APPLY DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @xvb, m.minuto, 0) AS e
GROUP BY m.minuto
ORDER BY m.minuto;
GO

/* FV5 fn_MarcadorSegunGoles
   Esperado: 226, 2 - 0 (el segundo es un gol en contra del 3 de XVB, que suma
   para XVA); 227, 0 - 1; 228, 1 - 1; 229, 2 - 2 con 1 - 1 en los 90 minutos y
   4 - 3 por penales. Todos coinciden con el resultado guardado en PARTIDO. */
SELECT 'FV5' AS caso, p.numero_partido, m.goles_local, m.goles_visitante, m.goles_local_90, m.goles_visitante_90,
       m.penales_local, m.penales_visitante, f.resultado AS resultado_guardado
FROM Torneo.PARTIDO AS p
CROSS APPLY DesarrolloPartido.fn_MarcadorSegunGoles(p.id_partido) AS m
INNER JOIN Torneo.vw_Fixture AS f ON f.id_partido = p.id_partido
WHERE p.numero_partido BETWEEN 226 AND 229
ORDER BY p.numero_partido;
GO

/* FV6 fn_Sanciones (selecciones de prueba)
   Esperado: 3 sanciones de 1 partido: dorsal 5 de XVB por doble amarilla
   (partido 226), dorsal 3 de XVC por roja directa (227) y dorsal 8 de XVA por
   acumulación (228, su segunda amarilla del torneo). */
SELECT 'FV6' AS caso, pa.nombre AS seleccion, j.dorsal, s.motivo,
       p.numero_partido AS partido_origen, s.partidos_de_suspension
FROM DesarrolloPartido.fn_Sanciones() AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = s.id_seleccion
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = s.id_partido_origen
WHERE pa.codigo_fifa LIKE 'XV_' AND pa.nombre LIKE 'Prueba XV_'
ORDER BY p.numero_partido;
GO

/* FV7 fn_JugadoresSuspendidos
   Esperado: en el partido 228 está suspendido el dorsal 3 de XVC y en el 229
   el dorsal 8 de XVA (cada uno cumple su primera y única fecha). En el 226 y
   el 227 no hay suspendidos. */
SELECT 'FV7' AS caso, p.numero_partido, j.dorsal, j.apellido, s.motivo, s.numero_partido_origen, s.partido_que_cumple
FROM Torneo.PARTIDO AS p
CROSS APPLY DesarrolloPartido.fn_JugadoresSuspendidos(p.id_partido) AS s
INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
WHERE p.numero_partido BETWEEN 226 AND 229
ORDER BY p.numero_partido;
GO

/* FV8 Criterios de suspensión parametrizables
   Dentro de una transacción que se deshace al final: con
   AMARILLAS_PARA_SUSPENSION = 3, el dorsal 8 de XVA ya no está suspendido
   para el partido 229 (tiene 2 amarillas); con FECHAS_SUSPENSION_ROJA_DIRECTA
   = 2, la roja del dorsal 3 de XVC pasa a 2 partidos.
   Esperado: 0 suspendidos en el 229 y 2 partidos para la roja; al final los
   dos parámetros vuelven a 2 y 1. */
DECLARE @id_229 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 229);

BEGIN TRANSACTION;
BEGIN TRY
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'AMARILLAS_PARA_SUSPENSION', @valor = 3;
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'FECHAS_SUSPENSION_ROJA_DIRECTA', @valor = 2;

    SELECT 'FV8 con 3 amarillas' AS caso, COUNT(*) AS suspendidos_en_el_partido_229
    FROM DesarrolloPartido.fn_JugadoresSuspendidos(@id_229);

    SELECT 'FV8 con 2 fechas por roja' AS caso, pa.nombre AS seleccion, j.dorsal, s.motivo, s.partidos_de_suspension
    FROM DesarrolloPartido.fn_Sanciones() AS s
    INNER JOIN Torneo.JUGADOR AS j ON j.id_jugador = s.id_jugador
    INNER JOIN Torneo.SELECCION AS se ON se.id_seleccion = s.id_seleccion
    INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = se.id_pais
    WHERE s.motivo = 'ROJA DIRECTA' AND pa.codigo_fifa LIKE 'XV_' AND pa.nombre LIKE 'Prueba XV_';
END TRY
BEGIN CATCH
    PRINT N'FV8: FALLÓ, error inesperado: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0
    ROLLBACK TRANSACTION;

SELECT 'FV8 restaurado' AS caso, codigo, valor
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo IN ('AMARILLAS_PARA_SUSPENSION', 'FECHAS_SUSPENSION_ROJA_DIRECTA');
GO

/* FV9 fn_SeleccionesEnCompetencia (selecciones de prueba)
   Esperado: solo XVA, que ganó por penales el partido de cuartos (229). XVD
   lo perdió, y XVB y XVC no llegaron a la eliminación directa. */
SELECT 'FV9' AS caso, pa.nombre AS seleccion
FROM Torneo.fn_SeleccionesEnCompetencia() AS sc
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = sc.id_pais
WHERE pa.codigo_fifa LIKE 'XV_' AND pa.nombre LIKE 'Prueba XV_';
GO

/* FV10 fn_MercadosEnPrimeTime: simulación del partido 226 (19:00 UTC del 10/02/2027)
   Esperado, entre los países de prueba: en prime time (19 a 23 hs) XVA, XVB,
   XVC, XVD y XVN (UTC, a las 19) y XVM (UTC+2, a las 21); XVJ (UTC+9, a las
   04) no. XVA y XVB son los que juegan el partido. Dentro de una transacción
   que se deshace al final, con PRIME_TIME_DESDE = 21 queda solo XVM; al
   final el parámetro vuelve a 19. */
DECLARE @id_226 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);

SELECT 'FV10 mercados' AS caso, pa.codigo_fifa, m.huso_horario, m.hora_local, m.en_prime_time, m.juega_el_partido
FROM Publicidad.fn_MercadosEnPrimeTime(@id_226) AS m
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
WHERE pa.codigo_fifa LIKE 'XV_' AND pa.nombre LIKE 'Prueba XV_'
ORDER BY m.en_prime_time DESC, m.hora_local, pa.codigo_fifa;

BEGIN TRANSACTION;
BEGIN TRY
    SELECT 'FV10 conteo' AS caso, 'Desde las 19' AS franja, COUNT(*) AS paises_de_prueba_en_prime_time
    FROM Publicidad.fn_MercadosEnPrimeTime(@id_226) AS m INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
    WHERE m.en_prime_time = 1 AND pa.codigo_fifa LIKE 'XV_' AND pa.nombre LIKE 'Prueba XV_';

    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'PRIME_TIME_DESDE', @valor = 21;

    SELECT 'FV10 conteo' AS caso, 'Desde las 21' AS franja, COUNT(*) AS paises_de_prueba_en_prime_time
    FROM Publicidad.fn_MercadosEnPrimeTime(@id_226) AS m INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
    WHERE m.en_prime_time = 1 AND pa.codigo_fifa LIKE 'XV_' AND pa.nombre LIKE 'Prueba XV_';
END TRY
BEGIN CATCH
    PRINT N'FV10: FALLÓ, error inesperado: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0
    ROLLBACK TRANSACTION;
GO

/* FV11 fn_PrioridadPiezas del partido 226 (piezas de prueba)
   Esperado: las 2 piezas de prueba, en este orden: primero "Pieza Prueba
   Vistas 1", dirigida a XVA, que juega el partido, aunque su franja de PBI es
   0 (XVA no tiene PBI cargado); después "Pieza Prueba Vistas 2", de franja 9
   (XVJ) con 1 mercado en prime time (XVM). Sin otras campañas vigentes en
   febrero de 2027 tienen prioridad 1 y 2; si las hubiera, aparecen con otros
   números, pero en el mismo orden. */
DECLARE @id_226 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 226);
SELECT 'FV11' AS caso, pr.prioridad, pr.campania, pr.titulo, pr.dirigida_a_seleccion,
       pr.franja_pbi, pr.mercados_en_prime_time, pr.pbi_per_capita_max, pr.mercados_de_interes
FROM Publicidad.fn_PrioridadPiezas(@id_226) AS pr
WHERE pr.titulo LIKE N'Pieza Prueba Vistas%'
ORDER BY pr.prioridad;
GO

/* FV12 vw_HistorialTitularidad
   Esperado: el dorsal 8 de XVA figura como titular en los partidos 226 y 228
   y no figura en el 229, en el que estaba suspendido. En el 226, el dorsal 4
   de XVA sale en el minuto 17 y el 13 entra en el 17. */
SELECT 'FV12 XVA 8' AS caso, h.numero_partido, h.rival, h.condicion, h.jugo, h.minuto_ingreso, h.minuto_salida
FROM DesarrolloPartido.vw_HistorialTitularidad AS h
WHERE h.seleccion = 'Prueba XVA' AND h.dorsal = 8
ORDER BY h.numero_partido;

SELECT 'FV12 XVA partido 226' AS caso, h.dorsal, h.apellido, h.condicion, h.minuto_ingreso, h.minuto_salida
FROM DesarrolloPartido.vw_HistorialTitularidad AS h
WHERE h.seleccion = 'Prueba XVA' AND h.numero_partido = 226 AND h.dorsal IN (4, 13);
GO

/* FV13 vw_Goleadores (selecciones de prueba)
   Esperado: el 9 de XVA con 3 goles en 3 partidos; el 9 de XVD con 2; el 10
   de XVA, el 10 de XVD y el 9 de XVC con 1. No cuentan el gol en contra ni
   los penales de la definición. Control: 8 goles de goleadores más 1 en
   contra son los 9 goles de los resultados de los partidos 226 a 229. */
SELECT 'FV13' AS caso, seleccion, apellido, goles, partidos_con_gol
FROM DesarrolloPartido.vw_Goleadores
WHERE seleccion LIKE 'Prueba XV_'
ORDER BY goles DESC, apellido;

SELECT 'FV13 control' AS caso,
       (SELECT SUM(goles) FROM DesarrolloPartido.vw_Goleadores WHERE seleccion LIKE 'Prueba XV_') AS goles_de_goleadores,
       (SELECT COUNT(*) FROM DesarrolloPartido.GOL AS g
        INNER JOIN DesarrolloPartido.TIPO_GOL AS t ON t.id_tipo_gol = g.id_tipo_gol
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = g.id_partido
        WHERE t.es_en_contra = 1 AND p.numero_partido BETWEEN 226 AND 229)                      AS goles_en_contra,
       (SELECT SUM(goles_local + goles_visitante) FROM Torneo.PARTIDO
        WHERE numero_partido BETWEEN 226 AND 229)                                              AS goles_de_los_partidos;
GO

/* FV14 vw_HistorialArbitro
   Esperado: el árbitro principal del partido 227 ("Prueba Vistas 1") tiene
   registrados su informe y su sanción (apercibimiento); en el partido hubo
   0 amarillas y 1 roja. */
SELECT 'FV14' AS caso, h.apellido, h.pais, h.rol, h.numero_partido, h.resultado,
       h.amarillas_del_partido, h.rojas_del_partido, h.informe_postpartido, h.sancion
FROM Arbitraje.vw_HistorialArbitro AS h
WHERE h.numero_partido = 227 AND h.rol = 'PRINCIPAL';
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas de datos de prueba (también en la del
   parámetro PRUEBA_53_CUPO_GRUPO) y los parámetros con sus valores originales
   (AMARILLAS_PARA_SUSPENSION 2, FECHAS_SUSPENSION_ROJA_DIRECTA 1,
   PRIME_TIME_DESDE 19, SELECCIONES_POR_GRUPO 4).
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 226 AND 229)               AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa LIKE 'XV_' AND nombre LIKE 'Prueba XV_') AS paises_de_prueba,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO WHERE apellido LIKE N'Prueba Vistas%')                AS arbitros_de_prueba,
       (SELECT COUNT(*) FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba Vistas')  AS anunciantes_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Vistas%')         AS sedes_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'PRUEBA_53_CUPO_GRUPO') AS parametros_de_prueba;

SELECT 'Final' AS caso, codigo, valor
FROM DatosGenerales.PARAMETRO_REGLAMENTO
WHERE codigo IN ('AMARILLAS_PARA_SUSPENSION', 'FECHAS_SUSPENSION_ROJA_DIRECTA', 'PRIME_TIME_DESDE',
                 'SELECCIONES_POR_GRUPO')
ORDER BY codigo;
GO

SET NOEXEC OFF;
GO
