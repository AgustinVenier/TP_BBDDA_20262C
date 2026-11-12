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
 Archivo: 95_Test_Cifrado_Torneo.sql
 Objetivo: Probar los SP de Torneo que modifica 45_Cifrado_Torneo.sql: que el
           alta y la modificación de jugadores (usp_JUGADOR_Alta y
           usp_JUGADOR_Modificacion) y de cuerpos técnicos
           (usp_PERSONA_CUERPO_TECNICO_Alta y
           usp_PERSONA_CUERPO_TECNICO_Modificacion) y la convocatoria inicial
           (usp_RegistrarConvocatoria) guarden cifrado lo que escriben, que se
           lea descifrado y que rechacen los duplicados comparando los datos
           descifrados (en lugar de la restricción UNIQUE que se eliminó).
================================================================================

 Requiere haber ejecutado 40_Ejecutar_Cifrado.sql y tener cargadas las listas
 de convocados (32). Ejecutar como dueño de la base (dbo).

 Cada caso es independiente y se puede ejecutar solo. Hace sus altas de
 prueba dentro de una transacción que se deshace al final, así no queda nada;
 muestra lo que guardó en la grilla e imprime una línea en la pestaña
 Mensajes:
   OK     dio lo esperado (en los rechazos, con el mensaje del SP).
   ERROR  dio otra cosa.
 El test está bien si ninguna línea empieza con ERROR.

 Los casos de jugadores dan de baja primero a un jugador de la lista, para
 dejar lugar al de prueba (la lista está completa).
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM Torneo.JUGADOR)
    THROW 51013, N'No hay jugadores cargados. Ejecute primero las importaciones (31 a 35).', 1;
GO


/* Caso 1: usp_JUGADOR_Alta guarda cifrados el nombre, el apellido y la fecha
   de nacimiento, y la vista los devuelve descifrados. */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_lista INT, @id_baja INT, @id_jugador INT;

    SELECT TOP (1) @id_lista = id_lista, @id_baja = id_jugador FROM Torneo.JUGADOR
    WHERE fecha_baja IS NULL AND posicion_habitual <> 'ARQUERO' ORDER BY id_lista, dorsal;
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_baja, @motivo_baja = 'Prueba de cifrado', @fecha_baja = '2026-06-02';

    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
         @posicion_habitual = 'DEFENSOR', @dorsal = 99, @fecha_nacimiento = '2001-02-03', @id_jugador = @id_jugador OUTPUT;

    SELECT t.apellido AS apellido_guardado, v.nombre, v.apellido, v.fecha_nacimiento
    FROM Torneo.JUGADOR AS t
    INNER JOIN Seguridad.vw_Jugador AS v ON v.id_jugador = t.id_jugador
    WHERE t.id_jugador = @id_jugador;

    IF EXISTS (SELECT 1 FROM Seguridad.vw_Jugador
               WHERE id_jugador = @id_jugador AND nombre = N'Ñandú' AND apellido = N'Pérez Cifrado' AND fecha_nacimiento = '2001-02-03')
        PRINT N'OK     1. usp_JUGADOR_Alta guardó al jugador cifrado y se lee descifrado.';
    ELSE
        PRINT N'ERROR  1. El jugador dado de alta no se lee descifrado en Seguridad.vw_Jugador.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  1. Falló el alta del jugador: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 2: usp_JUGADOR_Alta rechaza al mismo jugador dos veces en la lista.
   Los bytes cifrados de los dos son distintos: el SP compara los datos
   descifrados. */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_lista INT, @id_baja INT;

    SELECT TOP (1) @id_lista = id_lista, @id_baja = id_jugador FROM Torneo.JUGADOR
    WHERE fecha_baja IS NULL AND posicion_habitual <> 'ARQUERO' ORDER BY id_lista, dorsal;
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_baja, @motivo_baja = 'Prueba de cifrado', @fecha_baja = '2026-06-02';

    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
         @posicion_habitual = 'DEFENSOR', @dorsal = 99;
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
         @posicion_habitual = 'DEFENSOR', @dorsal = 98;   -- el mismo: tiene que fallar

    PRINT N'ERROR  2. usp_JUGADOR_Alta aceptó dos veces al mismo jugador en la lista.';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE N'%ya figura en la lista%'
        PRINT N'OK     2. usp_JUGADOR_Alta rechazó al jugador repetido: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  2. Falló por otro motivo: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 3: usp_JUGADOR_Modificacion cifra lo que cambia (apellido y fecha) y
   deja lo demás (nombre). */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_lista INT, @id_baja INT, @id_jugador INT;

    SELECT TOP (1) @id_lista = id_lista, @id_baja = id_jugador FROM Torneo.JUGADOR
    WHERE fecha_baja IS NULL AND posicion_habitual <> 'ARQUERO' ORDER BY id_lista, dorsal;
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_baja, @motivo_baja = 'Prueba de cifrado', @fecha_baja = '2026-06-02';
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
         @posicion_habitual = 'DEFENSOR', @dorsal = 99, @fecha_nacimiento = '2001-02-03', @id_jugador = @id_jugador OUTPUT;

    EXEC Torneo.usp_JUGADOR_Modificacion @id_jugador = @id_jugador, @apellido = N'Pérez Modificado', @fecha_nacimiento = '2001-04-05';

    SELECT t.apellido AS apellido_guardado, v.nombre, v.apellido, v.fecha_nacimiento
    FROM Torneo.JUGADOR AS t
    INNER JOIN Seguridad.vw_Jugador AS v ON v.id_jugador = t.id_jugador
    WHERE t.id_jugador = @id_jugador;

    IF EXISTS (SELECT 1 FROM Seguridad.vw_Jugador
               WHERE id_jugador = @id_jugador AND nombre = N'Ñandú' AND apellido = N'Pérez Modificado' AND fecha_nacimiento = '2001-04-05')
        PRINT N'OK     3. usp_JUGADOR_Modificacion guardó el cambio cifrado y se lee descifrado.';
    ELSE
        PRINT N'ERROR  3. El jugador modificado no se lee descifrado en Seguridad.vw_Jugador.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  3. Falló la modificación del jugador: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 4: usp_JUGADOR_Modificacion rechaza ponerle a un jugador el nombre y
   el apellido de otro de la misma lista. */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_lista INT, @id_baja INT, @id_jugador INT, @otro_nombre NVARCHAR(60), @otro_apellido NVARCHAR(60);

    SELECT TOP (1) @id_lista = id_lista, @id_baja = id_jugador FROM Torneo.JUGADOR
    WHERE fecha_baja IS NULL AND posicion_habitual <> 'ARQUERO' ORDER BY id_lista, dorsal;
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @id_baja, @motivo_baja = 'Prueba de cifrado', @fecha_baja = '2026-06-02';
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
         @posicion_habitual = 'DEFENSOR', @dorsal = 99, @id_jugador = @id_jugador OUTPUT;

    -- Otro jugador activo de la misma lista.
    SELECT TOP (1) @otro_nombre = nombre, @otro_apellido = apellido FROM Seguridad.vw_Jugador
    WHERE id_lista = @id_lista AND fecha_baja IS NULL AND id_jugador <> @id_jugador ORDER BY dorsal;

    EXEC Torneo.usp_JUGADOR_Modificacion @id_jugador = @id_jugador, @nombre = @otro_nombre, @apellido = @otro_apellido;   -- tiene que fallar

    PRINT N'ERROR  4. usp_JUGADOR_Modificacion aceptó el nombre de otro jugador de la lista.';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE N'%Ya hay otro%en la lista%'
        PRINT N'OK     4. usp_JUGADOR_Modificacion rechazó el nombre repetido: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  4. Falló por otro motivo: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 5: usp_PERSONA_CUERPO_TECNICO_Alta guarda cifrado y se lee descifrado. */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_seleccion INT, @id_persona_ct INT;

    SELECT TOP (1) @id_seleccion = id_seleccion FROM Torneo.SELECCION ORDER BY id_seleccion;

    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_seleccion, @nombre = N'Íñigo', @apellido = N'Médico Cifrado',
         @rol = 'MEDICO', @fecha_nacimiento = '1975-08-09', @id_persona_ct = @id_persona_ct OUTPUT;

    SELECT t.apellido AS apellido_guardado, v.nombre, v.apellido, v.fecha_nacimiento, v.rol
    FROM Torneo.PERSONA_CUERPO_TECNICO AS t
    INNER JOIN Seguridad.vw_PersonaCuerpoTecnico AS v ON v.id_persona_ct = t.id_persona_ct
    WHERE t.id_persona_ct = @id_persona_ct;

    IF EXISTS (SELECT 1 FROM Seguridad.vw_PersonaCuerpoTecnico
               WHERE id_persona_ct = @id_persona_ct AND nombre = N'Íñigo' AND apellido = N'Médico Cifrado' AND fecha_nacimiento = '1975-08-09')
        PRINT N'OK     5. usp_PERSONA_CUERPO_TECNICO_Alta guardó a la persona cifrada y se lee descifrada.';
    ELSE
        PRINT N'ERROR  5. La persona dada de alta no se lee descifrada en Seguridad.vw_PersonaCuerpoTecnico.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  5. Falló el alta de la persona del cuerpo técnico: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 6: usp_PERSONA_CUERPO_TECNICO_Modificacion cifra lo que cambia (nombre
   y fecha) y deja lo demás (apellido). */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_seleccion INT, @id_persona_ct INT;

    SELECT TOP (1) @id_seleccion = id_seleccion FROM Torneo.SELECCION ORDER BY id_seleccion;
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_seleccion, @nombre = N'Otra', @apellido = N'Persona Cifrada',
         @rol = 'OTRO', @id_persona_ct = @id_persona_ct OUTPUT;

    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Modificacion @id_persona_ct = @id_persona_ct, @nombre = N'Otro', @fecha_nacimiento = '1980-01-01';

    SELECT t.apellido AS apellido_guardado, v.nombre, v.apellido, v.fecha_nacimiento, v.rol
    FROM Torneo.PERSONA_CUERPO_TECNICO AS t
    INNER JOIN Seguridad.vw_PersonaCuerpoTecnico AS v ON v.id_persona_ct = t.id_persona_ct
    WHERE t.id_persona_ct = @id_persona_ct;

    IF EXISTS (SELECT 1 FROM Seguridad.vw_PersonaCuerpoTecnico
               WHERE id_persona_ct = @id_persona_ct AND nombre = N'Otro' AND apellido = N'Persona Cifrada' AND fecha_nacimiento = '1980-01-01')
        PRINT N'OK     6. usp_PERSONA_CUERPO_TECNICO_Modificacion guardó el cambio cifrado y se lee descifrado.';
    ELSE
        PRINT N'ERROR  6. La persona modificada no se lee descifrada en Seguridad.vw_PersonaCuerpoTecnico.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  6. Falló la modificación de la persona del cuerpo técnico: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 7: usp_PERSONA_CUERPO_TECNICO_Modificacion rechaza ponerle a una
   persona el nombre y el apellido de otra del mismo cuerpo técnico. */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_seleccion INT, @id_persona_ct INT;

    SELECT TOP (1) @id_seleccion = id_seleccion FROM Torneo.SELECCION ORDER BY id_seleccion;
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_seleccion, @nombre = N'Íñigo', @apellido = N'Médico Cifrado',
         @rol = 'MEDICO';
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_seleccion, @nombre = N'Otra', @apellido = N'Persona Cifrada',
         @rol = 'OTRO', @id_persona_ct = @id_persona_ct OUTPUT;

    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Modificacion @id_persona_ct = @id_persona_ct, @nombre = N'Íñigo', @apellido = N'Médico Cifrado';   -- tiene que fallar

    PRINT N'ERROR  7. usp_PERSONA_CUERPO_TECNICO_Modificacion aceptó el nombre de otra persona del cuerpo técnico.';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE N'%Ya hay otro%en el cuerpo técnico%'
        PRINT N'OK     7. usp_PERSONA_CUERPO_TECNICO_Modificacion rechazó el nombre repetido: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  7. Falló por otro motivo: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 8: usp_RegistrarConvocatoria guarda cifrados a los 23 jugadores de una
   lista inicial y se leen descifrados. Se arma una selección de prueba con un
   país que no participa. */
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_pais SMALLINT, @id_seleccion INT, @id_lista INT;
    DECLARE @lista Torneo.TT_CONVOCADO;

    SELECT TOP (1) @id_pais = id_pais FROM DatosGenerales.PAIS
    WHERE id_pais NOT IN (SELECT id_pais FROM Torneo.SELECCION) ORDER BY id_pais;
    INSERT INTO Torneo.SELECCION (id_pais, confederacion, grupo) VALUES (@id_pais, 'UEFA', NULL);
    SET @id_seleccion = SCOPE_IDENTITY();
    INSERT INTO Torneo.LISTA_CONVOCADOS (id_seleccion, fecha_presentacion) VALUES (@id_seleccion, '2026-06-01');
    SET @id_lista = SCOPE_IDENTITY();

    -- 3 arqueros, 8 defensores, 6 mediocampistas y 6 delanteros.
    INSERT INTO @lista (nombre, apellido, posicion_habitual, dorsal, fecha_nacimiento, club_origen)
    SELECT N'Convocado', CONCAT(N'Prueba Convocatoria ', d.dorsal), d.posicion, d.dorsal, '1998-01-01', N'Club Prueba'
    FROM (VALUES (1, 'ARQUERO'), (12, 'ARQUERO'), (23, 'ARQUERO'),
                 (2, 'DEFENSOR'), (3, 'DEFENSOR'), (4, 'DEFENSOR'), (5, 'DEFENSOR'), (6, 'DEFENSOR'),
                 (13, 'DEFENSOR'), (14, 'DEFENSOR'), (15, 'DEFENSOR'),
                 (7, 'MEDIOCAMPISTA'), (8, 'MEDIOCAMPISTA'), (10, 'MEDIOCAMPISTA'), (16, 'MEDIOCAMPISTA'),
                 (17, 'MEDIOCAMPISTA'), (18, 'MEDIOCAMPISTA'),
                 (9, 'DELANTERO'), (11, 'DELANTERO'), (19, 'DELANTERO'), (20, 'DELANTERO'), (21, 'DELANTERO'),
                 (22, 'DELANTERO')) AS d (dorsal, posicion);

    EXEC Torneo.usp_RegistrarConvocatoria @id_seleccion = @id_seleccion, @jugadores = @lista, @mostrar_resultados = 0;

    SELECT TOP (5) t.apellido AS apellido_guardado, v.nombre, v.apellido, v.dorsal
    FROM Torneo.JUGADOR AS t
    INNER JOIN Seguridad.vw_Jugador AS v ON v.id_jugador = t.id_jugador
    WHERE t.id_lista = @id_lista
    ORDER BY v.dorsal;

    IF (SELECT COUNT(*) FROM Seguridad.vw_Jugador
        WHERE id_lista = @id_lista AND nombre = N'Convocado' AND apellido LIKE N'Prueba Convocatoria %') = 23
        PRINT N'OK     8. usp_RegistrarConvocatoria guardó a los 23 jugadores cifrados y se leen descifrados.';
    ELSE
        PRINT N'ERROR  8. Los 23 jugadores de la convocatoria no se leen descifrados en Seguridad.vw_Jugador.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  8. Falló la convocatoria: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO


/* Caso 9: después de los casos anteriores no queda ninguna clave abierta
   (los SP la cierran al terminar, también cuando fallan) ni datos de prueba. */
SELECT key_name AS clave_abierta FROM sys.openkeys;

IF EXISTS (SELECT 1 FROM sys.openkeys)
    PRINT N'ERROR  9. Quedó una clave abierta en la sesión.';
ELSE IF EXISTS (SELECT 1 FROM Seguridad.vw_Jugador WHERE apellido LIKE N'Pérez %' AND nombre = N'Ñandú')
     OR EXISTS (SELECT 1 FROM Seguridad.vw_Jugador WHERE apellido LIKE N'Prueba Convocatoria %')
     OR EXISTS (SELECT 1 FROM Seguridad.vw_PersonaCuerpoTecnico WHERE apellido IN (N'Médico Cifrado', N'Persona Cifrada'))
    PRINT N'ERROR  9. Quedaron personas de prueba guardadas.';
ELSE
    PRINT N'OK     9. No queda ninguna clave abierta ni personas de prueba.';
GO
