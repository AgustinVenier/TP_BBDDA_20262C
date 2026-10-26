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
 Archivo: 55_Test_SP_ABM_Torneo.sql
 Objetivo: Probar los SP de 05_SP_ABM_Torneo.sql (SEDE, SELECCION,
           LISTA_CONVOCADOS, JUGADOR, PERSONA_CUERPO_TECNICO y PARTIDO), con
           casos exitosos y su evidencia y casos que no cumplen las
           validaciones. Requiere haber ejecutado 00 a 20 y no depende del
           juego de datos.
           Crea sus propios datos de prueba (las sedes "Estadio Prueba ABM" y
           "Estadio Prueba ABM 2", los países de prueba XTA a XTE con sus
           selecciones en los grupos K y L, una lista completa para XTB y los
           partidos 201 a 209) y los borra al empezar y al
           terminar con los SP de baja, así que se puede ejecutar más de una vez.
           Las bajas rechazadas por historial usan el partido 204 (Prueba XTA -
           Prueba XTC), con una formación y una tarjeta al director técnico, que se
           arma y se borra en la sección HISTORIAL.
           SE1 y SE3 prueban el cupo de un grupo, así que el grupo L tiene que
           quedar completo con las 4 selecciones de prueba. Si el grupo ya tiene
           selecciones (por ejemplo, con las 48 del Mundial cargadas), el test
           ajusta SELECCIONES_POR_GRUPO mientras dura y después lo restaura
           (solo queda cambiada su fecha_modificacion).
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra los datos antes y después (columna "caso").
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba y
     SELECCIONES_POR_GRUPO con su valor original.
 Los países de prueba se llaman "Prueba <código>" y usan códigos FIFA que
 empiezan con X, que no tiene ningún miembro de la FIFA: así el test no choca
 con las selecciones reales que se importen.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Torneo.usp_PARTIDO_Alta', N'P') IS NULL
   OR OBJECT_ID(N'DesarrolloPartido.usp_AMONESTACION_Alta', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS')
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

-- Borra con los SP de baja los datos de prueba de este script.
IF OBJECT_ID(N'tempdb..#usp_LimpiarPruebas', N'P') IS NOT NULL
    DROP PROCEDURE #usp_LimpiarPruebas;
GO
CREATE PROCEDURE #usp_LimpiarPruebas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @id2 INT, @cupo TINYINT;

    -- Tarjetas, alineaciones y formaciones de los partidos de prueba (partido 204).
    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.AMONESTACION AS a INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
                  WHERE p.numero_partido BETWEEN 201 AND 209)
    BEGIN
        SELECT TOP (1) @id = a.id_amonestacion FROM DesarrolloPartido.AMONESTACION AS a
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = a.id_partido
        WHERE p.numero_partido BETWEEN 201 AND 209
        ORDER BY a.es_doble_amarilla DESC, a.id_amonestacion DESC;
        EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id;
    END;

    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.ALINEACION AS a INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
                  INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido WHERE p.numero_partido BETWEEN 201 AND 209)
    BEGIN
        SELECT TOP (1) @id = a.id_formacion, @id2 = a.id_jugador FROM DesarrolloPartido.ALINEACION AS a
        INNER JOIN DesarrolloPartido.FORMACION AS f ON f.id_formacion = a.id_formacion
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido WHERE p.numero_partido BETWEEN 201 AND 209;
        EXEC DesarrolloPartido.usp_ALINEACION_Baja @id_formacion = @id, @id_jugador = @id2;
    END;

    WHILE EXISTS (SELECT 1 FROM DesarrolloPartido.FORMACION AS f INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido
                  WHERE p.numero_partido BETWEEN 201 AND 209)
    BEGIN
        SELECT TOP (1) @id = f.id_formacion FROM DesarrolloPartido.FORMACION AS f
        INNER JOIN Torneo.PARTIDO AS p ON p.id_partido = f.id_partido WHERE p.numero_partido BETWEEN 201 AND 209;
        EXEC DesarrolloPartido.usp_FORMACION_Baja @id_formacion = @id;
    END;

    WHILE EXISTS (SELECT 1 FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 201 AND 209)
    BEGIN
        SELECT TOP (1) @id = id_partido FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 201 AND 209;
        IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id) = 'FINALIZADO'
            EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'EN_JUEGO';
        IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id) IN ('EN_JUEGO', 'SUSPENDIDO')
            EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'PROGRAMADO';
        EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;
    END;

    -- Selecciones de prueba con su lista, su cuerpo técnico y sus jugadores.
    DECLARE @pruebas TABLE (id_seleccion INT PRIMARY KEY);
    INSERT INTO @pruebas (id_seleccion)
    SELECT s.id_seleccion
    FROM Torneo.SELECCION AS s
    INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
    WHERE p.codigo_fifa IN ('XTA', 'XTB', 'XTC', 'XTD', 'XTE');

    WHILE EXISTS (SELECT 1 FROM Torneo.JUGADOR AS j
                  INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                  WHERE l.id_seleccion IN (SELECT id_seleccion FROM @pruebas))
    BEGIN
        SELECT TOP (1) @id = j.id_jugador FROM Torneo.JUGADOR AS j
        INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
        WHERE l.id_seleccion IN (SELECT id_seleccion FROM @pruebas);
        EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id, @eliminar_registro = 1;
    END;

    WHILE EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion IN (SELECT id_seleccion FROM @pruebas))
    BEGIN
        SELECT TOP (1) @id = id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO
        WHERE id_seleccion IN (SELECT id_seleccion FROM @pruebas);
        EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Baja @id_persona_ct = @id;
    END;

    WHILE EXISTS (SELECT 1 FROM Torneo.LISTA_CONVOCADOS WHERE id_seleccion IN (SELECT id_seleccion FROM @pruebas))
    BEGIN
        SELECT TOP (1) @id = id_lista FROM Torneo.LISTA_CONVOCADOS
        WHERE id_seleccion IN (SELECT id_seleccion FROM @pruebas);
        EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id;
    END;

    WHILE EXISTS (SELECT 1 FROM @pruebas)
    BEGIN
        SELECT TOP (1) @id = id_seleccion FROM @pruebas;
        EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id;
        DELETE FROM @pruebas WHERE id_seleccion = @id;
    END;

    WHILE EXISTS (SELECT 1 FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba ABM%')
    BEGIN
        SELECT TOP (1) @id = id_sede FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba ABM%';
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;
    END;

    -- Países de prueba (sin selecciones ni jugadores a esta altura).
    WHILE EXISTS (SELECT 1 FROM DatosGenerales.PAIS
                  WHERE codigo_fifa IN ('XTA', 'XTB', 'XTC', 'XTD', 'XTE') AND nombre LIKE 'Prueba XT_')
    BEGIN
        SELECT TOP (1) @id = id_pais FROM DatosGenerales.PAIS
        WHERE codigo_fifa IN ('XTA', 'XTB', 'XTC', 'XTD', 'XTE') AND nombre LIKE 'Prueba XT_';
        EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    END;

    -- Cupo de los grupos: si la preparación de SE1 lo ajustó, vuelve a su valor
    -- original, que quedó guardado en el parámetro de prueba PRUEBA_55_CUPO_GRUPO.
    IF EXISTS (SELECT 1 FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'PRUEBA_55_CUPO_GRUPO')
    BEGIN
        SET @cupo = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'PRUEBA_55_CUPO_GRUPO');
        EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'SELECCIONES_POR_GRUPO', @valor = @cupo;
        EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Baja @codigo = 'PRUEBA_55_CUPO_GRUPO';
    END;
END;
GO

EXEC #usp_LimpiarPruebas;
GO

-- Preparación: los países de prueba XTA a XTE ("Prueba XTA" a "Prueba XTE"),
-- todavía sin selección.
DECLARE @i INT = 0, @codigo CHAR(3), @nombre VARCHAR(60);
WHILE @i < 5
BEGIN
    SET @codigo = CONCAT('XT', CHAR(65 + @i));
    SET @nombre = CONCAT('Prueba ', @codigo);
    EXEC DatosGenerales.usp_PAIS_Alta @nombre = @nombre, @huso_horario = 'UTC', @codigo_fifa = @codigo;
    SET @i += 1;
END;
GO


/* ============================================================================
   SEDE
   ============================================================================ */

/* S1 (OK) Alta de una sede.
   Esperado: 0 sedes de prueba antes y 1 después, con el huso guardado como
   "Argentina Standard Time". La sede se crea sin espacios publicitarios (los
   4 espacios los agrega Torneo.usp_RegistrarSede, que se prueba en 60). */
DECLARE @id INT;

SELECT 'S1 antes' AS caso, COUNT(*) AS sedes_de_prueba FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba ABM%';

DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
EXEC Torneo.usp_SEDE_Alta
    @nombre_estadio = 'Estadio Prueba ABM', @ciudad = 'Buenos Aires', @id_pais = @id_pais,
    @capacidad = 30000, @huso_horario = 'argentina standard time',
    @latitud = -34.545500, @longitud = -58.449700, @id_sede = @id OUTPUT;

SELECT 'S1 después' AS caso, id_sede, nombre_estadio, ciudad, capacidad, huso_horario, latitud, longitud
FROM Torneo.SEDE
WHERE id_sede = @id;
GO

/* S2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 7 condiciones: nombre y ciudad obligatorios, no
   existe el país -1, capacidad no positiva, huso inexistente, latitud sin
   longitud y latitud fuera de rango. */
BEGIN TRY
    EXEC Torneo.usp_SEDE_Alta
        @nombre_estadio = '', @ciudad = '  ', @id_pais = -1, @capacidad = 0,
        @huso_horario = 'Hora de Marte', @latitud = 95;
    PRINT N'S2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'S2';
END CATCH;
GO

/* S3 (ERROR) Alta de una sede que ya existe.
   Esperado: error 50001 con 1 condición: ya existe la sede "Estadio Prueba ABM". */
DECLARE @id_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
BEGIN TRY
    EXEC Torneo.usp_SEDE_Alta
        @nombre_estadio = 'Estadio Prueba ABM', @ciudad = 'Rosario', @id_pais = @id_pais,
        @capacidad = 40000, @huso_horario = 'Argentina Standard Time';
    PRINT N'S3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'S3';
END CATCH;
GO

/* S4 (OK) Modificación parcial: capacidad y ciudad.
   Esperado: la capacidad pasa a 35000 y la ciudad a "Ciudad Autónoma de
   Buenos Aires"; el resto queda igual. */
DECLARE @id INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba ABM');

SELECT 'S4 antes' AS caso, id_sede, nombre_estadio, ciudad, capacidad, huso_horario FROM Torneo.SEDE WHERE id_sede = @id;

EXEC Torneo.usp_SEDE_Modificacion @id_sede = @id, @capacidad = 35000, @ciudad = 'Ciudad Autónoma de Buenos Aires';

SELECT 'S4 después' AS caso, id_sede, nombre_estadio, ciudad, capacidad, huso_horario FROM Torneo.SEDE WHERE id_sede = @id;
GO

-- S5 necesita un partido jugado en la sede: se prueba en la sección PARTIDO, después de PA8.


/* ============================================================================
   SELECCION
   ============================================================================ */

/* Preparación: el cupo del grupo L. SE1 da de alta 4 selecciones de prueba en
   el grupo L y SE3 comprueba que no entra una quinta, así que el cupo tiene que
   ser el de las selecciones que el grupo ya tiene más 4 (SE4 y PA4 usan además
   un lugar del grupo K). Con los datos iniciales el grupo está vacío y el cupo
   es 4, así que no cambia nada. Si el grupo ya tiene selecciones (por ejemplo,
   con las 48 del Mundial cargadas), se ajusta SELECCIONES_POR_GRUPO y su valor
   original queda en el parámetro de prueba PRUEBA_55_CUPO_GRUPO, que
   #usp_LimpiarPruebas usa para restaurarlo.
   Esperado: cupo 4 y 0 selecciones en el grupo L con los datos iniciales; con
   las 48 selecciones del Mundial, cupo 8 y 4 selecciones. */
DECLARE @cupo TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'SELECCIONES_POR_GRUPO');
DECLARE @en_el_grupo TINYINT = (SELECT COUNT(*) FROM Torneo.SELECCION WHERE grupo = 'L');

IF @en_el_grupo + 4 <> @cupo
BEGIN
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Alta @codigo = 'PRUEBA_55_CUPO_GRUPO',
        @descripcion = 'SELECCIONES_POR_GRUPO antes de ejecutar 55_Test_SP_ABM_Torneo.sql', @valor = @cupo;
    SET @cupo = @en_el_grupo + 4;
    EXEC DatosGenerales.usp_PARAMETRO_REGLAMENTO_Modificacion @codigo = 'SELECCIONES_POR_GRUPO', @valor = @cupo;
END;

SELECT 'Cupo del grupo L' AS caso, @cupo AS selecciones_por_grupo, @en_el_grupo AS selecciones_en_el_grupo_L;
GO

/* SE1 (OK) Alta de cuatro selecciones en el grupo L.
   Esperado: 0 selecciones de prueba antes y 4 después (Prueba XTA, Prueba XTB, Prueba XTC
   y Prueba XTD), con la confederación y el grupo en mayúsculas. */
DECLARE @xta SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XTA');
DECLARE @xtb SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XTB');
DECLARE @xtc SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XTC');
DECLARE @xtd SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XTD');

SELECT 'SE1 antes' AS caso, COUNT(*) AS selecciones_de_prueba
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.codigo_fifa IN ('XTA', 'XTB', 'XTC', 'XTD', 'XTE');

EXEC Torneo.usp_SELECCION_Alta @id_pais = @xta, @confederacion = 'conmebol', @grupo = 'l';
EXEC Torneo.usp_SELECCION_Alta @id_pais = @xtb, @confederacion = 'CONMEBOL', @grupo = 'L';
EXEC Torneo.usp_SELECCION_Alta @id_pais = @xtc, @confederacion = 'CONMEBOL', @grupo = 'L';
EXEC Torneo.usp_SELECCION_Alta @id_pais = @xtd, @confederacion = 'CONMEBOL', @grupo = 'L';

SELECT 'SE1 después' AS caso, s.id_seleccion, p.nombre AS seleccion, s.confederacion, s.grupo
FROM Torneo.SELECCION AS s
INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
WHERE p.codigo_fifa IN ('XTA', 'XTB', 'XTC', 'XTD', 'XTE');
GO

/* SE2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 3 condiciones: Prueba XTA ya tiene selección, la
   confederación FIFA no es válida y el grupo Z no existe. */
DECLARE @xta SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XTA');
BEGIN TRY
    EXEC Torneo.usp_SELECCION_Alta @id_pais = @xta, @confederacion = 'FIFA', @grupo = 'Z';
    PRINT N'SE2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'SE2';
END CATCH;
GO

/* SE3 (ERROR) Una quinta selección de prueba en el grupo L.
   Esperado: error 50001 con 1 condición: el grupo L ya completó su cupo
   (SELECCIONES_POR_GRUPO: 4 con los datos iniciales, o el que fijó la
   preparación si el grupo ya tenía selecciones). */
DECLARE @xte SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XTE');
BEGIN TRY
    EXEC Torneo.usp_SELECCION_Alta @id_pais = @xte, @confederacion = 'CONMEBOL', @grupo = 'L';
    PRINT N'SE3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'SE3';
END CATCH;
GO

/* SE4 (OK) Cambio de grupo de una selección sin partidos.
   Esperado: Prueba XTD pasa del grupo L al K. */
DECLARE @id INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTD');

SELECT 'SE4 antes' AS caso, id_seleccion, confederacion, grupo FROM Torneo.SELECCION WHERE id_seleccion = @id;
EXEC Torneo.usp_SELECCION_Modificacion @id_seleccion = @id, @grupo = 'K';
SELECT 'SE4 después' AS caso, id_seleccion, confederacion, grupo FROM Torneo.SELECCION WHERE id_seleccion = @id;
GO

-- SE5 y SE6 necesitan una selección con partidos: se prueban en la sección HISTORIAL.

/* SE7 (OK) Baja de una selección sin referencias.
   Esperado: Prueba XTD existe antes y no después. */
DECLARE @id INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTD');
SELECT 'SE7 antes' AS caso, COUNT(*) AS seleccion_xtd FROM Torneo.SELECCION WHERE id_seleccion = @id;
EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id;
SELECT 'SE7 después' AS caso, COUNT(*) AS seleccion_xtd FROM Torneo.SELECCION WHERE id_seleccion = @id;
GO


/* ============================================================================
   LISTA_CONVOCADOS
   ============================================================================ */

/* L1 (OK) Alta de la lista de Prueba XTA.
   Esperado: una lista nueva con fecha de presentación 01/06/2026. */
DECLARE @id_sel INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                       INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
DECLARE @id INT;
EXEC Torneo.usp_LISTA_CONVOCADOS_Alta @id_seleccion = @id_sel, @fecha_presentacion = '2026-06-01', @id_lista = @id OUTPUT;
SELECT 'L1 después' AS caso, id_lista, id_seleccion, fecha_presentacion FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id;
GO

/* L2 (ERROR) Alta para una selección que no existe y con fecha futura.
   Esperado: error 50001 con 2 condiciones: no existe la selección -1 y la
   fecha no puede ser futura. */
DECLARE @futura DATE = DATEADD(DAY, 10, GETDATE());
BEGIN TRY
    EXEC Torneo.usp_LISTA_CONVOCADOS_Alta @id_seleccion = -1, @fecha_presentacion = @futura;
    PRINT N'L2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'L2';
END CATCH;
GO

/* L3 (ERROR) Segunda lista para la misma selección.
   Esperado: error 50001 con 1 condición: la selección ya tiene su lista. */
DECLARE @id_sel INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                       INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
BEGIN TRY
    EXEC Torneo.usp_LISTA_CONVOCADOS_Alta @id_seleccion = @id_sel, @fecha_presentacion = '2026-06-02';
    PRINT N'L3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'L3';
END CATCH;
GO

/* L4 (OK) Modificación de la fecha de presentación.
   Esperado: la fecha pasa de 01/06/2026 a 30/05/2026. */
DECLARE @id INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
SELECT 'L4 antes' AS caso, id_lista, fecha_presentacion FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id;
EXEC Torneo.usp_LISTA_CONVOCADOS_Modificacion @id_lista = @id, @fecha_presentacion = '2026-05-30';
SELECT 'L4 después' AS caso, id_lista, fecha_presentacion FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id;
GO


/* ============================================================================
   JUGADOR (lista de Prueba XTA)
   ============================================================================ */

/* J1 (OK) Alta de dos jugadores.
   Esperado: 0 jugadores antes y 2 después. El primero, dado de alta el
   01/06/2026 con posición en mayúsculas; el segundo, sin fecha de alta, queda
   con la fecha de hoy. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                         INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                         INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
DECLARE @xta SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XTA');

SELECT 'J1 antes' AS caso, COUNT(*) AS jugadores FROM Torneo.JUGADOR WHERE id_lista = @id_lista;

EXEC Torneo.usp_JUGADOR_Alta
    @id_lista = @id_lista, @nombre = N'Carlos', @apellido = N'Prueba Uno', @posicion_habitual = 'delantero',
    @dorsal = 9, @fecha_nacimiento = '1998-02-10', @club_origen = N'Club Bolívar',
    @id_pais_nacimiento = @xta, @fecha_alta = '2026-06-01', @motivo_alta = 'Lista inicial';
EXEC Torneo.usp_JUGADOR_Alta
    @id_lista = @id_lista, @nombre = N'Marcelo', @apellido = N'Prueba Dos', @posicion_habitual = 'ARQUERO',
    @dorsal = 1, @club_origen = N'The Strongest';

SELECT 'J1 después' AS caso, id_jugador, dorsal, apellido, nombre, posicion_habitual, club_origen,
       fecha_alta, motivo_alta, fecha_baja
FROM Torneo.JUGADOR
WHERE id_lista = @id_lista;
GO

/* J2 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 6 condiciones: nombre obligatorio, apellido de
   más de 60 caracteres, posición no válida, dorsal fuera de rango, fecha de
   nacimiento futura y alta anterior a la presentación de la lista. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                         INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                         INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
DECLARE @futura DATE = DATEADD(YEAR, 1, GETDATE());
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Alta
        @id_lista = @id_lista, @nombre = N' ', @apellido = N'Apellido larguísimo que supera holgadamente los sesenta caracteres',
        @posicion_habitual = 'LIBERO', @dorsal = 0, @fecha_nacimiento = @futura, @fecha_alta = '2026-01-01';
    PRINT N'J2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'J2';
END CATCH;
GO

/* J3 (ERROR) Alta con dorsal ocupado y nombre repetido.
   Esperado: error 50001 con 2 condiciones: Carlos Prueba Uno ya figura en la
   lista y el dorsal 1 ya lo usa Marcelo Prueba Dos. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                         INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                         INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Alta
        @id_lista = @id_lista, @nombre = N'Carlos', @apellido = N'Prueba Uno',
        @posicion_habitual = 'DEFENSOR', @dorsal = 1;
    PRINT N'J3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'J3';
END CATCH;
GO

/* J4 (ERROR) Alta en una lista completa.
   Preparación: la lista de Prueba XTB con MAX_CONVOCADOS (26) jugadores de prueba
   ("Prueba Lleno 1" a "Prueba Lleno 26").
   Esperado: 26 jugadores activos en la lista de Prueba XTB y error 50001 con 1
   condición: la lista ya tiene 26 convocados activos, el máximo permitido
   (MAX_CONVOCADOS). */
DECLARE @id_sel INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                       INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTB');
DECLARE @maximo TINYINT = (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS');
DECLARE @id_lista INT, @n TINYINT = 1, @apellido NVARCHAR(60);

EXEC Torneo.usp_LISTA_CONVOCADOS_Alta @id_seleccion = @id_sel, @fecha_presentacion = '2026-06-01', @id_lista = @id_lista OUTPUT;
WHILE @n <= @maximo
BEGIN
    SET @apellido = CONCAT(N'Prueba Lleno ', @n);
    EXEC Torneo.usp_JUGADOR_Alta
        @id_lista = @id_lista, @nombre = N'Jugador', @apellido = @apellido,
        @posicion_habitual = 'DEFENSOR', @dorsal = @n, @fecha_alta = '2026-06-01';
    SET @n += 1;
END;

SELECT 'J4 lista de Prueba XTB' AS caso, COUNT(*) AS jugadores_activos
FROM Torneo.JUGADOR WHERE id_lista = @id_lista AND fecha_baja IS NULL;

BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Alta
        @id_lista = @id_lista, @nombre = N'Jugador', @apellido = N'Número 27',
        @posicion_habitual = 'DELANTERO', @dorsal = 27, @fecha_alta = '2026-06-05';
    PRINT N'J4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'J4';
END CATCH;
GO

/* J5 (OK) Modificación de dorsal y club.
   Esperado: Carlos Prueba Uno pasa del dorsal 9 al 10 y al club Wilstermann. */
DECLARE @id INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba Uno');
SELECT 'J5 antes' AS caso, id_jugador, dorsal, club_origen FROM Torneo.JUGADOR WHERE id_jugador = @id;
EXEC Torneo.usp_JUGADOR_Modificacion @id_jugador = @id, @dorsal = 10, @club_origen = N'Wilstermann';
SELECT 'J5 después' AS caso, id_jugador, dorsal, club_origen FROM Torneo.JUGADOR WHERE id_jugador = @id;
GO

/* J6 (ERROR) Modificación con dorsal ocupado y posición no válida.
   Esperado: error 50001 con 2 condiciones: la posición no es válida y el
   dorsal 1 ya lo usa Marcelo Prueba Dos. */
DECLARE @id INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba Uno');
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Modificacion @id_jugador = @id, @dorsal = 1, @posicion_habitual = 'VOLANTE';
    PRINT N'J6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'J6';
END CATCH;
GO

/* L5 (ERROR) Presentación de la lista posterior al alta de un jugador.
   Esperado: error 50001 con 1 condición: hay jugadores dados de alta antes
   de esa fecha (01/06/2026). */
DECLARE @id INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
BEGIN TRY
    EXEC Torneo.usp_LISTA_CONVOCADOS_Modificacion @id_lista = @id, @fecha_presentacion = '2026-06-02';
    PRINT N'L5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'L5';
END CATCH;
GO

/* L6 (ERROR) Baja de una lista con jugadores.
   Esperado: error 50001 con 1 condición: a la lista de Prueba XTA la
   referencian 2 registros de Torneo.JUGADOR (Prueba Uno y Prueba Dos). La
   lista sigue existiendo. */
DECLARE @id INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
BEGIN TRY
    EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id;
    PRINT N'L6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'L6';
END CATCH;
SELECT 'L6 después' AS caso, COUNT(*) AS listas FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id;
GO

/* J7 (OK) Baja lógica (baja de último momento).
   Esperado: Carlos Prueba Uno sigue en la tabla, con fecha de baja
   05/06/2026 y el motivo informado. */
DECLARE @id INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba Uno');
SELECT 'J7 antes' AS caso, id_jugador, fecha_baja, motivo_baja FROM Torneo.JUGADOR WHERE id_jugador = @id;
EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id, @motivo_baja = 'Desgarro en el isquiotibial', @fecha_baja = '2026-06-05';
SELECT 'J7 después' AS caso, id_jugador, fecha_baja, motivo_baja FROM Torneo.JUGADOR WHERE id_jugador = @id;
GO

/* J8 (ERROR) Segunda baja del mismo jugador y sin motivo.
   Esperado: error 50001 con 2 condiciones: el jugador ya fue dado de baja el
   05/06/2026 y el motivo es obligatorio. */
DECLARE @id INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba Uno');
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id;
    PRINT N'J8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'J8';
END CATCH;
GO

-- J9 necesita un jugador con historial: se prueba en la sección HISTORIAL.


/* ============================================================================
   PERSONA_CUERPO_TECNICO (Prueba XTA)
   ============================================================================ */

/* C1 (OK) Alta del director técnico y de un ayudante.
   Esperado: 0 antes y 2 personas después, con el rol en mayúsculas. */
DECLARE @id_sel INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                       INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
SELECT 'C1 antes' AS caso, COUNT(*) AS cuerpo_tecnico FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_sel;
EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_sel, @nombre = N'Óscar', @apellido = N'Prueba DT',
    @rol = 'director_tecnico', @fecha_nacimiento = '1970-05-20';
EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_sel, @nombre = N'Julio', @apellido = N'Prueba Ayudante',
    @rol = 'AYUDANTE_CAMPO';
SELECT 'C1 después' AS caso, id_persona_ct, apellido, nombre, rol, fecha_nacimiento
FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_sel;
GO

/* C2 (ERROR) Un segundo director técnico.
   Esperado: error 50001 con 1 condición: la selección ya tiene director técnico. */
DECLARE @id_sel INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                       INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
BEGIN TRY
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_sel, @nombre = N'Otro', @apellido = N'Técnico',
        @rol = 'DIRECTOR_TECNICO';
    PRINT N'C2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'C2';
END CATCH;
GO

/* C3 (ERROR) Alta con rol no válido y sin nombre, para una selección que no existe.
   Esperado: error 50001 con 3 condiciones: no existe la selección -1, el
   nombre es obligatorio y el rol UTILERO no es válido. */
BEGIN TRY
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = -1, @nombre = N'', @apellido = N'Sin Nombre',
        @rol = 'UTILERO';
    PRINT N'C3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'C3';
END CATCH;
GO

/* C4 (OK) Modificación del rol del ayudante.
   Esperado: el ayudante pasa a PREPARADOR_FISICO. */
DECLARE @id INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE apellido = N'Prueba Ayudante');
SELECT 'C4 antes' AS caso, id_persona_ct, apellido, rol FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_persona_ct = @id;
EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Modificacion @id_persona_ct = @id, @rol = 'PREPARADOR_FISICO';
SELECT 'C4 después' AS caso, id_persona_ct, apellido, rol FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_persona_ct = @id;
GO

/* C5 (ERROR) El ayudante como segundo director técnico.
   Esperado: error 50001 con 1 condición: la selección ya tiene director técnico. */
DECLARE @id INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE apellido = N'Prueba Ayudante');
BEGIN TRY
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Modificacion @id_persona_ct = @id, @rol = 'DIRECTOR_TECNICO';
    PRINT N'C5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'C5';
END CATCH;
GO

-- C6 necesita una tarjeta al director técnico: se prueba en la sección HISTORIAL.

/* C7 (OK) Baja del ayudante de prueba.
   Esperado: 2 personas antes y 1 después. */
DECLARE @id INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE apellido = N'Prueba Ayudante');
DECLARE @id_sel INT = (SELECT id_seleccion FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_persona_ct = @id);
SELECT 'C7 antes' AS caso, COUNT(*) AS cuerpo_tecnico FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_sel;
EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Baja @id_persona_ct = @id;
SELECT 'C7 después' AS caso, COUNT(*) AS cuerpo_tecnico FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id_sel;
GO


/* ============================================================================
   HISTORIAL (partido 204, Prueba XTA - Prueba XTC)
   Las bajas y los cambios que se rechazan porque hay historial necesitan un
   partido con formación y tarjetas. Se arma el partido 204 con los SP, se
   prueban esos casos y se borra todo antes de la sección PARTIDO.
   ============================================================================ */

/* Preparación (OK): partido 204 del 03/06/2026, de la fase de grupos, con la
   formación de Prueba XTA, el jugador "Rodrigo Prueba Tres" (dorsal 8) de
   titular y, con el partido EN_JUEGO, una amarilla al director técnico de
   Prueba XTA.
   Esperado: el partido EN_JUEGO con 1 formación, 1 jugador alineado y 1
   tarjeta. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba ABM');
DECLARE @xta INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
DECLARE @xtc INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTC');
DECLARE @id_lista INT = (SELECT id_lista FROM Torneo.LISTA_CONVOCADOS WHERE id_seleccion = @xta);
DECLARE @dt INT = (SELECT id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @xta AND rol = 'DIRECTOR_TECNICO');
DECLARE @id_partido INT, @id_formacion INT, @id_jugador INT;

EXEC Torneo.usp_JUGADOR_Alta
    @id_lista = @id_lista, @nombre = N'Rodrigo', @apellido = N'Prueba Tres', @posicion_habitual = 'MEDIOCAMPISTA',
    @dorsal = 8, @fecha_alta = '2026-06-01', @id_jugador = @id_jugador OUTPUT;
EXEC Torneo.usp_PARTIDO_Alta
    @numero_partido = 204, @id_sede = @sede, @fase = 'GRUPOS', @fecha_hora_local = '2026-06-03 16:00',
    @id_seleccion_local = @xta, @id_seleccion_visitante = @xtc, @id_partido = @id_partido OUTPUT;
EXEC DesarrolloPartido.usp_FORMACION_Alta
    @id_partido = @id_partido, @id_seleccion = @xta, @esquema_tactico = '4-4-2', @id_formacion = @id_formacion OUTPUT;
EXEC DesarrolloPartido.usp_ALINEACION_Alta
    @id_formacion = @id_formacion, @id_jugador = @id_jugador, @es_titular = 1, @posicion_en_cancha = 'MEDIOCAMPISTA';
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'EN_JUEGO';
EXEC DesarrolloPartido.usp_AMONESTACION_Alta
    @id_partido = @id_partido, @tipo_tarjeta = 'AMARILLA', @minuto = 30, @motivo = 'Protestas desde el banco',
    @id_persona_ct = @dt;

SELECT 'Historial preparado' AS caso, p.numero_partido, p.estado,
       (SELECT COUNT(*) FROM DesarrolloPartido.FORMACION WHERE id_partido = p.id_partido)    AS formaciones,
       (SELECT COUNT(*) FROM DesarrolloPartido.ALINEACION WHERE id_formacion = @id_formacion) AS alineados,
       (SELECT COUNT(*) FROM DesarrolloPartido.AMONESTACION WHERE id_partido = p.id_partido) AS tarjetas
FROM Torneo.PARTIDO AS p
WHERE p.id_partido = @id_partido;
GO

/* SE5 (ERROR) Cambio de grupo de una selección que ya jugó la fase de grupos.
   Esperado: error 50001 con 2 condiciones: la confederación no es válida y
   Prueba XTA ya tiene partidos de la fase de grupos (el 204). */
DECLARE @id INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
BEGIN TRY
    EXEC Torneo.usp_SELECCION_Modificacion @id_seleccion = @id, @confederacion = 'SUDAMERICA', @grupo = 'K';
    PRINT N'SE5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'SE5';
END CATCH;
GO

/* SE6 (ERROR) Baja de una selección con historial.
   Esperado: error 50001 que lista lo que referencia a Prueba XTA: su lista, su
   cuerpo técnico, sus partidos y sus formaciones (4 condiciones). */
DECLARE @id INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
BEGIN TRY
    EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id;
    PRINT N'SE6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'SE6';
END CATCH;
GO

/* J9 (ERROR) Borrado físico de un jugador con historial.
   Esperado: error 50001 con 1 condición: "Prueba Tres" figura en la
   formación del partido 204 (DesarrolloPartido.ALINEACION). El jugador no
   cambia. */
DECLARE @id INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba Tres');
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id, @eliminar_registro = 1;
    PRINT N'J9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'J9';
END CATCH;
SELECT 'J9 después' AS caso, id_jugador, apellido, nombre, dorsal FROM Torneo.JUGADOR WHERE id_jugador = @id;
GO

/* C6 (ERROR) Baja de un director técnico con una tarjeta registrada.
   Esperado: error 50001 con 1 condición: al director técnico de Prueba XTA lo
   referencia 1 registro de DesarrolloPartido.AMONESTACION (partido 204). */
DECLARE @id INT = (SELECT ct.id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO AS ct
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = ct.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                   WHERE p.codigo_fifa = 'XTA' AND ct.rol = 'DIRECTOR_TECNICO');
BEGIN TRY
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Baja @id_persona_ct = @id;
    PRINT N'C6: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'C6';
END CATCH;
GO

/* PA12 (ERROR) Baja de un partido con formación y eventos.
   Esperado: error 50001 que lista la formación y la tarjeta del partido 204. */
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 204);
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;
    PRINT N'PA12: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PA12';
END CATCH;
GO

/* Limpieza del historial (OK), con los SP de baja y en este orden: la
   tarjeta, el partido vuelve a PROGRAMADO, la alineación, la formación, el
   partido y el jugador "Prueba Tres".
   Esperado: 0 en todas las columnas. */
DECLARE @id_partido INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 204);
DECLARE @id_formacion INT = (SELECT id_formacion FROM DesarrolloPartido.FORMACION WHERE id_partido = @id_partido);
DECLARE @id_jugador INT = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba Tres');
DECLARE @id_tarjeta INT = (SELECT id_amonestacion FROM DesarrolloPartido.AMONESTACION WHERE id_partido = @id_partido);

EXEC DesarrolloPartido.usp_AMONESTACION_Baja @id_amonestacion = @id_tarjeta;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id_partido, @estado = 'PROGRAMADO';
EXEC DesarrolloPartido.usp_ALINEACION_Baja @id_formacion = @id_formacion, @id_jugador = @id_jugador;
EXEC DesarrolloPartido.usp_FORMACION_Baja @id_formacion = @id_formacion;
EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id_partido;
EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_jugador, @eliminar_registro = 1;

SELECT 'Historial borrado' AS caso,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido = 204)          AS partidos,
       (SELECT COUNT(*) FROM DesarrolloPartido.FORMACION WHERE id_formacion = @id_formacion) AS formaciones,
       (SELECT COUNT(*) FROM DesarrolloPartido.AMONESTACION WHERE id_amonestacion = @id_tarjeta) AS tarjetas,
       (SELECT COUNT(*) FROM Torneo.JUGADOR WHERE apellido = N'Prueba Tres')       AS jugadores;
GO


/* ============================================================================
   PARTIDO (sede de prueba, selecciones del grupo L)
   ============================================================================ */

/* PA1 (OK) Alta con la hora local de la sede.
   Esperado: el partido 201 (Prueba XTA - Prueba XTB, grupo L) queda PROGRAMADO con
   hora local 01/08/2026 16:00 y hora UTC 19:00, calculada con el huso de la
   sede (UTC-3). */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba ABM');
DECLARE @xta INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
DECLARE @xtb INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTB');
DECLARE @id INT;

EXEC Torneo.usp_PARTIDO_Alta
    @numero_partido = 201, @id_sede = @sede, @fase = 'grupos', @fecha_hora_local = '2026-08-01 16:00',
    @id_seleccion_local = @xta, @id_seleccion_visitante = @xtb, @id_partido = @id OUTPUT;

SELECT 'PA1 después' AS caso, numero_partido, fase, seleccion_local, seleccion_visitante,
       fecha_hora_local, fecha_hora_utc, estado
FROM Torneo.vw_Fixture WHERE id_partido = @id;
GO

/* PA2 (OK) Alta con la hora UTC.
   Esperado: el partido 202 (Prueba XTC - Prueba XTB) queda con hora UTC 05/08/2026 22:00
   y hora local 19:00. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba ABM');
DECLARE @xtc INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTC');
DECLARE @xtb INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTB');
DECLARE @id INT;

EXEC Torneo.usp_PARTIDO_Alta
    @numero_partido = 202, @id_sede = @sede, @fase = 'GRUPOS', @fecha_hora_utc = '2026-08-05 22:00',
    @id_seleccion_local = @xtc, @id_seleccion_visitante = @xtb, @id_partido = @id OUTPUT;

SELECT 'PA2 después' AS caso, numero_partido, seleccion_local, seleccion_visitante, fecha_hora_local, fecha_hora_utc
FROM Torneo.vw_Fixture WHERE id_partido = @id;
GO

/* PA3 (ERROR) Alta con todos los datos mal.
   Esperado: error 50001 con 5 condiciones: ya existe el partido 201, no
   existe la sede -1, la fase AMISTOSO no es válida, falta la fecha y hora, y
   la selección local y la visitante son la misma. */
DECLARE @xta INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Alta
        @numero_partido = 201, @id_sede = -1, @fase = 'AMISTOSO',
        @id_seleccion_local = @xta, @id_seleccion_visitante = @xta;
    PRINT N'PA3: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PA3';
END CATCH;
GO

/* PA4 (ERROR) Fase de grupos con selecciones de grupos distintos y descanso insuficiente.
   Preparación: la selección de Prueba XTE en el grupo K.
   Esperado: error 50001 con 2 condiciones: en la fase de grupos las dos
   selecciones tienen que ser del mismo grupo (Prueba XTA es del L y Prueba XTE
   del K) y Prueba XTA ya juega el partido 201 a menos de 24 horas. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba ABM');
DECLARE @xta INT = (SELECT s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
DECLARE @xte_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'XTE');
DECLARE @xte INT;
EXEC Torneo.usp_SELECCION_Alta @id_pais = @xte_pais, @confederacion = 'CONMEBOL', @grupo = 'K', @id_seleccion = @xte OUTPUT;
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Alta
        @numero_partido = 203, @id_sede = @sede, @fase = 'GRUPOS', @fecha_hora_utc = '2026-08-02 10:00',
        @id_seleccion_local = @xta, @id_seleccion_visitante = @xte;
    PRINT N'PA4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PA4';
END CATCH;
GO

/* PA5 (ERROR) Hora local y UTC que no coinciden, en una sede ocupada ese día.
   Esperado: error 50001 con 2 condiciones: la hora local no coincide con la
   UTC en el huso de la sede y la sede ya tiene el partido 201 ese día. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba ABM');
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Alta
        @numero_partido = 203, @id_sede = @sede, @fase = 'OCTAVOS',
        @fecha_hora_utc = '2026-08-01 23:00', @fecha_hora_local = '2026-08-01 23:00';
    PRINT N'PA5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PA5';
END CATCH;
GO

/* PA6 (OK) Cambio de fecha con la hora local.
   Esperado: el partido 201 pasa al 02/08/2026 a las 16:00 locales, y la hora
   UTC se recalcula (19:00). */
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
SELECT 'PA6 antes' AS caso, numero_partido, fecha_hora_local, fecha_hora_utc FROM Torneo.PARTIDO WHERE id_partido = @id;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @fecha_hora_local = '2026-08-02 16:00';
SELECT 'PA6 después' AS caso, numero_partido, fecha_hora_local, fecha_hora_utc FROM Torneo.PARTIDO WHERE id_partido = @id;
GO

/* PA7 (ERROR) Resultado y asistencia en un partido que no empezó.
   Esperado: error 50001 con 2 condiciones: el resultado solo se carga con el
   partido FINALIZADO y la asistencia se carga con el partido empezado o
   terminado. */
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @goles_local = 1, @goles_visitante = 0, @asistencia = 1000;
    PRINT N'PA7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PA7';
END CATCH;
GO

/* PA8 (OK) Carga histórica: un partido PROGRAMADO pasa a FINALIZADO con su resultado.
   Esperado: el partido 201 queda FINALIZADO, 2 a 1, con 28000 espectadores. */
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
SELECT 'PA8 antes' AS caso, numero_partido, resultado, asistencia, estado FROM Torneo.vw_Fixture WHERE id_partido = @id;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @goles_local = 2, @goles_visitante = 1,
    @asistencia = 28000, @estado = 'FINALIZADO';
SELECT 'PA8 después' AS caso, numero_partido, resultado, asistencia, estado FROM Torneo.vw_Fixture WHERE id_partido = @id;
GO

/* S5 (ERROR) Modificación de una sede con datos que no cierran.
   Esperado: error 50001 con 2 condiciones: la capacidad (1000) no puede ser
   menor que la asistencia ya registrada en la sede (28000, partido 201) y la
   longitud está fuera de rango. La sede no cambia. */
DECLARE @id INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba ABM');
BEGIN TRY
    EXEC Torneo.usp_SEDE_Modificacion @id_sede = @id, @capacidad = 1000, @latitud = -34.5, @longitud = -200;
    PRINT N'S5: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'S5';
END CATCH;
SELECT 'S5 después' AS caso, nombre_estadio, capacidad, latitud, longitud FROM Torneo.SEDE WHERE id_sede = @id;
GO

/* PA9 (ERROR) Cambios que no corresponden en un partido finalizado.
   Preparación: la sede "Estadio Prueba ABM 2", con capacidad para 20000.
   Esperado: error 50001 con 3 condiciones: el partido está FINALIZADO y ya
   no se puede cambiar la sede, en la fase de grupos no hay definición por
   penales y la asistencia supera la capacidad de la sede pedida (Estadio
   Prueba ABM 2, 20000). */
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
DECLARE @arg_pais SMALLINT = (SELECT id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa = 'ARG');
DECLARE @otra INT;
EXEC Torneo.usp_SEDE_Alta
    @nombre_estadio = 'Estadio Prueba ABM 2', @ciudad = 'Córdoba', @id_pais = @arg_pais,
    @capacidad = 20000, @huso_horario = 'Argentina Standard Time', @id_sede = @otra OUTPUT;
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @id_sede = @otra,
        @penales_local = 4, @penales_visitante = 2, @asistencia = 60000;
    PRINT N'PA9: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PA9';
END CATCH;
GO

/* PA10 (ERROR) Paso de estado no permitido.
   Esperado: error 50001 con 1 condición: un partido no puede pasar de
   FINALIZADO a SUSPENDIDO. */
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
BEGIN TRY
    EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'SUSPENDIDO';
    PRINT N'PA10: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'PA10';
END CATCH;
GO

/* PA11 (OK) Reapertura de un partido finalizado y vuelta a PROGRAMADO.
   Esperado: al pasar a EN_JUEGO se borra el resultado (goles en NULL); como
   no tiene eventos, después puede volver a PROGRAMADO. */
DECLARE @id INT = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'EN_JUEGO';
SELECT 'PA11 reabierto' AS caso, numero_partido, goles_local, goles_visitante, asistencia, estado FROM Torneo.PARTIDO WHERE id_partido = @id;
EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'PROGRAMADO';
SELECT 'PA11 después' AS caso, numero_partido, goles_local, goles_visitante, estado FROM Torneo.PARTIDO WHERE id_partido = @id;
GO

/* S6 (OK) Cambio de huso de una sede con partidos.
   Esperado: la sede pasa a "Pacific SA Standard Time" (Chile, UTC-4 en
   agosto) y la hora local de los partidos 201 y 202 se recalcula una hora
   antes; la hora UTC no cambia. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba ABM');
SELECT 'S6 antes' AS caso, numero_partido, fecha_hora_local, fecha_hora_utc FROM Torneo.PARTIDO WHERE id_sede = @sede ORDER BY numero_partido;
EXEC Torneo.usp_SEDE_Modificacion @id_sede = @sede, @huso_horario = 'Pacific SA Standard Time';
SELECT 'S6 después' AS caso, numero_partido, fecha_hora_local, fecha_hora_utc FROM Torneo.PARTIDO WHERE id_sede = @sede ORDER BY numero_partido;
GO

/* S7 (ERROR) Baja de una sede con partidos.
   Esperado: error 50001 con 1 condición: la referencian 2 registros de
   Torneo.PARTIDO. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba ABM');
BEGIN TRY
    EXEC Torneo.usp_SEDE_Baja @id_sede = @sede;
    PRINT N'S7: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'S7';
END CATCH;
GO

/* S8 (OK) Baja de una sede sin partidos.
   Esperado: "Estadio Prueba ABM 2" (la de PA9, que no tiene partidos ni
   espacios publicitarios) existe antes y no después. */
DECLARE @sede INT = (SELECT id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba ABM 2');
SELECT 'S8 antes' AS caso, COUNT(*) AS sedes FROM Torneo.SEDE WHERE id_sede = @sede;
EXEC Torneo.usp_SEDE_Baja @id_sede = @sede;
SELECT 'S8 después' AS caso, COUNT(*) AS sedes FROM Torneo.SEDE WHERE id_sede = @sede;
GO

-- PA12 (baja de un partido con formación y eventos) se prueba en la sección HISTORIAL.

/* PA13 (OK) Baja de los partidos de prueba.
   Esperado: 2 partidos de prueba antes y 0 después. */
DECLARE @id INT;
SELECT 'PA13 antes' AS caso, COUNT(*) AS partidos_de_prueba FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 201 AND 209;
SET @id = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 201);
EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;
SET @id = (SELECT id_partido FROM Torneo.PARTIDO WHERE numero_partido = 202);
EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;
SELECT 'PA13 después' AS caso, COUNT(*) AS partidos_de_prueba FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 201 AND 209;
GO

/* J10 (OK) Borrado físico de los jugadores de prueba (no tienen historial).
   Esperado: 2 jugadores antes y 0 después. */
DECLARE @id_lista INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                         INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                         INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
DECLARE @id INT;
SELECT 'J10 antes' AS caso, COUNT(*) AS jugadores FROM Torneo.JUGADOR WHERE id_lista = @id_lista;
SET @id = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba Uno');
EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id, @eliminar_registro = 1;
SET @id = (SELECT id_jugador FROM Torneo.JUGADOR WHERE apellido = N'Prueba Dos');
EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id, @eliminar_registro = 1;
SELECT 'J10 después' AS caso, COUNT(*) AS jugadores FROM Torneo.JUGADOR WHERE id_lista = @id_lista;
GO

/* L7 (OK) Baja de la lista de Prueba XTA, que ya no tiene jugadores.
   Esperado: 1 lista antes y 0 después.
   L8 (ERROR) Baja de la misma lista otra vez.
   Esperado: error 50001 con 1 condición: no existe una lista con ese id. */
DECLARE @id INT = (SELECT l.id_lista FROM Torneo.LISTA_CONVOCADOS AS l
                   INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                   INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XTA');
SELECT 'L7 antes' AS caso, COUNT(*) AS listas FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id;
EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id;
SELECT 'L7 después' AS caso, COUNT(*) AS listas FROM Torneo.LISTA_CONVOCADOS WHERE id_lista = @id;

BEGIN TRY
    EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id;
    PRINT N'L8: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'L8';
END CATCH;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas de datos de prueba (también en la del
   parámetro PRUEBA_55_CUPO_GRUPO) y SELECCIONES_POR_GRUPO con su valor
   original (4 con los datos iniciales).
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio LIKE 'Estadio Prueba ABM%')      AS sedes_de_prueba,
       (SELECT COUNT(*) FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('XTA', 'XTB', 'XTC', 'XTD', 'XTE'))                             AS selecciones_de_prueba,
       (SELECT COUNT(*) FROM Torneo.JUGADOR WHERE apellido LIKE N'Prueba%')                     AS jugadores_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PERSONA_CUERPO_TECNICO WHERE apellido LIKE N'Prueba%')      AS cuerpo_tecnico_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido BETWEEN 201 AND 209)           AS partidos_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa LIKE 'XT_' AND nombre LIKE 'Prueba XT_') AS paises_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'PRUEBA_55_CUPO_GRUPO')  AS parametros_de_prueba,
       (SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'SELECCIONES_POR_GRUPO')    AS selecciones_por_grupo;
GO

SET NOEXEC OFF;
GO
