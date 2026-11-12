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
 Archivo: 27_SP_Roles.sql
 Objetivo: Crear el SP Seguridad.usp_ConfigurarRoles (el esquema Seguridad lo
           crea 02_CrearEsquemas.sql), que crea los roles de aplicación con
           privilegios mínimos, un usuario sin login por rol y sus
           permisos sobre los SP y las vistas. Se deniega el acceso directo a
           las tablas: los cambios se hacen con los SP y las consultas, con
           las vistas de Reportes y los SP de consulta.
================================================================================

 Orden: ejecutar después de 26_SP_Reportes.sql. Se incluye en
 00_Ejecutar_PrepararBase.sql. Se puede volver a ejecutar: el SP crea solo lo
 que falta y vuelve a aplicar los permisos.

 Usuarios: cada rol tiene un usuario SIN LOGIN (usr_administrador,
 usr_cargador_resultados, usr_gestor_publicidad y usr_consulta). Nadie puede
 iniciar sesión con ellos: los scripts de test los usan con EXECUTE AS USER
 para mostrar los permisos de cada rol. En producción se agregan a los roles
 los usuarios de Windows o los logins de la aplicación; no se agregan usuarios
 a db_owner, db_datareader ni db_datawriter.

 Roles (el cuadro completo de permisos lo devuelve el SP al final):
   rol_AdministradorOperativo  ABM y SP de negocio de todos los módulos,
                               reportes y SP de consulta. Cifra y descifra
                               los datos personales.
   rol_CargadorResultados      Iniciar y finalizar partidos, y registrar
                               formaciones, cambios, goles y amonestaciones.
                               Lee los partidos y las plantillas, para saber
                               qué cargar, y los tipos de gol; el resto de
                               los reportes, no. Descifra.
   rol_GestorPublicidad        ABM y asignación de publicidad, sus reportes
                               y los países. No ve datos personales.
   rol_ConsultaReportes        Solo las vistas y los SP de Reportes, y los
                               países. Descifra.
 Ningún rol lee ni modifica las tablas (tampoco las de catálogos: se
 consultan con los SP de 25_SP_Consultas.sql) ni usa el esquema Seguridad.
 Los permisos sobre la clave de los datos personales (41_SP_Cifrado.sql) se
 dan solo si la clave ya existe: 40_Ejecutar_Cifrado.sql vuelve a ejecutar
 el SP después de crearla.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

/*
  usp_ConfigurarRoles
  Crea los cuatro roles y sus usuarios si no existen, asocia cada
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

    /* Un usuario sin LOGIN por rol: no permite iniciar sesión. */
    IF DATABASE_PRINCIPAL_ID(N'usr_administrador') IS NULL
        CREATE USER usr_administrador WITHOUT LOGIN;
    IF DATABASE_PRINCIPAL_ID(N'usr_cargador_resultados') IS NULL
        CREATE USER usr_cargador_resultados WITHOUT LOGIN;
    IF DATABASE_PRINCIPAL_ID(N'usr_gestor_publicidad') IS NULL
        CREATE USER usr_gestor_publicidad WITHOUT LOGIN;
    IF DATABASE_PRINCIPAL_ID(N'usr_consulta') IS NULL
        CREATE USER usr_consulta WITHOUT LOGIN;

    /* Cada usuario en su rol. */
    IF IS_ROLEMEMBER(N'rol_AdministradorOperativo', N'usr_administrador') = 0
        ALTER ROLE rol_AdministradorOperativo ADD MEMBER usr_administrador;
    IF IS_ROLEMEMBER(N'rol_CargadorResultados', N'usr_cargador_resultados') = 0
        ALTER ROLE rol_CargadorResultados ADD MEMBER usr_cargador_resultados;
    IF IS_ROLEMEMBER(N'rol_GestorPublicidad', N'usr_gestor_publicidad') = 0
        ALTER ROLE rol_GestorPublicidad ADD MEMBER usr_gestor_publicidad;
    IF IS_ROLEMEMBER(N'rol_ConsultaReportes', N'usr_consulta') = 0
        ALTER ROLE rol_ConsultaReportes ADD MEMBER usr_consulta;

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
       reportes no. Los tipos de gol son un catálogo fijo (28_Cargar_DatosIniciales.sql). */
    GRANT SELECT ON OBJECT::Reportes.vw_Resultados TO rol_CargadorResultados;
    GRANT SELECT ON OBJECT::Reportes.vw_Plantillas TO rol_CargadorResultados;

    /* Gestor de publicidad: ABM, asignación y reportes de su módulo. */
    GRANT EXECUTE ON SCHEMA::Publicidad TO rol_GestorPublicidad;
    GRANT SELECT ON OBJECT::Reportes.vw_OcupacionPublicitaria TO rol_GestorPublicidad;
    GRANT SELECT ON OBJECT::Reportes.vw_IngresosPublicitariosPorMoneda TO rol_GestorPublicidad;
    GRANT EXECUTE ON OBJECT::Reportes.usp_OcupacionPublicitaria TO rol_GestorPublicidad;

    /* Consulta: solo vistas y SP del esquema de reportes. */
    GRANT SELECT, EXECUTE ON SCHEMA::Reportes TO rol_ConsultaReportes;

    /* Catálogos: los datos de referencia se consultan con los SP de
       25_SP_Consultas.sql, no leyendo las tablas. El administrador ya los
       tiene por su EXECUTE sobre los esquemas; a los demás se les da el que
       necesitan. */
    GRANT EXECUTE ON OBJECT::DesarrolloPartido.usp_ConsultarTiposGol TO rol_CargadorResultados;
    GRANT EXECUTE ON OBJECT::DatosGenerales.usp_ConsultarPaises TO rol_GestorPublicidad, rol_ConsultaReportes;

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
    DENY EXECUTE ON OBJECT::Arbitraje.usp_ImportarArbitrosCSV TO rol_AdministradorOperativo;
    DENY EXECUTE ON OBJECT::Torneo.usp_ImportarImagenSede TO rol_AdministradorOperativo;
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

    /* Uso de la clave de los datos personales, si ya está creada (40_Ejecutar_Cifrado.sql).
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

    /* Evidencia: roles con su usuario, y el cuadro de permisos. */
    SELECT r.name AS rol,
           u.name AS usuario_sin_login
    FROM sys.database_role_members AS rm
    INNER JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
    INNER JOIN sys.database_principals AS u ON u.principal_id = rm.member_principal_id
    WHERE r.name LIKE N'rol[_]%' AND u.name LIKE N'usr[_]%'
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
