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

 Fecha: 08/11/2026
 Archivo: 82_Test_Rol_CargadorResultados.sql
 Objetivo: Comprobar con HAS_PERMS_BY_NAME los permisos efectivos del usuario
           usr_test_cargador_resultados para su rol. Cada control indica permiso esperado y real.
================================================================================

 Requiere haber ejecutado 40_Seguridad.sql. Los usuarios usr_test_* son
 principals SIN LOGIN; solo sirven para impersonación de prueba.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF DATABASE_PRINCIPAL_ID(N'usr_test_cargador_resultados') IS NULL
    THROW 51010, N'Falta el usuario de prueba. Ejecute primero 40_Seguridad.sql.', 1;
GO

DECLARE @permisos TABLE (
    control     NVARCHAR(180) NOT NULL,
    permitido   BIT           NULL,
    esperado    BIT           NOT NULL
);

EXECUTE AS USER = N'usr_test_cargador_resultados';
INSERT INTO @permisos (control, permitido, esperado)
VALUES
    (N'Iniciar un partido', HAS_PERMS_BY_NAME(N'Torneo.usp_IniciarPartido', N'OBJECT', N'EXECUTE'), 1),
    (N'Finalizar un partido', HAS_PERMS_BY_NAME(N'Torneo.usp_FinalizarPartido', N'OBJECT', N'EXECUTE'), 1),
    (N'Registrar goles', HAS_PERMS_BY_NAME(N'DesarrolloPartido.usp_RegistrarGol', N'OBJECT', N'EXECUTE'), 1),
    (N'Asignar publicidad', HAS_PERMS_BY_NAME(N'Publicidad.usp_AsignarPublicidadPartido', N'OBJECT', N'EXECUTE'), 0),
    (N'Consultar reportes', HAS_PERMS_BY_NAME(N'Reportes.usp_Goleadores', N'OBJECT', N'EXECUTE'), 0),
    (N'Leer tabla de jugadores directamente', HAS_PERMS_BY_NAME(N'Torneo.JUGADOR', N'OBJECT', N'SELECT'), 0),
    (N'Insertar tarjetas directamente', HAS_PERMS_BY_NAME(N'DesarrolloPartido.AMONESTACION', N'OBJECT', N'INSERT'), 0);
REVERT;

SELECT control,
       permitido AS permiso_efectivo,
       esperado AS permiso_esperado,
       CASE WHEN ISNULL(permitido, 0) = esperado THEN N'OK' ELSE N'FALLÓ' END AS resultado
FROM @permisos
ORDER BY control;

IF EXISTS (SELECT 1 FROM @permisos WHERE ISNULL(permitido, 0) <> esperado)
    THROW 51011, N'La matriz de permisos no coincide con lo esperado para este rol.', 1;
GO

