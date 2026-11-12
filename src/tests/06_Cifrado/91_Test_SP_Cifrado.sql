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
 Archivo: 91_Test_SP_Cifrado.sql
 Objetivo: Probar los objetos del cifrado de 41_SP_Cifrado.sql: las claves que
           crea usp_ConfigurarCifrado, los SP que abren y cierran la clave
           (usp_AbrirClave y usp_CerrarClave) y las funciones que cifran
           (fn_CifrarTexto y fn_CifrarFecha).
================================================================================

 Requiere haber ejecutado 40_Ejecutar_Cifrado.sql. Ejecutar como dueño de la
 base (dbo). No modifica ningún dato.

 Cada caso es independiente y se puede ejecutar solo. Muestra lo que probó en
 la grilla e imprime una línea en la pestaña Mensajes:
   OK     dio lo esperado.
   ERROR  dio otra cosa.
 El test está bien si ninguna línea empieza con ERROR.
*/

USE MundialFutbol;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF KEY_ID(N'ClaveDatosPersonales') IS NULL
    THROW 51012, N'Falta el cifrado de los datos personales. Ejecute primero 40_Ejecutar_Cifrado.sql.', 1;
GO


/* Caso 1: existen la clave simétrica AES_256 y el certificado que la protege. */
SELECT k.name AS clave, k.algorithm_desc AS algoritmo, c.name AS protegida_por_certificado
FROM sys.symmetric_keys AS k
INNER JOIN sys.key_encryptions AS ke ON ke.key_id = k.symmetric_key_id
INNER JOIN sys.certificates AS c ON c.thumbprint = ke.thumbprint
WHERE k.name = N'ClaveDatosPersonales';

IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'ClaveDatosPersonales' AND algorithm_desc = N'AES_256')
   AND CERT_ID(N'CertDatosPersonales') IS NOT NULL
    PRINT N'OK     1. Existen la clave ClaveDatosPersonales (AES_256) y el certificado CertDatosPersonales.';
ELSE
    PRINT N'ERROR  1. Falta la clave ClaveDatosPersonales (AES_256) o el certificado CertDatosPersonales.';
GO


/* Caso 2: con la clave cerrada, las funciones no cifran: devuelven NULL. */
SELECT Seguridad.fn_CifrarTexto(N'Messi')      AS texto_cifrado,
       Seguridad.fn_CifrarFecha('1987-06-24')  AS fecha_cifrada;

IF Seguridad.fn_CifrarTexto(N'Messi') IS NULL AND Seguridad.fn_CifrarFecha('1987-06-24') IS NULL
    PRINT N'OK     2. Con la clave cerrada, fn_CifrarTexto y fn_CifrarFecha devuelven NULL.';
ELSE
    PRINT N'ERROR  2. Las funciones cifraron con la clave cerrada.';
GO


/* Caso 3: con la clave abierta, fn_CifrarTexto cifra. El mismo texto cifrado
   dos veces da bytes distintos (por eso no sirve una restricción UNIQUE), y
   los dos se descifran igual. */
DECLARE @cifrado_1 VARBINARY(256), @cifrado_2 VARBINARY(256);

EXEC Seguridad.usp_AbrirClave;
SET @cifrado_1 = Seguridad.fn_CifrarTexto(N'Messi');
SET @cifrado_2 = Seguridad.fn_CifrarTexto(N'Messi');
EXEC Seguridad.usp_CerrarClave;

SELECT @cifrado_1 AS cifrado_1, @cifrado_2 AS cifrado_2,
       CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @cifrado_1)) AS descifrado_1,
       CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @cifrado_2)) AS descifrado_2;

IF @cifrado_1 <> @cifrado_2
   AND CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @cifrado_1)) = N'Messi'
   AND CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @cifrado_2)) = N'Messi'
    PRINT N'OK     3. fn_CifrarTexto cifra: dos cifrados del mismo texto son distintos y los dos se descifran como "Messi".';
ELSE
    PRINT N'ERROR  3. fn_CifrarTexto no cifró, dio dos veces lo mismo o no se descifra como "Messi".';
GO


/* Caso 4: con la clave abierta, fn_CifrarFecha cifra la fecha como texto
   aaaa-mm-dd. */
DECLARE @fecha_cifrada VARBINARY(256);

EXEC Seguridad.usp_AbrirClave;
SET @fecha_cifrada = Seguridad.fn_CifrarFecha('1987-06-24');
EXEC Seguridad.usp_CerrarClave;

SELECT @fecha_cifrada AS fecha_cifrada,
       CONVERT(NVARCHAR(10), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @fecha_cifrada)) AS fecha_descifrada;

IF CONVERT(NVARCHAR(10), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, @fecha_cifrada)) = N'1987-06-24'
    PRINT N'OK     4. fn_CifrarFecha cifra la fecha y se descifra como 1987-06-24.';
ELSE
    PRINT N'ERROR  4. fn_CifrarFecha no cifró o la fecha no se descifra como 1987-06-24.';
GO


/* Caso 5: usp_AbrirClave deja la clave abierta en la sesión y usp_CerrarClave
   la cierra. */
DECLARE @abierta_despues_de_abrir BIT = 0, @abierta_despues_de_cerrar BIT = 0;

EXEC Seguridad.usp_AbrirClave;
IF EXISTS (SELECT 1 FROM sys.openkeys WHERE database_id = DB_ID() AND key_name = N'ClaveDatosPersonales')
    SET @abierta_despues_de_abrir = 1;

EXEC Seguridad.usp_CerrarClave;
IF EXISTS (SELECT 1 FROM sys.openkeys WHERE database_id = DB_ID() AND key_name = N'ClaveDatosPersonales')
    SET @abierta_despues_de_cerrar = 1;

SELECT @abierta_despues_de_abrir AS abierta_despues_de_abrir, @abierta_despues_de_cerrar AS abierta_despues_de_cerrar;

IF @abierta_despues_de_abrir = 1 AND @abierta_despues_de_cerrar = 0
    PRINT N'OK     5. usp_AbrirClave abrió la clave y usp_CerrarClave la cerró.';
ELSE
    PRINT N'ERROR  5. usp_AbrirClave no abrió la clave o usp_CerrarClave no la cerró.';
GO


/* Caso 6: usp_CerrarClave con la clave ya cerrada no da error (los SP la
   llaman también desde el CATCH). */
BEGIN TRY
    EXEC Seguridad.usp_CerrarClave;
    PRINT N'OK     6. usp_CerrarClave con la clave ya cerrada no da error.';
END TRY
BEGIN CATCH
    PRINT N'ERROR  6. usp_CerrarClave con la clave ya cerrada dio error: ' + ERROR_MESSAGE();
END CATCH;
GO


/* Caso 7: después de los casos anteriores no queda ninguna clave abierta. */
SELECT key_name AS clave_abierta FROM sys.openkeys;

IF EXISTS (SELECT 1 FROM sys.openkeys)
    PRINT N'ERROR  7. Quedó una clave abierta en la sesión.';
ELSE
    PRINT N'OK     7. No queda ninguna clave abierta en la sesión.';
GO
