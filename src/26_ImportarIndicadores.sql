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

 Fecha: 29/10/2026
 Archivo: 26_ImportarIndicadores.sql
 Objetivo: Importar el PBI per cápita (NY.GDP.PCAP.CD) de todos los países
           del sistema, con los SP de 25_SP_Importar_Indicadores.sql:
             1. desde el archivo XML que devolvió la API del Banco Mundial
                (2015 a 2025), guardado sin cambios en datos/fuentes/bancomundial/;
             2. consultando la API, para traer los valores de los últimos 10
                años (incluye las revisiones que haya publicado el Banco
                Mundial después de descargar el archivo).
           Requiere haber ejecutado 00 a 25. Se puede ejecutar más de una
           vez: lo que ya está cargado queda SIN CAMBIOS.
================================================================================

 Antes de ejecutar:
   - CAMBIAR @carpeta (sección 1) por la ruta de la carpeta datos\ del
     repositorio en tu máquina. Es distinta para cada uno: depende de dónde
     se clonó el repositorio.
   - La cuenta del servicio de SQL Server tiene que poder leer esa carpeta.
     El error "does not exist or you don't have file access rights" aparece
     tanto si la ruta está mal como si falta el permiso. Para darlo, desde
     PowerShell como administrador (con comillas simples, porque con dobles
     PowerShell toma $ como variable):
       icacls '<carpeta del repositorio>\datos' /grant 'NT Service\MSSQLSERVER:(OI)(CI)RX'
     MSSQLSERVER es la instancia por defecto. Con una instancia con nombre la
     cuenta es NT Service\MSSQL$<instancia>, por ejemplo MSSQL$SQLEXPRESS. El
     nombre se ve con: Get-Service -Name 'MSSQL*'
   - La parte 2 necesita internet y OLE Automation, que la instancia trae
     deshabilitado. Este script lo habilita solo mientras consulta la API y
     después lo deja como estaba. Hace falta ser sysadmin. Si no hay conexión,
     la parte 2 falla con su motivo y la parte 1 queda importada.
   - Para descargar el archivo de nuevo, ver datos/fuentes/bancomundial/README.md.

 Resultado: por cada importación, el resumen (leídos, insertados,
 actualizados, sin cambios, omitidos y rechazados), los omitidos por motivo y
 los rechazados con sus motivos.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- 1. Archivo XML.
-- CAMBIAR: ruta de la carpeta datos\ del repositorio en tu máquina, terminada en \ (ver "Antes de ejecutar").
DECLARE @carpeta  NVARCHAR(400) = N'C:\Users\Rodrigo\Desktop\TP_BBDDA_20262C\datos\';
DECLARE @archivo  NVARCHAR(400) = @carpeta + N'fuentes\bancomundial\pbi_per_capita_2015_2025.xml';

EXEC DatosGenerales.usp_ImportarIndicadoresXML @ruta_archivo = @archivo;
GO


-- 2. API del Banco Mundial, con OLE Automation habilitado solo durante la consulta.
DECLARE @ole_antes        INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                 WHERE name = N'Ole Automation Procedures');
DECLARE @avanzadas_antes  INT = (SELECT CAST(value_in_use AS INT) FROM sys.configurations
                                 WHERE name = N'show advanced options');
DECLARE @numero_error     INT;
DECLARE @mensaje_error    NVARCHAR(2048);

IF @ole_antes = 0
BEGIN
    IF @avanzadas_antes = 0
    BEGIN
        EXEC sp_configure 'show advanced options', 1;
        RECONFIGURE;
    END;
    EXEC sp_configure 'Ole Automation Procedures', 1;
    RECONFIGURE;
END;

BEGIN TRY
    EXEC DatosGenerales.usp_ImportarIndicadoresAPI @codigo_indicador = 'NY.GDP.PCAP.CD';
END TRY
BEGIN CATCH
    SELECT @numero_error = ERROR_NUMBER(), @mensaje_error = ERROR_MESSAGE();
END CATCH;

IF @ole_antes = 0
BEGIN
    EXEC sp_configure 'Ole Automation Procedures', 0;
    RECONFIGURE;
    IF @avanzadas_antes = 0
    BEGIN
        EXEC sp_configure 'show advanced options', 0;
        RECONFIGURE;
    END;
END;

-- El error se informa después de restaurar la configuración.
IF @mensaje_error IS NOT NULL
BEGIN
    SET @numero_error = IIF(@numero_error >= 50000, @numero_error, 50000);
    THROW @numero_error, @mensaje_error, 1;
END;
GO


-- Evidencia: el último PBI per cápita de cada país.
SELECT p.nombre AS pais, p.codigo_iso3, ie.anio AS ultimo_anio, ie.valor AS pbi_per_capita_usd,
       ie.fecha_actualizacion
FROM DatosGenerales.PAIS AS p
OUTER APPLY (SELECT TOP (1) anio, valor, fecha_actualizacion
             FROM DatosGenerales.INDICADOR_ECONOMICO
             WHERE id_pais = p.id_pais AND codigo_indicador = 'NY.GDP.PCAP.CD'
             ORDER BY anio DESC) AS ie
ORDER BY ie.valor DESC;
GO
