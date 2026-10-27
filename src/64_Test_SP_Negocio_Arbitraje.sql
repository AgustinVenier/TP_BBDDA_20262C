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
 Archivo: 64_Test_SP_Negocio_Arbitraje.sql
 Objetivo: Probar los SP de 14_SP_Negocio_Arbitraje.sql (usp_RegistrarArbitro
           y usp_DesignarTernaArbitral): alta de árbitros con sus idiomas,
           designación de los cinco roles, rechazo por conflicto de
           nacionalidad (caso obligatorio) y advertencia por posible cruce
           desde dieciseisavos. Requiere haber ejecutado 00 a 20; no depende del
           juego de datos.
           Usa sus propios datos de prueba: la sede "Estadio Prueba
           Designaciones", cuatro selecciones de prueba (XRA a XRD, sin
           jugadores), el país de prueba XRN (sin selección), los árbitros de
           prueba ("Prueba Conflicto A" de XRA, "Prueba Conflicto B" de XRB,
           "Prueba Cruce" de XRC y "Prueba Neutral 1" a "10" de XRN) y los
           partidos 248 (XRC - XRD, ya jugado y con su terna), 245 (XRA - XRB),
           246 (XRC - XRD, 18 horas después) y 247 (sin selecciones). Todo se
           borra al empezar y al terminar, así que se puede ejecutar más de
           una vez.
           Los casos obligatorios se prueban acá con datos propios.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
     Las advertencias de posible cruce aparecen en Mensajes y en la columna
     "advertencia" de la consulta del SP.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
 Los países de prueba se llaman "Prueba <código>" y usan códigos FIFA que
 empiezan con X, que no tiene ningún miembro de la FIFA: así el test no choca
 con las selecciones ni los árbitros reales que se importen.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Arbitraje.usp_DesignarTernaArbitral', N'P') IS NULL
   OR OBJECT_ID(N'Torneo.usp_RegistrarSeleccion', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE codigo_iso IN ('en', 'fr', 'es', 'de') HAVING COUNT(*) = 4)
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

-- Da de alta con los SP un país de prueba ("Prueba <código>") y, si
-- @con_seleccion = 1, su selección (sin jugadores) con su lista presentada el
-- 01/06/2026 y su director técnico ("Prueba DT <código>").
-- Los procedimientos temporales se crean en tempdb, que puede tener otra
-- intercalación que la base: por eso el código se usa con COLLATE DATABASE_DEFAULT.
IF OBJECT_ID(N'tempdb..#usp_CrearSeleccionPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_CrearSeleccionPrueba;
GO
CREATE PROCEDURE #usp_CrearSeleccionPrueba
    @codigo_fifa    CHAR(3),
    @con_seleccion  BIT = 1,
    @id_seleccion   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @nombre      VARCHAR(60)  = CONCAT('Prueba ', @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @dt_apellido NVARCHAR(60) = CONCAT(N'Prueba DT ', @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @id_pais SMALLINT;

    EXEC DatosGenerales.usp_PAIS_Alta @nombre = @nombre, @huso_horario = 'UTC', @codigo_fifa = @codigo_fifa,
        @id_pais = @id_pais OUTPUT;
    IF @con_seleccion = 0 RETURN;
    EXEC Torneo.usp_RegistrarSeleccion
        @id_pais = @id_pais, @confederacion = 'UEFA', @grupo = NULL, @fecha_presentacion = '2026-06-01',
        @dt_nombre = N'Director', @dt_apellido = @dt_apellido, @id_seleccion = @id_seleccion OUTPUT, @mostrar = 0;
END;
GO

-- Borra con los SP de baja una selección de prueba (cuerpo técnico, lista y
-- selección) y su país. Sus partidos y sus árbitros tienen que estar borrados antes.
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

-- Devuelve el id de un árbitro de prueba por su apellido.
IF OBJECT_ID(N'tempdb..#usp_Arbitro', N'P') IS NOT NULL
    DROP PROCEDURE #usp_Arbitro;
GO
CREATE PROCEDURE #usp_Arbitro
    @apellido    NVARCHAR(60),
    @id_arbitro  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @id_arbitro = (SELECT id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = @apellido COLLATE DATABASE_DEFAULT);
END;
GO

IF OBJECT_ID(N'tempdb..#usp_LimpiarPruebas', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPruebas;
GO
CREATE PROCEDURE #usp_LimpiarPruebas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @id_arbitro INT;

    -- Partidos de prueba con sus designaciones. Un partido jugado vuelve primero
    -- a PROGRAMADO, porque la designación de un partido jugado no se puede borrar.
    WHILE EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 245 AND 248)
    BEGIN
        SELECT TOP (1) @id = id_partido FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 245 AND 248;
        IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id) = 'FINALIZADO'
            EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'EN_JUEGO';
        IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id) IN ('EN_JUEGO', 'SUSPENDIDO')
            EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'PROGRAMADO';
        WHILE EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id)
        BEGIN
            SELECT TOP (1) @id_arbitro = id_arbitro FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id;
            EXEC Arbitraje.usp_DESIGNACION_ARBITRAL_Baja @id_partido = @id, @id_arbitro = @id_arbitro;
        END;
        EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;
    END;

    -- Árbitros de los países de prueba, con sus idiomas.
    WHILE EXISTS (SELECT 1 FROM Arbitraje.ARBITRO AS a INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais
                  WHERE p.codigo_fifa IN ('XRA', 'XRB', 'XRC', 'XRD', 'XRN') AND p.nombre LIKE 'Prueba XR%')
    BEGIN
        SELECT TOP (1) @id_arbitro = a.id_arbitro FROM Arbitraje.ARBITRO AS a
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais
        WHERE p.codigo_fifa IN ('XRA', 'XRB', 'XRC', 'XRD', 'XRN') AND p.nombre LIKE 'Prueba XR%';
        WHILE EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id_arbitro)
        BEGIN
            SELECT TOP (1) @id = id_idioma FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id_arbitro;
            EXEC Arbitraje.usp_ARBITRO_IDIOMA_Baja @id_arbitro = @id_arbitro, @id_idioma = @id;
        END;
        EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id_arbitro, @eliminar_registro = 1;
    END;

    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XRA';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XRB';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XRC';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XRD';
    EXEC #usp_BorrarSeleccionPrueba @codigo_fifa = 'XRN';

    SET @id = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Designaciones');
    IF @id IS NOT NULL
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;
END;
GO

EXEC #usp_LimpiarPruebas;
GO

/* Preparación (OK): sede, selecciones y países de prueba, árbitros de prueba y
   partidos de prueba.
   - Árbitros: "Prueba Conflicto A" (de XRA), "Prueba Conflicto B" (de XRB),
     "Prueba Cruce" (de XRC) y "Prueba Neutral 1" a "10" (de XRN, sin
     selección); todos FIFA salvo "Prueba Neutral 3", de CONFEDERACION.
   - Partido 248 (dieciseisavos, 30/08/2026, XRC - XRD): con la terna de los
     neutrales 6 a 10, se juega y termina 1 - 0. XRC sigue en competencia.
   - Partidos 245 (XRA - XRB) y, 18 horas después, 246 (XRC - XRD), de
     octavos; 247, de octavos, sin selecciones definidas.
   Esperado: el fixture de los cuatro partidos, con el 248 FINALIZADO. */
DECLARE @can SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'CAN');
DECLARE @sede INT, @xra INT, @xrb INT, @xrc INT, @xrd INT, @id_248 INT;
DECLARE @i INT = 1, @id_pais SMALLINT, @apellido NVARCHAR(60), @categoria VARCHAR(15);
DECLARE @a INT, @b INT, @c INT, @d INT, @e INT;

EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Designaciones', @ciudad = 'Vancouver', @id_pais = @can,
    @capacidad = 54000, @huso_horario = 'Pacific Standard Time', @id_sede = @sede OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XRA', @id_seleccion = @xra OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XRB', @id_seleccion = @xrb OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XRC', @id_seleccion = @xrc OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XRD', @id_seleccion = @xrd OUTPUT;
EXEC #usp_CrearSeleccionPrueba @codigo_fifa = 'XRN', @con_seleccion = 0;

SET @id_pais = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XRA');
EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Árbitro', @apellido = N'Prueba Conflicto A', @categoria = 'FIFA';
SET @id_pais = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XRB');
EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Árbitro', @apellido = N'Prueba Conflicto B', @categoria = 'FIFA';
SET @id_pais = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XRC');
EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Árbitro', @apellido = N'Prueba Cruce', @categoria = 'FIFA';
SET @id_pais = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XRN');
WHILE @i <= 10
BEGIN
    SET @apellido = CONCAT(N'Prueba Neutral ', @i);
    SET @categoria = IIF(@i = 3, 'CONFEDERACION', 'FIFA');
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Árbitro', @apellido = @apellido, @categoria = @categoria;
    SET @i += 1;
END;

EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 248, @id_sede = @sede, @fase = 'DIECISEISAVOS', @fecha_hora_utc = '2026-08-30 02:00',
    @id_seleccion_local = @xrc, @id_seleccion_visitante = @xrd, @id_partido = @id_248 OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 6', @a OUTPUT;   EXEC #usp_Arbitro N'Prueba Neutral 7', @b OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 8', @c OUTPUT;   EXEC #usp_Arbitro N'Prueba Neutral 9', @d OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 10', @e OUTPUT;
EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_248, @id_principal = @a,
    @id_asistente_1 = @b, @id_asistente_2 = @c, @id_cuarto = @d, @id_var = @e, @mostrar = 0;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_248, @estado = 'EN_JUEGO';
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_248, @estado = 'FINALIZADO', @goles_local = 1, @goles_visitante = 0;

EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 245, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2026-09-05 02:00',
    @id_seleccion_local = @xra, @id_seleccion_visitante = @xrb;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 246, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2026-09-05 20:00',
    @id_seleccion_local = @xrc, @id_seleccion_visitante = @xrd;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 247, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2026-09-10 20:00';

SELECT 'Preparación' AS caso, numero_partido, fase, seleccion_local, resultado, seleccion_visitante, fecha_hora_utc, estado
FROM Torneo.vw_Fixture WHERE numero_partido BETWEEN 245 AND 248 ORDER BY fecha_hora_utc;
GO


/* ============================================================================
   usp_RegistrarArbitro
   ============================================================================ */

/* RA1 (OK) Alta de un árbitro con dos idiomas.
   Esperado: la consulta del SP muestra al árbitro del país de prueba XRN,
   categoría FIFA, con los idiomas francés e inglés. */
DECLARE @xrn SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XRN');
EXEC Arbitraje.usp_RegistrarArbitro @id_pais = @xrn, @nombre = N'Kofi', @apellido = N'Prueba Arbitro', @categoria = 'FIFA',
    @idiomas = 'en, FR', @fecha_nacimiento = '1987-05-14';
GO

/* RA2 (ERROR) Sin idiomas.
   Esperado: error 50001 con 1 condición: hay que informar al menos un idioma. */
DECLARE @xrn SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XRN');
BEGIN TRY
    EXEC Arbitraje.usp_RegistrarArbitro @id_pais = @xrn, @nombre = N'Ama', @apellido = N'Prueba Sin Idioma',
        @categoria = 'FIFA', @idiomas = ' , ';
    PRINT N'RA2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RA2';
END CATCH;
GO

/* RA3 (ERROR) Idiomas que no existen.
   Esperado: error 50001 con 1 condición que lista los códigos xx y zz. */
DECLARE @xrn SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XRN');
BEGIN TRY
    EXEC Arbitraje.usp_RegistrarArbitro @id_pais = @xrn, @nombre = N'Ama', @apellido = N'Prueba Idiomas',
        @categoria = 'FIFA', @idiomas = 'en,xx,zz';
    PRINT N'RA3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RA3';
END CATCH;
GO

/* RA4 (ERROR) Árbitro repetido: falla el alta y no se registra ningún idioma.
   Esperado: el error 50001 lo informa Arbitraje.usp_ARBITRO_Alta; la
   cantidad de idiomas registrados de árbitros no cambia. */
DECLARE @xrn SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XRN');
DECLARE @antes INT = (SELECT COUNT(*) FROM Arbitraje.ARBITRO_IDIOMA);
BEGIN TRY
    EXEC Arbitraje.usp_RegistrarArbitro @id_pais = @xrn, @nombre = N'Kofi', @apellido = N'Prueba Arbitro', @categoria = 'FIFA',
        @idiomas = 'es,de', @mostrar = 0;
    PRINT N'RA4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'RA4';
END CATCH;
SELECT 'RA4 después' AS caso, @antes AS idiomas_antes, COUNT(*) AS idiomas_despues FROM Arbitraje.ARBITRO_IDIOMA;
GO


/* ============================================================================
   usp_DesignarTernaArbitral
   ============================================================================ */

/* DT1 (ERROR) Caso obligatorio: designación descartada por conflicto de nacionalidad.
   En XRA - XRB se propone a "Prueba Conflicto A" (de XRA) como principal y a
   "Prueba Conflicto B" (de XRB) como cuarto árbitro, y a "Prueba Neutral 3"
   (categoría de confederación) como VAR.
   Esperado: error 50001 con 3 condiciones: dos conflictos de nacionalidad y
   que el VAR tiene que ser de categoría FIFA. No queda ningún árbitro
   designado. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @conflicto_a INT, @conflicto_b INT, @n1 INT, @n2 INT, @n3 INT;
EXEC #usp_Arbitro N'Prueba Conflicto A', @conflicto_a OUTPUT;   EXEC #usp_Arbitro N'Prueba Conflicto B', @conflicto_b OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 1', @n1 OUTPUT;              EXEC #usp_Arbitro N'Prueba Neutral 2', @n2 OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 3', @n3 OUTPUT;
BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido, @id_principal = @conflicto_a,
        @id_asistente_1 = @n1, @id_asistente_2 = @n2, @id_cuarto = @conflicto_b, @id_var = @n3;
    PRINT N'DT1: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DT1';
END CATCH;
SELECT 'DT1 después' AS caso, COUNT(*) AS designaciones FROM Arbitraje.DESIGNACION_ARBITRAL WHERE id_partido = @id_partido;
GO

/* DT2 (ERROR) Un árbitro en dos roles, un rol sin árbitro y un id que no existe.
   Esperado: error 50001 con 3 condiciones. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @n4 INT;
EXEC #usp_Arbitro N'Prueba Neutral 4', @n4 OUTPUT;
BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido, @id_principal = @n4,
        @id_asistente_1 = @n4, @id_asistente_2 = NULL, @id_cuarto = -1, @id_var = @n4;
    PRINT N'DT2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DT2';
END CATCH;
GO

/* DT3 (OK) Designación completa con una advertencia de posible cruce.
   "Prueba Cruce" es de XRC, que sigue en competencia (ganó el partido 248 y
   juega el 246), así que en un partido de octavos puede cruzarse con XRA o
   XRB.
   Esperado: se designan los cinco árbitros; en Mensajes aparece la
   advertencia y la consulta del SP marca a "Prueba Cruce" con "PUEDE CRUZARSE". */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @n4 INT, @cruce INT, @n1 INT, @n3 INT, @n5 INT;
EXEC #usp_Arbitro N'Prueba Neutral 4', @n4 OUTPUT;   EXEC #usp_Arbitro N'Prueba Cruce', @cruce OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 1', @n1 OUTPUT;   EXEC #usp_Arbitro N'Prueba Neutral 3', @n3 OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 5', @n5 OUTPUT;
EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido, @id_principal = @n4,
    @id_asistente_1 = @cruce, @id_asistente_2 = @n1, @id_cuarto = @n3, @id_var = @n5;
GO

/* DT4 (ERROR) Segunda designación para el mismo partido.
   Esperado: error 50001 con 1 condición: el partido ya tiene árbitros designados. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 245);
DECLARE @a INT, @b INT, @c INT, @d INT, @e INT;
EXEC #usp_Arbitro N'Prueba Neutral 6', @a OUTPUT;   EXEC #usp_Arbitro N'Prueba Neutral 7', @b OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 8', @c OUTPUT;   EXEC #usp_Arbitro N'Prueba Neutral 9', @d OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 10', @e OUTPUT;
BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido, @id_principal = @a,
        @id_asistente_1 = @b, @id_asistente_2 = @c, @id_cuarto = @d, @id_var = @e;
    PRINT N'DT4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DT4';
END CATCH;
GO

/* DT5 (ERROR) Árbitros que ya dirigen otro partido a menos de 24 horas.
   Esperado: error 50001 con 2 condiciones: "Prueba Neutral 4" y "Prueba
   Neutral 5" ya dirigen el partido 245, a menos de 24 horas del 246. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @n4 INT, @n5 INT, @b INT, @c INT, @d INT;
EXEC #usp_Arbitro N'Prueba Neutral 4', @n4 OUTPUT;   EXEC #usp_Arbitro N'Prueba Neutral 5', @n5 OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 7', @b OUTPUT;    EXEC #usp_Arbitro N'Prueba Neutral 8', @c OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 9', @d OUTPUT;
BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido, @id_principal = @n4,
        @id_asistente_1 = @b, @id_asistente_2 = @c, @id_cuarto = @d, @id_var = @n5;
    PRINT N'DT5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DT5';
END CATCH;
GO

/* DT6 (ERROR) Partido ya jugado y partido sin selecciones definidas.
   Esperado: dos errores 50001. DT6a, con 2 condiciones: el partido 248 está
   FINALIZADO y ya tiene su terna. DT6b, con 1 condición: en el 247 las dos selecciones
   tienen que estar definidas para controlar la nacionalidad. */
DECLARE @a INT, @b INT, @c INT, @d INT, @e INT;
EXEC #usp_Arbitro N'Prueba Neutral 6', @a OUTPUT;   EXEC #usp_Arbitro N'Prueba Neutral 7', @b OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 8', @c OUTPUT;   EXEC #usp_Arbitro N'Prueba Neutral 9', @d OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 10', @e OUTPUT;
DECLARE @p248 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 248);
DECLARE @p247 INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 247);
BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @p248, @id_principal = @a,
        @id_asistente_1 = @b, @id_asistente_2 = @c, @id_cuarto = @d, @id_var = @e;
    PRINT N'DT6a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DT6a';
END CATCH;
BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @p247, @id_principal = @a,
        @id_asistente_1 = @b, @id_asistente_2 = @c, @id_cuarto = @d, @id_var = @e;
    PRINT N'DT6b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DT6b';
END CATCH;
GO

/* DT7 (ERROR) Un árbitro inactivo.
   El árbitro "Prueba Arbitro" (RA1) se da de baja (lógica) y se lo propone
   como cuarto árbitro del partido 246.
   Esperado: error 50001 con 1 condición: el árbitro no está activo. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 246);
DECLARE @prueba INT, @a INT, @b INT, @c INT, @e INT;
EXEC #usp_Arbitro N'Prueba Arbitro', @prueba OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 6', @a OUTPUT;   EXEC #usp_Arbitro N'Prueba Neutral 7', @b OUTPUT;
EXEC #usp_Arbitro N'Prueba Neutral 8', @c OUTPUT;   EXEC #usp_Arbitro N'Prueba Neutral 10', @e OUTPUT;
EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @prueba;
BEGIN TRY
    EXEC Arbitraje.usp_DesignarTernaArbitral @id_partido = @id_partido, @id_principal = @a,
        @id_asistente_1 = @b, @id_asistente_2 = @c, @id_cuarto = @prueba, @id_var = @e;
    PRINT N'DT7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'DT7';
END CATCH;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO AS a INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais
        WHERE p.codigo_fifa LIKE 'XR_')                                                    AS arbitros_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 245 AND 248)      AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa LIKE 'XR_')             AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Designaciones') AS sedes_de_prueba;
GO

SET NOEXEC OFF;
GO
