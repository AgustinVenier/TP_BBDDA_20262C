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

 Fecha: 09/11/2026
 Archivo: 93_Test_Cifrado_Torneo.sql
 Objetivo: Probar los SP de Torneo que modifica 43_Cifrado_Torneo.sql: que el
           alta y la modificación de jugadores (usp_JUGADOR_Alta y
           usp_JUGADOR_Modificacion) y de cuerpos técnicos
           (usp_PERSONA_CUERPO_TECNICO_Alta y
           usp_PERSONA_CUERPO_TECNICO_Modificacion) guarden cifrado lo que
           escriben, que se lea descifrado, que controlen los duplicados
           comparando los datos descifrados (en lugar de la restricción UNIQUE
           que se eliminó) y que cierren la clave al terminar, también cuando
           fallan.
================================================================================

 Requiere haber ejecutado 40_Ejecutar_Cifrado.sql y tener cargadas las listas
 de convocados (32). Ejecutar como dueño de la base (dbo). Todo se hace dentro
 de una transacción que se deshace, así no queda nada. Si algún control no da
 lo esperado, el script termina con error.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM Torneo.JUGADOR)
    THROW 51013, N'No hay jugadores cargados. Ejecute primero las importaciones (30 a 35).', 1;
GO

DECLARE @controles TABLE (n INT IDENTITY, control NVARCHAR(200), esperado NVARCHAR(200), obtenido NVARCHAR(400));
DECLARE @id_lista INT, @id_seleccion INT, @libre INT, @id INT, @otro_nombre NVARCHAR(60), @otro_apellido NVARCHAR(60),
        @id_ct1 INT, @id_ct2 INT, @guardado VARBINARY(256), @fecha_guardada VARBINARY(256);

-- La primera lista, y un jugador que no sea arquero para darlo de baja y dejar lugar al de prueba.
SELECT TOP (1) @id_lista = id_lista, @id_seleccion = id_seleccion FROM Torneo.LISTA_CONVOCADOS ORDER BY id_lista;
SELECT TOP (1) @libre = id_jugador FROM Torneo.JUGADOR
WHERE id_lista = @id_lista AND fecha_baja IS NULL AND posicion_habitual <> 'ARQUERO' ORDER BY dorsal;
-- Otro jugador de la misma lista, para la modificación que lo repite.
SELECT TOP (1) @otro_nombre = nombre, @otro_apellido = apellido FROM Seguridad.vw_Jugador
WHERE id_lista = @id_lista AND fecha_baja IS NULL AND id_jugador <> @libre ORDER BY dorsal;

BEGIN TRY
    BEGIN TRANSACTION;

    /* 1. usp_JUGADOR_Alta cifra nombre, apellido y fecha de nacimiento, y se lee descifrado. */
    EXEC Torneo.usp_JUGADOR_Baja @id_jugador = @libre, @motivo_baja = 'Prueba de cifrado', @fecha_baja = '2026-06-02';
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
         @posicion_habitual = 'DEFENSOR', @dorsal = 99, @fecha_nacimiento = '2001-02-03', @id_jugador = @id OUTPUT;
    SELECT @guardado = apellido, @fecha_guardada = fecha_nacimiento FROM Torneo.JUGADOR WHERE id_jugador = @id;
    INSERT INTO @controles (control, esperado, obtenido)
    VALUES (N'usp_JUGADOR_Alta: apellido y fecha guardados', N'cifrados',
            IIF(@guardado IS NULL OR @fecha_guardada IS NULL, N'NULL',
                IIF(CONVERT(NVARCHAR(60), @guardado) = N'Pérez Cifrado', N'en texto', N'cifrados')));
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_JUGADOR_Alta: leído en Seguridad.vw_Jugador', N'Ñandú Pérez Cifrado 2001-02-03',
           CONCAT(nombre, N' ', apellido, N' ', fecha_nacimiento)
    FROM Seguridad.vw_Jugador WHERE id_jugador = @id;
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_JUGADOR_Alta: claves abiertas al terminar', N'0', CAST(COUNT(*) AS NVARCHAR(10)) FROM sys.openkeys;

    /* 2. usp_JUGADOR_Alta rechaza al mismo jugador en la misma lista (los bytes
          cifrados son distintos: el control compara los datos descifrados). */
    BEGIN TRY
        EXEC Torneo.usp_JUGADOR_Alta @id_lista = @id_lista, @nombre = N'Ñandú', @apellido = N'Pérez Cifrado',
             @posicion_habitual = 'DEFENSOR', @dorsal = 98;
        INSERT INTO @controles (control, esperado, obtenido) VALUES (N'usp_JUGADOR_Alta del mismo jugador', N'rechazada', N'aceptada');
    END TRY
    BEGIN CATCH
        INSERT INTO @controles (control, esperado, obtenido)
        VALUES (N'usp_JUGADOR_Alta del mismo jugador', N'rechazada',
                IIF(ERROR_MESSAGE() LIKE N'%ya figura en la lista%', N'rechazada', LEFT(ERROR_MESSAGE(), 400)));
    END CATCH;
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_JUGADOR_Alta rechazada: claves abiertas al terminar', N'0', CAST(COUNT(*) AS NVARCHAR(10)) FROM sys.openkeys;

    /* 3. usp_JUGADOR_Modificacion cifra lo que cambia y deja lo demás. */
    EXEC Torneo.usp_JUGADOR_Modificacion @id_jugador = @id, @apellido = N'Pérez Modificado', @fecha_nacimiento = '2001-04-05';
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_JUGADOR_Modificacion: leído en Seguridad.vw_Jugador', N'Ñandú Pérez Modificado 2001-04-05',
           CONCAT(nombre, N' ', apellido, N' ', fecha_nacimiento)
    FROM Seguridad.vw_Jugador WHERE id_jugador = @id;
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_JUGADOR_Modificacion: apellido guardado', N'cifrado',
           IIF(apellido IS NULL, N'NULL', IIF(CONVERT(NVARCHAR(60), apellido) = N'Pérez Modificado', N'en texto', N'cifrado'))
    FROM Torneo.JUGADOR WHERE id_jugador = @id;

    /* 4. usp_JUGADOR_Modificacion rechaza el nombre y apellido de otro jugador de la lista. */
    BEGIN TRY
        EXEC Torneo.usp_JUGADOR_Modificacion @id_jugador = @id, @nombre = @otro_nombre, @apellido = @otro_apellido;
        INSERT INTO @controles (control, esperado, obtenido)
        VALUES (N'usp_JUGADOR_Modificacion con el nombre de otro jugador de la lista', N'rechazada', N'aceptada');
    END TRY
    BEGIN CATCH
        INSERT INTO @controles (control, esperado, obtenido)
        VALUES (N'usp_JUGADOR_Modificacion con el nombre de otro jugador de la lista', N'rechazada',
                IIF(ERROR_MESSAGE() LIKE N'%Ya hay otro%en la lista%', N'rechazada', LEFT(ERROR_MESSAGE(), 400)));
    END CATCH;

    /* 5. usp_PERSONA_CUERPO_TECNICO_Alta cifra lo que guarda y se lee descifrado. */
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_seleccion, @nombre = N'Íñigo', @apellido = N'Médico Cifrado',
         @rol = 'MEDICO', @fecha_nacimiento = '1975-08-09', @id_persona_ct = @id_ct1 OUTPUT;
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Alta @id_seleccion = @id_seleccion, @nombre = N'Otra', @apellido = N'Persona Cifrada',
         @rol = 'OTRO', @id_persona_ct = @id_ct2 OUTPUT;
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_PERSONA_CUERPO_TECNICO_Alta: apellido guardado', N'cifrado',
           IIF(apellido IS NULL, N'NULL', IIF(CONVERT(NVARCHAR(60), apellido) = N'Médico Cifrado', N'en texto', N'cifrado'))
    FROM Torneo.PERSONA_CUERPO_TECNICO WHERE id_persona_ct = @id_ct1;
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_PERSONA_CUERPO_TECNICO_Alta: leído en Seguridad.vw_PersonaCuerpoTecnico',
           N'Íñigo Médico Cifrado 1975-08-09 MEDICO', CONCAT(nombre, N' ', apellido, N' ', fecha_nacimiento, N' ', rol)
    FROM Seguridad.vw_PersonaCuerpoTecnico WHERE id_persona_ct = @id_ct1;

    /* 6. usp_PERSONA_CUERPO_TECNICO_Modificacion cifra lo que cambia y rechaza
          el nombre de otra persona del mismo cuerpo técnico. */
    EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Modificacion @id_persona_ct = @id_ct2, @nombre = N'Otro', @fecha_nacimiento = '1980-01-01';
    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'usp_PERSONA_CUERPO_TECNICO_Modificacion: leído descifrado', N'Otro Persona Cifrada 1980-01-01',
           CONCAT(nombre, N' ', apellido, N' ', fecha_nacimiento)
    FROM Seguridad.vw_PersonaCuerpoTecnico WHERE id_persona_ct = @id_ct2;
    BEGIN TRY
        EXEC Torneo.usp_PERSONA_CUERPO_TECNICO_Modificacion @id_persona_ct = @id_ct2, @nombre = N'Íñigo', @apellido = N'Médico Cifrado';
        INSERT INTO @controles (control, esperado, obtenido)
        VALUES (N'usp_PERSONA_CUERPO_TECNICO_Modificacion con el nombre de otra persona', N'rechazada', N'aceptada');
    END TRY
    BEGIN CATCH
        INSERT INTO @controles (control, esperado, obtenido)
        VALUES (N'usp_PERSONA_CUERPO_TECNICO_Modificacion con el nombre de otra persona', N'rechazada',
                IIF(ERROR_MESSAGE() LIKE N'%Ya hay otro%en el cuerpo técnico%', N'rechazada', LEFT(ERROR_MESSAGE(), 400)));
    END CATCH;

    INSERT INTO @controles (control, esperado, obtenido)
    SELECT N'Claves abiertas al terminar los SP', N'0', CAST(COUNT(*) AS NVARCHAR(10)) FROM sys.openkeys;
END TRY
BEGIN CATCH
    INSERT INTO @controles (control, esperado, obtenido)
    VALUES (N'Error inesperado', N'ninguno', CONCAT(N'error ', ERROR_NUMBER(), N': ', LEFT(ERROR_MESSAGE(), 350)));
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

/* 7. Después del ROLLBACK no queda nada de prueba. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Personas de prueba que quedaron', N'0',
       CAST((SELECT COUNT(*) FROM Seguridad.vw_Jugador WHERE apellido LIKE N'Pérez %' AND nombre = N'Ñandú')
          + (SELECT COUNT(*) FROM Seguridad.vw_PersonaCuerpoTecnico WHERE apellido IN (N'Médico Cifrado', N'Persona Cifrada'))
            AS NVARCHAR(10));

SELECT n, control, esperado, obtenido, IIF(esperado = obtenido, N'OK', N'FALLÓ') AS resultado
FROM @controles
ORDER BY n;

IF EXISTS (SELECT 1 FROM @controles WHERE esperado <> obtenido)
    THROW 51014, N'Los SP de Torneo con cifrado (43) no dan lo esperado.', 1;
GO
