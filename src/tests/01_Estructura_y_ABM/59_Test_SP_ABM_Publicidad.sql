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
 Archivo: 59_Test_SP_ABM_Publicidad.sql
 Objetivo: Probar los SP de 09_SP_ABM_Publicidad.sql (ANUNCIANTE, CAMPANIA,
           PIEZA_PUBLICITARIA, PIEZA_PAIS_INTERES, ESPACIO_PUBLICITARIO y
           EXHIBICION), con casos exitosos y su evidencia y casos que no
           cumplen las validaciones. Requiere haber ejecutado 01 a 28; no
           depende del juego de datos.
           Usa sus propios datos de prueba ("Pirelli1 S.p.A." con sus
           campañas y piezas, "Lavazza1", sin campañas, las sedes "Gillette
           Stadium1" y "Lumen Field1", los países Islandia1 y Senegal1 con sus
           selecciones y los partidos 220 y 221). Lo que no prueba este
           script se carga con INSERT directos a las tablas. Corre dentro de
           una transacción que se deshace al final, así que no deja datos y
           se puede ejecutar más de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba. Si no da
     0, quedó algo sin deshacer.
 Los países y sedes de prueba se llaman como uno real con un 1 al final: así
 no chocan con los datos reales que se importen.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd arranca con OFF; los métodos XML lo necesitan en ON
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Publicidad.usp_EXHIBICION_Alta', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es')
BEGIN
    RAISERROR(N'Faltan los SP de ABM o los datos iniciales: ejecutar los scripts 01 a 28.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Todo el test corre en una transacción que se deshace al final: no deja datos de prueba.
BEGIN TRANSACTION;
GO


/* ============================================================================
   ANUNCIANTE
   ============================================================================ */

/* AN1 (OK) Alta de un anunciante.
   Esperado: 0 antes y 1 después, de Italia. */
DECLARE @id_pais_ita SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ITA');
DECLARE @id_anunciante INT;
SELECT 'AN1 antes' AS caso, COUNT(*) AS anunciantes_de_prueba FROM Publicidad.ANUNCIANTE WHERE razon_social IN (N'Pirelli1 S.p.A.', N'Lavazza1');
EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = N'  Pirelli1 S.p.A. ', @id_pais = @id_pais_ita, @id_anunciante = @id_anunciante OUTPUT;
SELECT 'AN1 después' AS caso, a.id_anunciante, a.razon_social, p.nombre AS pais
FROM Publicidad.ANUNCIANTE AS a INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais WHERE a.id_anunciante = @id_anunciante;
GO

/* AN2 (ERROR) Alta sin razón social y con un país que no existe.
   Esperado: error 50001 con 2 condiciones. */
BEGIN TRY
    EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = N'', @id_pais = -1;
    PRINT N'AN2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AN2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AN2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AN3 (ERROR) Alta repetida.
   Esperado: error 50001 con 1 condición: ya existe el anunciante. */
DECLARE @id_pais_ita SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ITA');
BEGIN TRY
    EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = N'Pirelli1 S.p.A.', @id_pais = @id_pais_ita;
    PRINT N'AN3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AN3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AN3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* AN4 (OK) Cambio de país.
   Esperado: el anunciante pasa de Italia a España. */
DECLARE @id_anunciante INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Pirelli1 S.p.A.');
DECLARE @id_pais_esp SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ESP');
EXEC Publicidad.usp_ANUNCIANTE_Modificacion @id_anunciante = @id_anunciante, @id_pais = @id_pais_esp;
SELECT 'AN4 después' AS caso, a.razon_social, p.nombre AS pais
FROM Publicidad.ANUNCIANTE AS a INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais WHERE a.id_anunciante = @id_anunciante;
GO

/* AN6 (ERROR) Modificación con la razón social de otro anunciante y un país que no existe.
   Preparación: con un INSERT, un segundo anunciante, "Lavazza1", de Italia.
   Esperado: error 50001 con 2 condiciones: ya existe otro anunciante
   "Pirelli1 S.p.A." y no existe el país -1. El anunciante no cambia. */
DECLARE @id_pais_ita SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ITA');
DECLARE @id_anunciante INT;
INSERT INTO Publicidad.ANUNCIANTE (razon_social, id_pais) VALUES (N'Lavazza1', @id_pais_ita);
SET @id_anunciante = SCOPE_IDENTITY();
BEGIN TRY
    EXEC Publicidad.usp_ANUNCIANTE_Modificacion @id_anunciante = @id_anunciante, @razon_social = N'Pirelli1 S.p.A.', @id_pais = -1;
    PRINT N'AN6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AN6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AN6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'AN6 después' AS caso, a.razon_social, p.nombre AS pais
FROM Publicidad.ANUNCIANTE AS a INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = a.id_pais WHERE a.id_anunciante = @id_anunciante;
GO

/* AN7 (OK) Baja de un anunciante sin campañas.
   Esperado: 2 anunciantes de prueba antes y 1 después (se borra
   "Lavazza1"). */
DECLARE @id_anunciante INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Lavazza1');
SELECT 'AN7 antes' AS caso, COUNT(*) AS anunciantes_de_prueba FROM Publicidad.ANUNCIANTE WHERE razon_social IN (N'Pirelli1 S.p.A.', N'Lavazza1');
EXEC Publicidad.usp_ANUNCIANTE_Baja @id_anunciante = @id_anunciante;
SELECT 'AN7 después' AS caso, COUNT(*) AS anunciantes_de_prueba FROM Publicidad.ANUNCIANTE WHERE razon_social IN (N'Pirelli1 S.p.A.', N'Lavazza1');
GO

-- AN5 necesita un anunciante con campañas: se prueba al final de la sección CAMPANIA.


/* ============================================================================
   CAMPANIA
   ============================================================================ */

/* CM1 (OK) Alta de una campaña de agosto de 2026.
   Esperado: una campaña nueva del 01/08/2026 al 31/08/2026. */
DECLARE @id_anunciante INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Pirelli1 S.p.A.');
DECLARE @id_campania INT;
EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @id_anunciante, @nombre = N'Pirelli1 Mundial 2026', @fecha_inicio = '2026-08-01',
    @fecha_fin = '2026-08-31', @id_campania = @id_campania OUTPUT;
SELECT 'CM1 después' AS caso, id_campania, nombre, fecha_inicio, fecha_fin FROM Publicidad.CAMPANIA WHERE id_campania = @id_campania;
GO

/* CM2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 3 condiciones: no existe el anunciante -1, el
   nombre es obligatorio y la fecha de fin es anterior a la de inicio. */
BEGIN TRY
    EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = -1, @nombre = N' ', @fecha_inicio = '2026-08-31', @fecha_fin = '2026-08-01';
    PRINT N'CM2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CM2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CM2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* CM3 (ERROR) Campaña repetida para el mismo anunciante.
   Esperado: error 50001 con 1 condición. */
DECLARE @id_anunciante INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Pirelli1 S.p.A.');
BEGIN TRY
    EXEC Publicidad.usp_CAMPANIA_Alta @id_anunciante = @id_anunciante, @nombre = N'Pirelli1 Mundial 2026', @fecha_inicio = '2026-09-01', @fecha_fin = '2026-09-30';
    PRINT N'CM3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CM3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CM3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* CM4 (OK) Extensión de la campaña.
   Esperado: la fecha de fin pasa del 31/08/2026 al 15/09/2026. */
DECLARE @id_campania INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Pirelli1 Mundial 2026');
SELECT 'CM4 antes' AS caso, id_campania, fecha_inicio, fecha_fin FROM Publicidad.CAMPANIA WHERE id_campania = @id_campania;
EXEC Publicidad.usp_CAMPANIA_Modificacion @id_campania = @id_campania, @fecha_fin = '2026-09-15';
SELECT 'CM4 después' AS caso, id_campania, fecha_inicio, fecha_fin FROM Publicidad.CAMPANIA WHERE id_campania = @id_campania;
GO

/* AN5 (ERROR) Baja de un anunciante con campañas.
   Esperado: error 50001 con 1 condición: a "Pirelli1 S.p.A." lo
   referencia 1 registro de Publicidad.CAMPANIA. */
DECLARE @id_anunciante INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Pirelli1 S.p.A.');
BEGIN TRY
    EXEC Publicidad.usp_ANUNCIANTE_Baja @id_anunciante = @id_anunciante;
    PRINT N'AN5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'AN5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'AN5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

-- CM5 necesita una campaña con exhibiciones: se prueba en la sección EXHIBICION, después de EX1.


/* ============================================================================
   PIEZA_PUBLICITARIA
   ============================================================================ */

/* PZ1 (OK) Alta de dos piezas.
   Esperado: "Pirelli Cinturato" en español de 20 segundos y "Pirelli P Zero" sin
   idioma ni duración. */
DECLARE @id_campania INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Pirelli1 Mundial 2026');
DECLARE @id_idioma_es SMALLINT = (SELECT id_idioma FROM DatosGenerales.IDIOMA WHERE codigo_iso = 'es');
EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Alta @id_campania = @id_campania, @titulo = N'Pirelli Cinturato', @id_idioma = @id_idioma_es, @duracion_segundos = 20;
EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Alta @id_campania = @id_campania, @titulo = N'Pirelli P Zero';
SELECT 'PZ1 después' AS caso, pz.id_pieza, pz.titulo, i.nombre AS idioma, pz.duracion_segundos
FROM Publicidad.PIEZA_PUBLICITARIA AS pz LEFT JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = pz.id_idioma
WHERE pz.id_campania = @id_campania;
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
    IF ERROR_NUMBER() = 50001
        PRINT N'PZ2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PZ2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PZ3 (ERROR) Título repetido en la misma campaña.
   Esperado: error 50001 con 1 condición. */
DECLARE @id_campania INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Pirelli1 Mundial 2026');
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Alta @id_campania = @id_campania, @titulo = N'Pirelli Cinturato';
    PRINT N'PZ3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PZ3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PZ3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PZ4 (OK) Cambio de duración.
   Esperado: "Pirelli Cinturato" pasa de 20 a 30 segundos. */
DECLARE @id_pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli Cinturato');
EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Modificacion @id_pieza = @id_pieza, @duracion_segundos = 30;
SELECT 'PZ4 después' AS caso, id_pieza, titulo, duracion_segundos FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id_pieza;
GO

/* PZ5 (ERROR) Modificación con el título de otra pieza, un idioma que no existe y duración cero.
   Esperado: error 50001 con 3 condiciones: la campaña ya tiene otra pieza
   "Pirelli P Zero", no existe el idioma -1 y la duración debe ser mayor que
   cero. "Pirelli Cinturato" no cambia. */
DECLARE @id_pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli Cinturato');
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Modificacion @id_pieza = @id_pieza, @titulo = N'Pirelli P Zero', @id_idioma = -1,
        @duracion_segundos = 0;
    PRINT N'PZ5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PZ5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PZ5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'PZ5 después' AS caso, id_pieza, titulo, id_idioma, duracion_segundos FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id_pieza;
GO

-- La baja de una pieza con mercados y exhibiciones se prueba en PZ6, al final
-- del script, con "Pirelli Cinturato".


/* ============================================================================
   PIEZA_PAIS_INTERES
   ============================================================================ */

/* PI1 (OK) Dos mercados de interés para "Pirelli Cinturato".
   Esperado: la pieza queda dirigida a Argentina y México. */
DECLARE @id_pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli Cinturato');
DECLARE @id_pais_arg SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
DECLARE @id_pais_mex SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'MEX');
EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Alta @id_pieza = @id_pieza, @id_pais = @id_pais_arg;
EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Alta @id_pieza = @id_pieza, @id_pais = @id_pais_mex;
SELECT 'PI1 después' AS caso, p.nombre AS mercado FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ppi.id_pais WHERE ppi.id_pieza = @id_pieza;
GO

/* PI2 (ERROR) Pieza y país que no existen.
   Esperado: error 50001 con 2 condiciones. */
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Alta @id_pieza = -1, @id_pais = -1;
    PRINT N'PI2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PI2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PI2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PI3 (ERROR) Mercado repetido.
   Esperado: error 50001 con 1 condición: la pieza ya tiene a Argentina como
   mercado de interés. */
DECLARE @id_pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli Cinturato');
DECLARE @id_pais_arg SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Alta @id_pieza = @id_pieza, @id_pais = @id_pais_arg;
    PRINT N'PI3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PI3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PI3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PI4 (OK) Baja del mercado México.
   PI5 (ERROR) Baja del mismo mercado otra vez.
   Esperado: PI4 deja solo a Argentina; PI5 falla con 1 condición. */
DECLARE @id_pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli Cinturato');
DECLARE @id_pais_mex SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'MEX');
EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Baja @id_pieza = @id_pieza, @id_pais = @id_pais_mex;
SELECT 'PI4 después' AS caso, p.nombre AS mercado FROM Publicidad.PIEZA_PAIS_INTERES AS ppi
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ppi.id_pais WHERE ppi.id_pieza = @id_pieza;
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PAIS_INTERES_Baja @id_pieza = @id_pieza, @id_pais = @id_pais_mex;
    PRINT N'PI5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PI5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PI5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   ESPACIO_PUBLICITARIO (sede de prueba cargada con un INSERT, sin espacios)
   ============================================================================ */

/* ES1 (OK) Alta de los cuatro espacios de una sede.
   Esperado: 0 espacios antes y 4 después (números 1 a 4). */
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @sede INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Gillette Stadium1', 'Boston', @id_pais_usa, 65000, 'Eastern Standard Time');
SET @sede = SCOPE_IDENTITY();
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
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Gillette Stadium1');
BEGIN TRY
    EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @sede, @numero_espacio = 5, @tarifa_usd = -1;
    PRINT N'ES2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'ES2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'ES2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* ES3 (OK) Cambio de tarifa.
   Esperado: el espacio 1 pasa de 90000 a 95000 USD. */
DECLARE @id_espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                   WHERE s.nombre_estadio = 'Gillette Stadium1' AND e.numero_espacio = 1);
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Modificacion @id_espacio = @id_espacio, @tarifa_usd = 95000;
SELECT 'ES3 después' AS caso, numero_espacio, tarifa_usd FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_espacio = @id_espacio;
GO

/* ES4 (OK) Baja del espacio 4, que no tiene exhibiciones.
   ES5 (ERROR) Alta de un espacio con un número que ya está en la sede.
   Esperado: ES4 deja 3 espacios; ES5 falla con 1 condición: la sede ya tiene
   el espacio número 3. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Gillette Stadium1');
DECLARE @id_espacio INT = (SELECT id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede AND numero_espacio = 4);
EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Baja @id_espacio = @id_espacio;
SELECT 'ES4 después' AS caso, COUNT(*) AS espacios FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede;
BEGIN TRY
    EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Alta @id_sede = @sede, @numero_espacio = 3, @tarifa_usd = 50000;
    PRINT N'ES5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'ES5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'ES5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* ES7 (ERROR) Modificación con tarifa negativa y descripción demasiado larga.
   Esperado: error 50001 con 2 condiciones: la tarifa no puede ser negativa y
   la descripción supera los 100 caracteres. El espacio 1 no cambia. */
DECLARE @id_espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                   WHERE s.nombre_estadio = 'Gillette Stadium1' AND e.numero_espacio = 1);
DECLARE @larga VARCHAR(200) = REPLICATE('Descripción demasiado larga. ', 5);
BEGIN TRY
    EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Modificacion @id_espacio = @id_espacio, @tarifa_usd = -1, @descripcion = @larga;
    PRINT N'ES7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'ES7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'ES7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'ES7 después' AS caso, numero_espacio, tarifa_usd, descripcion FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_espacio = @id_espacio;
GO

-- ES6 necesita un espacio con exhibiciones: se prueba en la sección EXHIBICION, después de EX1.


/* ============================================================================
   EXHIBICION (partido de prueba 220 en la sede de prueba)
   ============================================================================ */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Gillette Stadium1');
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc)
VALUES (220, @sede, 'OCTAVOS', '2026-08-15 16:00', '2026-08-15 20:00');
GO

/* EX1 (OK) Exhibición con el costo de la tarifa.
   Esperado: "Pirelli Cinturato" en el espacio 1, con costo 95000.0000 USD (la
   tarifa del espacio en ese momento). */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 220);
DECLARE @espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                        WHERE s.nombre_estadio = 'Gillette Stadium1' AND e.numero_espacio = 1);
DECLARE @pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli Cinturato');
EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @id_partido, @id_espacio = @espacio, @id_pieza = @pieza;
SELECT 'EX1 después' AS caso, e.numero_espacio, pz.titulo, ex.costo, ex.codigo_moneda
FROM Publicidad.EXHIBICION AS ex
INNER JOIN Publicidad.ESPACIO_PUBLICITARIO AS e ON e.id_espacio = ex.id_espacio
INNER JOIN Publicidad.PIEZA_PUBLICITARIA AS pz ON pz.id_pieza = ex.id_pieza
WHERE ex.id_partido = @id_partido;
GO

/* CM5 (ERROR) Achicar una campaña que ya tiene exhibiciones fuera del período nuevo.
   Esperado: error 50001 con 1 condición: con fin el 10/08/2026 quedaría
   afuera el partido 220 (15/08/2026), en el que ya se exhibe "Pirelli Cinturato".
   La campaña no cambia. */
DECLARE @id_campania INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Pirelli1 Mundial 2026');
BEGIN TRY
    EXEC Publicidad.usp_CAMPANIA_Modificacion @id_campania = @id_campania, @fecha_fin = '2026-08-10';
    PRINT N'CM5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CM5: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CM5: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
SELECT 'CM5 después' AS caso, nombre, fecha_inicio, fecha_fin FROM Publicidad.CAMPANIA WHERE id_campania = @id_campania;
GO

/* ES6 (ERROR) Baja de un espacio con exhibiciones.
   Esperado: error 50001 con 1 condición: al espacio 1 de "Gillette
   Stadium1" lo referencia 1 registro de Publicidad.EXHIBICION (EX1). */
DECLARE @id_espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                   WHERE s.nombre_estadio = 'Gillette Stadium1' AND e.numero_espacio = 1);
BEGIN TRY
    EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Baja @id_espacio = @id_espacio;
    PRINT N'ES6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'ES6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'ES6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* EX2 (ERROR) Exhibición con todos los datos mal.
   Preparación, con INSERT: la sede "Lumen Field1" con su espacio 1, y la
   campaña "Pirelli1 Qatar 2022" (noviembre y diciembre de 2022) con la pieza
   "Pirelli Qatar".
   Esperado: error 50001 con 4 condiciones: el espacio no es de la sede del
   partido, la campaña de la pieza no está vigente en la fecha del partido,
   el costo es negativo y la moneda no tiene 3 letras. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 220);
DECLARE @id_pais_usa SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'USA');
DECLARE @id_anunciante INT = (SELECT id_anunciante FROM Publicidad.ANUNCIANTE WHERE razon_social = N'Pirelli1 S.p.A.');
DECLARE @sede2 INT, @id_campania INT;
INSERT INTO Torneo.SEDE (nombre_estadio, ciudad, id_pais, capacidad, huso_horario)
VALUES ('Lumen Field1', 'Seattle', @id_pais_usa, 68000, 'Pacific Standard Time');
SET @sede2 = SCOPE_IDENTITY();
INSERT INTO Publicidad.ESPACIO_PUBLICITARIO (id_sede, numero_espacio, tarifa_usd) VALUES (@sede2, 1, 50000);
INSERT INTO Publicidad.CAMPANIA (id_anunciante, nombre, fecha_inicio, fecha_fin)
VALUES (@id_anunciante, N'Pirelli1 Qatar 2022', '2022-11-01', '2022-12-31');
SET @id_campania = SCOPE_IDENTITY();
INSERT INTO Publicidad.PIEZA_PUBLICITARIA (id_campania, titulo) VALUES (@id_campania, N'Pirelli Qatar');
DECLARE @espacio INT = (SELECT id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede2 AND numero_espacio = 1);
DECLARE @pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli Qatar');
BEGIN TRY
    EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @id_partido, @id_espacio = @espacio, @id_pieza = @pieza,
        @costo = -10, @codigo_moneda = 'EURO';
    PRINT N'EX2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'EX2: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'EX2: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* EX3 (ERROR) Espacio ocupado y pieza ya exhibida en el partido.
   Esperado: error 50001 con 2 condiciones. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 220);
DECLARE @espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                        WHERE s.nombre_estadio = 'Gillette Stadium1' AND e.numero_espacio = 1);
DECLARE @pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli Cinturato');
BEGIN TRY
    EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @id_partido, @id_espacio = @espacio, @id_pieza = @pieza;
    PRINT N'EX3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'EX3: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'EX3: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* EX4 (OK) Exhibición con costo en otra moneda, y su modificación.
   Esperado: "Pirelli P Zero" en el espacio 2 a 1500 EUR; después el costo
   pasa a 1750.50. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 220);
DECLARE @espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                        WHERE s.nombre_estadio = 'Gillette Stadium1' AND e.numero_espacio = 2);
DECLARE @pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli P Zero');
EXEC Publicidad.usp_EXHIBICION_Alta @id_partido = @id_partido, @id_espacio = @espacio, @id_pieza = @pieza,
    @costo = 1500, @codigo_moneda = 'eur';
SELECT 'EX4 alta' AS caso, costo, codigo_moneda FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido AND id_espacio = @espacio;
EXEC Publicidad.usp_EXHIBICION_Modificacion @id_partido = @id_partido, @id_espacio = @espacio, @costo = 1750.50;
SELECT 'EX4 después' AS caso, costo, codigo_moneda FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido AND id_espacio = @espacio;
GO

/* EX5 (ERROR) Modificación y baja de la publicidad de un partido jugado.
   Preparación, con INSERT: los países Islandia1 y Senegal1 con sus
   selecciones y el partido 221 (20/08/2026, octavos, en "Gillette
   Stadium1"), ya jugado (1 - 0), con "Pirelli P Zero" en el espacio 3.
   Esperado: dos errores 50001 de 1 condición cada uno: el partido 221 está
   FINALIZADO y la exhibición ya es parte del historial para facturar. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Gillette Stadium1');
DECLARE @id_pais_isl SMALLINT, @id_pais_sen SMALLINT, @id_seleccion_isl INT, @id_seleccion_sen INT, @id_partido INT;
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Islandia1', 'Greenwich Standard Time');
SET @id_pais_isl = SCOPE_IDENTITY();
INSERT INTO DatosGenerales.PAIS (nombre, huso_horario) VALUES ('Senegal1', 'Greenwich Standard Time');
SET @id_pais_sen = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_isl, 'UEFA');
SET @id_seleccion_isl = SCOPE_IDENTITY();
INSERT INTO Torneo.SELECCION (id_pais, confederacion) VALUES (@id_pais_sen, 'CAF');
SET @id_seleccion_sen = SCOPE_IDENTITY();
INSERT INTO Torneo.PARTIDO (numero_partido, id_sede, fase, fecha_hora_local, fecha_hora_utc,
                            id_seleccion_local, id_seleccion_visitante, goles_local, goles_visitante, estado)
VALUES (221, @sede, 'OCTAVOS', '2026-08-20 16:00', '2026-08-20 20:00', @id_seleccion_isl, @id_seleccion_sen, 1, 0, 'FINALIZADO');
SET @id_partido = SCOPE_IDENTITY();
DECLARE @espacio INT = (SELECT id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @sede AND numero_espacio = 3);
DECLARE @pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli P Zero');
INSERT INTO Publicidad.EXHIBICION (id_partido, id_espacio, id_pieza, costo, codigo_moneda)
VALUES (@id_partido, @espacio, @pieza, 70000, 'USD');
SELECT 'EX5 partido jugado' AS caso, f.numero_partido, f.seleccion_local, f.resultado, f.seleccion_visitante, f.estado,
       (SELECT COUNT(*) FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido) AS exhibiciones
FROM Torneo.vw_Fixture AS f WHERE f.id_partido = @id_partido;
BEGIN TRY
    EXEC Publicidad.usp_EXHIBICION_Modificacion @id_partido = @id_partido, @id_espacio = @espacio, @costo = 1;
    PRINT N'EX5a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'EX5a: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'EX5a: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
BEGIN TRY
    EXEC Publicidad.usp_EXHIBICION_Baja @id_partido = @id_partido, @id_espacio = @espacio;
    PRINT N'EX5b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'EX5b: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'EX5b: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* EX6 (OK) Baja de una exhibición de un partido que no se jugó.
   Esperado: 2 exhibiciones antes y 1 después. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 220);
DECLARE @espacio INT = (SELECT e.id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO AS e INNER JOIN Torneo.SEDE AS s ON s.id_sede = e.id_sede
                        WHERE s.nombre_estadio = 'Gillette Stadium1' AND e.numero_espacio = 2);
SELECT 'EX6 antes' AS caso, COUNT(*) AS exhibiciones FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido;
EXEC Publicidad.usp_EXHIBICION_Baja @id_partido = @id_partido, @id_espacio = @espacio;
SELECT 'EX6 después' AS caso, COUNT(*) AS exhibiciones FROM Publicidad.EXHIBICION WHERE id_partido = @id_partido;
GO

/* PZ6 (ERROR) Baja de una pieza con mercados y una exhibición.
   Esperado: error 50001 con 2 condiciones. */
DECLARE @id_pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli Cinturato');
BEGIN TRY
    EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Baja @id_pieza = @id_pieza;
    PRINT N'PZ6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'PZ6: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'PZ6: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO

/* PZ7 (OK) Baja de una pieza sin mercados ni exhibiciones.
   Esperado: "Pirelli Qatar" (la de EX2) existe antes y no después. */
DECLARE @id_pieza INT = (SELECT id_pieza FROM Publicidad.PIEZA_PUBLICITARIA WHERE titulo = N'Pirelli Qatar');
SELECT 'PZ7 antes' AS caso, COUNT(*) AS piezas FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id_pieza;
EXEC Publicidad.usp_PIEZA_PUBLICITARIA_Baja @id_pieza = @id_pieza;
SELECT 'PZ7 después' AS caso, COUNT(*) AS piezas FROM Publicidad.PIEZA_PUBLICITARIA WHERE id_pieza = @id_pieza;
GO

/* CM6 (OK) Baja de una campaña sin piezas.
   Esperado: "Pirelli1 Qatar 2022", que se quedó sin piezas en PZ7, existe
   antes y no después.
   CM7 (ERROR) Baja de una campaña con piezas.
   Esperado: error 50001 con 1 condición: a "Pirelli1 Mundial 2026" la referencian 2
   registros de Publicidad.PIEZA_PUBLICITARIA. */
DECLARE @id_campania INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Pirelli1 Qatar 2022');
DECLARE @con_piezas INT = (SELECT id_campania FROM Publicidad.CAMPANIA WHERE nombre = N'Pirelli1 Mundial 2026');
SELECT 'CM6 antes' AS caso, COUNT(*) AS campanias FROM Publicidad.CAMPANIA WHERE id_campania = @id_campania;
EXEC Publicidad.usp_CAMPANIA_Baja @id_campania = @id_campania;
SELECT 'CM6 después' AS caso, COUNT(*) AS campanias FROM Publicidad.CAMPANIA WHERE id_campania = @id_campania;

BEGIN TRY
    EXEC Publicidad.usp_CAMPANIA_Baja @id_campania = @con_piezas;
    PRINT N'CM7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        PRINT N'CM7: OK, falló la validación como se esperaba.';
    ELSE
        PRINT CONCAT(N'CM7: FALLÓ, error inesperado ', ERROR_NUMBER(), N'.');
    PRINT ERROR_MESSAGE();
END CATCH;
GO


/* ============================================================================
   VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
ROLLBACK TRANSACTION;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Publicidad.ANUNCIANTE WHERE razon_social IN (N'Pirelli1 S.p.A.', N'Lavazza1')) AS anunciantes_de_prueba,
       (SELECT COUNT(*) FROM Publicidad.CAMPANIA WHERE nombre LIKE N'Pirelli1%')                    AS campanias_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio IN ('Gillette Stadium1', 'Lumen Field1')) AS sedes_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE nombre IN ('Islandia1', 'Senegal1'))         AS paises_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (220, 221))                     AS partidos_de_prueba;
GO

SET NOEXEC OFF;
GO
