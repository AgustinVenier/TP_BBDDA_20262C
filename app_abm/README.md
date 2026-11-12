# ABM de sedes (Python)

`abm_sedes.py` es una aplicación de escritorio (customtkinter + pyodbc) para el ABM de las sedes del Mundial. No lee ni modifica ninguna tabla directamente: todo pasa por stored procedures, así funciona con un usuario de `rol_AdministradorOperativo`, que tiene denegado el `SELECT` sobre las tablas (`src/06_Seguridad_Roles/27_SP_Roles.sql`).

| Operación | En la aplicación | SP |
|---|---|---|
| Consulta | Tabla de sedes con búsqueda (lupa) | `Torneo.usp_ConsultarSedes` |
| Alta | Formulario "Nueva sede" | `Torneo.usp_RegistrarSede` (la sede y sus 4 espacios publicitarios, en una transacción) |
| Modificación | Clic en una sede: se precargan sus datos y tarifas; "Guardar cambios" | `Torneo.usp_ConsultarSede` y `Torneo.usp_ModificarSede` (la sede y las tarifas, en una transacción) |
| Baja | "Eliminar sede seleccionada" | `Torneo.usp_EliminarSede` (solo una sede sin partidos ni exhibiciones) |
| Foto | Debajo de la tabla: cargar, reemplazar o quitar | `Torneo.usp_ConsultarImagenSede` y `usp_SEDE_IMAGEN_Alta`, `_Modificacion` y `_Baja` |

Los países y los husos horarios de las listas salen de `DatosGenerales.usp_ConsultarPaises` y `usp_ConsultarHusosHorarios` (`src/05_Consultas_Reportes/25_SP_Consultas.sql`). Al elegir el país, sugiere su huso horario.

Antes de subir una foto la achica a 1280 px de lado y la guarda como JPEG (o PNG si tiene transparencia); la base acepta PNG o JPEG de hasta 2 MB. El botón "Importar fotos del repositorio" carga de una vez las 24 fotos prebajadas de `datos/fuentes/sedes/` con `Torneo.usp_ImportarImagenesSedes` (lo mismo que `src/07_Datos/35_Importar_ImagenesSedes.sql`). Como lee archivos del servidor, es una tarea de DBA: `rol_AdministradorOperativo` tiene denegado ese SP, igual que las demás importaciones, y la carpeta tiene que ser visible para el servicio de SQL Server.

El ícono de la ventana y de la barra de tareas es `copa.ico`, un trofeo dibujado para el proyecto (no el trofeo oficial).

## Reportes XML

Además de la pestaña "Sedes", la aplicación tiene la pestaña "Reportes XML" para los reportes XML (R2 y R6, código en `pestanas_xml.py`): elige el reporte y la selección, muestra el XML y lo guarda como `.xml` (carpeta sugerida: `datos/salidas/`).

| Reporte | SP | Opción |
|---|---|---|
| Tarjetas y suspensiones activas | `Reportes.usp_TarjetasXML` | Fecha de corte con un calendario (entra el día elegido completo) |
| Selecciones y plantillas | `Reportes.usp_SeleccionesYPlantillasXML` | Incluir bajas |

La lista de selecciones sale de `Torneo.usp_ConsultarSelecciones`. El XML se muestra en paralelo: a la izquierda el texto tal cual y a la derecha un árbol con los atributos de cada elemento. El XML lo arma el SP; la aplicación solo lo indenta, lo muestra y lo guarda. Si el SP no devuelve filas (un `FOR XML` vacío devuelve `NULL`), avisa que no hay datos. Para ver datos hace falta la base cargada con `31` y `32`.

## Uso

```
pip install -r requirements.txt
python abm_sedes.py
```

Requiere la base `MundialFutbol` creada desde cero con `src/00_Ejecutar_PrepararBase.sql` (incluye los SP de consulta) y el ODBC Driver 18 for SQL Server; para ver las sedes del Mundial y sus fotos, también `32`, `34` y `35`. Por defecto se conecta a `localhost` (la instancia por defecto de SQL Server) con autenticación de Windows. Se puede cambiar con las variables de entorno `MUNDIAL_SERVER` (por ejemplo `localhost\SQLEXPRESS` para una instancia con nombre), `MUNDIAL_DATABASE` y `MUNDIAL_DRIVER`.
