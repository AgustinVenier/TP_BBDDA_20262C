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
 Archivo: 66_Test_SP_Importacion.sql
 Objetivo: Probar los SP de 16_SP_Importacion.sql: el upsert de cada dataset
           (alta si el registro es nuevo, actualización si cambió, sin cambios
           si se importa dos veces lo mismo), la traducción de los valores de
           las fuentes y la conservación del historial. Incluye el caso
           obligatorio de importación con errores parciales: un lote con
           filas válidas e inválidas que se procesa fila por fila, importa
           las válidas e informa las demás, y que reimportado no duplica nada.
           Requiere haber ejecutado 00 a 20; no depende del juego de datos.
           Usa datos de prueba propios (las selecciones de Prueba XMA y
           Prueba XMB, la sede "Estadio Prueba Importación", el partido 255, un
           árbitro y tres países de prueba con sus indicadores) y los borra al
           empezar y al terminar, así que se puede ejecutar más de una vez.
================================================================================

 Cómo leer los resultados:
   - Casos OK: la grilla muestra la acción que informó el SP (INSERTADO,
     ACTUALIZADO o SIN CAMBIOS) y los datos que quedaron.
   - Casos ERROR: en Mensajes se imprime "OK" y el mensaje que devolvió el SP.
     Si el SP no falla, o falla con un error que no es de validación, se
     imprime "FALLÓ".
   - Al final, la verificación tiene que mostrar 0 datos de prueba.
 Los países de prueba usan códigos ISO alfa-3 de uso privado (XIA, XIB), así
 los indicadores importados nunca se mezclan con los reales del Banco Mundial.
 Las selecciones de prueba son de los países "Prueba XMA" y "Prueba XMB", con
 códigos FIFA que empiezan con X, que no tiene ningún miembro de la FIFA: así
 el test no choca con las selecciones reales que se importen.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'Torneo.usp_ImportarJugador', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM DatosGenerales.IDIOMA WHERE codigo_iso IN ('en', 'fr') HAVING COUNT(*) = 2)
BEGIN
    RAISERROR(N'Faltan los SP de importación o los datos iniciales: ejecutar los scripts 00 a 20.', 16, 1);
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

    -- Partido importado.
    SELECT @id = id_partido FROM Torneo.PARTIDO WHERE numero_partido = 255;
    IF @@ROWCOUNT > 0
    BEGIN
        IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id) = 'FINALIZADO'
            EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'EN_JUEGO';
        IF (SELECT estado FROM Torneo.PARTIDO WHERE id_partido = @id) = 'EN_JUEGO'
            EXEC Torneo.usp_PARTIDO_Modificacion @id_partido = @id, @estado = 'PROGRAMADO';
        EXEC Torneo.usp_PARTIDO_Baja @id_partido = @id;
    END;

    -- Sede importada con sus espacios.
    SELECT @id = id_sede FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Importación';
    IF @@ROWCOUNT > 0
    BEGIN
        WHILE EXISTS (SELECT 1 FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id)
        BEGIN
            SELECT TOP (1) @id2 = id_espacio FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = @id;
            EXEC Publicidad.usp_ESPACIO_PUBLICITARIO_Baja @id_espacio = @id2;
        END;
        EXEC Torneo.usp_SEDE_Baja @id_sede = @id;
    END;

    -- Selecciones de prueba (Prueba XMA y Prueba XMB) con su lista, su cuerpo técnico y sus jugadores.
    WHILE EXISTS (SELECT 1 FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
                  WHERE p.codigo_fifa IN ('XMA', 'XMB'))
    BEGIN
        SELECT TOP (1) @id = s.id_seleccion FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('XMA', 'XMB');
        WHILE EXISTS (SELECT 1 FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                      WHERE l.id_seleccion = @id)
        BEGIN
            SELECT TOP (1) @id2 = j.id_jugador FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
            WHERE l.id_seleccion = @id;
            EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id2, @eliminar_registro = 1;
        END;
        WHILE EXISTS (SELECT 1 FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id)
        BEGIN
            SELECT TOP (1) @id2 = id_persona_ct FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_seleccion = @id;
            EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Baja @id_persona_ct = @id2;
        END;
        SELECT @id2 = id_lista FROM Torneo.LISTA_CONVOCADOS WHERE id_seleccion = @id;
        IF @@ROWCOUNT > 0
            EXEC Torneo.usp_LISTA_CONVOCADOS_Baja @id_lista = @id2;
        EXEC Torneo.usp_SELECCION_Baja @id_seleccion = @id;
    END;

    -- Árbitro importado con sus idiomas.
    WHILE EXISTS (SELECT 1 FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Eze')
    BEGIN
        SELECT TOP (1) @id = id_arbitro FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Eze';
        WHILE EXISTS (SELECT 1 FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id)
        BEGIN
            SELECT TOP (1) @id2 = id_idioma FROM Arbitraje.ARBITRO_IDIOMA WHERE id_arbitro = @id;
            EXEC Arbitraje.usp_ARBITRO_IDIOMA_Baja @id_arbitro = @id, @id_idioma = @id2;
        END;
        EXEC Arbitraje.usp_ARBITRO_Baja @id_arbitro = @id, @eliminar_registro = 1;
    END;

    -- Países de prueba con sus indicadores.
    WHILE EXISTS (SELECT 1 FROM DatosGenerales.INDICADOR_ECONOMICO AS ie INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
                  WHERE p.nombre LIKE 'Pais Prueba Importacion%')
    BEGIN
        SELECT TOP (1) @id = ie.id_indicador FROM DatosGenerales.INDICADOR_ECONOMICO AS ie
        INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
        WHERE p.nombre LIKE 'Pais Prueba Importacion%';
        EXEC DatosGenerales.usp_INDICADOR_ECONOMICO_Baja @id_indicador = @id;
    END;
    WHILE EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE nombre LIKE 'Pais Prueba Importacion%')
    BEGIN
        SELECT TOP (1) @id = id_pais FROM DatosGenerales.PAIS WHERE nombre LIKE 'Pais Prueba Importacion%';
        EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    END;

    -- Países de las selecciones de prueba (sus selecciones y su árbitro ya se borraron).
    WHILE EXISTS (SELECT 1 FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XMA', 'XMB') AND nombre LIKE 'Prueba XM_')
    BEGIN
        SELECT TOP (1) @id = id_pais FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XMA', 'XMB') AND nombre LIKE 'Prueba XM_';
        EXEC DatosGenerales.usp_PAIS_Baja @id_pais = @id;
    END;
END;
GO

EXEC #usp_LimpiarPruebas;
GO

-- Preparación: los países de prueba para los indicadores. "Pais Prueba
-- Importacion B1" y "B2" comparten el código XIB, como Inglaterra y Escocia
-- comparten GBR.
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Pais Prueba Importacion A',  @huso_horario = 'UTC', @codigo_iso3 = 'XIA';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Pais Prueba Importacion B1', @huso_horario = 'UTC', @codigo_iso3 = 'XIB';
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Pais Prueba Importacion B2', @huso_horario = 'UTC', @codigo_iso3 = 'XIB';
GO


/* ============================================================================
   usp_ImportarIndicadorEconomico (API del Banco Mundial)
   ============================================================================ */

/* II1 (OK) Alta, reimportación sin cambios y actualización.
   Esperado: el PBI per cápita 2023 de "Pais Prueba Importacion A" (código
   XIA) se importa tres veces: INSERTADO (13700), SIN CAMBIOS (13700 otra vez)
   y ACTUALIZADO (13800). */
DECLARE @a1 VARCHAR(15), @a2 VARCHAR(15), @a3 VARCHAR(15);
EXEC DatosGenerales.usp_ImportarIndicadorEconomico @codigo_iso3 = 'xia', @codigo_indicador = 'ny.gdp.pcap.cd', @anio = 2023, @valor = 13700, @accion = @a1 OUTPUT;
EXEC DatosGenerales.usp_ImportarIndicadorEconomico @codigo_iso3 = 'XIA', @codigo_indicador = 'NY.GDP.PCAP.CD', @anio = 2023, @valor = 13700, @accion = @a2 OUTPUT;
EXEC DatosGenerales.usp_ImportarIndicadorEconomico @codigo_iso3 = 'XIA', @codigo_indicador = 'NY.GDP.PCAP.CD', @anio = 2023, @valor = 13800, @accion = @a3 OUTPUT;
SELECT 'II1' AS caso, @a1 AS primera, @a2 AS segunda, @a3 AS tercera,
       (SELECT valor FROM DatosGenerales.INDICADOR_ECONOMICO AS ie INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
        WHERE p.codigo_iso3 = 'XIA' AND ie.anio = 2023) AS valor_final;
GO

/* II2 (OK) Un código ISO compartido (como GBR para Inglaterra y Escocia).
   Esperado: el valor de XIB se registra para "Pais Prueba Importacion B1" y
   para "B2" (2 filas) y la acción es INSERTADO. */
DECLARE @a VARCHAR(15);
EXEC DatosGenerales.usp_ImportarIndicadorEconomico @codigo_iso3 = 'XIB', @codigo_indicador = 'NY.GDP.PCAP.CD', @anio = 2023, @valor = 49500, @accion = @a OUTPUT;
SELECT 'II2' AS caso, @a AS accion, p.nombre AS pais, ie.anio, ie.valor
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE p.codigo_iso3 = 'XIB' AND ie.anio = 2023;
GO

/* II3 (ERROR) Datos incompletos o con formato inválido.
   Esperado: tres errores 50001. II3a con 1 condición: no hay ningún país con
   código XXX. II3b con 3 condiciones: el código AR no tiene 3 letras y faltan
   el año y el valor. II3c con 2 condiciones: el código del indicador tiene un
   guion y el año 1950 es anterior a 1960; XIA no queda con ningún valor de 1950. */
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadorEconomico @codigo_iso3 = 'XXX', @codigo_indicador = 'NY.GDP.PCAP.CD', @anio = 2023, @valor = 1;
    PRINT N'II3a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'II3a';
END CATCH;
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadorEconomico @codigo_iso3 = 'AR', @codigo_indicador = 'NY.GDP.PCAP.CD', @anio = NULL, @valor = NULL;
    PRINT N'II3b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'II3b';
END CATCH;
BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadorEconomico @codigo_iso3 = 'XIA', @codigo_indicador = 'NY-GDP', @anio = 1950, @valor = 1;
    PRINT N'II3c: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'II3c';
END CATCH;
SELECT 'II3c después' AS caso, COUNT(*) AS valores_1950_de_xia
FROM DatosGenerales.INDICADOR_ECONOMICO AS ie INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
WHERE p.codigo_iso3 = 'XIA' AND ie.anio = 1950;
GO


/* ============================================================================
   usp_ImportarSede (scraping del artículo del torneo)
   ============================================================================ */

/* IS1 (OK) Alta, reimportación sin cambios y actualización.
   Esperado: INSERTADO (la sede con sus 4 espacios a 50000 USD), SIN CAMBIOS
   y ACTUALIZADO (la capacidad pasa de 65000 a 66000). */
DECLARE @a1 VARCHAR(15), @a2 VARCHAR(15), @a3 VARCHAR(15);
EXEC Torneo.usp_ImportarSede @nombre_estadio = 'Estadio Prueba Importación', @ciudad = 'Boston', @codigo_fifa_pais = 'usa',
    @capacidad = 65000, @huso_horario = 'Eastern Standard Time', @latitud = 42.091300, @longitud = -71.264300,
    @tarifa_espacio_usd = 50000, @accion = @a1 OUTPUT;
EXEC Torneo.usp_ImportarSede @nombre_estadio = 'Estadio Prueba Importación', @ciudad = 'Boston', @codigo_fifa_pais = 'USA',
    @capacidad = 65000, @huso_horario = 'Eastern Standard Time', @latitud = 42.091300, @longitud = -71.264300, @accion = @a2 OUTPUT;
EXEC Torneo.usp_ImportarSede @nombre_estadio = 'Estadio Prueba Importación', @ciudad = 'Boston', @codigo_fifa_pais = 'USA',
    @capacidad = 66000, @huso_horario = 'Eastern Standard Time', @latitud = 42.091300, @longitud = -71.264300, @accion = @a3 OUTPUT;
SELECT 'IS1' AS caso, @a1 AS primera, @a2 AS segunda, @a3 AS tercera, s.capacidad,
       (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO AS e WHERE e.id_sede = s.id_sede) AS espacios
FROM Torneo.SEDE AS s WHERE s.nombre_estadio = 'Estadio Prueba Importación';
GO

/* IS2 (ERROR) País desconocido y sin nombre de estadio.
   Esperado: error 50001 con 2 condiciones. */
BEGIN TRY
    EXEC Torneo.usp_ImportarSede @nombre_estadio = ' ', @ciudad = 'Nowhere', @codigo_fifa_pais = 'ZZZ',
        @capacidad = 1000, @huso_horario = 'UTC';
    PRINT N'IS2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IS2';
END CATCH;
GO


/* ============================================================================
   usp_ImportarPartido (fixture y resultados oficiales)
   ============================================================================ */

-- Preparación: los países de prueba XMA y XMB con sus selecciones (con su lista y su
-- director técnico) para el partido y los jugadores.
DECLARE @xma SMALLINT, @xmb SMALLINT;
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XMA', @huso_horario = 'UTC', @codigo_fifa = 'XMA', @id_pais = @xma OUTPUT;
EXEC DatosGenerales.usp_PAIS_Alta @nombre = 'Prueba XMB', @huso_horario = 'UTC', @codigo_fifa = 'XMB', @id_pais = @xmb OUTPUT;
EXEC Torneo.usp_RegistrarSeleccion @id_pais = @xma, @confederacion = 'CAF', @grupo = NULL, @fecha_presentacion = '2026-06-01',
    @dt_nombre = N'Ade', @dt_apellido = N'Prueba DT', @mostrar = 0;
EXEC Torneo.usp_RegistrarSeleccion @id_pais = @xmb, @confederacion = 'CAF', @grupo = NULL, @fecha_presentacion = '2026-06-01',
    @dt_nombre = N'Sipho', @dt_apellido = N'Prueba DT', @mostrar = 0;
GO

/* IP1 (OK) Alta de un partido con resultado, con la fase en inglés.
   Esperado: el partido 255 (Prueba XMA - Prueba XMB) se registra como OCTAVOS
   ("Round of 16"), con la hora local 12/09/2026 15:00 en la sede (19:00 UTC),
   FINALIZADO 2 - 1 con 60000 espectadores. Acción INSERTADO. */
DECLARE @a VARCHAR(15);
EXEC Torneo.usp_ImportarPartido @numero_partido = 255, @nombre_estadio = 'Estadio Prueba Importación', @fase = 'Round of 16',
    @fecha_hora_local = '2026-09-12 15:00', @codigo_fifa_local = 'XMA', @codigo_fifa_visitante = 'xmb',
    @goles_local = 2, @goles_visitante = 1, @asistencia = 60000, @accion = @a OUTPUT;
SELECT 'IP1' AS caso, @a AS accion, numero_partido, fase, fecha_hora_local, fecha_hora_utc, seleccion_local,
       resultado, seleccion_visitante, asistencia, estado
FROM Torneo.vw_Fixture WHERE numero_partido = 255;
GO

/* IP2 (OK) Reimportación del mismo partido y corrección de la asistencia.
   Esperado: SIN CAMBIOS con los mismos datos; ACTUALIZADO al cambiar la
   asistencia a 61500. */
DECLARE @a1 VARCHAR(15), @a2 VARCHAR(15);
EXEC Torneo.usp_ImportarPartido @numero_partido = 255, @nombre_estadio = 'Estadio Prueba Importación', @fase = 'Round of 16',
    @fecha_hora_local = '2026-09-12 15:00', @codigo_fifa_local = 'XMA', @codigo_fifa_visitante = 'XMB',
    @goles_local = 2, @goles_visitante = 1, @asistencia = 60000, @accion = @a1 OUTPUT;
EXEC Torneo.usp_ImportarPartido @numero_partido = 255, @nombre_estadio = 'Estadio Prueba Importación', @fase = 'Round of 16',
    @fecha_hora_local = '2026-09-12 15:00', @codigo_fifa_local = 'XMA', @codigo_fifa_visitante = 'XMB',
    @goles_local = 2, @goles_visitante = 1, @asistencia = 61500, @accion = @a2 OUTPUT;
SELECT 'IP2' AS caso, @a1 AS primera, @a2 AS segunda, asistencia FROM Torneo.PARTIDO WHERE numero_partido = 255;
GO

/* IP3 (OK) Se conserva la información histórica.
   Un archivo trae otra fecha para el partido ya jugado.
   Esperado: SIN CAMBIOS; la fecha y hora del partido finalizado no se
   modifican. */
DECLARE @a VARCHAR(15);
EXEC Torneo.usp_ImportarPartido @numero_partido = 255, @nombre_estadio = 'Estadio Prueba Importación', @fase = 'Round of 16',
    @fecha_hora_local = '2026-09-13 18:00', @codigo_fifa_local = 'XMA', @codigo_fifa_visitante = 'XMB',
    @goles_local = 2, @goles_visitante = 1, @asistencia = 61500, @accion = @a OUTPUT;
SELECT 'IP3' AS caso, @a AS accion, fecha_hora_local, estado FROM Torneo.PARTIDO WHERE numero_partido = 255;
GO

/* IP4 (ERROR) Estadio y selección que no existen.
   Esperado: error 50001 con 2 condiciones. */
BEGIN TRY
    EXEC Torneo.usp_ImportarPartido @numero_partido = 254, @nombre_estadio = 'Estadio Inexistente', @fase = 'Final',
        @fecha_hora_utc = '2026-09-20 19:00', @codigo_fifa_local = 'XMA', @codigo_fifa_visitante = 'ZZZ';
    PRINT N'IP4: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IP4';
END CATCH;
GO


/* ============================================================================
   usp_ImportarJugador (planteles)
   ============================================================================ */

/* IJ1 (OK) Alta con la posición abreviada, reimportación y actualización.
   Esperado: INSERTADO ("FW" se guarda como DELANTERO), SIN CAMBIOS y
   ACTUALIZADO (el club pasa a Enyimba). */
DECLARE @a1 VARCHAR(15), @a2 VARCHAR(15), @a3 VARCHAR(15);
EXEC Torneo.usp_ImportarJugador @codigo_fifa_seleccion = 'XMA', @nombre = N'Chidi', @apellido = N'Prueba Okafor', @posicion = 'FW',
    @dorsal = 9, @fecha_nacimiento = '1999-03-21', @club_origen = N'Rangers International', @accion = @a1 OUTPUT;
EXEC Torneo.usp_ImportarJugador @codigo_fifa_seleccion = 'XMA', @nombre = N'Chidi', @apellido = N'Prueba Okafor', @posicion = 'FW',
    @dorsal = 9, @fecha_nacimiento = '1999-03-21', @club_origen = N'Rangers International', @accion = @a2 OUTPUT;
EXEC Torneo.usp_ImportarJugador @codigo_fifa_seleccion = 'XMA', @nombre = N'Chidi', @apellido = N'Prueba Okafor', @posicion = 'FW',
    @dorsal = 9, @fecha_nacimiento = '1999-03-21', @club_origen = N'Enyimba', @accion = @a3 OUTPUT;
SELECT 'IJ1' AS caso, @a1 AS primera, @a2 AS segunda, @a3 AS tercera, j.posicion_habitual, j.club_origen, j.fecha_alta, j.motivo_alta
FROM Torneo.JUGADOR AS j WHERE j.apellido = N'Prueba Okafor';
GO

/* IJ2 (ERROR) Selección desconocida y posición no válida.
   Esperado: dos errores 50001. IJ2a, de usp_ImportarJugador: no hay una
   selección con código ZZZ. IJ2b, de usp_JUGADOR_Alta: la posición XX no es
   válida. */
BEGIN TRY
    EXEC Torneo.usp_ImportarJugador @codigo_fifa_seleccion = 'ZZZ', @nombre = N'Uno', @apellido = N'Prueba', @posicion = 'GK', @dorsal = 1;
    PRINT N'IJ2a: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IJ2a';
END CATCH;
BEGIN TRY
    EXEC Torneo.usp_ImportarJugador @codigo_fifa_seleccion = 'XMA', @nombre = N'Dos', @apellido = N'Prueba', @posicion = 'XX', @dorsal = 2;
    PRINT N'IJ2b: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IJ2b';
END CATCH;
GO


/* ============================================================================
   usp_ImportarArbitro (nómina de árbitros)
   ============================================================================ */

/* IA1 (OK) Alta, reimportación y un idioma nuevo.
   Esperado: INSERTADO (categoría CONFEDERATION guardada como CONFEDERACION,
   idioma inglés), SIN CAMBIOS y ACTUALIZADO (se agrega el francés; no se
   quita ningún idioma). */
DECLARE @a1 VARCHAR(15), @a2 VARCHAR(15), @a3 VARCHAR(15);
EXEC Arbitraje.usp_ImportarArbitro @codigo_fifa_pais = 'XMA', @nombre = N'Emeka', @apellido = N'Prueba Eze', @categoria = 'Confederation',
    @idiomas = 'en', @fecha_nacimiento = '1986-11-02', @accion = @a1 OUTPUT;
EXEC Arbitraje.usp_ImportarArbitro @codigo_fifa_pais = 'XMA', @nombre = N'Emeka', @apellido = N'Prueba Eze', @categoria = 'Confederation',
    @idiomas = 'en', @fecha_nacimiento = '1986-11-02', @accion = @a2 OUTPUT;
EXEC Arbitraje.usp_ImportarArbitro @codigo_fifa_pais = 'XMA', @nombre = N'Emeka', @apellido = N'Prueba Eze', @categoria = 'Confederation',
    @idiomas = 'en,fr', @fecha_nacimiento = '1986-11-02', @accion = @a3 OUTPUT;
SELECT 'IA1' AS caso, @a1 AS primera, @a2 AS segunda, @a3 AS tercera, a.categoria,
       STRING_AGG(i.codigo_iso, ',') WITHIN GROUP (ORDER BY i.codigo_iso) AS idiomas
FROM Arbitraje.ARBITRO AS a
INNER JOIN Arbitraje.ARBITRO_IDIOMA AS ai ON ai.id_arbitro = a.id_arbitro
INNER JOIN DatosGenerales.IDIOMA AS i ON i.id_idioma = ai.id_idioma
WHERE a.apellido = N'Prueba Eze'
GROUP BY a.categoria;
GO

/* IA2 (ERROR) País desconocido y sin nombre.
   Esperado: error 50001 con 2 condiciones. */
BEGIN TRY
    EXEC Arbitraje.usp_ImportarArbitro @codigo_fifa_pais = 'ZZZ', @nombre = NULL, @apellido = N'Prueba', @categoria = 'FIFA', @idiomas = 'en';
    PRINT N'IA2: FALLÓ, se esperaba un error de validación.';
END TRY
BEGIN CATCH
    EXEC #usp_MostrarError @caso = 'IA2';
END CATCH;
GO


/* ============================================================================
   Caso obligatorio: importación con errores parciales
   El lote simula la tabla de staging que carga un proceso de la Entrega 6
   (por ejemplo, desde un CSV de planteles). Se procesa fila por fila, cada
   una en su TRY/CATCH: las filas válidas se importan y las inválidas quedan
   informadas con su motivo, sin frenar al resto.
   Esperado (primera corrida): 5 filas INSERTADO y 3 con ERROR (posición no
   válida, apellido faltante y dorsal ocupado).
   Esperado (segunda corrida del mismo lote): las 5 filas válidas dan SIN
   CAMBIOS, las 3 inválidas vuelven a fallar y la cantidad de jugadores de
   Prueba XMA no cambia (no hay duplicados).
   ============================================================================ */
DECLARE @lote TABLE (
    fila      INT PRIMARY KEY,
    seleccion VARCHAR(10),
    nombre    NVARCHAR(120),
    apellido  NVARCHAR(120),
    posicion  VARCHAR(30),
    dorsal    TINYINT,
    nacimiento DATE,
    club      NVARCHAR(200)
);
INSERT INTO @lote (fila, seleccion, nombre, apellido, posicion, dorsal, nacimiento, club)
VALUES (1, 'XMA', N'Tunde',    N'Prueba Balogun', 'GK', 1,  '1995-01-10', N'Enyimba'),
       (2, 'XMA', N'Ifeanyi',  N'Prueba Nwosu',   'DF', 2,  '1997-06-04', N'Kano Pillars'),
       (3, 'XMA', N'Segun',    N'Prueba Adeyemi', 'DF', 3,  '1998-09-15', N'Shooting Stars'),
       (4, 'XMA', N'Obinna',   N'Prueba Eze',     'MF', 8,  '1996-02-28', N'Rivers United'),
       (5, 'XMA', N'Kelechi',  N'Prueba Obi',     'FW', 11, '2000-12-01', N'Remo Stars'),
       (6, 'XMA', N'Yakubu',   N'Prueba Musa',    'XX', 14, '1999-07-07', N'Plateau United'),
       (7, 'XMA', N'Femi',     NULL,              'MF', 15, '1994-04-19', N'Lobi Stars'),
       (8, 'XMA', N'Ahmed',    N'Prueba Bello',   'DF', 9,  '1998-10-30', N'Akwa United');

DECLARE @resultado TABLE (corrida INT, fila INT, accion VARCHAR(15), detalle NVARCHAR(2048));
DECLARE @corrida INT = 1, @i INT, @accion VARCHAR(15);
DECLARE @seleccion VARCHAR(10), @nombre NVARCHAR(120), @apellido NVARCHAR(120), @posicion VARCHAR(30),
        @dorsal TINYINT, @nacimiento DATE, @club NVARCHAR(200);
DECLARE @jugadores_antes INT;

WHILE @corrida <= 2
BEGIN
    SET @jugadores_antes = (SELECT COUNT(*) FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
                            INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
                            INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XMA');
    SET @i = 1;
    WHILE @i <= (SELECT COUNT(*) FROM @lote)
    BEGIN
        SELECT @seleccion = seleccion, @nombre = nombre, @apellido = apellido, @posicion = posicion,
               @dorsal = dorsal, @nacimiento = nacimiento, @club = club
        FROM @lote WHERE fila = @i;
        BEGIN TRY
            SET @accion = NULL;
            EXEC Torneo.usp_ImportarJugador @codigo_fifa_seleccion = @seleccion, @nombre = @nombre, @apellido = @apellido,
                @posicion = @posicion, @dorsal = @dorsal, @fecha_nacimiento = @nacimiento, @club_origen = @club,
                @accion = @accion OUTPUT;
            INSERT INTO @resultado (corrida, fila, accion) VALUES (@corrida, @i, @accion);
        END TRY
        BEGIN CATCH
            INSERT INTO @resultado (corrida, fila, accion, detalle) VALUES (@corrida, @i, 'ERROR', ERROR_MESSAGE());
        END CATCH;
        SET @i += 1;
    END;

    SELECT 'Lote, corrida ' + CAST(@corrida AS VARCHAR(1)) AS caso,
           SUM(IIF(accion = 'INSERTADO', 1, 0))   AS insertados,
           SUM(IIF(accion = 'ACTUALIZADO', 1, 0)) AS actualizados,
           SUM(IIF(accion = 'SIN CAMBIOS', 1, 0)) AS sin_cambios,
           SUM(IIF(accion = 'ERROR', 1, 0))       AS con_error,
           @jugadores_antes                       AS jugadores_antes,
           (SELECT COUNT(*) FROM Torneo.JUGADOR AS j INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = j.id_lista
            INNER JOIN Torneo.SELECCION AS s ON s.id_seleccion = l.id_seleccion
            INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais WHERE p.codigo_fifa = 'XMA') AS jugadores_despues
    FROM @resultado
    WHERE corrida = @corrida;

    SET @corrida += 1;
END;

-- Detalle por fila de la primera corrida: las que fallaron muestran el mensaje del SP.
SELECT 'Lote, detalle' AS caso, r.fila, l.apellido, l.posicion, l.dorsal, r.accion, REPLACE(r.detalle, NCHAR(13) + NCHAR(10), ' ') AS detalle
FROM @resultado AS r INNER JOIN @lote AS l ON l.fila = r.fila
WHERE r.corrida = 1
ORDER BY r.fila;
GO


/* ============================================================================
   LIMPIEZA Y VERIFICACIÓN FINAL
   Esperado: 0 en todas las columnas.
   ============================================================================ */
EXEC #usp_LimpiarPruebas;

SELECT 'Final' AS caso,
       (SELECT COUNT(*) FROM Torneo.SELECCION AS s INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
        WHERE p.codigo_fifa IN ('XMA', 'XMB'))                                                      AS selecciones_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE codigo_fifa IN ('XMA', 'XMB') AND nombre LIKE 'Prueba XM_') AS paises_de_seleccion,
       (SELECT COUNT(*) FROM Torneo.SEDE WHERE nombre_estadio = 'Estadio Prueba Importación')       AS sedes_de_prueba,
       (SELECT COUNT(*) FROM Torneo.PARTIDO WHERE numero_partido IN (254, 255))                       AS partidos_de_prueba,
       (SELECT COUNT(*) FROM Arbitraje.ARBITRO WHERE apellido = N'Prueba Eze')                        AS arbitros_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.PAIS WHERE nombre LIKE 'Pais Prueba Importacion%')      AS paises_de_prueba,
       (SELECT COUNT(*) FROM DatosGenerales.INDICADOR_ECONOMICO AS ie INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = ie.id_pais
        WHERE p.nombre LIKE 'Pais Prueba Importacion%')                                             AS indicadores_de_prueba;
GO

SET NOEXEC OFF;
GO
