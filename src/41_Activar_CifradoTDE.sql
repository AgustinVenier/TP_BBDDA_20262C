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
 Archivo: 41_Activar_CifradoTDE.sql
 Objetivo: Proteger en reposo la base MundialFutbol con TDE AES-256. El DEK
           queda cifrado por el certificado del servidor creado y respaldado
           previamente en master.
================================================================================

 Requisitos: ejecutar como sysadmin en SQL Server 2022 Standard o Enterprise.
 Antes de ejecutar:
   1. Crear en master la clave maestra y el certificado CertMundialFutbolTDE.
   2. Exportar el certificado y su clave privada con contraseña robusta y guardar
      ambos archivos fuera del servidor, en dos ubicaciones controladas.
   3. Seguir el instructivo doc/Seguridad-y-Respaldo-Entrega-8.md. No guardar
      contraseñas ni archivos de clave privada en el repositorio.

 TDE cifra los archivos de datos, el log y los backups de esta base. No cifra
 las conexiones ni oculta datos a usuarios que tengan permiso de consultarlos.
 El acceso lógico se limita aparte con los roles de 40_Seguridad.sql.
*/

USE master;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 51000, N'La activación de TDE requiere sysadmin.', 1;

IF SERVERPROPERTY('EngineEdition') = 4
    THROW 51003, N'TDE no está disponible en SQL Server Express. Use Standard o Enterprise.', 1;

IF DB_ID(N'MundialFutbol') IS NULL
    THROW 51001, N'No existe MundialFutbol. Ejecute primero la preparación de la base.', 1;

IF NOT EXISTS (
    SELECT 1
    FROM master.sys.certificates
    WHERE name = N'CertMundialFutbolTDE'
      AND pvt_key_encryption_type_desc <> N'NO_PRIVATE_KEY'
)
    THROW 51002, N'Falta CertMundialFutbolTDE con clave privada en master. Provisionar y respaldar el certificado antes de activar TDE.', 1;
GO

USE MundialFutbol;
GO

IF EXISTS (
    SELECT 1
    FROM sys.dm_database_encryption_keys AS dek
    CROSS JOIN master.sys.certificates AS cert
    WHERE dek.database_id = DB_ID(N'MundialFutbol')
      AND cert.name = N'CertMundialFutbolTDE'
      AND (dek.encryptor_thumbprint IS NULL OR dek.encryptor_thumbprint <> cert.thumbprint)
)
    THROW 51004, N'La DEK existente usa otro certificado. No se cambia automáticamente; revisar y planificar la rotación del certificado.', 1;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.dm_database_encryption_keys
    WHERE database_id = DB_ID(N'MundialFutbol')
)
BEGIN
    CREATE DATABASE ENCRYPTION KEY
        WITH ALGORITHM = AES_256
        ENCRYPTION BY SERVER CERTIFICATE CertMundialFutbolTDE;
END;
GO

ALTER DATABASE MundialFutbol SET ENCRYPTION ON;
GO

/* La activación es asíncrona; encryption_state = 3 indica que terminó. */
SELECT DB_NAME(dek.database_id) AS base,
       dek.encryption_state,
       dek.encryption_state_desc,
       dek.key_algorithm,
       dek.key_length,
       dek.percent_complete,
       dek.encryptor_type,
       CONVERT(VARCHAR(130), dek.encryptor_thumbprint, 1) AS huella_certificado
FROM sys.dm_database_encryption_keys AS dek
WHERE dek.database_id = DB_ID(N'MundialFutbol');
GO




