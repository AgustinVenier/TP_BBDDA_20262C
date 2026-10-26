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
 Archivo: 58_Test_SP_ABM_Publicidad.sql
 Objetivo: Probar los SP de 08_SP_ABM_Publicidad.sql (ANUNCIANTE, CAMPANIA,
           PIEZA_PUBLICITARIA, PIEZA_PAIS_INTERES, ESPACIO_PUBLICITARIO y
           EXHIBICION), con casos exitosos y su evidencia y casos que no
           cumplen las validaciones. Requiere haber ejecutado 00 a 20; no
           depende del juego de datos.
           Usa datos de prueba propios ("Anunciante Prueba S.A." con sus
           campañas y piezas, "Anunciante Prueba Dos", sin campañas, las
           sedes "Estadio Prueba Publicidad" y
           "Estadio Prueba Publicidad 2", los países de prueba XBA y XBB con
           sus selecciones y los partidos 220 y 221) y los borra al empezar y al
           terminar con los SP de baja, así que se puede ejecutar más de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
 Los países de prueba se llaman "Prueba <código>" y usan códigos FIFA que
 empiezan con X, que no tiene ningún miembro de la FIFA: así el test no choca
 con las selecciones reales que se importen.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Publicidad.usp_EXHIBICION_Alta', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es')
BEGIN
    RAISERROR(N'Faltan los SP de ABM o los datos iniciales: ejecutar los scripts 00 a 20.', 16, 1);
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

IF OBJECT_ID(N'tempdb..#usp_LimpiarPruebas', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPruebas;
GO
CREATE PROCEDURE #usp_LimpiarPruebas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @id2 INT;

    -- Partidos de prueba con sus exhibiciones. Un partido jugado vuelve primero
    -- a PROGRAMADO, porque la publicidad de un partido jugado no se puede borrar.
    WHILE EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE numero_partido IN (220, 221))
    BEGIN
        SELECT TOP (1) @id = id_partido FROM Torneo.PARTIDO WHERE numero_partido IN (220, 221);
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

    -- Selecciones y países de prueba (XBA y XBB).
    WHILE EXISTS (SELECT 1 FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                  WHERE p.codigo_fifa IN ('XBA', 'XBB') AND p.nombre LIKE 'Prueba XB_')
    BEGIN
        SELECT TOP (1) @id = s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('XBA', 'XBB') AND p.nombre LIKE 'Prueba XB_';
        EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id;
    END;
    WHILE EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XBA', 'XBB') AND nombre LIKE 'Prueba XB_')
    BEGIN
        SELECT TOP (1) @id = id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XBA', 'XBB') AND nombre LIKE 'Prueba XB_';
        EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    END;

    -- Sedes de prueba con sus espacios.
    WHILE EXISTS (SELECT 1 FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Publicidad%')
    BEGIN
        SELECT TOP (1) @id = id_sede FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Publicidad%';
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
                  WHERE a.razon_social = N'Anunciante Prueba S.A.')
    BEGIN
        SELECT TOP (1) @id = ppi.id_pieza, @id2 = ppi.id_pais
        FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
        INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = ppi.id_pieza
        INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
        INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
        WHERE a.razon_social = N'Anunciante Prueba S.A.';
        EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Baja @id_pieza = @id, @id_pais = @id2;
    END;
    WHILE EXISTS (SELECT 1 FROM Publicidad.PIEZA_PUBLICITARIA AS pz
                  INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
                  INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
                  WHERE a.razon_social = N'Anunciante Prueba S.A.')
    BEGIN
        SELECT TOP (1) @id = pz.id_pieza
        FROM Publicidad.PIEZA_PUBLICITARIA AS pz
        INNER JOIN Publicidad.CAMPANIA AS c ON c.id_campania = pz.id_campania
        INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
        WHERE a.razon_social = N'Anunciante Prueba S.A.';
        EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Baja @id_pieza = @id;
    END;
    WHILE EXISTS (SELECT 1 FROM Publicidad.CAMPANIA AS c
                  INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
                  WHERE a.razon_social = N'Anunciante Prueba S.A.')
    BEGIN
        SELECT TOP (1) @id = c.id_campania FROM Publicidad.CAMPANIA AS c
        INNER JOIN Publicidad.ANUNCIANTE AS a ON a.id_anunciante = c.id_anunciante
        WHERE a.razon_social = N'Anunciante Prueba S.A.';
        EXEC Publicidad.usp_CAMPANIA_Baja @id_campania = @id;
    END;
    SELECT @id = id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba S.A.';
    IF @@ROWCOUNT > 0
        EXEC Publicidad.usp_ANUNCIANTE_Baja @id_anunciante = @id;

    -- El segundo anunciante de prueba (AN6 y AN7), que no tiene campañas.
    SELECT @id = id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba Dos';
    IF @@ROWCOUNT > 0
        EXEC Publicidad.usp_ANUNCIANTE_Baja @id_anunciante = @id;
END;
GO

EXEC #usp_LimpiarPruebas;
GO


/* ============================================================================
   ANUNCIANTE
   ============================================================================ */

/* AN1 (OK) Alta de un anunciante.
   Esperado: 0 antes y 1 después, de Italia. */
DECLARE @ita SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ITA');
DECLARE @id INT;
SELECT 'AN1 antes' AS caso, COUNT(*) AS anunciantes_de_prueba FROM Publicidad.ANUNCIANTE WHERE razon_social LIKE N'Anunciante Prueba%';
EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = N'  Anunciante Prueba S.A. ', @id_pais = @ita, @id_anunciante = @id OUTPUT;
SELECT 'AN1 después' AS caso, a.id_anunciante, a.razon_social, p.nombre AS pais
FROM Publicidad.ANUNCIANTE AS a INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais WHERE a.id_anunciante = @id;
GO

/* AN2 (ERROR) Alta sin razón social y con un país que no existe.
   Esperado: error 50001 con 2 condiciones. */
BEGIN TRY
    EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = N'', @id_pais = -1;
    PRINT N'AN2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AN2';
END CATCH;
GO

/* AN3 (ERROR) Alta repetida.
   Esperado: error 50001 con 1 condición: ya existe el anunciante. */
DECLARE @ita SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ITA');
BEGIN TRY
    EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = N'Anunciante Prueba S.A.', @id_pais = @ita;
    PRINT N'AN3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AN3';
END CATCH;
GO

/* AN4 (OK) Cambio de país.
   Esperado: el anunciante pasa de Italia a España. */
DECLARE @id INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba S.A.');
DECLARE @esp SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ESP');
EXEC Publicidad.usp_ANUNCIANTE_Modificacion @id_anunciante = @id, @id_pais = @esp;
SELECT 'AN4 después' AS caso, a.razon_social, p.nombre AS pais
FROM Publicidad.ANUNCIANTE AS a INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais WHERE a.id_anunciante = @id;
GO

/* AN6 (ERROR) Modificación con la razón social de otro anunciante y un país que no existe.
   Preparación: un segundo anunciante, "Anunciante Prueba Dos", de Italia.
   Esperado: error 50001 con 2 condiciones: ya existe otro anunciante
   "Anunciante Prueba S.A." y no existe el país -1. El anunciante no cambia. */
DECLARE @ita SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ITA');
DECLARE @id INT;
EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = N'Anunciante Prueba Dos', @id_pais = @ita, @id_anunciante = @id OUTPUT;
BEGIN TRY
    EXEC Publicidad.usp_ANUNCIANTE_Modificacion @id_anunciante = @id, @razon_social = N'Anunciante Prueba S.A.', @id_pais = -1;
    PRINT N'AN6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AN6';
END CATCH;
SELECT 'AN6 después' AS caso, a.razon_social, p.nombre AS pais
FROM Publicidad.ANUNCIANTE AS a INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais WHERE a.id_anunciante = @id;
GO

/* AN7 (OK) Baja de un anunciante sin campañas.
   Esperado: 2 anunciantes de prueba antes y 1 después (se borra "Anunciante
   Prueba Dos"). */
DECLARE @id INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba Dos');
SELECT 'AN7 antes' AS caso, COUNT(*) AS anunciantes_de_prueba FROM Publicidad.ANUNCIANTE WHERE razon_social LIKE N'Anunciante Prueba%';
EXEC Publicidad.usp_ANUNCIANTE_Baja @id_anunciante = @id;
SELECT 'AN7 después' AS caso, COUNT(*) AS anunciantes_de_prueba FROM Publicidad.ANUNCIANTE WHERE razon_social LIKE N'Anunciante Prueba%';
GO

-- AN5 necesita un anunciante con campañas: se prueba al final de la sección CAMPANIA.


/* ============================================================================
   CAMPANIA
   ============================================================================ */

/* CM1 (OK) Alta de una campaña de agosto de 2026.
   Esperado: una campaña nueva del 01/08/2026 al 31/08/2026. */
DECLARE @an INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba S.A.');
DECLARE @id INT;
EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @an, @nombre = N'Campaña Prueba', @fecha_inicio = '2026-08-01',
    @fecha_fin = '2026-08-31', @id_campania = @id OUTPUT;
SELECT 'CM1 después' AS caso, id_campania, nombre, fecha_inicio, fecha_fin FROM Publicidad.CAMPANIA WHERE id_campania = @id;
GO

/* CM2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 3 condiciones: no existe el anunciante -1, el
   nombre es obligatorio y la fecha de fin es anterior a la de inicio. */
BEGIN TRY
    EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = -1, @nombre = N' ', @fecha_inicio = '2026-08-31', @fecha_fin = '2026-08-01';
    PRINT N'CM2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CM2';
END CATCH;
GO

/* CM3 (ERROR) Campaña repetida para el mismo anunciante.
   Esperado: error 50001 con 1 condición. */
DECLARE @an INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba S.A.');
BEGIN TRY
    EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @an, @nombre = N'Campaña Prueba', @fecha_inicio = '2026-09-01', @fecha_fin = '2026-09-30';
    PRINT N'CM3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CM3';
END CATCH;
GO

/* CM4 (OK) Extensión de la campaña.
   Esperado: la fecha de fin pasa del 31/08/2026 al 15/09/2026. */
DECLARE @id INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Campaña Prueba');
SELECT 'CM4 antes' AS caso, id_campania, fecha_inicio, fecha_fin FROM Publicidad.CAMPANIA WHERE id_campania = @id;
EXEC Publicidad.usp_CAMPANIA_Modificacion @id_campania = @id, @fecha_fin = '2026-09-15';
SELECT 'CM4 después' AS caso, id_campania, fecha_inicio, fecha_fin FROM Publicidad.CAMPANIA WHERE id_campania = @id;
GO

/* AN5 (ERROR) Baja de un anunciante con campañas.
   Esperado: error 50001 con 1 condición: a "Anunciante Prueba S.A." lo
   referencia 1 registro de Publicidad.CAMPANIA. */
DECLARE @id INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba S.A.');
BEGIN TRY
    EXEC Publicidad.usp_ANUNCIANTE_Baja @id_anunciante = @id;
    PRINT N'AN5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'AN5';
END CATCH;
GO

-- CM5 necesita una campaña con exhibiciones: se prueba en la sección EXHIBICION, después de EX1.


/* ============================================================================
   PIEZA_PUBLICITARIA
   ============================================================================ */

/* PZ1 (OK) Alta de dos piezas.
   Esperado: "Pieza Prueba" en español de 20 segundos y "Pieza Prueba 2" sin
   idioma ni duración. */
DECLARE @cm INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Campaña Prueba');
DECLARE @es SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es');
EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Alta @id_campania = @cm, @titulo = N'Pieza Prueba', @id_idioma = @es, @duracion_segundos = 20;
EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Alta @id_campania = @cm, @titulo = N'Pieza Prueba 2';
SELECT 'PZ1 después' AS caso, pz.id_pieza, pz.titulo, i.nombre AS idioma, pz.duracion_segundos
FROM Publicidad.PIEZA_PUBLICITARIA AS pz LEFT JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = pz.id_idioma
WHERE pz.id_campania = @cm;
GO

/* PZ2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 4 condiciones: no existe la campaña -1, el
   título es obligatorio, no existe el idioma -1 y la duración debe ser
   mayor que cero. */
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Alta @id_campania = -1, @titulo = N'', @id_idioma = -1, @duracion_segundos = 0;
    PRINT N'PZ2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PZ2';
END CATCH;
GO

/* PZ3 (ERROR) Título repetido en la misma campaña.
   Esperado: error 50001 con 1 condición. */
DECLARE @cm INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Campaña Prueba');
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Alta @id_campania = @cm, @titulo = N'Pieza Prueba';
    PRINT N'PZ3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PZ3';
END CATCH;
GO

/* PZ4 (OK) Cambio de duración.
   Esperado: "Pieza Prueba" pasa de 20 a 30 segundos. */
DECLARE @id INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba');
EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Modificacion @id_pieza = @id, @duracion_segundos = 30;
SELECT 'PZ4 después' AS caso, id_pieza, titulo, duracion_segundos FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id;
GO

/* PZ5 (ERROR) Modificación con el título de otra pieza, un idioma que no existe y duración cero.
   Esperado: error 50001 con 3 condiciones: la campaña ya tiene otra pieza
   "Pieza Prueba 2", no existe el idioma -1 y la duración debe ser mayor que
   cero. "Pieza Prueba" no cambia. */
DECLARE @id INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba');
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Modificacion @id_pieza = @id, @titulo = N'Pieza Prueba 2', @id_idioma = -1,
        @duracion_segundos = 0;
    PRINT N'PZ5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PZ5';
END CATCH;
SELECT 'PZ5 después' AS caso, id_pieza, titulo, id_idioma, duracion_segundos FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id;
GO

-- La baja de una pieza con mercados y exhibiciones se prueba en PZ6, al final
-- del script, con "Pieza Prueba".


/* ============================================================================
   PIEZA_PAIS_INTERES
   ============================================================================ */

/* PI1 (OK) Dos mercados de interés para "Pieza Prueba".
   Esperado: la pieza queda dirigida a Argentina y México. */
DECLARE @id INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba');
DECLARE @arg SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
DECLARE @mex SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'MEX');
EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Alta @id_pieza = @id, @id_pais = @arg;
EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Alta @id_pieza = @id, @id_pais = @mex;
SELECT 'PI1 después' AS caso, p.nombre AS mercado FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ppi.id_pais WHERE ppi.id_pieza = @id;
GO

/* PI2 (ERROR) Pieza y país que no existen.
   Esperado: error 50001 con 2 condiciones. */
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Alta @id_pieza = -1, @id_pais = -1;
    PRINT N'PI2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PI2';
END CATCH;
GO

/* PI3 (ERROR) Mercado repetido.
   Esperado: error 50001 con 1 condición: la pieza ya tiene a Argentina como
   mercado de interés. */
DECLARE @id INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba');
DECLARE @arg SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Alta @id_pieza = @id, @id_pais = @arg;
    PRINT N'PI3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PI3';
END CATCH;
GO

/* PI4 (OK) Baja del mercado México.
   PI5 (ERROR) Baja del mismo mercado otra vez.
   Esperado: PI4 deja solo a Argentina; PI5 falla con 1 condición. */
DECLARE @id INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba');
DECLARE @mex SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'MEX');
EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Baja @id_pieza = @id, @id_pais = @mex;
SELECT 'PI4 después' AS caso, p.nombre AS mercado FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ppi.id_pais WHERE ppi.id_pieza = @id;
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Baja @id_pieza = @id, @id_pais = @mex;
    PRINT N'PI5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PI5';
END CATCH;
GO


/* ============================================================================
   ESPACIO_PUBLICITARIO (sede de prueba creada con el ABM, sin espacios)
   ============================================================================ */

/* ES1 (OK) Alta de los cuatro espacios de una sede.
   Esperado: 0 espacios antes y 4 después (números 1 a 4). */
DECLARE @usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT;
EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Publicidad', @ciudad = 'Boston', @id_pais = @usa,
    @capacidad = 65000, @huso_horario = 'Eastern Standard Time', @id_sede = @sede OUTPUT;
SELECT 'ES1 antes' AS caso, COUNT(*) AS espacios FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede;
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @sede, @numero_espacio = 1, @tarifa_usd = 90000, @descripcion = 'Panel central';
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @sede, @numero_espacio = 2, @tarifa_usd = 80000;
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @sede, @numero_espacio = 3, @tarifa_usd = 70000;
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @sede, @numero_espacio = 4, @tarifa_usd = 60000;
SELECT 'ES1 después' AS caso, id_espacio, numero_espacio, descripcion, tarifa_usd FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede;
GO

/* ES2 (ERROR) Un quinto espacio, con número fuera de rango y tarifa negativa.
   Esperado: error 50001 con 3 condiciones: la sede ya tiene sus 4 espacios,
   el número debe estar entre 1 y 4 y la tarifa no puede ser negativa. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Publicidad');
BEGIN TRY
    EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @sede, @numero_espacio = 5, @tarifa_usd = -1;
    PRINT N'ES2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ES2';
END CATCH;
GO

/* ES3 (OK) Cambio de tarifa.
   Esperado: el espacio 1 pasa de 90000 a 95000 USD. */
DECLARE @id INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                   WHERE s.nombre_estadio = 'Estadio Prueba Publicidad' AND e.numero_espacio = 1);
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Modificacion @id_espacio = @id, @tarifa_usd = 95000;
SELECT 'ES3 después' AS caso, numero_espacio, tarifa_usd FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_espacio = @id;
GO

/* ES4 (OK) Baja del espacio 4, que no tiene exhibiciones.
   ES5 (ERROR) Alta de un espacio con un número que ya está en la sede.
   Esperado: ES4 deja 3 espacios; ES5 falla con 1 condición: la sede ya tiene
   el espacio número 3. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Publicidad');
DECLARE @id INT = (SELECT id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede AND numero_espacio = 4);
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Baja @id_espacio = @id;
SELECT 'ES4 después' AS caso, COUNT(*) AS espacios FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede;
BEGIN TRY
    EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @sede, @numero_espacio = 3, @tarifa_usd = 50000;
    PRINT N'ES5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ES5';
END CATCH;
GO

/* ES7 (ERROR) Modificación con tarifa negativa y descripción demasiado larga.
   Esperado: error 50001 con 2 condiciones: la tarifa no puede ser negativa y
   la descripción supera los 100 caracteres. El espacio 1 no cambia. */
DECLARE @id INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                   WHERE s.nombre_estadio = 'Estadio Prueba Publicidad' AND e.numero_espacio = 1);
DECLARE @larga VARCHAR(200) = REPLICATE('Descripción demasiado larga. ', 5);
BEGIN TRY
    EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Modificacion @id_espacio = @id, @tarifa_usd = -1, @descripcion = @larga;
    PRINT N'ES7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ES7';
END CATCH;
SELECT 'ES7 después' AS caso, numero_espacio, tarifa_usd, descripcion FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_espacio = @id;
GO

-- ES6 necesita un espacio con exhibiciones: se prueba en la sección EXHIBICION, después de EX1.


/* ============================================================================
   EXHIBICION (partido de prueba 220 en la sede de prueba)
   ============================================================================ */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Publicidad');
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 220, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2026-08-15 20:00';
GO

/* EX1 (OK) Exhibición con el costo de la tarifa.
   Esperado: "Pieza Prueba" en el espacio 1, con costo 95000.0000 USD (la
   tarifa del espacio en ese momento). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 220);
DECLARE @espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                        WHERE s.nombre_estadio = 'Estadio Prueba Publicidad' AND e.numero_espacio = 1);
DECLARE @pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba');
EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @id_partido, @id_espacio = @espacio, @id_pieza = @pieza;
SELECT 'EX1 después' AS caso, e.numero_espacio, pz.titulo, ex.costo, ex.codigo_moneda
FROM Publicidad.EXHIBICION AS ex
INNER JOIN Publicidad.ESPACIO_PUBLICITARIO AS e ON e.id_espacio = ex.id_espacio
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = ex.id_pieza
WHERE ex.id_partido = @id_partido;
GO

/* CM5 (ERROR) Achicar una campaña que ya tiene exhibiciones fuera del período nuevo.
   Esperado: error 50001 con 1 condición: con fin el 10/08/2026 quedaría
   afuera el partido 220 (15/08/2026), en el que ya se exhibe "Pieza Prueba".
   La campaña no cambia. */
DECLARE @id INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Campaña Prueba');
BEGIN TRY
    EXEC Publicidad.usp_CAMPANIA_Modificacion @id_campania = @id, @fecha_fin = '2026-08-10';
    PRINT N'CM5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CM5';
END CATCH;
SELECT 'CM5 después' AS caso, nombre, fecha_inicio, fecha_fin FROM Publicidad.CAMPANIA WHERE id_campania = @id;
GO

/* ES6 (ERROR) Baja de un espacio con exhibiciones.
   Esperado: error 50001 con 1 condición: al espacio 1 de "Estadio Prueba
   Publicidad" lo referencia 1 registro de Publicidad.EXHIBICION (EX1). */
DECLARE @id INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                   WHERE s.nombre_estadio = 'Estadio Prueba Publicidad' AND e.numero_espacio = 1);
BEGIN TRY
    EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Baja @id_espacio = @id;
    PRINT N'ES6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'ES6';
END CATCH;
GO

/* EX2 (ERROR) Exhibición con todos los datos mal.
   Preparación: la sede "Estadio Prueba Publicidad 2" con su espacio 1, y la
   campaña "Campaña Prueba 2022" (noviembre y diciembre de 2022) con la pieza
   "Pieza Prueba 2022".
   Esperado: error 50001 con 4 condiciones: el espacio no es de la sede del
   partido, la campaña de la pieza no está vigente en la fecha del partido,
   el costo es negativo y la moneda no tiene 3 letras. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 220);
DECLARE @usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @an INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Anunciante Prueba S.A.');
DECLARE @sede2 INT, @cm INT;
EXEC Torneo.usp_SEDE_Alta @nombre_estadio = 'Estadio Prueba Publicidad 2', @ciudad = 'Seattle', @id_pais = @usa,
    @capacidad = 68000, @huso_horario = 'Pacific Standard Time', @id_sede = @sede2 OUTPUT;
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @sede2, @numero_espacio = 1, @tarifa_usd = 50000;
EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @an, @nombre = N'Campaña Prueba 2022', @fecha_inicio = '2022-11-01',
    @fecha_fin = '2022-12-31', @id_campania = @cm OUTPUT;
EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Alta @id_campania = @cm, @titulo = N'Pieza Prueba 2022';
DECLARE @espacio INT = (SELECT id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede2 AND numero_espacio = 1);
DECLARE @pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba 2022');
BEGIN TRY
    EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @id_partido, @id_espacio = @espacio, @id_pieza = @pieza,
        @costo = -10, @codigo_moneda = 'EURO';
    PRINT N'EX2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'EX2';
END CATCH;
GO

/* EX3 (ERROR) Espacio ocupado y pieza ya exhibida en el partido.
   Esperado: error 50001 con 2 condiciones. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 220);
DECLARE @espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                        WHERE s.nombre_estadio = 'Estadio Prueba Publicidad' AND e.numero_espacio = 1);
DECLARE @pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba');
BEGIN TRY
    EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @id_partido, @id_espacio = @espacio, @id_pieza = @pieza;
    PRINT N'EX3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'EX3';
END CATCH;
GO

/* EX4 (OK) Exhibición con costo en otra moneda, y su modificación.
   Esperado: "Pieza Prueba 2" en el espacio 2 a 1500 EUR; después el costo
   pasa a 1750.50. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 220);
DECLARE @espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                        WHERE s.nombre_estadio = 'Estadio Prueba Publicidad' AND e.numero_espacio = 2);
DECLARE @pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba 2');
EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @id_partido, @id_espacio = @espacio, @id_pieza = @pieza,
    @costo = 1500, @codigo_moneda = 'eur';
SELECT 'EX4 alta' AS caso, costo, codigo_moneda FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido AND id_espacio = @espacio;
EXEC Publicidad.usp_EXHIBICION_Modificacion @id_partido = @id_partido, @id_espacio = @espacio, @costo = 1750.50;
SELECT 'EX4 después' AS caso, costo, codigo_moneda FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido AND id_espacio = @espacio;
GO

/* EX5 (ERROR) Modificación y baja de la publicidad de un partido jugado.
   Preparación: los países de prueba XBA y XBB con sus selecciones y el partido 221
   (20/08/2026, octavos, en "Estadio Prueba Publicidad") con "Pieza Prueba 2"
   en el espacio 3. El partido se juega y termina 1 - 0.
   Esperado: dos errores 50001 de 1 condición cada uno: el partido 221 está
   FINALIZADO y la exhibición ya es parte del historial para facturar. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Publicidad');
DECLARE @xba_pais SMALLINT, @xbb_pais SMALLINT;
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XBA', @huso_horario = 'UTC', @codigo_fifa = 'XBA', @id_pais = @xba_pais OUTPUT;
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XBB', @huso_horario = 'UTC', @codigo_fifa = 'XBB', @id_pais = @xbb_pais OUTPUT;
DECLARE @xba INT, @xbb INT, @id_partido INT;
EXEC Torneo.usp_SELECCION_Alta @id_pais = @xba_pais, @confederacion = 'UEFA', @id_seleccion = @xba OUTPUT;
EXEC Torneo.usp_SELECCION_Alta @id_pais = @xbb_pais, @confederacion = 'UEFA', @id_seleccion = @xbb OUTPUT;
EXEC Torneo.usp_PARTIDO_Alta @numero_partido = 221, @id_sede = @sede, @fase = 'OCTAVOS', @fecha_hora_utc = '2026-08-20 20:00',
    @id_seleccion_local = @xba, @id_seleccion_visitante = @xbb, @id_partido = @id_partido OUTPUT;
DECLARE @espacio INT = (SELECT id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede AND numero_espacio = 3);
DECLARE @pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba 2');
EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @id_partido, @id_espacio = @espacio, @id_pieza = @pieza;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'FINALIZADO', @goles_local = 1, @goles_visitante = 0;
SELECT 'EX5 partido jugado' AS caso, f.numero_partido, f.seleccion_local, f.resultado, f.seleccion_visitante, f.estado,
       (SELECT COUNT(*) FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido) AS exhibiciones
FROM Torneo.vw_Fixture AS f WHERE f.id_partido = @id_partido;
BEGIN TRY
    EXEC Publicidad.usp_EXHIBICION_Modificacion @id_partido = @id_partido, @id_espacio = @espacio, @costo = 1;
    PRINT N'EX5a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'EX5a';
END CATCH;
BEGIN TRY
    EXEC Publicidad.usp_EXHIBICION_Baja @id_partido = @id_partido, @id_espacio = @espacio;
    PRINT N'EX5b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'EX5b';
END CATCH;
GO

/* EX6 (OK) Baja de una exhibición de un partido que no se jugó.
   Esperado: 2 exhibiciones antes y 1 después. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 220);
DECLARE @espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                        WHERE s.nombre_estadio = 'Estadio Prueba Publicidad' AND e.numero_espacio = 2);
SELECT 'EX6 antes' AS caso, COUNT(*) AS exhibiciones FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido;
EXEC Publicidad.usp_EXHIBICION_Baja @id_partido = @id_partido, @id_espacio = @espacio;
SELECT 'EX6 después' AS caso, COUNT(*) AS exhibiciones FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido;
GO

/* PZ6 (ERROR) Baja de una pieza con mercados y una exhibición.
   Esperado: error 50001 con 2 condiciones. */
DECLARE @id INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba');
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Baja @id_pieza = @id;
    PRINT N'PZ6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PZ6';
END CATCH;
GO

/* PZ7 (OK) Baja de una pieza sin mercados ni exhibiciones.
   Esperado: "Pieza Prueba 2022" (la de EX2) existe antes y no después. */
DECLARE @id INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pieza Prueba 2022');
SELECT 'PZ7 antes' AS caso, COUNT(*) AS piezas FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id;
EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Baja @id_pieza = @id;
SELECT 'PZ7 después' AS caso, COUNT(*) AS piezas FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id;
GO

/* CM6 (OK) Baja de una campaña sin piezas.
   Esperado: "Campaña Prueba 2022", que se quedó sin piezas en PZ7, existe
   antes y no después.
   CM7 (ERROR) Baja de una campaña con piezas.
   Esperado: error 50001 con 1 condición: a "Campaña Prueba" la referencian 2
   registros de Publicidad.PIEZA_PUBLICITARIA. */
DECLARE @id INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Campaña Prueba 2022');
DECLARE @con_piezas INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Campaña Prueba');
SELECT 'CM6 antes' AS caso, COUNT(*) AS campanias FROM Publicidad.CAMPANIA WHERE id_campania = @id;
EXEC Publicidad.usp_CAMPANIA_Baja @id_campania = @id;
SELECT 'CM6 después' AS caso, COUNT(*) AS campanias FROM Publicidad.CAMPANIA WHERE id_campania = @id;

BEGIN TRY
    EXEC Publicidad.usp_CAMPANIA_Baja @id_campania = @con_piezas;
    PRINT N'CM7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'CM7';
END CATCH;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Publicidad.ANUNCIANTE WHERE razon_social LIKE N'Anunciante Prueba%') AS anunciantes_de_prueba,
       (SELECT COUNT(*) FROM Publicidad.CAMPANIA WHERE nombre LIKE N'Campaña Prueba%')            AS campanias_de_prueba,
       (SELECT COUNT(*) FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo LIKE N'Pieza Prueba%')    AS piezas_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba Publicidad%')   AS sedes_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('XBA', 'XBB'))                                                    AS selecciones_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XBA', 'XBB') AND nombre LIKE 'Prueba XB_') AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (220, 221))                     AS partidos_de_prueba;
GO

SET NOEXEC OFF;
GO
