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

 Fecha: 10/11/2026
 Archivo: 97_Test_Cifrado_Reportes.sql
 Objetivo: Probar las vistas y el SP de Reportes que modifica
           47_Cifrado_Reportes.sql: que devuelvan los nombres de jugadores,
           cuerpos técnicos y árbitros descifrados (vw_Goles, vw_Tarjetas,
           vw_SuspensionesActivas, vw_Arbitros, vw_DesignacionesArbitrales,
           vw_Plantillas, vw_Resultados y usp_SeleccionesYPlantillasXML), y que
           un jugador dado de alta por SP aparezca descifrado en vw_Plantillas.
================================================================================

 Requiere haber ejecutado 40_Ejecutar_Cifrado.sql y tener cargado el torneo
 (32). Ejecutar como dueño de la base (dbo).

 Cada caso es independiente y se puede ejecutar solo. Muestra lo que probó en
 la grilla e imprime una línea en la pestaña Mensajes:
   OK     dio lo esperado.
   ERROR  dio otra cosa.
 El test está bien si ninguna línea empieza con ERROR.

 Si una persona no se pudiera descifrar, su nombre y su apellido saldrían
 NULL, y los textos que los juntan quedarían vacíos (", " en lugar de
 "Apellido, Nombre"). Eso es lo que controlan los casos.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM DesarrolloPartido.GOL)
    THROW 51013, N'No hay partidos jugados cargados. Ejecute primero las importaciones (31 a 35).', 1;
GO


/* Caso 1: Reportes.vw_Plantillas muestra a los jugadores descifrados. */
SELECT TOP (5) * FROM Reportes.vw_Plantillas;

IF EXISTS (SELECT 1 FROM Reportes.vw_Plantillas WHERE apellido IS NULL OR nombre IS NULL)
    PRINT N'ERROR  1. Reportes.vw_Plantillas tiene jugadores sin nombre: no los descifra.';
ELSE
    PRINT N'OK     1. Reportes.vw_Plantillas muestra los nombres descifrados.';
GO


/* Caso 2: Reportes.vw_Goles muestra al autor de cada gol descifrado. */
SELECT TOP (5) * FROM Reportes.vw_Goles;

IF EXISTS (SELECT 1 FROM Reportes.vw_Goles WHERE apellido IS NULL OR nombre IS NULL OR jugador = N', ')
    PRINT N'ERROR  2. Reportes.vw_Goles tiene goles sin autor: no lo descifra.';
ELSE
    PRINT N'OK     2. Reportes.vw_Goles muestra a los autores descifrados.';
GO


/* Caso 3: Reportes.vw_Tarjetas muestra descifrados a la persona que la
   recibió y al árbitro principal. */
SELECT TOP (5) * FROM Reportes.vw_Tarjetas;

IF EXISTS (SELECT 1 FROM Reportes.vw_Tarjetas
           WHERE apellido IS NULL OR nombre IS NULL OR persona = N', ' OR arbitro_principal = N', ')
    PRINT N'ERROR  3. Reportes.vw_Tarjetas tiene tarjetas sin persona o sin árbitro: no los descifra.';
ELSE
    PRINT N'OK     3. Reportes.vw_Tarjetas muestra a las personas y a los árbitros descifrados.';
GO


/* Caso 4: Reportes.vw_SuspensionesActivas muestra al jugador descifrado
   (puede no haber suspensiones activas). */
SELECT TOP (5) * FROM Reportes.vw_SuspensionesActivas;

IF EXISTS (SELECT 1 FROM Reportes.vw_SuspensionesActivas WHERE jugador IS NULL OR jugador = N', ')
    PRINT N'ERROR  4. Reportes.vw_SuspensionesActivas tiene suspensiones sin jugador: no lo descifra.';
ELSE
    PRINT N'OK     4. Reportes.vw_SuspensionesActivas muestra a los jugadores descifrados.';
GO


/* Caso 5: Reportes.vw_Arbitros y Reportes.vw_DesignacionesArbitrales muestran
   al árbitro descifrado. */
SELECT TOP (5) * FROM Reportes.vw_Arbitros;
SELECT TOP (5) * FROM Reportes.vw_DesignacionesArbitrales;

IF EXISTS (SELECT 1 FROM Reportes.vw_Arbitros WHERE arbitro IS NULL OR arbitro = N', ')
   OR EXISTS (SELECT 1 FROM Reportes.vw_DesignacionesArbitrales WHERE arbitro IS NULL OR arbitro = N', ')
    PRINT N'ERROR  5. Reportes.vw_Arbitros o Reportes.vw_DesignacionesArbitrales tiene árbitros sin nombre: no los descifra.';
ELSE
    PRINT N'OK     5. Reportes.vw_Arbitros y Reportes.vw_DesignacionesArbitrales muestran a los árbitros descifrados.';
GO


/* Caso 6: Reportes.vw_Resultados muestra a los goleadores descifrados. Un
   goleador sin apellido dejaría el detalle empezando con un espacio o con
   ",  " en el medio. */
SELECT TOP (5) * FROM Reportes.vw_Resultados WHERE goles_del_local IS NOT NULL;

IF EXISTS (SELECT 1 FROM Reportes.vw_Resultados
           WHERE LEFT(goles_del_local, 1) = N' ' OR goles_del_local LIKE N'%,  %'
              OR LEFT(goles_del_visitante, 1) = N' ' OR goles_del_visitante LIKE N'%,  %')
    PRINT N'ERROR  6. Reportes.vw_Resultados tiene goleadores sin apellido: no los descifra.';
ELSE
    PRINT N'OK     6. Reportes.vw_Resultados muestra a los goleadores descifrados.';
GO


/* Caso 7: Reportes.usp_SeleccionesYPlantillasXML arma el XML con los nombres
   descifrados: tiene a un jugador de la selección con su nombre, y ningún
   <Nombre> vacío. */
DECLARE @xml TABLE (reporte XML);
DECLARE @id_seleccion INT, @jugador NVARCHAR(130), @texto NVARCHAR(MAX);

-- Una selección y el nombre de uno de sus jugadores.
SELECT TOP (1) @id_seleccion = l.id_seleccion, @jugador = CONCAT(v.nombre, N' ', v.apellido)
FROM Seguridad.vw_Jugador AS v
INNER JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_lista = v.id_lista
WHERE v.fecha_baja IS NULL
ORDER BY v.id_jugador;

INSERT INTO @xml (reporte)
EXEC Reportes.usp_SeleccionesYPlantillasXML @id_seleccion = @id_seleccion;

SELECT @jugador AS jugador_buscado, reporte FROM @xml;
SELECT @texto = CONVERT(NVARCHAR(MAX), reporte) FROM @xml;

IF CHARINDEX(N'<Nombre>' + @jugador + N'</Nombre>', @texto) > 0 AND CHARINDEX(N'<Nombre> </Nombre>', @texto) = 0
    PRINT N'OK     7. Reportes.usp_SeleccionesYPlantillasXML arma el XML con los nombres descifrados.';
ELSE
    PRINT N'ERROR  7. El XML de Reportes.usp_SeleccionesYPlantillasXML no tiene al jugador buscado o tiene nombres vacíos.';
GO


/* Caso 8: un jugador dado de alta con usp_JUGADOR_Alta aparece descifrado en
   Reportes.vw_Plantillas. Se da de baja primero a un jugador de la lista,
   para dejar lugar al de prueba, y todo se deshace al final. */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_lista INT, @id_baja INT, @id_jugador INT;

    SELECT TOP (1) @id_lista = id_lista, @id_baja = id_jugador FROM Torneo.JUGADOR
    WHERE fecha_baja IS NULL AND posicion_habitual <> 'ARQUERO' ORDER BY id_lista, dorsal;
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_baja, @motivo_baja = 'Prueba de cifrado', @fecha_baja = '2026-06-02';

    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
         @posicion_habitual = 'DEFENSOR', @dorsal = 99, @id_jugador = @id_jugador OUTPUT;

    SELECT * FROM Reportes.vw_Plantillas WHERE id_jugador = @id_jugador;

    IF EXISTS (SELECT 1 FROM Reportes.vw_Plantillas WHERE id_jugador = @id_jugador AND nombre = N'Ñandú' AND apellido = N'Pérez Cifrado')
        PRINT N'OK     8. El jugador dado de alta aparece descifrado en Reportes.vw_Plantillas.';
    ELSE
        PRINT N'ERROR  8. El jugador dado de alta no aparece descifrado en Reportes.vw_Plantillas.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  8. Falló el alta del jugador: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
