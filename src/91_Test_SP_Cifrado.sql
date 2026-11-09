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
 Archivo: 91_Test_SP_Cifrado.sql
 Objetivo: Probar los objetos del cifrado de 41_SP_Cifrado.sql: las claves que
           crea Seguridad.usp_ConfigurarCifrado, la apertura y el cierre de la
           clave (Seguridad.usp_AbrirClave y Seguridad.usp_CerrarClave, también
           cuando un SP llama a otro) y las funciones que cifran
           (Seguridad.fn_CifrarTexto y Seguridad.fn_CifrarFecha).
================================================================================

 Requiere haber ejecutado 40_Ejecutar_Cifrado.sql. Ejecutar como dueño de la
 base (dbo). No modifica datos. Si algún control no da lo esperado, el script
 termina con error.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
GO

-- Por si una corrida anterior quedó a medias con la clave abierta.
IF EXISTS (SELECT 1 FROM sys.openkeys WHERE database_id = DB_ID() AND key_name = N'ClaveDatosPersonales')
    CLOSE SYMMETRIC KEY ClaveDatosPersonales;
GO

DECLARE @controles TABLE (n INT IDENTITY, control NVARCHAR(200), esperado NVARCHAR(200), obtenido NVARCHAR(400));
DECLARE @abierta_afuera BIT, @abierta_adentro BIT, @a VARBINARY(256), @b VARBINARY(256), @f VARBINARY(256);

/* 1. Claves (usp_ConfigurarCifrado): clave maestra de la base, certificado y
      clave simétrica AES_256 protegida por el certificado. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Clave maestra de la base', N'existe',
       IIF(EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##'), N'existe', N'no existe');
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Certificado CertDatosPersonales con clave privada', N'ENCRYPTED_BY_MASTER_KEY',
       ISNULL((SELECT pvt_key_encryption_type_desc FROM sys.certificates WHERE name = N'CertDatosPersonales'), N'no existe');
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Clave ClaveDatosPersonales: algoritmo y protección', N'AES_256 por CertDatosPersonales',
       ISNULL((SELECT k.algorithm_desc + N' por ' + c.name
               FROM sys.symmetric_keys AS k
               INNER JOIN sys.key_encryptions AS ke ON ke.key_id = k.symmetric_key_id
               INNER JOIN sys.certificates AS c ON c.thumbprint = ke.thumbprint
               WHERE k.name = N'ClaveDatosPersonales'), N'no existe');

/* 2. Con la clave cerrada, las funciones devuelven NULL (y los SP no pueden
      guardar un nombre vacío: lo prueba 92). */
INSERT INTO @controles (control, esperado, obtenido)
VALUES (N'fn_CifrarTexto con la clave cerrada', N'NULL',
        ISNULL(CONVERT(NVARCHAR(400), Seguridad.fn_CifrarTexto(N'Messi'), 1), N'NULL')),
       (N'fn_CifrarFecha con la clave cerrada', N'NULL',
        ISNULL(CONVERT(NVARCHAR(400), Seguridad.fn_CifrarFecha('1987-06-24'), 1), N'NULL'));

/* 3. usp_AbrirClave abre la clave y avisa que la abrió esta llamada. */
EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_afuera OUTPUT;
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'usp_AbrirClave con la clave cerrada: @abierta_aca y clave en sys.openkeys', N'1, abierta',
       CONCAT(@abierta_afuera, N', ',
              IIF(EXISTS (SELECT 1 FROM sys.openkeys WHERE database_id = DB_ID() AND key_name = N'ClaveDatosPersonales'),
                  N'abierta', N'cerrada'));

/* 4. Un SP llamado por otro: la clave ya está abierta, así que el de adentro
      no la abrió y su usp_CerrarClave no la cierra. */
EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_adentro OUTPUT;
EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_adentro;
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'usp_AbrirClave con la clave abierta y usp_CerrarClave de ese llamado', N'0, sigue abierta',
       CONCAT(@abierta_adentro, N', ',
              IIF(EXISTS (SELECT 1 FROM sys.openkeys WHERE database_id = DB_ID() AND key_name = N'ClaveDatosPersonales'),
                  N'sigue abierta', N'se cerró'));

/* 5. Con la clave abierta: el mismo texto cifrado dos veces da bytes distintos
      (por eso no sirve una restricción UNIQUE) y los dos se descifran igual. */
SELECT @a = Seguridad.fn_CifrarTexto(N'Messi'), @b = Seguridad.fn_CifrarTexto(N'Messi'),
       @f = Seguridad.fn_CifrarFecha('1987-06-24');
INSERT INTO @controles (control, esperado, obtenido)
VALUES (N'fn_CifrarTexto: "Messi" cifrado dos veces', N'bytes distintos, Messi y Messi al descifrar',
        CONCAT(IIF(@a = @b, N'bytes iguales', N'bytes distintos'), N', ',
               CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @a)), N' y ',
               CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @b)),
               N' al descifrar')),
       (N'fn_CifrarFecha: 24/06/1987 descifrada como texto aaaa-mm-dd', N'1987-06-24',
        ISNULL(CONVERT(NVARCHAR(10), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @f)), N'NULL')),
       (N'fn_CifrarTexto: el dato cifrado leído como texto', N'no es Messi',
        IIF(CONVERT(NVARCHAR(60), @a) = N'Messi', N'es Messi', N'no es Messi'));

/* 6. usp_CerrarClave del que la abrió la cierra, y llamarla otra vez no da error
      (se llama también desde el CATCH de los SP). */
EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_afuera;
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'usp_CerrarClave del que la abrió', N'cerrada',
       IIF(EXISTS (SELECT 1 FROM sys.openkeys WHERE database_id = DB_ID() AND key_name = N'ClaveDatosPersonales'),
           N'abierta', N'cerrada');
BEGIN TRY
    EXEC Seguridad.usp_CerrarClave @abierta_aca = 1;
    INSERT INTO @controles (control, esperado, obtenido) VALUES (N'usp_CerrarClave con la clave ya cerrada', N'sin error', N'sin error');
END TRY
BEGIN CATCH
    INSERT INTO @controles (control, esperado, obtenido)
    VALUES (N'usp_CerrarClave con la clave ya cerrada', N'sin error', CONCAT(N'error ', ERROR_NUMBER()));
END CATCH;

/* 7. Al terminar, ninguna clave queda abierta en la sesión. */
INSERT INTO @controles (control, esperado, obtenido)
SELECT N'Claves abiertas en la sesión', N'0', CAST(COUNT(*) AS NVARCHAR(10)) FROM sys.openkeys;

SELECT n, control, esperado, obtenido, IIF(esperado = obtenido, N'OK', N'FALLÓ') AS resultado
FROM @controles
ORDER BY n;

IF EXISTS (SELECT 1 FROM @controles WHERE esperado <> obtenido)
    THROW 51014, N'Los objetos del cifrado (41) no dan lo esperado.', 1;
GO
