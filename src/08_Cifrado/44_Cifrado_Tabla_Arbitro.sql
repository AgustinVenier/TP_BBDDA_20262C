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
 Archivo: 44_Cifrado_Tabla_Arbitro.sql
 Objetivo: Modificar Arbitraje.ARBITRO para que guarde cifrados el nombre, el
           apellido y la fecha de nacimiento de los árbitros, cifrar
           los datos que ya tiene y crear la vista Seguridad.vw_Arbitro, que
           los devuelve descifrados.
           Su script de testing es 94_Test_Cifrado_Tabla_Arbitro.sql.
================================================================================

 Orden: lo ejecuta 40_Ejecutar_Cifrado.sql, después de 41_SP_Cifrado.sql y de
 configurar las claves. Los scripts 42, 43 y 44 hacen lo mismo, cada uno sobre
 su tabla. Después van 45, 46 y 47, que modifican los SP, las funciones y las
 vistas que usan estas columnas: hasta que se ejecutan, los objetos que leen
 las columnas cifradas devuelven bytes.

 Cambios en la tabla:
   - nombre y apellido pasan de NVARCHAR(60) NOT NULL a VARBINARY(256) NOT NULL.
   - fecha_nacimiento pasa de DATE NULL a VARBINARY(256) NULL.
   - Se elimina UQ_ARBITRO_pais_apellido_nombre: el mismo nombre cifrado dos
     veces da bytes distintos, así que la restricción ya no detectaría
     duplicados. Los controlan los SP de alta, modificación e importación
     (46), que descifran y comparan.
   - Las columnas conservan su nombre, pero quedan al final de la tabla.

 Vista descifrada: Seguridad.vw_Arbitro tiene las mismas columnas que la
 tabla, con el nombre, el apellido y la fecha de nacimiento descifrados y con
 su tipo original. Los SP y las vistas que leen esos datos
 (46_Cifrado_DesarrolloYArbitraje.sql y 47_Cifrado_Reportes.sql) leen la
 vista en lugar de la tabla; los que escriben, escriben la tabla y cifran
 con Seguridad.fn_CifrarTexto y Seguridad.fn_CifrarFecha. La vista descifra con los permisos del usuario que
 consulta: quien no tiene permiso sobre la clave (27_SP_Roles.sql) ve NULL.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO


/*
  usp_CifrarArbitro
    1. Guarda los datos cifrados en una tabla temporal.
    2. Elimina las columnas originales y las vuelve a crear como VARBINARY.
    3. Copia los datos cifrados a las columnas nuevas.
  La fecha se cifra como texto aaaa-mm-dd, igual que en fn_CifrarFecha; no se
  usa esa función porque, con la tabla ya cifrada, el SP no se podría volver a
  crear (la columna ya no es DATE).
  - Si algo falla, la transacción se deshace sola (XACT_ABORT) y la tabla queda
    como estaba.
  - Si la clave no está abierta, el cifrado da NULL: el NOT NULL de nombre y
    apellido falla y se deshace todo.
  - Si la tabla ya está cifrada (nombre ya es VARBINARY) no hace nada, así que
    se puede ejecutar más de una vez.
  Devuelve una fila con la tabla, el estado y la cantidad de filas.
*/
CREATE OR ALTER PROCEDURE Seguridad.usp_CifrarArbitro
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado NVARCHAR(30) = N'YA ESTABA CIFRADA';

    IF EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID(N'Arbitraje.ARBITRO') AND name = N'nombre'
                 AND TYPE_NAME(system_type_id) <> N'varbinary')
    BEGIN
        BEGIN TRANSACTION;
        EXEC Seguridad.usp_AbrirClave;

        -- 1. Los datos cifrados, en una tabla temporal.
        SELECT id_arbitro,
               Seguridad.fn_CifrarTexto(nombre)           AS nombre,
               Seguridad.fn_CifrarTexto(apellido)         AS apellido,
               Seguridad.fn_CifrarTexto(CONVERT(NVARCHAR(10), fecha_nacimiento, 23)) AS fecha_nacimiento  -- como fn_CifrarFecha
        INTO #cifrado
        FROM Arbitraje.ARBITRO;

        -- 2. Las columnas originales se reemplazan por columnas VARBINARY con el mismo nombre.
        --    El mismo nombre cifrado dos veces da bytes distintos: la restricción de unicidad ya no sirve.
        ALTER TABLE Arbitraje.ARBITRO DROP CONSTRAINT IF EXISTS UQ_ARBITRO_pais_apellido_nombre;
        ALTER TABLE Arbitraje.ARBITRO DROP COLUMN nombre, apellido, fecha_nacimiento;
        ALTER TABLE Arbitraje.ARBITRO
            ADD nombre           VARBINARY(256) NULL,
                apellido         VARBINARY(256) NULL,
                fecha_nacimiento VARBINARY(256) NULL;

        -- 3. Los datos cifrados vuelven a la tabla; nombre y apellido vuelven a ser obligatorios.
        UPDATE t
        SET nombre           = c.nombre,
            apellido         = c.apellido,
            fecha_nacimiento = c.fecha_nacimiento
        FROM Arbitraje.ARBITRO AS t
        INNER JOIN #cifrado AS c ON c.id_arbitro = t.id_arbitro;

        ALTER TABLE Arbitraje.ARBITRO ALTER COLUMN nombre   VARBINARY(256) NOT NULL;
        ALTER TABLE Arbitraje.ARBITRO ALTER COLUMN apellido VARBINARY(256) NOT NULL;

        EXEC Seguridad.usp_CerrarClave;
        COMMIT TRANSACTION;
        SET @estado = N'CIFRADA';
    END;

    SELECT N'Arbitraje.ARBITRO' AS tabla, @estado AS estado, COUNT(*) AS filas_cifradas
    FROM Arbitraje.ARBITRO;
END;
GO

EXEC Seguridad.usp_CifrarArbitro;
GO


/*
  vw_Arbitro
  La tabla con los datos personales descifrados. DECRYPTBYKEYAUTOCERT abre la
  clave con el certificado en el momento (una vez por consulta), así que no
  hace falta usp_AbrirClave. El resultado se convierte al mismo tipo con que se
  cifró (NVARCHAR): convertirlo a VARCHAR daría otro texto. La fecha está
  guardada como texto aaaa-mm-dd (estilo 23).
*/
CREATE OR ALTER VIEW Seguridad.vw_Arbitro
AS
SELECT a.id_arbitro,
       a.id_pais,
       CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, a.nombre))   AS nombre,
       CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, a.apellido)) AS apellido,
       CONVERT(DATE, CONVERT(NVARCHAR(10),
           DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, a.fecha_nacimiento)), 23)     AS fecha_nacimiento,
       a.categoria,
       a.activo
FROM Arbitraje.ARBITRO AS a;
GO

/* Evidencia: las columnas como quedaron y cómo se ve un dato guardado. */
SELECT c.name                               AS columna,
       TYPE_NAME(c.system_type_id)          AS tipo,
       c.max_length                         AS largo,
       IIF(c.is_nullable = 1, N'SÍ', N'NO') AS admite_null
FROM sys.columns AS c
WHERE c.object_id = OBJECT_ID(N'Arbitraje.ARBITRO')
  AND c.name IN (N'nombre', N'apellido', N'fecha_nacimiento')
ORDER BY c.column_id;

SELECT TOP (3) t.id_arbitro, t.apellido AS apellido_guardado, v.apellido AS apellido_en_Seguridad_vw_Arbitro
FROM Arbitraje.ARBITRO AS t
INNER JOIN Seguridad.vw_Arbitro AS v ON v.id_arbitro = t.id_arbitro
ORDER BY t.id_arbitro;
GO
