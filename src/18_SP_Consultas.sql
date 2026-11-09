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
 Archivo: 18_SP_Consultas.sql
 Objetivo: Crear los SP de consulta para las aplicaciones, para que no lean
           ninguna tabla directamente (app_abm\abm_sedes.py usa los de países,
           husos y sedes):
             DatosGenerales.usp_ConsultarPaises               países, para elegir uno
             DatosGenerales.usp_ConsultarHusosHorarios        husos de sys.time_zone_info
             DatosGenerales.usp_ConsultarParametroReglamento  un parámetro del reglamento
             Torneo.usp_ConsultarSedes                        sedes, con búsqueda
             Torneo.usp_ConsultarSede                         una sede, con sus 4 tarifas
             Torneo.usp_ConsultarImagenSede                   la foto de una sede
             Torneo.usp_ConsultarSelecciones                  selecciones y su lista
           Requiere haber ejecutado 01 a 06. Su script de testing es
           68_Test_SP_Consultas.sql.
================================================================================

 Por qué SP y no SELECT sobre las tablas: con la seguridad de la Entrega 8
 (29_Seguridad.sql), los roles de aplicación tienen DENY SELECT sobre los
 esquemas de datos. rol_AdministradorOperativo tiene EXECUTE sobre esos
 esquemas, y como los SP y las tablas son de dbo, el encadenamiento de
 propiedad deja que el SP lea las tablas sin dar SELECT a quien lo ejecuta:
 la aplicación funciona con un usuario del rol.

 Los SP de consulta no fallan si no encuentran nada: devuelven la consulta
 vacía (o NULL en el OUTPUT), porque buscar algo que no existe no es un error.
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
  usp_ConsultarPaises
  Todos los países, ordenados por nombre, con su huso horario (la aplicación
  de sedes lo sugiere al elegir el país).
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ConsultarPaises
AS
BEGIN
    SET NOCOUNT ON;

    SELECT id_pais, nombre, codigo_fifa, huso_horario
    FROM DatosGenerales.PAIS
    ORDER BY nombre;
END;
GO


/*
  usp_ConsultarHusosHorarios
  Los husos horarios que acepta SQL Server (sys.time_zone_info), con su desfase
  actual respecto de UTC, ordenados por desfase.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ConsultarHusosHorarios
AS
BEGIN
    SET NOCOUNT ON;

    SELECT name AS huso_horario, current_utc_offset AS desfase_utc
    FROM sys.time_zone_info
    ORDER BY current_utc_offset, name;
END;
GO


/*
  usp_ConsultarParametroReglamento
  El valor de un parámetro del reglamento (ej. MAX_CONVOCADOS), en @valor y
  como consulta. Si el código no existe, @valor queda en NULL.
*/
CREATE OR ALTER PROCEDURE DatosGenerales.usp_ConsultarParametroReglamento
    @codigo  VARCHAR(50),
    @valor   TINYINT = NULL OUTPUT,
    @mostrar BIT     = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT @valor = valor
    FROM DatosGenerales.PARAMETRO_REGLAMENTO
    WHERE codigo = TRIM(@codigo);

    IF @mostrar = 1
        SELECT TRIM(@codigo) AS codigo, @valor AS valor;
END;
GO


/*
  usp_ConsultarSedes
  Las sedes con su país y la cantidad de espacios publicitarios. Con @buscar,
  solo las que lo contienen en el nombre del estadio, la ciudad o el país.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ConsultarSedes
    @buscar NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @patron NVARCHAR(102) = N'%' + ISNULL(TRIM(@buscar), N'') + N'%';

    SELECT s.id_sede, s.nombre_estadio, s.ciudad, p.nombre AS pais, s.capacidad, s.huso_horario,
           (SELECT COUNT(*) FROM Publicidad.ESPACIO_PUBLICITARIO AS e WHERE e.id_sede = s.id_sede) AS espacios
    FROM Torneo.SEDE AS s
    INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
    WHERE s.nombre_estadio LIKE @patron OR s.ciudad LIKE @patron OR p.nombre LIKE @patron
    ORDER BY p.nombre, s.ciudad, s.nombre_estadio;
END;
GO


/*
  usp_ConsultarSede
  Todos los datos de una sede, con las tarifas de sus espacios 1 a 4 (para
  precargar el formulario de edición). Sin fila si la sede no existe.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ConsultarSede
    @id_sede INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.id_sede, s.nombre_estadio, s.ciudad, s.id_pais, p.nombre AS pais, s.capacidad,
           s.huso_horario, s.latitud, s.longitud,
           (SELECT tarifa_usd FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = s.id_sede AND numero_espacio = 1) AS tarifa_espacio_1,
           (SELECT tarifa_usd FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = s.id_sede AND numero_espacio = 2) AS tarifa_espacio_2,
           (SELECT tarifa_usd FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = s.id_sede AND numero_espacio = 3) AS tarifa_espacio_3,
           (SELECT tarifa_usd FROM Publicidad.ESPACIO_PUBLICITARIO WHERE id_sede = s.id_sede AND numero_espacio = 4) AS tarifa_espacio_4
    FROM Torneo.SEDE AS s
    INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
    WHERE s.id_sede = @id_sede;
END;
GO


/*
  usp_ConsultarImagenSede
  La foto de una sede, con su formato y fecha de carga. Sin fila si la sede no
  tiene foto (o no existe).
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ConsultarImagenSede
    @id_sede INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT imagen, formato, fecha_carga
    FROM Torneo.SEDE_IMAGEN
    WHERE id_sede = @id_sede;
END;
GO


/*
  usp_ConsultarSelecciones
  Las selecciones con su país y su lista de convocados (id_lista NULL si
  todavía no la presentó), ordenadas por país.
*/
CREATE OR ALTER PROCEDURE Torneo.usp_ConsultarSelecciones
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.id_seleccion, p.nombre AS pais, s.confederacion, s.grupo,
           l.id_lista, p.id_pais, p.codigo_fifa
    FROM Torneo.SELECCION AS s
    INNER JOIN DatosGenerales.PAIS AS p ON p.id_pais = s.id_pais
    LEFT JOIN Torneo.LISTA_CONVOCADOS AS l ON l.id_seleccion = s.id_seleccion
    ORDER BY p.nombre;
END;
GO


-- Evidencia: SP de consulta creados.
SELECT s.name AS esquema, p.name AS procedimiento, p.modify_date AS ultima_modificacion
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE p.name LIKE N'usp[_]Consultar%'
ORDER BY s.name, p.name;
GO
