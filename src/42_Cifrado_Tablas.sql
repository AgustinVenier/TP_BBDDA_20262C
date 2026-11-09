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
 Archivo: 42_Cifrado_Tablas.sql
 Objetivo: Modificar Torneo.JUGADOR, Torneo.PERSONA_CUERPO_TECNICO y
           Arbitraje.ARBITRO para que guarden cifrados el nombre, el apellido y
           la fecha de nacimiento, cifrar los datos que ya tienen y crear una
           vista de cada tabla con esos datos descifrados.
           Su script de testing es 92_Test_Cifrado_Tablas.sql.
================================================================================

 Orden: lo ejecuta 40_Ejecutar_Cifrado.sql, después de 41_SP_Cifrado.sql y de
 configurar las claves. Después van 43, 44 y 45, que modifican los SP, las
 funciones y las vistas que usan estas columnas: entre este script y esos, los
 objetos que leen las columnas cifradas devuelven bytes.

 Cambios en cada tabla:
   - nombre y apellido pasan de NVARCHAR(60) NOT NULL a VARBINARY(256) NOT NULL.
   - fecha_nacimiento pasa de DATE NULL a VARBINARY(256) NULL.
   - Se eliminan UQ_JUGADOR_lista_apellido_nombre y
     UQ_ARBITRO_pais_apellido_nombre: el mismo nombre cifrado dos veces da bytes
     distintos, así que la restricción ya no detectaría duplicados. Los
     controlan los SP de alta, modificación e importación (43 y 44), que
     descifran y comparan.
   - Las columnas conservan su nombre, pero quedan al final de la tabla.

 Vistas descifradas: Seguridad.vw_Jugador, Seguridad.vw_PersonaCuerpoTecnico y
 Seguridad.vw_Arbitro tienen las mismas columnas que su tabla, con el nombre,
 el apellido y la fecha de nacimiento descifrados y con su tipo original. Los
 SP y las vistas que leen esos datos (43, 44 y 45) leen la vista en lugar de la
 tabla; los que escriben, escriben la tabla y cifran con
 Seguridad.fn_CifrarTexto y Seguridad.fn_CifrarFecha. Descifran con los
 permisos del usuario que consulta: quien no tiene permiso sobre la clave
 (29_Seguridad.sql) ve NULL.
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO


/*
  usp_CifrarDatosPersonales
  Por cada tabla: agrega las columnas cifradas, cifra las filas que hay,
  controla que no quede ninguna sin cifrar, reemplaza las columnas originales
  y elimina la restricción de unicidad. Todo en una transacción: si algo falla,
  las tablas quedan como estaban. Una tabla que ya está cifrada (nombre ya es
  VARBINARY) se saltea, así que se puede ejecutar más de una vez.
  Las sentencias que usan las columnas nuevas van con SQL dinámico: un SP que
  nombra una columna que todavía no existe en una tabla existente no compila.
*/
CREATE OR ALTER PROCEDURE Seguridad.usp_CifrarDatosPersonales
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @tablas TABLE (
        orden          TINYINT PRIMARY KEY,
        esquema        SYSNAME,
        tabla          SYSNAME,
        restriccion    SYSNAME NULL,
        estado         NVARCHAR(30) NULL,
        filas          INT NULL
    );
    INSERT INTO @tablas (orden, esquema, tabla, restriccion)
    VALUES (1, N'Torneo',    N'JUGADOR',                N'UQ_JUGADOR_lista_apellido_nombre'),
           (2, N'Torneo',    N'PERSONA_CUERPO_TECNICO', NULL),
           (3, N'Arbitraje', N'ARBITRO',                N'UQ_ARBITRO_pais_apellido_nombre');

    DECLARE @orden TINYINT, @esquema SYSNAME, @tabla SYSNAME, @restriccion SYSNAME,
            @objeto NVARCHAR(300), @sql NVARCHAR(MAX), @filas INT, @sin_cifrar INT,
            @abierta_aca BIT, @mensaje NVARCHAR(2048);

    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC Seguridad.usp_AbrirClave @abierta_aca = @abierta_aca OUTPUT;

        SET @orden = 1;
        WHILE @orden <= 3
        BEGIN
            SELECT @esquema = esquema, @tabla = tabla, @restriccion = restriccion
            FROM @tablas WHERE orden = @orden;
            SET @objeto = QUOTENAME(@esquema) + N'.' + QUOTENAME(@tabla);

            IF EXISTS (SELECT 1 FROM sys.columns
                       WHERE object_id = OBJECT_ID(@objeto) AND name = N'nombre'
                         AND TYPE_NAME(system_type_id) = N'varbinary')
            BEGIN
                SET @sql = N'SELECT @filas = COUNT(*) FROM ' + @objeto + N';';
                EXEC sys.sp_executesql @sql, N'@filas INT OUTPUT', @filas = @filas OUTPUT;
                UPDATE @tablas SET estado = N'YA ESTABA CIFRADA', filas = @filas WHERE orden = @orden;
            END
            ELSE
            BEGIN
                -- 1. La restricción de unicidad sobre nombre y apellido.
                IF @restriccion IS NOT NULL AND OBJECT_ID(QUOTENAME(@esquema) + N'.' + QUOTENAME(@restriccion), N'UQ') IS NOT NULL
                BEGIN
                    SET @sql = N'ALTER TABLE ' + @objeto + N' DROP CONSTRAINT ' + QUOTENAME(@restriccion) + N';';
                    EXEC sys.sp_executesql @sql;
                END;

                -- 2. Las columnas cifradas, que admiten NULL hasta cifrar las filas que hay.
                SET @sql = N'ALTER TABLE ' + @objeto + N' ADD nombre_cifrado VARBINARY(256) NULL, '
                         + N'apellido_cifrado VARBINARY(256) NULL, fecha_nacimiento_cifrada VARBINARY(256) NULL;';
                EXEC sys.sp_executesql @sql;

                -- 3. Las filas que hay, cifradas.
                SET @sql = N'UPDATE ' + @objeto + N' SET nombre_cifrado = Seguridad.fn_CifrarTexto(nombre), '
                         + N'apellido_cifrado = Seguridad.fn_CifrarTexto(apellido), '
                         + N'fecha_nacimiento_cifrada = Seguridad.fn_CifrarFecha(fecha_nacimiento); '
                         + N'SET @filas = @@ROWCOUNT;';
                EXEC sys.sp_executesql @sql, N'@filas INT OUTPUT', @filas = @filas OUTPUT;

                -- 4. Ninguna fila sin cifrar: si la clave no estaba abierta, el cifrado da NULL.
                SET @sql = N'SELECT @sin_cifrar = COUNT(*) FROM ' + @objeto
                         + N' WHERE nombre_cifrado IS NULL OR apellido_cifrado IS NULL'
                         + N' OR (fecha_nacimiento IS NOT NULL AND fecha_nacimiento_cifrada IS NULL)'
                         + N' OR CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N''CertDatosPersonales''), NULL, nombre_cifrado)) <> nombre'
                         + N' OR CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N''CertDatosPersonales''), NULL, apellido_cifrado)) <> apellido'
                         + N' OR CONVERT(NVARCHAR(10), DECRYPTBYKEYAUTOCERT(CERT_ID(N''CertDatosPersonales''), NULL, fecha_nacimiento_cifrada))'
                         + N' <> CONVERT(NVARCHAR(10), fecha_nacimiento, 23);';
                EXEC sys.sp_executesql @sql, N'@sin_cifrar INT OUTPUT', @sin_cifrar = @sin_cifrar OUTPUT;
                IF @sin_cifrar > 0
                BEGIN
                    SET @mensaje = CONCAT(N'Seguridad.usp_CifrarDatosPersonales: ', @sin_cifrar, N' filas de ',
                                          @esquema, N'.', @tabla, N' no se cifraron bien. No se cambió ninguna tabla.');
                    THROW 50001, @mensaje, 1;
                END;

                -- 5. Nombre y apellido vuelven a ser obligatorios.
                SET @sql = N'ALTER TABLE ' + @objeto + N' ALTER COLUMN nombre_cifrado VARBINARY(256) NOT NULL; '
                         + N'ALTER TABLE ' + @objeto + N' ALTER COLUMN apellido_cifrado VARBINARY(256) NOT NULL;';
                EXEC sys.sp_executesql @sql;

                -- 6. Las columnas originales se reemplazan por las cifradas, con el mismo nombre.
                SET @sql = N'ALTER TABLE ' + @objeto + N' DROP COLUMN nombre, apellido, fecha_nacimiento;';
                EXEC sys.sp_executesql @sql;

                SET @sql = @esquema + N'.' + @tabla + N'.nombre_cifrado';
                EXEC sys.sp_rename @sql, N'nombre', N'COLUMN';
                SET @sql = @esquema + N'.' + @tabla + N'.apellido_cifrado';
                EXEC sys.sp_rename @sql, N'apellido', N'COLUMN';
                SET @sql = @esquema + N'.' + @tabla + N'.fecha_nacimiento_cifrada';
                EXEC sys.sp_rename @sql, N'fecha_nacimiento', N'COLUMN';

                UPDATE @tablas SET estado = N'CIFRADA', filas = @filas WHERE orden = @orden;
            END;

            SET @orden += 1;
        END;

        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC Seguridad.usp_CerrarClave @abierta_aca = @abierta_aca;
        THROW;
    END CATCH;

    SELECT esquema + N'.' + tabla AS tabla, estado, filas AS filas_cifradas
    FROM @tablas ORDER BY orden;
END;
GO

EXEC Seguridad.usp_CifrarDatosPersonales;
GO


/*
  vw_Jugador, vw_PersonaCuerpoTecnico, vw_Arbitro
  Cada tabla con los datos personales descifrados. DECRYPTBYKEYAUTOCERT abre la
  clave con el certificado en el momento (una vez por consulta), así que no
  hace falta usp_AbrirClave. El resultado se convierte al mismo tipo con que se
  cifró (NVARCHAR): convertirlo a VARCHAR daría otro texto. La fecha está
  guardada como texto aaaa-mm-dd (estilo 23).
*/
CREATE OR ALTER VIEW Seguridad.vw_Jugador
AS
SELECT j.id_jugador,
       j.id_lista,
       j.id_pais_nacimiento,
       CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, j.nombre))   AS nombre,
       CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, j.apellido)) AS apellido,
       CONVERT(DATE, CONVERT(NVARCHAR(10),
           DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, j.fecha_nacimiento)), 23)     AS fecha_nacimiento,
       j.club_origen,
       j.posicion_habitual,
       j.dorsal,
       j.fecha_alta,
       j.motivo_alta,
       j.fecha_baja,
       j.motivo_baja
FROM Torneo.JUGADOR AS j;
GO

CREATE OR ALTER VIEW Seguridad.vw_PersonaCuerpoTecnico
AS
SELECT ct.id_persona_ct,
       ct.id_seleccion,
       ct.id_pais_nacimiento,
       CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, ct.nombre))   AS nombre,
       CONVERT(NVARCHAR(60), DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, ct.apellido)) AS apellido,
       CONVERT(DATE, CONVERT(NVARCHAR(10),
           DECRYPTBYKEYAUTOCERT(CERT_ID(N'CertDatosPersonales'), NULL, ct.fecha_nacimiento)), 23)     AS fecha_nacimiento,
       ct.rol
FROM Torneo.PERSONA_CUERPO_TECNICO AS ct;
GO

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
SELECT OBJECT_SCHEMA_NAME(c.object_id) + N'.' + OBJECT_NAME(c.object_id) AS tabla,
       c.name                                                          AS columna,
       TYPE_NAME(c.system_type_id)                                     AS tipo,
       c.max_length                                                    AS largo,
       IIF(c.is_nullable = 1, N'SÍ', N'NO')                            AS admite_null
FROM sys.columns AS c
WHERE c.object_id IN (OBJECT_ID(N'Torneo.JUGADOR'), OBJECT_ID(N'Torneo.PERSONA_CUERPO_TECNICO'), OBJECT_ID(N'Arbitraje.ARBITRO'))
  AND c.name IN (N'nombre', N'apellido', N'fecha_nacimiento')
ORDER BY tabla, c.column_id;

SELECT TOP (3) j.id_jugador, j.apellido AS apellido_guardado, v.apellido AS apellido_en_Seguridad_vw_Jugador
FROM Torneo.JUGADOR AS j
INNER JOIN Seguridad.vw_Jugador AS v ON v.id_jugador = j.id_jugador
ORDER BY j.id_jugador;
GO
