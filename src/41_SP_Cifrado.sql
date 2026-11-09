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
 Archivo: 41_SP_Cifrado.sql
 Objetivo: Crear los objetos del cifrado de los datos personales (nombre,
           apellido y fecha de nacimiento de jugadores, cuerpos técnicos y
           árbitros): el SP que crea las claves, los SP que abren y cierran la
           clave, y las funciones que cifran. Para leer los datos descifrados,
           42_Cifrado_Tablas.sql crea una vista por tabla.
           Su script de testing es 91_Test_SP_Cifrado.sql.
================================================================================

 Orden: lo ejecuta 40_Ejecutar_Cifrado.sql, después de 29_Seguridad.sql (que
 crea el esquema Seguridad). Este script solo crea los objetos; 40 ejecuta
 Seguridad.usp_ConfigurarCifrado con la contraseña de la clave maestra.

 Cómo funciona el cifrado:
   - Jerarquía de claves de la base: la clave maestra de la base protege al
     certificado CertDatosPersonales, y el certificado protege a la clave
     simétrica ClaveDatosPersonales (AES_256), que es la que cifra los datos.
   - ENCRYPTBYKEY cifra con la clave simétrica, que tiene que estar abierta en
     la sesión: los SP que escriben llaman a usp_AbrirClave antes del INSERT o
     UPDATE y a usp_CerrarClave después (y en el CATCH). Una función no puede
     abrir la clave (SQL Server no permite OPEN SYMMETRIC KEY en funciones).
   - Para leer, DECRYPTBYKEYAUTOCERT descifra abriendo la clave con el
     certificado en el momento. Se usa en las vistas Seguridad.vw_Jugador,
     vw_PersonaCuerpoTecnico y vw_Arbitro (42), que tienen las mismas columnas
     que su tabla con los datos personales descifrados: los SP y las vistas que
     leen esos datos leen la vista en lugar de la tabla. No se usa una función
     de descifrado: en una consulta, SQL Server abre la clave una sola vez para
     todas las filas, pero una función que no logra integrar en la consulta se
     ejecuta por separado en cada fila y abre la clave cada vez (una vista de
     715 filas pasaba de 60 ms a 4 segundos). Una vista siempre se integra.
   - ENCRYPTBYKEY da un resultado distinto cada vez para el mismo texto: no se
     puede comparar ni indexar el dato cifrado. Las búsquedas y los controles
     de duplicados comparan sobre las vistas descifradas, dentro de los SP.
   - Permisos. SQL Server controla el uso de la clave y del certificado con el
     usuario que consulta, aunque lo haga a través de un SP o una vista (el
     encadenamiento de propiedad no alcanza a las claves). Por eso:
       * usp_AbrirClave y usp_CerrarClave se ejecutan como su dueño (EXECUTE AS
         OWNER): cualquier SP que escribe puede abrir la clave sin que su
         usuario tenga permiso para abrirla por su cuenta.
       * Cifrar (fn_CifrarTexto, fn_CifrarFecha) necesita ver la clave: VIEW
         DEFINITION sobre ClaveDatosPersonales.
       * Descifrar necesita además CONTROL sobre el certificado. Se otorga con
         DENY de ALTER y TAKE OWNERSHIP, así el rol puede usarlo pero no
         quitarle la clave privada ni apropiárselo; borrarlo tampoco puede,
         porque protege a la clave.
       * Seguridad.usp_ConfigurarRoles (29) da esos permisos solo a los roles
         que trabajan con datos personales. Para los demás, los datos
         descifrados salen NULL.
     Las funciones de cifrado no usan EXECUTE AS a propósito: con EXECUTE AS
     una función no se puede integrar en la consulta y cambia de contexto en
     cada fila.
   - Nadie usa directamente estos objetos: 29 deniega el esquema Seguridad a
     todos los roles; los SP y las vistas los usan por el encadenamiento de
     propiedad.

 Resguardo: si se pierde el certificado, los datos cifrados no se pueden
 recuperar. Después de crearlo, el DBA lo respalda con su clave privada fuera
 del servidor:
     BACKUP CERTIFICATE CertDatosPersonales TO FILE = N'<ruta>\CertDatosPersonales.cer'
         WITH PRIVATE KEY (FILE = N'<ruta>\CertDatosPersonales.pvk',
                           ENCRYPTION BY PASSWORD = N'<contraseña>');
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO


/*
  usp_ConfigurarCifrado
  Crea la clave maestra de la base, el certificado y la clave simétrica, si no
  existen. La contraseña protege a la clave maestra (además de la clave maestra
  del servicio); no se guarda en ninguna tabla. Se puede ejecutar más de una
  vez: lo que ya existe no se recrea, porque recrear el certificado o la clave
  dejaría ilegibles los datos ya cifrados.
*/
CREATE OR ALTER PROCEDURE Seguridad.usp_ConfigurarCifrado
    @contrasenia_clave_maestra NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores NVARCHAR(2048) = N'';
    DECLARE @nl      NCHAR(2)       = NCHAR(13) + NCHAR(10);
    DECLARE @sql     NVARCHAR(MAX);

    IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
       AND NULLIF(TRIM(@contrasenia_clave_maestra), N'') IS NULL
        SET @errores += @nl + N'- La contraseña de la clave maestra es obligatoria.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'Seguridad.usp_ConfigurarCifrado: no se pudo configurar el cifrado.' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* CREATE MASTER KEY no acepta variables: va con SQL dinámico, duplicando las
       comillas de la contraseña. */
    IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    BEGIN
        SET @sql = N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'''
                 + REPLACE(@contrasenia_clave_maestra, N'''', N'''''') + N''';';
        EXEC sys.sp_executesql @sql;
    END;

    IF CERT_ID(N'CertDatosPersonales') IS NULL
        CREATE CERTIFICATE CertDatosPersonales
            WITH SUBJECT = N'Cifrado de datos personales de MundialFutbol',  -- sin comas: separan campos del sujeto
                 EXPIRY_DATE = '20301231';

    IF KEY_ID(N'ClaveDatosPersonales') IS NULL
        CREATE SYMMETRIC KEY ClaveDatosPersonales
            WITH ALGORITHM = AES_256
            ENCRYPTION BY CERTIFICATE CertDatosPersonales;

    SELECT k.name                                  AS clave,
           k.algorithm_desc                        AS algoritmo,
           k.key_length                            AS bits,
           c.name                                  AS protegida_por_certificado,
           c.expiry_date                           AS vence_certificado
    FROM sys.symmetric_keys AS k
    INNER JOIN sys.key_encryptions AS ke ON ke.key_id = k.symmetric_key_id
    INNER JOIN sys.certificates AS c ON c.thumbprint = ke.thumbprint
    WHERE k.name = N'ClaveDatosPersonales';
END;
GO


/*
  usp_AbrirClave
  Abre la clave simétrica en la sesión, para que ENCRYPTBYKEY (en
  fn_CifrarTexto y fn_CifrarFecha) pueda cifrar. Devuelve en @abierta_aca si la
  abrió esta llamada: así, cuando un SP llama a otro que también la abre, el de
  adentro no la cierra antes de que termine el de afuera.
*/
CREATE OR ALTER PROCEDURE Seguridad.usp_AbrirClave
    @abierta_aca BIT = NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM sys.openkeys
               WHERE database_id = DB_ID() AND key_name = N'ClaveDatosPersonales')
        SET @abierta_aca = 0;
    ELSE
    BEGIN
        OPEN SYMMETRIC KEY ClaveDatosPersonales DECRYPTION BY CERTIFICATE CertDatosPersonales;
        SET @abierta_aca = 1;
    END;
END;
GO


/*
  usp_CerrarClave
  Cierra la clave si la abrió el SP que llama (@abierta_aca = 1, lo que
  devolvió usp_AbrirClave) y sigue abierta. Con @abierta_aca = 0 no hace
  nada. No da error si la clave ya estaba cerrada, así que se puede llamar
  también desde el CATCH.
*/
CREATE OR ALTER PROCEDURE Seguridad.usp_CerrarClave
    @abierta_aca BIT = 1
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(@abierta_aca, 0) = 1
       AND EXISTS (SELECT 1 FROM sys.openkeys
                   WHERE database_id = DB_ID() AND key_name = N'ClaveDatosPersonales')
        CLOSE SYMMETRIC KEY ClaveDatosPersonales;
END;
GO


/*
  fn_CifrarTexto
  Cifra un nombre o un apellido. Necesita la clave abierta (usp_AbrirClave):
  con la clave cerrada devuelve NULL, y como nombre y apellido no admiten NULL,
  el INSERT o UPDATE falla en lugar de guardar un dato vacío.
*/
CREATE OR ALTER FUNCTION Seguridad.fn_CifrarTexto (@texto NVARCHAR(60))
RETURNS VARBINARY(256)
AS
BEGIN
    RETURN ENCRYPTBYKEY(KEY_GUID(N'ClaveDatosPersonales'), @texto);
END;
GO


/*
  fn_CifrarFecha
  Cifra una fecha de nacimiento. ENCRYPTBYKEY cifra texto o binario: la fecha
  se guarda como texto aaaa-mm-dd (estilo 23). Necesita la clave abierta; con
  la clave cerrada devuelve NULL, y como la fecha de nacimiento admite NULL,
  los SP que la cifran controlan que no se pierda (fecha con valor y cifrado
  NULL).
*/
CREATE OR ALTER FUNCTION Seguridad.fn_CifrarFecha (@fecha DATE)
RETURNS VARBINARY(256)
AS
BEGIN
    RETURN ENCRYPTBYKEY(KEY_GUID(N'ClaveDatosPersonales'), CONVERT(NVARCHAR(10), @fecha, 23));
END;
GO
