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
 Archivo: 85_Test_CifradoTDE.sql
 Objetivo: Verificar que MundialFutbol está completamente cifrada con TDE
           AES-256 y que el certificado servidor esperado protege su DEK.
================================================================================

 Ejecutar como administrador de SQL Server después de 41_Activar_CifradoTDE.sql.
 La transición a encryption_state = 3 ocurre en segundo plano.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

DECLARE @estado TINYINT,
        @algoritmo NVARCHAR(32),
        @longitud INT,
        @huella VARBINARY(64),
        @huella_esperada VARBINARY(64);

SELECT @estado = encryption_state,
       @algoritmo = key_algorithm,
       @longitud = key_length,
       @huella = encryptor_thumbprint
FROM sys.dm_database_encryption_keys
WHERE database_id = DB_ID();

SELECT @huella_esperada = thumbprint
FROM master.sys.certificates
WHERE name = N'CertMundialFutbolTDE';

SELECT DB_NAME() AS base,
       @estado AS estado_cifrado,
       @algoritmo AS algoritmo,
       @longitud AS bits,
       CONVERT(VARCHAR(130), @huella, 1) AS huella_dek,
       CASE WHEN @estado = 3
                  AND @algoritmo = N'AES'
                  AND @longitud = 256
                  AND @huella = @huella_esperada
            THEN N'OK' ELSE N'FALLÓ' END AS resultado;

IF @estado IS NULL OR @estado <> 3
    THROW 51020, N'TDE todavía no terminó o no está habilitado. Espere y vuelva a ejecutar la verificación.', 1;
IF @algoritmo <> N'AES' OR @longitud <> 256 OR @huella IS NULL OR @huella_esperada IS NULL OR @huella <> @huella_esperada
    THROW 51021, N'La base no está protegida por el certificado y algoritmo esperados.', 1;
GO



