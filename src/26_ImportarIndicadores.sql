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
 Objetivo: Importar el PBI per cápita (NY.GDP.PCAP.CD) de los últimos 10
           años de todos los países del sistema, consultando la API del Banco
           Mundial con DatosGenerales.usp_ImportarIndicadoresAPI
           (25_SP_Importar_Indicadores.sql).
           Requiere haber ejecutado 00 a 20, 22 y 25. Va antes de
           32_DatosComplementarios.sql, que usa este PBI para asignar la
           publicidad. Se puede ejecutar más de una vez: lo que ya está
           cargado queda SIN CAMBIOS, y si el Banco Mundial revisó el valor
           de un año, se actualiza.
================================================================================

 Antes de ejecutar:
   - Necesita internet y OLE Automation, que la instancia trae deshabilitado.
     Este script lo habilita solo mientras consulta la API y después lo deja
     como estaba. Hace falta ser sysadmin. Si no hay conexión, falla con su
     motivo y no se importa nada.

 Resultado: el resumen de la importación (leídos, insertados, actualizados,
 sin cambios, omitidos y rechazados), los omitidos por motivo y los
 rechazados con sus motivos.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- API del Banco Mundial, con OLE Automation habilitado solo durante la consulta.
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
