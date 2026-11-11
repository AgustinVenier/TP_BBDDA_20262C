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
 Archivo: 78_Test_Rol_CargadorResultados.sql
 Objetivo: Probar lo que puede y lo que no puede hacer el usuario
           usr_test_cargador_resultados (rol_CargadorResultados).
================================================================================

 Requiere haber ejecutado 00_Ejecutar_PrepararBase.sql (roles), las
 importaciones y 40_Ejecutar_Cifrado.sql.

 usr_test_cargador_resultados es un usuario SIN LOGIN: nadie puede iniciar
 sesión con él. Cada caso se ejecuta "como" ese usuario con EXECUTE AS USER y
 vuelve a dbo con REVERT.

 Cada caso imprime una línea en la pestaña Mensajes:
   OK     el usuario pudo hacer lo que debe poder, o fue rechazado en lo
          que no debe poder (se muestra el mensaje de SQL Server).
   ERROR  pasó lo contrario de lo esperado.
 El test está bien si ninguna línea empieza con ERROR.

 Lo que PUEDE hacer: iniciar y finalizar partidos; registrar formaciones,
 cambios, goles y amonestaciones; leer los partidos (Reportes.vw_Resultados)
 y las plantillas (Reportes.vw_Plantillas, con los nombres descifrados); y
 consultar los tipos de gol (DesarrolloPartido.usp_ConsultarTiposGol).
 Lo que NO PUEDE hacer: el resto de los reportes, los ABM, la publicidad,
 leer o modificar las tablas, ni usar directamente los objetos de cifrado.

 Los SP que puede ejecutar se prueban de dos formas:
   - La amarilla se registra de verdad, dentro de una transacción que se
     deshace al final del caso: no queda guardada.
   - Los demás reciben datos vacíos: pasan el control de permisos y los
     rechaza la validación del SP (error 50000 o mayor), sin guardar nada.
     Si el rechazo fuera por permisos (error 229), el caso da ERROR.
 Los casos que no debe poder hacer tampoco cambian nada aunque el permiso
 estuviera mal dado: datos vacíos, un partido que no existe (id -1) o un
 INSERT sin filas (WHERE 1 = 0).
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF DATABASE_PRINCIPAL_ID(N'usr_test_cargador_resultados') IS NULL
    THROW 51010, N'Falta el usuario de prueba. Ejecute primero 27_SP_Roles.sql (lo incluye 00_Ejecutar_PrepararBase.sql).', 1;
IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM DesarrolloPartido.FORMACION)
    THROW 51013, N'No hay partidos con formaciones cargados. Ejecute primero las importaciones (30 a 35).', 1;
GO

PRINT N'=== Lo que PUEDE hacer usr_test_cargador_resultados ===';
GO


/* Caso 1: PUEDE leer los partidos, para saber qué cargar. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    SELECT TOP (5) id_partido, partido, estado
    FROM Reportes.vw_Resultados
    ORDER BY id_partido;
    PRINT N'OK     1. Puede leer Reportes.vw_Resultados.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  1. No pudo leer Reportes.vw_Resultados: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 2: PUEDE leer las plantillas, con nombre y apellido descifrados.
   Si no tuviera permiso sobre la clave, la vista se leería igual pero los
   nombres saldrían NULL: por eso el caso controla que no haya ninguno en
   NULL. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    SELECT TOP (5) id_jugador, seleccion, dorsal, apellido, nombre
    FROM Reportes.vw_Plantillas
    ORDER BY id_seleccion, dorsal;

    IF EXISTS (SELECT 1 FROM Reportes.vw_Plantillas WHERE apellido IS NULL OR nombre IS NULL)
        PRINT N'ERROR  2. Lee Reportes.vw_Plantillas, pero los nombres salen NULL: no descifra.';
    ELSE
        PRINT N'OK     2. Puede leer Reportes.vw_Plantillas con los nombres descifrados.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  2. No pudo leer Reportes.vw_Plantillas: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 3: PUEDE registrar una amarilla. Se registra de verdad a un titular
   de un partido finalizado que no tiene tarjetas, y se deshace al final.
   El SP muestra al jugador con el nombre descifrado.  */

EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRANSACTION;
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarAmonestacion @id_partido = 1, @tipo_tarjeta = 'AMARILLA',
                                                     @minuto = 10, @motivo = 'Patada', @id_jugador = 1;
    PRINT N'OK     3. Puede registrar una amarilla con DesarrolloPartido.usp_RegistrarAmonestacion (se deshace).';
END TRY
BEGIN CATCH
    PRINT N'ERROR  3. No pudo registrar la amarilla: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- deshace la amarilla de prueba
REVERT;
GO


/* Caso 4: PUEDE registrar una formación. Para eso también necesita usar el
   tipo tabla DesarrolloPartido.TT_ALINEACION (declarar la variable). */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    DECLARE @jugadores DesarrolloPartido.TT_ALINEACION;
    EXEC DesarrolloPartido.usp_RegistrarFormacion @id_partido = 1, @id_seleccion = 1,
                                                  @esquema_tactico = 1, @jugadores = @jugadores;
    PRINT N'OK     4. Puede ejecutar DesarrolloPartido.usp_RegistrarFormacion.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() >= 50000   -- lo rechazó la validación del SP: el permiso está
        PRINT N'OK     4. Puede usar TT_ALINEACION y ejecutar DesarrolloPartido.usp_RegistrarFormacion (lo rechaza la validación del SP).';
    ELSE
        PRINT N'ERROR  4. No pudo ejecutar DesarrolloPartido.usp_RegistrarFormacion: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 5: PUEDE iniciar un partido. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    EXEC Torneo.usp_IniciarPartido @id_partido = -1;
    PRINT N'OK     5. Puede ejecutar Torneo.usp_IniciarPartido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() >= 50000
        PRINT N'OK     5. Puede ejecutar Torneo.usp_IniciarPartido (lo rechaza la validación del SP).';
    ELSE
        PRINT N'ERROR  5. No pudo ejecutar Torneo.usp_IniciarPartido: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 6: PUEDE consultar los tipos de gol
   (DesarrolloPartido.usp_ConsultarTiposGol) para elegir el del gol, y
   registrar un gol. Se pasa un partido que no existe (id -1), para que lo
   rechace la validación del SP y no guarde nada. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    DECLARE @id_tipo_gol TINYINT;
    DECLARE @tipos_gol TABLE (id_tipo_gol TINYINT, descripcion VARCHAR(40), es_en_contra BIT);

    INSERT INTO @tipos_gol EXEC DesarrolloPartido.usp_ConsultarTiposGol;
    SELECT id_tipo_gol, descripcion, es_en_contra FROM @tipos_gol ORDER BY id_tipo_gol;
    SELECT TOP (1) @id_tipo_gol = id_tipo_gol FROM @tipos_gol ORDER BY id_tipo_gol;

    EXEC DesarrolloPartido.usp_RegistrarGol @id_partido = -1, @id_jugador_autor = 1,
                                            @id_tipo_gol = @id_tipo_gol, @periodo = 'PRIMER_TIEMPO';
    PRINT N'OK     6. Puede ejecutar DesarrolloPartido.usp_RegistrarGol.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() >= 50000
        PRINT N'OK     6. Puede consultar los tipos de gol y ejecutar DesarrolloPartido.usp_RegistrarGol (lo rechaza la validación del SP).';
    ELSE
        PRINT N'ERROR  6. No pudo consultar los tipos de gol o ejecutar DesarrolloPartido.usp_RegistrarGol: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 7: PUEDE registrar un cambio. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    EXEC DesarrolloPartido.usp_RegistrarCambio @id_partido = -1, @id_jugador_sale = 2,
                                               @id_jugador_entra = 22, @minuto = 67, @motivo = 'LESION';
    PRINT N'OK     7. Puede ejecutar DesarrolloPartido.usp_RegistrarCambio.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() >= 50000
        PRINT N'OK     7. Puede ejecutar DesarrolloPartido.usp_RegistrarCambio (lo rechaza la validación del SP).';
    ELSE
        PRINT N'ERROR  7. No pudo ejecutar DesarrolloPartido.usp_RegistrarCambio: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 8: PUEDE finalizar un partido. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    EXEC Torneo.usp_FinalizarPartido @id_partido = -1;
    PRINT N'OK     8. Puede ejecutar Torneo.usp_FinalizarPartido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() >= 50000
        PRINT N'OK     8. Puede ejecutar Torneo.usp_FinalizarPartido (lo rechaza la validación del SP).';
    ELSE
        PRINT N'ERROR  8. No pudo ejecutar Torneo.usp_FinalizarPartido: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


PRINT N'';
PRINT N'=== Lo que NO PUEDE hacer usr_test_cargador_resultados ===';
GO


/* Caso 9: NO PUEDE leer otros reportes: solo los partidos y las plantillas. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    SELECT TOP (5) * FROM Reportes.vw_Tarjetas;
    PRINT N'ERROR  9. Pudo leer Reportes.vw_Tarjetas y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229   -- 229: permiso denegado
        PRINT N'OK     9. No puede leer Reportes.vw_Tarjetas: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  9. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 10: NO PUEDE ejecutar los SP de reportes. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    EXEC Reportes.usp_Goleadores;
    PRINT N'ERROR 10. Pudo ejecutar Reportes.usp_Goleadores y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    10. No puede ejecutar Reportes.usp_Goleadores: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 10. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 11: NO PUEDE dar de alta un jugador. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = NULL, @nombre = NULL, @apellido = NULL,
                                 @posicion_habitual = NULL, @dorsal = NULL;
    PRINT N'ERROR 11. Pudo ejecutar Torneo.usp_JUGADOR_Alta y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    11. No puede ejecutar Torneo.usp_JUGADOR_Alta: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 11. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 12: NO PUEDE asignar la publicidad de un partido. Se pasa un partido
   que no existe: sin id, el SP asignaría todos los partidos. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = -1;
    PRINT N'ERROR 12. Pudo ejecutar Publicidad.usp_AsignarPublicidadPartido y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    12. No puede ejecutar Publicidad.usp_AsignarPublicidadPartido: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 12. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 13: NO PUEDE leer una tabla directamente. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    SELECT TOP (5) * FROM Torneo.JUGADOR;
    PRINT N'ERROR 13. Pudo leer la tabla Torneo.JUGADOR y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    13. No puede leer Torneo.JUGADOR: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 13. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 14: NO PUEDE insertar una tarjeta directamente en la tabla (sin pasar
   por el SP y sus validaciones). */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    INSERT INTO DesarrolloPartido.AMONESTACION (id_partido, id_jugador, tipo_tarjeta, minuto)
    SELECT NULL, NULL, 'AMARILLA', 1 ;
    PRINT N'ERROR 14. Pudo insertar en DesarrolloPartido.AMONESTACION y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    14. No puede insertar en DesarrolloPartido.AMONESTACION: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 14. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 15: NO PUEDE leer la vista descifrada de jugadores directamente: los
   datos personales los ve solo a través de las plantillas. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
BEGIN TRY
    SELECT TOP (5) id_jugador, apellido, nombre, fecha_nacimiento FROM Seguridad.vw_Jugador;
    PRINT N'ERROR 15. Pudo leer Seguridad.vw_Jugador y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    15. No puede leer Seguridad.vw_Jugador: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 15. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 16: NO PUEDE modificar el certificado (por ejemplo, quitarle la clave
   privada). No se intenta el ALTER: se pregunta si tiene el permiso. */
EXECUTE AS USER = N'usr_test_cargador_resultados';
IF HAS_PERMS_BY_NAME(N'CertDatosPersonales', N'CERTIFICATE', N'ALTER') = 0
    PRINT N'OK    16. No tiene permiso para modificar el certificado CertDatosPersonales.';
ELSE
    PRINT N'ERROR 16. Tiene permiso para modificar el certificado CertDatosPersonales y no debería.';
REVERT;
GO
