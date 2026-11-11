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
 Archivo: 96_Test_Cifrado_DesarrolloYArbitraje.sql
 Objetivo: Probar los objetos de DesarrolloPartido y Arbitraje que modifica
           46_Cifrado_DesarrolloYArbitraje.sql: que las vistas y la función
           que muestran personas (vw_Goleadores, vw_HistorialTitularidad,
           vw_HistorialArbitro y fn_EquipoEnCancha) devuelvan los nombres
           descifrados; y que el alta y la modificación de árbitros
           (usp_ARBITRO_Alta y usp_ARBITRO_Modificacion) guarden cifrado lo
           que escriben, se lea descifrado y rechacen los duplicados
           comparando los datos descifrados.
================================================================================

 Requiere haber ejecutado 40_Ejecutar_Cifrado.sql y tener cargado el torneo
 (32), con goles, formaciones y designaciones. Ejecutar como dueño de la base
 (dbo).

 Cada caso es independiente y se puede ejecutar solo. Los que dan de alta
 árbitros de prueba lo hacen dentro de una transacción que se deshace al
 final, así no queda nada. Cada caso muestra lo que probó en la grilla e
 imprime una línea en la pestaña Mensajes:
   OK     dio lo esperado (en los rechazos, con el mensaje del SP).
   ERROR  dio otra cosa.
 El test está bien si ninguna línea empieza con ERROR.

 En las vistas, si una persona no se pudiera descifrar, su nombre y su
 apellido saldrían NULL: eso es lo que controlan los casos 1 a 4.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM DesarrolloPartido.GOL) OR NOT EXISTS (SELECT 1 FROM Arbitraje.DESIGNACION_ARBITRAL)
    THROW 51013, N'No hay partidos jugados cargados. Ejecute primero las importaciones (30 a 35).', 1;
GO


/* Caso 1: DesarrolloPartido.vw_Goleadores muestra los nombres descifrados. */
SELECT TOP (5) * FROM DesarrolloPartido.vw_Goleadores;

IF EXISTS (SELECT 1 FROM DesarrolloPartido.vw_Goleadores WHERE apellido IS NULL OR nombre IS NULL)
    PRINT N'ERROR  1. DesarrolloPartido.vw_Goleadores tiene goleadores sin nombre: no los descifra.';
ELSE
    PRINT N'OK     1. DesarrolloPartido.vw_Goleadores muestra los nombres descifrados.';
GO


/* Caso 2: DesarrolloPartido.vw_HistorialTitularidad muestra los nombres
   descifrados. */
SELECT TOP (5) * FROM DesarrolloPartido.vw_HistorialTitularidad;

IF EXISTS (SELECT 1 FROM DesarrolloPartido.vw_HistorialTitularidad WHERE apellido IS NULL OR nombre IS NULL)
    PRINT N'ERROR  2. DesarrolloPartido.vw_HistorialTitularidad tiene jugadores sin nombre: no los descifra.';
ELSE
    PRINT N'OK     2. DesarrolloPartido.vw_HistorialTitularidad muestra los nombres descifrados.';
GO


/* Caso 3: Arbitraje.vw_HistorialArbitro muestra los nombres descifrados. */
SELECT TOP (5) * FROM Arbitraje.vw_HistorialArbitro;

IF EXISTS (SELECT 1 FROM Arbitraje.vw_HistorialArbitro WHERE apellido IS NULL OR nombre IS NULL)
    PRINT N'ERROR  3. Arbitraje.vw_HistorialArbitro tiene árbitros sin nombre: no los descifra.';
ELSE
    PRINT N'OK     3. Arbitraje.vw_HistorialArbitro muestra los nombres descifrados.';
GO


/* Caso 4: DesarrolloPartido.fn_EquipoEnCancha muestra los nombres descifrados
   (el equipo de un partido con formación, al minuto 1). */
DECLARE @id_partido INT, @id_seleccion INT;

SELECT TOP (1) @id_partido = id_partido, @id_seleccion = id_seleccion FROM DesarrolloPartido.FORMACION ORDER BY id_partido;

SELECT * FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion, 1, 0);

IF NOT EXISTS (SELECT 1 FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion, 1, 0))
    PRINT N'ERROR  4. DesarrolloPartido.fn_EquipoEnCancha no devolvió jugadores.';
ELSE IF EXISTS (SELECT 1 FROM DesarrolloPartido.fn_EquipoEnCancha(@id_partido, @id_seleccion, 1, 0)
                WHERE apellido IS NULL OR nombre IS NULL)
    PRINT N'ERROR  4. DesarrolloPartido.fn_EquipoEnCancha tiene jugadores sin nombre: no los descifra.';
ELSE
    PRINT N'OK     4. DesarrolloPartido.fn_EquipoEnCancha muestra los nombres descifrados.';
GO


/* Caso 5: usp_ARBITRO_Alta guarda cifrados el nombre, el apellido y la fecha
   de nacimiento, y la vista los devuelve descifrados. */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_pais SMALLINT, @id INT;

    SELECT TOP (1) @id_pais = id_pais FROM DatosGenerales.PAIS ORDER BY id_pais;

    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Ñuño', @apellido = N'Árbitro Cifrado',
         @categoria = 'FIFA', @fecha_nacimiento = '1984-10-11', @id_arbitro = @id OUTPUT;

    SELECT t.apellido AS apellido_guardado, v.nombre, v.apellido, v.fecha_nacimiento
    FROM Arbitraje.ARBITRO AS t
    INNER JOIN Seguridad.vw_Arbitro AS v ON v.id_arbitro = t.id_arbitro
    WHERE t.id_arbitro = @id;

    IF EXISTS (SELECT 1 FROM Seguridad.vw_Arbitro
               WHERE id_arbitro = @id AND nombre = N'Ñuño' AND apellido = N'Árbitro Cifrado' AND fecha_nacimiento = '1984-10-11')
        PRINT N'OK     5. usp_ARBITRO_Alta guardó al árbitro cifrado y se lee descifrado.';
    ELSE
        PRINT N'ERROR  5. El árbitro dado de alta no se lee descifrado en Seguridad.vw_Arbitro.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  5. Falló el alta del árbitro: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 6: usp_ARBITRO_Alta rechaza al mismo árbitro dos veces en el mismo
   país. Los bytes cifrados de los dos son distintos: el SP compara los datos
   descifrados. */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_pais SMALLINT;

    SELECT TOP (1) @id_pais = id_pais FROM DatosGenerales.PAIS ORDER BY id_pais;

    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Ñuño', @apellido = N'Árbitro Cifrado', @categoria = 'FIFA';
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Ñuño', @apellido = N'Árbitro Cifrado', @categoria = 'FIFA';   -- el mismo: tiene que fallar

    PRINT N'ERROR  6. usp_ARBITRO_Alta aceptó dos veces al mismo árbitro.';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE N'%Ya hay un árbitro%'
        PRINT N'OK     6. usp_ARBITRO_Alta rechazó al árbitro repetido: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  6. Falló por otro motivo: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 7: usp_ARBITRO_Modificacion cifra lo que cambia (apellido y fecha) y
   deja lo demás (nombre). */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_pais SMALLINT, @id INT;

    SELECT TOP (1) @id_pais = id_pais FROM DatosGenerales.PAIS ORDER BY id_pais;
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Otro', @apellido = N'Árbitro Prueba',
         @categoria = 'FIFA', @id_arbitro = @id OUTPUT;

    EXEC Arbitraje.usp_ARBITRO_Modificacion @id_arbitro = @id, @apellido = N'Árbitro Modificado', @fecha_nacimiento = '1990-12-13';

    SELECT t.apellido AS apellido_guardado, v.nombre, v.apellido, v.fecha_nacimiento
    FROM Arbitraje.ARBITRO AS t
    INNER JOIN Seguridad.vw_Arbitro AS v ON v.id_arbitro = t.id_arbitro
    WHERE t.id_arbitro = @id;

    IF EXISTS (SELECT 1 FROM Seguridad.vw_Arbitro
               WHERE id_arbitro = @id AND nombre = N'Otro' AND apellido = N'Árbitro Modificado' AND fecha_nacimiento = '1990-12-13')
        PRINT N'OK     7. usp_ARBITRO_Modificacion guardó el cambio cifrado y se lee descifrado.';
    ELSE
        PRINT N'ERROR  7. El árbitro modificado no se lee descifrado en Seguridad.vw_Arbitro.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  7. Falló la modificación del árbitro: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 8: usp_ARBITRO_Modificacion rechaza ponerle a un árbitro el nombre y
   el apellido de otro del mismo país. */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_pais SMALLINT, @id INT;

    SELECT TOP (1) @id_pais = id_pais FROM DatosGenerales.PAIS ORDER BY id_pais;
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Ñuño', @apellido = N'Árbitro Cifrado', @categoria = 'FIFA';
    EXEC Arbitraje.usp_ARBITRO_Alta @id_pais = @id_pais, @nombre = N'Otro', @apellido = N'Árbitro Prueba',
         @categoria = 'FIFA', @id_arbitro = @id OUTPUT;

    EXEC Arbitraje.usp_ARBITRO_Modificacion @id_arbitro = @id, @nombre = N'Ñuño', @apellido = N'Árbitro Cifrado';   -- tiene que fallar

    PRINT N'ERROR  8. usp_ARBITRO_Modificacion aceptó el nombre de otro árbitro del país.';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE N'%Ya hay otro árbitro%'
        PRINT N'OK     8. usp_ARBITRO_Modificacion rechazó el nombre repetido: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  8. Falló por otro motivo: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 9: después de los casos anteriores no queda ninguna clave abierta
   (los SP la cierran al terminar, también cuando fallan) ni árbitros de
   prueba. */
SELECT key_name AS clave_abierta FROM sys.openkeys;

IF EXISTS (SELECT 1 FROM sys.openkeys)
    PRINT N'ERROR  9. Quedó una clave abierta en la sesión.';
ELSE IF EXISTS (SELECT 1 FROM Seguridad.vw_Arbitro
                WHERE apellido IN (N'Árbitro Cifrado', N'Árbitro Prueba', N'Árbitro Modificado'))
    PRINT N'ERROR  9. Quedaron árbitros de prueba guardados.';
ELSE
    PRINT N'OK     9. No queda ninguna clave abierta ni árbitros de prueba.';
GO
