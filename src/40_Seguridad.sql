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
 Objetivo: Crear el esquema Seguridad y el SP Seguridad.usp_ConfigurarRoles, que
           crea los roles de aplicación con privilegios mínimos, los usuarios sin
           login para probarlos y sus permisos sobre los SP y las vistas. Se
           deniega el acceso directo a las tablas: los cambios se hacen con los
           SP existentes y las consultas, con las vistas de Reportes.
================================================================================

 Orden: ejecutar después de 30_SP_Reportes.sql. Se incluye en
 37_Ejecutar_PrepararBase.sql. Se puede volver a ejecutar: el SP crea solo lo
 que falta y vuelve a aplicar los permisos.

 Los usuarios usr_test_* son PRINCIPALS SIN LOGIN únicamente para demostrar los
 permisos con EXECUTE AS USER. En producción se asignan usuarios de Windows o
 logins de aplicación a los roles; no se agregan usuarios a db_owner,
 db_datareader ni db_datawriter.

 Roles:
   rol_AdministradorOperativo  ABM y SP de negocio de todos los módulos, y reportes.
   rol_CargadorResultados      Iniciar y finalizar partidos, y registrar
                               formaciones, cambios, goles y amonestaciones.
                               Lee los partidos y las plantillas, para saber
                               qué cargar; el resto de los reportes, no.
   rol_GestorPublicidad        ABM y asignación de publicidad, y sus reportes.
   rol_ConsultaReportes        Solo las vistas y los SP de Reportes.

 Datos personales cifrados (41_SP_Cifrado.sql): ningún rol usa directamente
 las funciones de cifrado (se deniega el esquema Seguridad), pero SQL Server
 controla el uso de la clave con el usuario que consulta, aunque lo haga a
 través de un SP o una vista. Por eso, cuando las claves ya existen, el SP da
 permiso para usarlas a los roles que trabajan con datos personales:
   rol_AdministradorOperativo  cifrar y descifrar (da de alta y modifica personas).
   rol_CargadorResultados      descifrar (los nombres en formaciones, tarjetas, avisos y plantillas).
   rol_ConsultaReportes        descifrar (los nombres en los reportes).
   rol_GestorPublicidad        ninguno: no trabaja con datos personales.
 38_Ejecutar_Cifrado.sql vuelve a ejecutar el SP después de crear las claves.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

/* Esquema de los objetos de seguridad y cifrado. CREATE SCHEMA debe ser la
   única sentencia de su lote: si ya existe, se saltea con NOEXEC. */
IF SCHEMA_ID(N'Seguridad') IS NOT NULL SET NOEXEC ON;
GO
CREATE SCHEMA Seguridad AUTHORIZATION dbo;
GO
SET NOEXEC OFF;
GO


/*
  usp_ConfigurarRoles
  Crea los cuatro roles y sus usuarios de prueba si no existen, asocia cada
  usuario a su rol y aplica los permisos. Los GRANT y DENY se pueden repetir
  sin error, así que el SP se puede ejecutar más de una vez.
*/
CREATE OR ALTER PROCEDURE Seguridad.usp_ConfigurarRoles
AS
BEGIN
    SET NOCOUNT ON;

    /* Roles de aplicación. AdministradorOperativo no es sysadmin ni db_owner. */
    IF DATABASE_PRINCIPAL_ID(N'rol_AdministradorOperativo') IS NULL
        CREATE ROLE rol_AdministradorOperativo AUTHORIZATION dbo;
    IF DATABASE_PRINCIPAL_ID(N'rol_CargadorResultados') IS NULL
        CREATE ROLE rol_CargadorResultados AUTHORIZATION dbo;
    IF DATABASE_PRINCIPAL_ID(N'rol_GestorPublicidad') IS NULL
        CREATE ROLE rol_GestorPublicidad AUTHORIZATION dbo;
    IF DATABASE_PRINCIPAL_ID(N'rol_ConsultaReportes') IS NULL
        CREATE ROLE rol_ConsultaReportes AUTHORIZATION dbo;

    /* Usuarios de demostración sin LOGIN: no permiten iniciar sesión. */
    IF DATABASE_PRINCIPAL_ID(N'usr_test_administrador') IS NULL
        CREATE USER usr_test_administrador WITHOUT LOGIN;
    IF DATABASE_PRINCIPAL_ID(N'usr_test_cargador_resultados') IS NULL
        CREATE USER usr_test_cargador_resultados WITHOUT LOGIN;
    IF DATABASE_PRINCIPAL_ID(N'usr_test_gestor_publicidad') IS NULL
        CREATE USER usr_test_gestor_publicidad WITHOUT LOGIN;
    IF DATABASE_PRINCIPAL_ID(N'usr_test_consulta') IS NULL
        CREATE USER usr_test_consulta WITHOUT LOGIN;

    /* Cada usuario de demostración en su rol. */
    IF IS_ROLEMEMBER(N'rol_AdministradorOperativo', N'usr_test_administrador') = 0
        ALTER ROLE rol_AdministradorOperativo ADD MEMBER usr_test_administrador;
    IF IS_ROLEMEMBER(N'rol_CargadorResultados', N'usr_test_cargador_resultados') = 0
        ALTER ROLE rol_CargadorResultados ADD MEMBER usr_test_cargador_resultados;
    IF IS_ROLEMEMBER(N'rol_GestorPublicidad', N'usr_test_gestor_publicidad') = 0
        ALTER ROLE rol_GestorPublicidad ADD MEMBER usr_test_gestor_publicidad;
    IF IS_ROLEMEMBER(N'rol_ConsultaReportes', N'usr_test_consulta') = 0
        ALTER ROLE rol_ConsultaReportes ADD MEMBER usr_test_consulta;

    /* Administrador operativo: todos los SP de los módulos y los reportes. El
       permiso por esquema incluye los tipos tabla de esos esquemas (los que
       reciben usp_RegistrarConvocatoria y usp_RegistrarFormacion). */
    GRANT EXECUTE ON SCHEMA::DatosGenerales TO rol_AdministradorOperativo;
    GRANT EXECUTE ON SCHEMA::Torneo TO rol_AdministradorOperativo;
    GRANT EXECUTE ON SCHEMA::DesarrolloPartido TO rol_AdministradorOperativo;
    GRANT EXECUTE ON SCHEMA::Arbitraje TO rol_AdministradorOperativo;
    GRANT EXECUTE ON SCHEMA::Publicidad TO rol_AdministradorOperativo;
    GRANT SELECT, EXECUTE ON SCHEMA::Reportes TO rol_AdministradorOperativo;

    /* Cargador de resultados: operación del partido y eventos en cancha. El tipo
       tabla de la formación necesita su propio permiso: sin él, el usuario no
       puede declarar la variable que recibe usp_RegistrarFormacion. */
    GRANT EXECUTE ON OBJECT::Torneo.usp_IniciarPartido TO rol_CargadorResultados;
    GRANT EXECUTE ON OBJECT::Torneo.usp_FinalizarPartido TO rol_CargadorResultados;
    GRANT EXECUTE ON OBJECT::DesarrolloPartido.usp_RegistrarFormacion TO rol_CargadorResultados;
    GRANT EXECUTE ON OBJECT::DesarrolloPartido.usp_RegistrarCambio TO rol_CargadorResultados;
    GRANT EXECUTE ON OBJECT::DesarrolloPartido.usp_RegistrarGol TO rol_CargadorResultados;
    GRANT EXECUTE ON OBJECT::DesarrolloPartido.usp_RegistrarAmonestacion TO rol_CargadorResultados;
    GRANT EXECUTE ON TYPE::DesarrolloPartido.TT_ALINEACION TO rol_CargadorResultados;

    /* Para saber qué cargar, el cargador lee dos vistas de Reportes: los
       partidos (id, selecciones y estado) y las plantillas (id, dorsal, nombre
       y posición de cada jugador; sin la fecha de nacimiento). El resto de los
       reportes no. Los tipos de gol son un catálogo fijo (20_Ejecutar_DatosIniciales.sql). */
    GRANT SELECT ON OBJECT::Reportes.vw_Resultados TO rol_CargadorResultados;
    GRANT SELECT ON OBJECT::Reportes.vw_Plantillas TO rol_CargadorResultados;

    /* Gestor de publicidad: ABM, asignación y reportes de su módulo. */
    GRANT EXECUTE ON SCHEMA::Publicidad TO rol_GestorPublicidad;
    GRANT SELECT ON OBJECT::Reportes.vw_OcupacionPublicitaria TO rol_GestorPublicidad;
    GRANT SELECT ON OBJECT::Reportes.vw_IngresosPublicitariosPorMoneda TO rol_GestorPublicidad;
    GRANT EXECUTE ON OBJECT::Reportes.usp_OcupacionPublicitaria TO rol_GestorPublicidad;

    /* Consulta: solo vistas y SP del esquema de reportes. */
    GRANT SELECT, EXECUTE ON SCHEMA::Reportes TO rol_ConsultaReportes;

    /* Las cargas que leen rutas del servidor requieren ADMINISTER BULK OPERATIONS.
       Se reservan para una sesión controlada de DBA; ningún rol de aplicación puede
       invocar estos módulos, aunque el administrador operativo tenga EXECUTE por
       esquema. La instancia debe restringir los paths visibles al servicio SQL. */
    DENY EXECUTE ON OBJECT::DatosGenerales.usp_LeerArchivoUTF8 TO rol_AdministradorOperativo;
    DENY EXECUTE ON OBJECT::Torneo.usp_ImportarSedesJSON TO rol_AdministradorOperativo;
    DENY EXECUTE ON OBJECT::Torneo.usp_ImportarSeleccionesJSON TO rol_AdministradorOperativo;
    DENY EXECUTE ON OBJECT::Torneo.usp_ImportarPartidosJSON TO rol_AdministradorOperativo;
    DENY EXECUTE ON OBJECT::Torneo.usp_ImportarJugadoresCSV TO rol_AdministradorOperativo;
    DENY EXECUTE ON OBJECT::Torneo.usp_ImportarCuerpoTecnicoCSV TO rol_AdministradorOperativo;
    DENY EXECUTE ON OBJECT::Arbitraje.usp_ImportarDesignacionesCSV TO rol_AdministradorOperativo;
    DENY EXECUTE ON OBJECT::Torneo.usp_ImportarImagenesSedes TO rol_AdministradorOperativo;

    /* Defensa en profundidad: ningún rol de aplicación lee o modifica directamente
       las tablas, ni usa los objetos de Seguridad (las funciones de cifrado y
       los SP que abren la clave). Al compartir propietario dbo, el
       encadenamiento de propiedad permite que los SP y las vistas usen las
       tablas y las funciones sin conceder esos permisos a quien los invoca. */
    DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DatosGenerales TO rol_AdministradorOperativo, rol_CargadorResultados, rol_GestorPublicidad, rol_ConsultaReportes;
    DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Torneo TO rol_AdministradorOperativo, rol_CargadorResultados, rol_GestorPublicidad, rol_ConsultaReportes;
    DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DesarrolloPartido TO rol_AdministradorOperativo, rol_CargadorResultados, rol_GestorPublicidad, rol_ConsultaReportes;
    DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Arbitraje TO rol_AdministradorOperativo, rol_CargadorResultados, rol_GestorPublicidad, rol_ConsultaReportes;
    DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Publicidad TO rol_AdministradorOperativo, rol_CargadorResultados, rol_GestorPublicidad, rol_ConsultaReportes;
    DENY SELECT, EXECUTE ON SCHEMA::Seguridad TO rol_AdministradorOperativo, rol_CargadorResultados, rol_GestorPublicidad, rol_ConsultaReportes;

    /* Uso de la clave de los datos personales, si ya está creada (38_Ejecutar_Cifrado.sql).
       Cifrar necesita ver la clave (VIEW DEFINITION); los SP la abren con
       Seguridad.usp_AbrirClave, que se ejecuta como su dueño. Descifrar necesita
       además CONTROL sobre el certificado: se otorga sin ALTER ni TAKE OWNERSHIP,
       así el rol puede usarlo pero no quitarle la clave privada ni apropiárselo
       (y no puede borrarlo porque protege a la clave). Con GRANT por objeto, el
       gestor de publicidad queda sin acceso: para él, descifrar devuelve NULL. */
    IF KEY_ID(N'ClaveDatosPersonales') IS NOT NULL AND CERT_ID(N'CertDatosPersonales') IS NOT NULL
    BEGIN
        GRANT VIEW DEFINITION ON SYMMETRIC KEY::ClaveDatosPersonales TO rol_AdministradorOperativo, rol_CargadorResultados, rol_ConsultaReportes;
        GRANT CONTROL ON CERTIFICATE::CertDatosPersonales TO rol_AdministradorOperativo, rol_CargadorResultados, rol_ConsultaReportes;
        DENY ALTER, TAKE OWNERSHIP ON CERTIFICATE::CertDatosPersonales TO rol_AdministradorOperativo, rol_CargadorResultados, rol_ConsultaReportes;
        DENY VIEW DEFINITION ON SYMMETRIC KEY::ClaveDatosPersonales TO rol_GestorPublicidad;
        DENY CONTROL ON CERTIFICATE::CertDatosPersonales TO rol_GestorPublicidad;
    END;

    /* Evidencia: roles con su usuario de prueba, y el cuadro de permisos. */
    SELECT r.name AS rol,
           u.name AS usuario_prueba_sin_login
    FROM sys.database_role_members AS rm
    INNER JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
    INNER JOIN sys.database_principals AS u ON u.principal_id = rm.member_principal_id
    WHERE r.name LIKE N'rol[_]%' AND u.name LIKE N'usr[_]test[_]%'
    ORDER BY r.name, u.name;

    SELECT pr.name                                              AS rol,
           pe.state_desc                                        AS estado,
           pe.permission_name                                   AS permiso,
           pe.class_desc                                        AS sobre,
           CASE pe.class
                WHEN 3 THEN SCHEMA_NAME(pe.major_id)
                WHEN 1 THEN OBJECT_SCHEMA_NAME(pe.major_id) + N'.' + OBJECT_NAME(pe.major_id)
                WHEN 6 THEN (SELECT SCHEMA_NAME(t.schema_id) + N'.' + t.name
                             FROM sys.types AS t WHERE t.user_type_id = pe.major_id)
                WHEN 24 THEN (SELECT k.name FROM sys.symmetric_keys AS k WHERE k.symmetric_key_id = pe.major_id)
                WHEN 25 THEN (SELECT c.name FROM sys.certificates AS c WHERE c.certificate_id = pe.major_id)
           END                                                  AS objeto
    FROM sys.database_permissions AS pe
    INNER JOIN sys.database_principals AS pr ON pr.principal_id = pe.grantee_principal_id
    WHERE pr.name LIKE N'rol[_]%'
    ORDER BY pr.name, pe.state_desc DESC, pe.class_desc, objeto, pe.permission_name;
END;
GO

EXEC Seguridad.usp_ConfigurarRoles;
GO
