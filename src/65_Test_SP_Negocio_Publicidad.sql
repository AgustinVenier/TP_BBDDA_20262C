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
 Archivo: 65_Test_SP_Negocio_Publicidad.sql
 Objetivo: Probar los SP de 15_SP_Negocio_Publicidad.sql
           (usp_RegistrarPiezaPublicitaria y usp_AsignarPublicidadPartido),
           la simulación de prime time (fn_MercadosEnPrimeTime) y la
           prioridad de piezas (fn_PrioridadPiezas), incluido el caso
           obligatorio de un partido en prime time en más de cuatro mercados,
           en el que el sistema elige solo cuatro piezas.
           Requiere haber ejecutado 00 a 20; no depende del juego de datos.
           Usa sus propios datos de prueba: los países de prueba XPA y XPB
           (con selección, sin jugadores) y XPC a XPI (mercados, con su huso
           horario y su PBI per cápita 2024), el anunciante "Anunciante Prueba
           Negocio" con cinco campañas de febrero y marzo de 2027 (una pieza
           cada una), las sedes "Estadio Prueba Publicidad Negocio" (con sus 4
           espacios) y "Estadio Prueba Sin Espacios", y los partidos 250 a
           252. Los partidos son de 2027 para que las únicas piezas candidatas
           sean las del test; si hay otras campañas vigentes en febrero o marzo
           de 2027, el test lo avisa al empezar.
           Todo se borra al empezar y al terminar.
           Los casos obligatorios se prueban acá con datos propios.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.

 Mercados de prueba (partido 250: 20/02/2027 a las 19:00 UTC; prime time de
 19 a 23 hs y franjas de PBI de 10.000 USD, según 20_DatosIniciales.sql):
   Código  Huso                        Hora local  Prime time  PBI 2024  Franja
   XPA     UTC                         19:00       sí          20000     2
   XPB     UTC                         19:00       sí          -         -   (no es mercado de ninguna pieza)
   XPC     GMT Standard Time           19:00       sí          95000     9
   XPD     Romance Standard Time       20:00       sí          52000     5
   XPE     W. Europe Standard Time     20:00       sí          45000     4
   XPF     E. Europe Standard Time     21:00       sí          15000     1
   XPG     FLE Standard Time           21:00       sí          41000     4
   XPH     Tokyo Standard Time         04:00       no          88000     8
   XPI     Eastern Standard Time       14:00       no          93000     9
 Los países de prueba se llaman "Prueba <código>" y usan códigos FIFA que
 empiezan con X, que no tiene ningún miembro de la FIFA.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Publicidad.usp_AsignarPublicidadPartido', N'P') IS NULL
   OR OBJECT_ID(N'Torneo.usp_RegistrarSede', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO
                  WHERE codigo IN ('PRIME_TIME_DESDE', 'PRIME_TIME_HASTA', 'PBI_FRANJA_MILES_USD') HAVING COUNT(*) = 3)
BEGIN
    RAISERROR(N'Faltan los SP de negocio o los datos iniciales: ejecutar los scripts 00 a 20.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Las piezas de otras campañas vigentes en febrero o marzo de 2027 competirían
-- con las de prueba, y la asignación podría elegirlas: si las hay, se avisa.
DECLARE @otras INT = (SELECT COUNT(*)
                      FROM Publicidad.CAMPANIA AS c
                      INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
                      WHERE a.razon_social <> N'Anunciante Prueba Negocio'
                        AND c.fecha_inicio <= '2027-03-31' AND c.fecha_fin >= '2027-02-01');
IF @otras > 0
    PRINT CONCAT(N'ADVERTENCIA: hay ', @otras, N' campaña(s) ajenas a este test vigentes en febrero o marzo ',
                 N'de 2027. Sus piezas compiten con las de prueba, así que la asignación puede no dar el ',
                 N'resultado esperado.');
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

-- Da de alta con los SP un país de prueba ("Prueba <código>") con su huso
-- horario y, si se informa, su PBI per cápita 2024; si @con_seleccion = 1,
-- también su selección (sin jugadores) con su lista y su director técnico.
-- Los procedimientos temporales se crean en tempdb, que puede tener otra
-- intercalación que la base: por eso el código se usa con COLLATE DATABASE_DEFAULT.
IF OBJECT_ID(N'tempdb..#usp_CrearPaisPrueba', N'P') IS NOT NULL
    DROP PROCEDURE #usp_CrearPaisPrueba;
GO
CREATE PROCEDURE #usp_CrearPaisPrueba
    @codigo_fifa    CHAR(3),
    @huso_horario   VARCHAR(50),
    @pbi            DECIMAL(18,4) = NULL,
    @con_seleccion  BIT = 0,
    @id_seleccion   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @nombre      VARCHAR(60)  = CONCAT('Prueba ', @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @dt_apellido NVARCHAR(60) = CONCAT(N'Prueba DT ', @codigo_fifa COLLATE DATABASE_DEFAULT);
    DECLARE @id_pais SMALLINT;

    EXEC DatosGenerales.usp_PAIS_Alta @nombre = @nombre, @huso_horario = @huso_horario, @codigo_fifa = @codigo_fifa,
        @id_pais = @id_pais OUTPUT;
    IF @pbi IS NOT NULL
        EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Alta @id_pais = @id_pais, @codigo_indicador = 'NY.GDP.PCAP.CD',
            @anio = 2024, @valor = @pbi;
    IF @con_seleccion = 1
        EXEC Torneo.usp_RegistrarSeleccion
            @id_pais = @id_pais, @confederacion = 'UEFA', @grupo = NULL, @fecha_presentacion = '2026-06-01',
            @dt_nombre = N'Director', @dt_apellido = @dt_apellido, @id_seleccion = @id_seleccion OUTPUT, @mostrar = 0;
END;
GO

-- Borra con los SP de baja un país de prueba: sus indicadores, su selección
-- (cuerpo técnico, lista y selección) y el país. Sus partidos, anunciantes y
-- mercados de interés tienen que estar borrados antes.
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

IF OBJECT_ID(N'tempdb..#usp_LimpiarPruebas', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPruebas;
GO
CREATE PROCEDURE #usp_LimpiarPruebas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @id2 INT;

    -- Partidos de prueba con su publicidad. Un partido jugado vuelve primero a
    -- PROGRAMADO, porque la publicidad de un partido jugado no se puede borrar.
    WHILE EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 250 AND 252)
    BEGIN
        SELECT TOP (1) @id = id_partido FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 250 AND 252;
        IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id) = 'FINALIZADO'
            EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'EN_JUEGO';
        IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id) IN ('EN_JUEGO', 'SUSPENDIDO')
            EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'PROGRAMADO';
        WHILE EXISTS (SELECT 1 FROM Publicidad.EXHIBICION WHERE id_partido = @id)
        BEGIN
            SELECT TOP (1) @id2 = id_espacio FROM Publicidad.EXHIBICION WHERE id_partido = @id;
            EXEC Publicidad.usp_EXHIBICION_Baja @id_partido = @id, @id_espacio = @id2;
        END;
        EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;
    END;

    -- Sedes de prueba con sus espacios.
    WHILE EXISTS (SELECT 1 FROM Torneo.SEDE WHERE nombre_estadio IN ('Estadio Prueba Publicidad Negocio', 'Estadio Prueba Sin Espacios'))
    BEGIN
        SELECT TOP (1) @id = id_sede FROM Torneo.SEDE
        WHERE nombre_estadio IN ('Estadio Prueba Publicidad Negocio', 'Estadio Prueba Sin Espacios');
        WHILE EXISTS (SELECT 1 FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id)
        BEGIN
            SELECT TOP (1) @id2 = id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id;
            EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Baja @id_espacio = @id2;
        END;
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;
    END;

    -- Anunciante de prueba con sus campañas, piezas y mercados.
    WHILE EXISTS (SELECT 1 FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
                  INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = ppi.id_pieza
                  INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
                  INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
                  WHERE a.razon_social = N'Anunciante Prueba Negocio')
    BEGIN
        SELECT TOP (1) @id = ppi.id_pieza, @id2 = ppi.id_pais
        FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
        INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = ppi.id_pieza
        INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
        INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
        WHERE a.razon_social = N'Anunciante Prueba Negocio';
        EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Baja @id_pieza = @id, @id_pais = @id2;
    END;
    WHILE EXISTS (SELECT 1 FROM Publicidad.PIEZA_PUBLICITARIA AS pz
                  INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
                  INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
                  WHERE a.razon_social = N'Anunciante Prueba Negocio')
    BEGIN
        SELECT TOP (1) @id = pz.id_pieza FROM Publicidad.PIEZA_PUBLICITARIA AS pz
        INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
        INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
        WHERE a.razon_social = N'Anunciante Prueba Negocio';
        EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Baja @id_pieza = @id;
    END;
    WHILE EXISTS (SELECT 1 FROM Publicidad.CAMPANIA AS c INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
                  WHERE a.razon_social = N'Anunciante Prueba Negocio')
    BEGIN
        SELECT TOP (1) @id = c.id_campania FROM Publicidad.CAMPANIA AS c
        INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
        WHERE a.razon_social = N'Anunciante Prueba Negocio';
        EXEC Publicidad.usp_CAMPANIA_Baja @id_campania = @id;
    END;
    SET @id = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba Negocio');
    IF @id IS NOT NULL
        EXEC Publicidad.usp_ANUNCIANTE_Baja @id_anunciante = @id;

    -- Países de prueba, con sus indicadores y sus selecciones.
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XPA';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XPB';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XPC';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XPD';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XPE';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XPF';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XPG';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XPH';
    EXEC #usp_BorrarPaisPrueba @codigo_fifa = 'XPI';
END;
GO

EXEC #usp_LimpiarPruebas;
GO

/* Preparación (OK): países de prueba (ver la tabla del encabezado),
   anunciante con cinco campañas, sedes y partidos.
   - Campañas 1 a 3: del 01/02/2027 al 31/03/2027. Campañas 4 y 5: del
     01/02/2027 al 28/02/2027.
   - Partido 250: XPA - XPB, de octavos, el 20/02/2027 a las 19:00 UTC, en
     "Estadio Prueba Publicidad Negocio" (espacios 1 a 4 a 70000, 60000,
     50000 y 40000 USD).
   - Partido 251: el 21/02/2027 en "Estadio Prueba Sin Espacios".
   - Partido 252: el 15/03/2027, cuando solo siguen vigentes las campañas 1 a 3.
   Las piezas de las campañas 2 a 5 se dan de alta acá; la de la campaña 1,
   en PP1. */
DECLARE @usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @xpa INT, @xpb INT, @id_pais_xpc SMALLINT, @id_anunciante INT, @c2 INT, @c3 INT, @c4 INT, @c5 INT;
DECLARE @sede INT, @sin_espacios INT;

EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XPA', @huso_horario = 'UTC',                     @pbi = 20000, @con_seleccion = 1, @id_seleccion = @xpa OUTPUT;
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XPB', @huso_horario = 'UTC',                                   @con_seleccion = 1, @id_seleccion = @xpb OUTPUT;
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XPC', @huso_horario = 'GMT Standard Time',       @pbi = 95000;
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XPD', @huso_horario = 'Romance Standard Time',   @pbi = 52000;
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XPE', @huso_horario = 'W. Europe Standard Time', @pbi = 45000;
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XPF', @huso_horario = 'E. Europe Standard Time', @pbi = 15000;
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XPG', @huso_horario = 'FLE Standard Time',       @pbi = 41000;
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XPH', @huso_horario = 'Tokyo Standard Time',     @pbi = 88000;
EXEC #usp_CrearPaisPrueba @codigo_fifa = 'XPI', @huso_horario = 'Eastern Standard Time',   @pbi = 93000;

SET @id_pais_xpc = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XPC');
EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = N'Anunciante Prueba Negocio', @id_pais = @id_pais_xpc, @id_anunciante = @id_anunciante OUTPUT;
EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @id_anunciante, @nombre = N'Campaña Prueba Negocio',
    @fecha_inicio = '2027-02-01', @fecha_fin = '2027-03-31';
EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @id_anunciante, @nombre = N'Campaña Prueba Negocio 2',
    @fecha_inicio = '2027-02-01', @fecha_fin = '2027-03-31', @id_campania = @c2 OUTPUT;
EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @id_anunciante, @nombre = N'Campaña Prueba Negocio 3',
    @fecha_inicio = '2027-02-01', @fecha_fin = '2027-03-31', @id_campania = @c3 OUTPUT;
EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @id_anunciante, @nombre = N'Campaña Prueba Negocio 4',
    @fecha_inicio = '2027-02-01', @fecha_fin = '2027-02-28', @id_campania = @c4 OUTPUT;
EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @id_anunciante, @nombre = N'Campaña Prueba Negocio 5',
    @fecha_inicio = '2027-02-01', @fecha_fin = '2027-02-28', @id_campania = @c5 OUTPUT;
EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @c2, @titulo = N'Pieza Prueba Negocio Europa',
    @mercados = 'XPC,XPD,XPE', @codigo_idioma = 'en', @mostrar = 0;
EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @c3, @titulo = N'Pieza Prueba Negocio Mixta',
    @mercados = 'XPI,XPF', @codigo_idioma = 'en', @mostrar = 0;
EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @c4, @titulo = N'Pieza Prueba Negocio Asia',
    @mercados = 'XPH', @codigo_idioma = 'en', @mostrar = 0;
EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @c5, @titulo = N'Pieza Prueba Negocio Sur',
    @mercados = 'XPG,XPE', @codigo_idioma = 'en', @mostrar = 0;

EXEC Torneo.usp_RegistrarSede
    @nombre_estadio = 'Estadio Prueba Publicidad Negocio', @ciudad = 'Atlanta', @id_pais = @usa, @capacidad = 71000,
    @huso_horario = 'Eastern Standard Time', @tarifa_espacio_1 = 70000, @tarifa_espacio_2 = 60000,
    @tarifa_espacio_3 = 50000, @tarifa_espacio_4 = 40000, @id_sede = @sede OUTPUT, @mostrar = 0;
EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Sin Espacios', @ciudad = 'Denver', @id_pais = @usa,
    @capacidad = 76000, @huso_horario = 'Mountain Standard Time', @id_sede = @sin_espacios OUTPUT;

EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 250, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2027-02-20 19:00',
    @id_seleccion_local = @xpa, @id_seleccion_visitante = @xpb;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 251, @id_sede = @sin_espacios, @fase = 'OCTAVOS', @fecha_hora_utc = '2027-02-21 19:00';
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 252, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2027-03-15 19:00';

SELECT 'Preparación' AS caso, numero_partido, seleccion_local, seleccion_visitante, nombre_estadio, fecha_hora_utc
FROM Torneo.vw_Fixture WHERE numero_partido BETWEEN 250 AND 252 ORDER BY numero_partido;
GO


/* ============================================================================
   usp_RegistrarPiezaPublicitaria
   ============================================================================ */

/* PP1 (OK) Pieza dirigida a una selección, con mercados repetidos y en minúsculas.
   Esperado: la consulta del SP muestra la pieza "Pieza Prueba Negocio", en
   español y de 20 segundos, con dos mercados: Prueba XPA y Prueba XPG (el
   repetido se registra una sola vez). */
DECLARE @campania INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Campaña Prueba Negocio');
EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @campania, @titulo = N'Pieza Prueba Negocio',
    @mercados = 'xpa, XPG,XPA', @codigo_idioma = 'ES', @duracion_segundos = 20;
GO

/* PP2 (ERROR) Pieza sin mercados.
   Esperado: error 50001 con 1 condición: hay que informar al menos un
   mercado de interés. */
DECLARE @campania INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Campaña Prueba Negocio');
BEGIN TRY
    EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @campania, @titulo = N'Pieza Prueba Negocio 2', @mercados = ',';
    PRINT N'PP2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PP2';
END CATCH;
GO

/* PP3 (ERROR) Mercados e idioma que no existen.
   Esperado: error 50001 con 2 condiciones: los códigos de país XXX y YYY no
   existen y no existe el idioma "qq". */
DECLARE @campania INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Campaña Prueba Negocio');
BEGIN TRY
    EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @campania, @titulo = N'Pieza Prueba Negocio 2',
        @mercados = 'XPA,XXX,YYY', @codigo_idioma = 'qq';
    PRINT N'PP3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PP3';
END CATCH;
GO

/* PP4 (ERROR) Título repetido: falla el alta de la pieza y no se registra ningún mercado.
   Esperado: el error 50001 lo informa Publicidad.usp_PIEZA_PUBLICITARIA_Alta;
   la cantidad de mercados de interés no cambia. */
DECLARE @campania INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Campaña Prueba Negocio');
DECLARE @antes INT = (SELECT COUNT(*) FROM Publicidad.PIEZA_PAIS_INTERES);
BEGIN TRY
    EXEC Publicidad.usp_RegistrarPiezaPublicitaria @id_campania = @campania, @titulo = N'Pieza Prueba Negocio',
        @mercados = 'XPC,XPD', @mostrar = 0;
    PRINT N'PP4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PP4';
END CATCH;
SELECT 'PP4 después' AS caso, @antes AS mercados_antes, COUNT(*) AS mercados_despues FROM Publicidad.PIEZA_PAIS_INTERES;
GO


/* ============================================================================
   Caso obligatorio: prime time en más de cuatro mercados y elección de cuatro piezas
   ============================================================================ */

/* SIM (OK) Simulación de prime time del partido 250 (19:00 UTC del 20/02/2027).
   Esperado: 7 países de prueba en prime time (de 19 a 23 hs locales): XPA,
   XPB y XPC a las 19, XPD y XPE a las 20, XPF y XPG a las 21; XPH (04:00) y
   XPI (14:00) quedan afuera. De ellos, 6 son mercados de interés de las
   piezas (todos menos XPB). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
SELECT 'SIM' AS caso, pa.codigo_fifa, m.mercado, m.huso_horario, m.hora_local, m.en_prime_time, m.juega_el_partido
FROM Publicidad.fn_MercadosEnPrimeTime(@id_partido) AS m
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
WHERE pa.codigo_fifa LIKE 'XP_' AND pa.nombre LIKE 'Prueba XP%'
ORDER BY m.en_prime_time DESC, m.hora_local, pa.codigo_fifa;
SELECT 'SIM conteo' AS caso, COUNT(*) AS paises_de_prueba_en_prime_time
FROM Publicidad.fn_MercadosEnPrimeTime(@id_partido) AS m
INNER JOIN DatosGenerales.PAIS AS pa ON pa.id_pais = m.id_pais
WHERE pa.codigo_fifa LIKE 'XP_' AND pa.nombre LIKE 'Prueba XP%' AND m.en_prime_time = 1;
GO

/* PRI (OK) Piezas candidatas del partido 250, en orden de prioridad.
   Esperado: 5 candidatas (una por campaña vigente), con los mercados de las
   piezas en prime time en 6 países (más de 4), en este orden:
     1. "Pieza Prueba Negocio": dirigida a XPA, que juega el partido (franja 4).
     2. "Pieza Prueba Negocio Europa": franja 9 (XPC), 3 mercados en prime time.
     3. "Pieza Prueba Negocio Mixta": franja 9 (XPI), 1 mercado en prime time.
     4. "Pieza Prueba Negocio Asia": franja 8 (XPH).
     5. "Pieza Prueba Negocio Sur": franja 4 (XPE).
   La 2 y la 3 muestran el desempate por prime time dentro de la misma franja. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
SELECT 'PRI' AS caso, prioridad, campania, titulo, dirigida_a_seleccion, franja_pbi,
       mercados_en_prime_time, pbi_per_capita_max, mercados_de_interes
FROM Publicidad.fn_PrioridadPiezas(@id_partido)
ORDER BY prioridad;
GO

/* AP1 (OK) Asignación de las cuatro piezas.
   Esperado: de las 5 candidatas se registran solo las 4 de mayor prioridad:
   la pieza de prioridad 1 en el espacio de mayor tarifa (espacio 1, 70000) y
   así sucesivamente; "Pieza Prueba Negocio Sur" queda afuera. El costo de
   cada una es la tarifa de su espacio, en USD. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
SELECT 'AP1 antes' AS caso, COUNT(*) AS candidatas,
       (SELECT COUNT(*) FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido) AS exhibiciones
FROM Publicidad.fn_PrioridadPiezas(@id_partido);
EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido;
GO

/* AP2 (ERROR) Asignar otra vez sin pedir reasignación.
   Esperado: error 50001 con 1 condición: el partido ya tiene publicidad
   asignada (para reemplazarla, @reasignar = 1). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido;
    PRINT N'AP2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AP2';
END CATCH;
GO

/* AP3 (OK) Reasignación después de cambiar la tarifa de un espacio.
   El espacio 4 de la sede de prueba pasa a ser el más caro.
   Esperado: se reemplazan las 4 exhibiciones en la misma transacción; la
   pieza de prioridad 1 queda ahora en el espacio 4, con su tarifa nueva. Al
   final la tarifa vuelve a su valor original. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
DECLARE @e4 INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                   WHERE s.nombre_estadio = 'Estadio Prueba Publicidad Negocio' AND e.numero_espacio = 4);
DECLARE @tarifa DECIMAL(9,2) = (SELECT tarifa_usd FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_espacio = @e4);
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Modificacion @id_espacio = @e4, @tarifa_usd = 999999;
EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido, @reasignar = 1;
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Modificacion @id_espacio = @e4, @tarifa_usd = @tarifa;
GO

/* AP4 (ERROR) Publicidad para un partido ya jugado.
   Preparación: el partido 250 se juega y termina 1 - 0.
   Esperado: error 50001 con 2 condiciones: el partido 250 está FINALIZADO y
   ya tiene publicidad asignada. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 250);
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'FINALIZADO', @goles_local = 1, @goles_visitante = 0;
BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido;
    PRINT N'AP4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AP4';
END CATCH;
GO

/* AP5 (ERROR) Partido en una sede sin espacios publicitarios.
   Esperado: error 50001 con 1 condición: la sede tiene 0 espacios
   publicitarios y tienen que ser 4. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 251);
BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido;
    PRINT N'AP5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AP5';
END CATCH;
GO

/* AP6 (ERROR) Menos de cuatro piezas candidatas.
   El 15/03/2027 solo siguen vigentes las campañas 1 a 3.
   Esperado: error 50001 con 1 condición: hay 3 piezas candidatas y hacen
   falta 4. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 252);
BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = @id_partido;
    PRINT N'AP6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AP6';
END CATCH;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo LIKE N'Pieza Prueba Negocio%') AS piezas_de_prueba,
       (SELECT COUNT(*) FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba Negocio')   AS anunciantes_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 250 AND 252)                   AS partidos_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE
        WHERE nombre_estadio IN ('Estadio Prueba Publicidad Negocio', 'Estadio Prueba Sin Espacios'))  AS sedes_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa LIKE 'XP_' AND nombre LIKE 'Prueba XP%') AS paises_de_prueba;
GO

SET NOEXEC OFF;
GO
