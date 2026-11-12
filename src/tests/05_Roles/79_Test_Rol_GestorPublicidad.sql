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
 Archivo: 79_Test_Rol_GestorPublicidad.sql
 Objetivo: Probar lo que puede y lo que no puede hacer el usuario
           usr_test_gestor_publicidad (rol_GestorPublicidad).
================================================================================

 Requiere haber ejecutado 00_Ejecutar_PrepararBase.sql (roles), las
 importaciones y 40_Ejecutar_Cifrado.sql.

 usr_test_gestor_publicidad es un usuario SIN LOGIN: nadie puede iniciar
 sesión con él. Cada caso se ejecuta "como" ese usuario con EXECUTE AS USER y
 vuelve a dbo con REVERT.

 Cada caso imprime una línea en la pestaña Mensajes:
   OK     el usuario pudo hacer lo que debe poder, o fue rechazado en lo
          que no debe poder (se muestra el mensaje de SQL Server).
   ERROR  pasó lo contrario de lo esperado.
 El test está bien si ninguna línea empieza con ERROR.

 Lo que PUEDE hacer: los ABM y la asignación de publicidad, y sus reportes
 (ocupación publicitaria e ingresos por moneda); y consultar los países
 (DatosGenerales.usp_ConsultarPaises).
 Lo que NO PUEDE hacer: los reportes deportivos, los ABM de otros módulos,
 leer o modificar las tablas, ni descifrar los datos personales: no trabaja
 con ellos.

 Los SP que puede ejecutar se prueban de dos formas:
   - El alta de un anunciante se hace de verdad, dentro de una transacción
     que se deshace al final del caso: no queda guardada.
   - La asignación recibe un partido que no existe (id -1): pasa el control
     de permisos y la rechaza la validación del SP (error 50000 o mayor),
     sin guardar nada. Si el rechazo fuera por permisos (error 229), el caso
     da ERROR.
 Los casos que no debe poder hacer tampoco cambian nada aunque el permiso
 estuviera mal dado: datos vacíos o un UPDATE sin filas (WHERE 1 = 0).
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF DATABASE_PRINCIPAL_ID(N'usr_test_gestor_publicidad') IS NULL
    THROW 51010, N'Falta el usuario de prueba. Ejecute primero 27_SP_Roles.sql (lo incluye 00_Ejecutar_PrepararBase.sql).', 1;
IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM Torneo.JUGADOR)
    THROW 51013, N'No hay datos del torneo cargados. Ejecute primero las importaciones (31 a 35).', 1;
GO

PRINT N'=== Lo que PUEDE hacer usr_test_gestor_publicidad ===';
GO


/* Caso 1: PUEDE leer la ocupación publicitaria. */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRY
    SELECT TOP (5) * FROM Reportes.vw_OcupacionPublicitaria;
    PRINT N'OK     1. Puede leer Reportes.vw_OcupacionPublicitaria.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  1. No pudo leer Reportes.vw_OcupacionPublicitaria: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 2: PUEDE leer los ingresos publicitarios por moneda. */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRY
    SELECT TOP (5) partido, sede, ingresos_usd, codigo_moneda, ingresos_en_moneda
    FROM Reportes.vw_IngresosPublicitariosPorMoneda;
    PRINT N'OK     2. Puede leer Reportes.vw_IngresosPublicitariosPorMoneda.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  2. No pudo leer Reportes.vw_IngresosPublicitariosPorMoneda: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 3: PUEDE ejecutar el reporte de ocupación publicitaria. */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRY
    EXEC Reportes.usp_OcupacionPublicitaria;
    PRINT N'OK     3. Puede ejecutar Reportes.usp_OcupacionPublicitaria.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  3. No pudo ejecutar Reportes.usp_OcupacionPublicitaria: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 4: PUEDE consultar los países (DatosGenerales.usp_ConsultarPaises)
   para elegir el del anunciante, y dar de alta un anunciante. Se da de alta de verdad y se deshace al
   final. */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @id_pais SMALLINT, @id_anunciante INT;
    DECLARE @paises TABLE (id_pais SMALLINT, nombre VARCHAR(60), codigo_fifa CHAR(3), huso_horario VARCHAR(50));

    INSERT INTO @paises EXEC DatosGenerales.usp_ConsultarPaises;
    SELECT TOP (5) id_pais, nombre, codigo_fifa FROM @paises ORDER BY nombre;
    SELECT TOP (1) @id_pais = id_pais FROM @paises ORDER BY nombre;

    EXEC Publicidad.usp_ANUNCIANTE_Alta @razon_social = N'Anunciante de prueba de rol', @id_pais = @id_pais,
                                        @id_anunciante = @id_anunciante OUTPUT;
    PRINT CONCAT(N'OK     4. Puede consultar los países y dar de alta un anunciante con Publicidad.usp_ANUNCIANTE_Alta (id ', @id_anunciante, N'; se deshace).');
END TRY
BEGIN CATCH
    PRINT N'ERROR  4. No pudo consultar los países o dar de alta el anunciante: ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- deshace el anunciante de prueba
REVERT;
GO


/* Caso 5: PUEDE asignar la publicidad de un partido. Se pasa un partido que
   no existe, para que falle por la validacion del SP y no inserte nada */

EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRY
    EXEC Publicidad.usp_AsignarPublicidadPartido @id_partido = -1;
    PRINT N'OK     5. Puede ejecutar Publicidad.usp_AsignarPublicidadPartido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() >= 50000   -- lo rechazó la validación del SP: el permiso está
        PRINT N'OK     5. Puede ejecutar Publicidad.usp_AsignarPublicidadPartido (con un partido que no existe lo rechaza la validación del SP).';
    ELSE
        PRINT N'ERROR  5. No pudo ejecutar Publicidad.usp_AsignarPublicidadPartido: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


PRINT N'';
PRINT N'=== Lo que NO PUEDE hacer usr_test_gestor_publicidad ===';
GO


/* Caso 6: NO PUEDE leer las plantillas: tienen datos personales. */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRY
    SELECT TOP (5) seleccion, dorsal, apellido, nombre FROM Reportes.vw_Plantillas;
    PRINT N'ERROR  6. Pudo leer Reportes.vw_Plantillas y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229   -- 229: permiso denegado
        PRINT N'OK     6. No puede leer Reportes.vw_Plantillas: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  6. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 7: NO PUEDE ejecutar los reportes deportivos. */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRY
    EXEC Reportes.usp_Goleadores;
    PRINT N'ERROR  7. Pudo ejecutar Reportes.usp_Goleadores y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK     7. No puede ejecutar Reportes.usp_Goleadores: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  7. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 8: NO PUEDE dar de alta un jugador. */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRY
    EXEC Torneo.usp_JUGADOR_Alta @id_lista = 25, @nombre = 'Leopoldo', @apellido = 'Messi',
                                 @posicion_habitual = 'Arquero', @dorsal = 19;
    PRINT N'ERROR  8. Pudo ejecutar Torneo.usp_JUGADOR_Alta y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK     8. No puede ejecutar Torneo.usp_JUGADOR_Alta: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  8. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 9: NO PUEDE leer las tablas de su propio módulo directamente: los
   anunciantes los maneja con los SP. */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRY
    SELECT TOP (5) * FROM Publicidad.ANUNCIANTE;
    PRINT N'ERROR  9. Pudo leer la tabla Publicidad.ANUNCIANTE y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK     9. No puede leer Publicidad.ANUNCIANTE: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR  9. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 10: NO PUEDE modificar las exhibiciones directamente. */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRY
    UPDATE Publicidad.EXHIBICION SET costo = 0;
    PRINT N'ERROR 10. Pudo modificar Publicidad.EXHIBICION y no debería.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        PRINT N'OK    10. No puede modificar Publicidad.EXHIBICION: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 10. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO


/* Caso 11: NO PUEDE abrir la clave de cifrado. SQL Server responde como si
   la clave no existiera (error 15151). */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
BEGIN TRY
    OPEN SYMMETRIC KEY ClaveDatosPersonales DECRYPTION BY CERTIFICATE CertDatosPersonales;
    PRINT N'ERROR 11. Pudo abrir la clave ClaveDatosPersonales y no debería.';
    CLOSE SYMMETRIC KEY ClaveDatosPersonales;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 15151   -- 15151: no existe o no tiene permiso
        PRINT N'OK    11. No puede abrir la clave ClaveDatosPersonales: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'ERROR 11. Falló por otro motivo, no por permisos: ' + ERROR_MESSAGE();
END CATCH;
REVERT;
GO

/* Caso 12: NO PUEDE descifrar los datos personales: no tiene permiso sobre
   el certificado que abre la clave. El usuario pregunta por su propio
   permiso (descifrar necesita CONTROL sobre el certificado). */
EXECUTE AS USER = N'usr_test_gestor_publicidad';
IF HAS_PERMS_BY_NAME(N'CertDatosPersonales', N'CERTIFICATE', N'CONTROL') = 1
    PRINT N'ERROR 12. Tiene permiso sobre el certificado CertDatosPersonales y no debería: podría descifrar.';
ELSE
    PRINT N'OK    12. No tiene permiso sobre el certificado CertDatosPersonales: no puede descifrar.';
REVERT;
GO
