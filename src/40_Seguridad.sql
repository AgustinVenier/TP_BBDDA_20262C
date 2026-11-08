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
 Archivo: 40_Seguridad.sql
 Objetivo: Crear roles de aplicación con privilegios mínimos, usuarios sin
           login para probarlos y permisos sobre las interfaces SP/vistas.
           Se deniega el acceso DML directo a los esquemas de datos: los cambios
           se realizan mediante los procedimientos almacenados existentes.
================================================================================

 Orden: ejecutar después de 30_SP_Reportes.sql. Se incluye en
 37_Ejecutar_PrepararBase.sql.

 Los usuarios usr_test_* son PRINCIPALS SIN LOGIN únicamente para demostrar los
 permisos con EXECUTE AS USER. En producción se asignan usuarios de Windows o
 logins de aplicación a los roles; no se agregan usuarios a db_owner,
 db_datareader ni db_datawriter.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

/* Roles de aplicación. AdministradorOperativo no es sysadmin ni db_owner. */
IF DATABASE_PRINCIPAL_ID(N'rol_AdministradorOperativo') IS NULL
    CREATE ROLE rol_AdministradorOperativo AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID(N'rol_CargadorResultados') IS NULL
    CREATE ROLE rol_CargadorResultados AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID(N'rol_GestorPublicidad') IS NULL
    CREATE ROLE rol_GestorPublicidad AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID(N'rol_ConsultaReportes') IS NULL
    CREATE ROLE rol_ConsultaReportes AUTHORIZATION dbo;
GO

/* Usuarios de demostración sin LOGIN: no permiten iniciar sesión. */
IF DATABASE_PRINCIPAL_ID(N'usr_test_administrador') IS NULL
    CREATE USER usr_test_administrador WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'usr_test_cargador_resultados') IS NULL
    CREATE USER usr_test_cargador_resultados WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'usr_test_gestor_publicidad') IS NULL
    CREATE USER usr_test_gestor_publicidad WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'usr_test_consulta') IS NULL
    CREATE USER usr_test_consulta WITHOUT LOGIN;
GO

/* Asociación idempotente de los usuarios de demostración a cada rol. */
IF NOT EXISTS (
    SELECT 1 FROM sys.database_role_members AS rm
    INNER JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
    INNER JOIN sys.database_principals AS u ON u.principal_id = rm.member_principal_id
    WHERE r.name = N'rol_AdministradorOperativo' AND u.name = N'usr_test_administrador'
)
    ALTER ROLE rol_AdministradorOperativo ADD MEMBER usr_test_administrador;
IF NOT EXISTS (
    SELECT 1 FROM sys.database_role_members AS rm
    INNER JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
    INNER JOIN sys.database_principals AS u ON u.principal_id = rm.member_principal_id
    WHERE r.name = N'rol_CargadorResultados' AND u.name = N'usr_test_cargador_resultados'
)
    ALTER ROLE rol_CargadorResultados ADD MEMBER usr_test_cargador_resultados;
IF NOT EXISTS (
    SELECT 1 FROM sys.database_role_members AS rm
    INNER JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
    INNER JOIN sys.database_principals AS u ON u.principal_id = rm.member_principal_id
    WHERE r.name = N'rol_GestorPublicidad' AND u.name = N'usr_test_gestor_publicidad'
)
    ALTER ROLE rol_GestorPublicidad ADD MEMBER usr_test_gestor_publicidad;
IF NOT EXISTS (
    SELECT 1 FROM sys.database_role_members AS rm
    INNER JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
    INNER JOIN sys.database_principals AS u ON u.principal_id = rm.member_principal_id
    WHERE r.name = N'rol_ConsultaReportes' AND u.name = N'usr_test_consulta'
)
    ALTER ROLE rol_ConsultaReportes ADD MEMBER usr_test_consulta;
GO

/* Administrador operativo: interfaz completa por SP y lectura de reportes. */
GRANT EXECUTE ON SCHEMA::DatosGenerales TO rol_AdministradorOperativo;
GRANT EXECUTE ON SCHEMA::Torneo TO rol_AdministradorOperativo;
GRANT EXECUTE ON SCHEMA::DesarrolloPartido TO rol_AdministradorOperativo;
GRANT EXECUTE ON SCHEMA::Arbitraje TO rol_AdministradorOperativo;
GRANT EXECUTE ON SCHEMA::Publicidad TO rol_AdministradorOperativo;
GRANT SELECT, EXECUTE ON SCHEMA::Reportes TO rol_AdministradorOperativo;
GO

/* Cargador de resultados: operación del partido y eventos en cancha. */
GRANT EXECUTE ON OBJECT::Torneo.usp_IniciarPartido TO rol_CargadorResultados;
GRANT EXECUTE ON OBJECT::Torneo.usp_FinalizarPartido TO rol_CargadorResultados;
GRANT EXECUTE ON OBJECT::DesarrolloPartido.usp_RegistrarFormacion TO rol_CargadorResultados;
GRANT EXECUTE ON OBJECT::DesarrolloPartido.usp_RegistrarCambio TO rol_CargadorResultados;
GRANT EXECUTE ON OBJECT::DesarrolloPartido.usp_RegistrarGol TO rol_CargadorResultados;
GRANT EXECUTE ON OBJECT::DesarrolloPartido.usp_RegistrarAmonestacion TO rol_CargadorResultados;
GO

/* Gestor de publicidad: ABM, asignación y reportes de su módulo. */
GRANT EXECUTE ON SCHEMA::Publicidad TO rol_GestorPublicidad;
GRANT SELECT ON OBJECT::Reportes.vw_OcupacionPublicitaria TO rol_GestorPublicidad;
GRANT SELECT ON OBJECT::Reportes.vw_IngresosPublicitariosPorMoneda TO rol_GestorPublicidad;
GRANT EXECUTE ON OBJECT::Reportes.usp_OcupacionPublicitaria TO rol_GestorPublicidad;
GO

/* Consulta: solo vistas y SP del esquema de reportes. */
GRANT SELECT, EXECUTE ON SCHEMA::Reportes TO rol_ConsultaReportes;
GO


/* Las cargas que leen rutas del servidor requieren ADMINISTER BULK OPERATIONS.
   Se reservan para una sesión controlada de DBA; ningún rol de aplicación puede
   invocar estos módulos, aunque el administrador operativo tenga EXECUTE por
   esquema. La instancia debe restringir los paths visibles al servicio SQL.
*/
DENY EXECUTE ON OBJECT::DatosGenerales.usp_LeerArchivoUTF8 TO rol_AdministradorOperativo;
DENY EXECUTE ON OBJECT::Torneo.usp_ImportarSedesJSON TO rol_AdministradorOperativo;
DENY EXECUTE ON OBJECT::Torneo.usp_ImportarSeleccionesJSON TO rol_AdministradorOperativo;
DENY EXECUTE ON OBJECT::Torneo.usp_ImportarPartidosJSON TO rol_AdministradorOperativo;
DENY EXECUTE ON OBJECT::Torneo.usp_ImportarJugadoresCSV TO rol_AdministradorOperativo;
DENY EXECUTE ON OBJECT::Torneo.usp_ImportarCuerpoTecnicoCSV TO rol_AdministradorOperativo;
DENY EXECUTE ON OBJECT::Arbitraje.usp_ImportarDesignacionesCSV TO rol_AdministradorOperativo;
GO
/*
   Defensa en profundidad: ningún rol de aplicación lee o modifica directamente
   tablas de negocio. Las operaciones pasan por SP y las consultas por Reportes.
   Al compartir propietario dbo, el encadenamiento de propiedad permite que los
   SP accedan a sus tablas sin conceder DML directo a sus invocadores.
*/
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DatosGenerales TO rol_AdministradorOperativo;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Torneo TO rol_AdministradorOperativo;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DesarrolloPartido TO rol_AdministradorOperativo;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Arbitraje TO rol_AdministradorOperativo;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Publicidad TO rol_AdministradorOperativo;

DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DatosGenerales TO rol_CargadorResultados;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Torneo TO rol_CargadorResultados;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DesarrolloPartido TO rol_CargadorResultados;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Arbitraje TO rol_CargadorResultados;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Publicidad TO rol_CargadorResultados;

DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DatosGenerales TO rol_GestorPublicidad;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Torneo TO rol_GestorPublicidad;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DesarrolloPartido TO rol_GestorPublicidad;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Arbitraje TO rol_GestorPublicidad;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Publicidad TO rol_GestorPublicidad;

DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DatosGenerales TO rol_ConsultaReportes;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Torneo TO rol_ConsultaReportes;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DesarrolloPartido TO rol_ConsultaReportes;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Arbitraje TO rol_ConsultaReportes;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Publicidad TO rol_ConsultaReportes;

GO

/* Evidencia de roles, usuarios y membresías creados. */
SELECT r.name AS rol,
       u.name AS usuario_prueba_sin_login
FROM sys.database_role_members AS rm
INNER JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
INNER JOIN sys.database_principals AS u ON u.principal_id = rm.member_principal_id
WHERE r.name LIKE N'rol[_]%' AND u.name LIKE N'usr[_]test[_]%'
ORDER BY r.name, u.name;
GO



