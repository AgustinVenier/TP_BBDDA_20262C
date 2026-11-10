# Entrega 8: seguridad y política de respaldos

## Alcance y supuestos

La base `MundialFutbol` guarda datos personales de jugadores, integrantes de cuerpos técnicos y árbitros. Se cifran con AES-256 el nombre, el apellido y la fecha de nacimiento de `Torneo.JUGADOR`, `Torneo.PERSONA_CUERPO_TECNICO` y `Arbitraje.ARBITRO`, y se limita el acceso con roles de base de datos. El cifrado es por columna (`ENCRYPTBYKEY`), así que funciona en cualquier edición de SQL Server, incluida Express. El cifrado y los roles se implementan con SP.

El cifrado no reemplaza la autorización: un usuario con permiso para leer un reporte ve los nombres descifrados. Por eso los roles no tienen `SELECT` ni DML directo sobre las tablas: los cambios se hacen con SP y las consultas con el esquema `Reportes`. La conexión cifrada en tránsito y el firewall se configuran en la instancia y el sistema operativo, fuera de estos scripts.

## Cifrado de los datos personales

### Claves

La clave maestra de la base protege al certificado `CertDatosPersonales`, y el certificado protege a la clave simétrica `ClaveDatosPersonales` (AES-256), que es la que cifra los datos. La clave maestra queda protegida por una contraseña y por la clave maestra del servicio de la instancia.

### Cómo se aplica

El cifrado es un script de modificación sobre la base ya cargada. `40_Ejecutar_Cifrado.sql` se ejecuta después de las importaciones y corre, en orden:

| Script | Qué hace |
|---|---|
| `41_SP_Cifrado.sql` | `Seguridad.usp_ConfigurarCifrado` crea la clave maestra, el certificado y la clave simétrica si no existen. También crea los SP que abren y cierran la clave y las funciones que cifran. |
| `42_Cifrado_Tablas.sql` | `Seguridad.usp_CifrarDatosPersonales` cambia las nueve columnas a `VARBINARY`, cifra los datos existentes y verifica cada fila antes de borrar la columna original, todo en una transacción. Después crea las vistas descifradas. |
| `43_Cifrado_Torneo.sql` | Actualiza los SP de `Torneo` que guardan o buscan personas (ABM, convocatorias, reemplazos, importaciones). |
| `44_Cifrado_DesarrolloYArbitraje.sql` | Lo mismo para `DesarrolloPartido` y `Arbitraje`. |
| `45_Cifrado_Reportes.sql` | Actualiza las vistas y los SP de `Reportes` que muestran nombres. |

La contraseña de la clave maestra se pasa con `:setvar ClaveMaestra` en el runner. El valor del repositorio es de ejemplo y hay que cambiarlo antes de ejecutar. `40` se puede ejecutar más de una vez: lo que ya está cifrado no se vuelve a cifrar, y las claves no se recrean, porque recrearlas dejaría ilegibles los datos cifrados. Después de cifrar se puede seguir importando: los SP de importación cifran lo que guardan.

### Cómo se guardan y se leen los datos

- **Al guardar**, los SP abren la clave con `Seguridad.usp_AbrirClave`, cifran con `Seguridad.fn_CifrarTexto` y `Seguridad.fn_CifrarFecha`, y la cierran con `Seguridad.usp_CerrarClave`, también si hay un error. Si un SP llama a otro, el de adentro no cierra la clave que abrió el de afuera. Con la clave cerrada el cifrado da `NULL`, y como nombre y apellido no admiten `NULL`, el `INSERT` falla en lugar de guardar un dato vacío.
- **Al leer**, los SP y las vistas usan `Seguridad.vw_Jugador`, `Seguridad.vw_PersonaCuerpoTecnico` y `Seguridad.vw_Arbitro`. Tienen las mismas columnas que su tabla, con los datos descifrados por `DECRYPTBYKEYAUTOCERT`. Una vista se integra en la consulta que la usa, así que la clave se abre una sola vez para todas las filas. Una función de descifrado se puede ejecutar fila por fila: en el reporte de suspensiones activas tardó 4,2 segundos, contra 63 ms con la vista.
- Las vistas de `Reportes` devuelven las mismas columnas y los mismos tipos que antes del cifrado, salvo `Reportes.vw_Plantillas`, que ya no devuelve la fecha de nacimiento (ver "Roles y permisos"). Se sacó también del modelo de Power BI, donde ningún visual la usaba.

### Consecuencias en el diseño

- `ENCRYPTBYKEY` da un resultado distinto cada vez, aun para el mismo texto. Por eso no se puede indexar ni comparar el dato cifrado, y se quitaron las restricciones `UNIQUE` que incluían esas columnas (en `JUGADOR` y `ARBITRO`). Los SP controlan los duplicados comparando sobre las vistas descifradas.
- Los tests de entregas anteriores que buscan personas por nombre directamente en las tablas dejan de encontrarlas: 54, 55, 56, 58, 60, 61, 64 y 68. Como su limpieza también busca por nombre, dejan datos de prueba. Los tests 57, 62, 63, 66 y 76 muestran los datos cifrados en lugar de los nombres. Las consultas de evidencia de las secciones 9 y 10 de `33_Cargar_DatosComplementarios.sql` también leen las tablas y fallan sobre la base cifrada; la carga de datos de ese script funciona.

### Resguardo del certificado

Si se pierde el certificado, los datos cifrados no se pueden recuperar. Después de la primera ejecución de `40`, el DBA respalda el certificado con su clave privada fuera del servidor, con acceso restringido, y nunca en el repositorio:

```sql
BACKUP CERTIFICATE CertDatosPersonales
    TO FILE = N'<ruta segura fuera del servidor>\CertDatosPersonales.cer'
    WITH PRIVATE KEY (
        FILE = N'<ruta segura fuera del servidor>\CertDatosPersonales.pvk',
        ENCRYPTION BY PASSWORD = N'<contraseña robusta>'
    );
```

La contraseña de la clave maestra se guarda con el mismo cuidado.

## Roles y permisos

| Rol | Puede | No puede | Datos personales |
|---|---|---|---|
| `rol_AdministradorOperativo` | Ejecutar los ABM y los SP de negocio de todos los módulos, incluidas las importaciones desde tablas de staging; leer y ejecutar `Reportes`. | Leer o modificar tablas directamente; ejecutar los loaders que leen archivos del servidor o consumen APIs; administrar el servidor. | Cifra y descifra (da de alta y modifica personas). |
| `rol_CargadorResultados` | Iniciar y finalizar partidos; registrar formaciones, cambios, goles y amonestaciones mediante SP; leer los partidos (`Reportes.vw_Resultados`) y las plantillas (`Reportes.vw_Plantillas`) para saber qué cargar. | Gestionar publicidad, leer o ejecutar los demás reportes, o leer y modificar tablas directamente. | Descifra (los SP buscan a los jugadores de la formación y de las tarjetas, y las plantillas muestran nombres). |
| `rol_GestorPublicidad` | Ejecutar el ABM y la asignación de publicidad; consultar la ocupación y los ingresos publicitarios. | Consultar reportes deportivos o leer y modificar tablas directamente. | Ninguno: no puede descifrar. |
| `rol_ConsultaReportes` | Leer las vistas y ejecutar los SP del esquema `Reportes`. | Ejecutar operaciones de negocio, importaciones o modificaciones. | Descifra (los reportes muestran nombres). |

La fecha de nacimiento no la ve ningún rol: `Reportes.vw_Plantillas` no la devuelve, porque el reporte de plantillas no la pide (nombre, posición, club y dorsal) y esa vista la leen el cargador de resultados y el rol de consulta, que no la necesitan. Se guarda cifrada y solo la lee el DBA, con las vistas de `Seguridad`. Los tipos de gol que usa el cargador son un catálogo fijo (`28_Cargar_DatosIniciales.sql`), así que no tiene una vista para consultarlos.

`27_SP_Roles.sql` crea el SP `Seguridad.usp_ConfigurarRoles` (el esquema `Seguridad` lo crea `02_CrearEsquemas.sql`). El SP crea los roles y los usuarios de prueba, y otorga los permisos por esquema o por procedimiento. Deniega `SELECT`, `INSERT`, `UPDATE` y `DELETE` directos en los cinco esquemas de datos, y `SELECT` y `EXECUTE` sobre `Seguridad`. Los objetos pertenecen a `dbo`, así que el encadenamiento de propiedad deja que los SP y las vistas usen las tablas sin dar esos permisos a quien los invoca. `40` vuelve a ejecutar el SP después de crear las claves, para dar los permisos sobre la clave.

### Permiso sobre la clave

El encadenamiento de propiedad no alcanza a las claves ni a los certificados. SQL Server comprueba el permiso del usuario que consulta, aunque el descifrado ocurra dentro de una vista; sin ese permiso, el dato descifrado sale `NULL`. Por eso los tres roles que trabajan con datos personales reciben:

- `VIEW DEFINITION` sobre `ClaveDatosPersonales`, necesario para cifrar y descifrar.
- `CONTROL` sobre `CertDatosPersonales`, necesario para descifrar con el certificado.
- `DENY ALTER` y `DENY TAKE OWNERSHIP` sobre el certificado. Así no pueden quitarle la clave privada (lo que dejaría los datos irrecuperables) ni apropiárselo. Tampoco pueden borrar la clave ni el certificado.

El gestor de publicidad recibe `DENY` sobre la clave y el certificado. Los roles no pueden leer los datos cifrados de las tablas, así que solo descifran lo que les muestran los SP y las vistas que tienen permitidos.

### Usuarios

Los usuarios `usr_test_*` son principals `WITHOUT LOGIN`; solo sirven para impersonación en las pruebas. En el despliegue real, el DBA crea o mapea logins de Windows o de aplicación y los agrega al rol que corresponde. No se deben agregar usuarios de aplicación a `db_owner`, `db_datareader` ni `db_datawriter`.

Las importaciones que leen archivos del servidor (`BULK INSERT`, `OPENROWSET(BULK)`) o consumen APIs (OLE Automation) quedan reservadas a una sesión de DBA. Requieren permisos de servidor que no se dan a los roles de aplicación: `ADMINISTER BULK OPERATIONS` y `sysadmin`.

## Política de respaldos

La política de respaldo (RPO, plan de backups, retención, ubicación de las copias y verificación) está en [`Politica-de-Respaldo-Entrega-8.md`](Politica-de-Respaldo-Entrega-8.md). Acá queda solo lo que el cifrado le agrega a una restauración:

- Las columnas cifradas siguen cifradas en los backups, y la clave maestra, el certificado y la clave simétrica viajan con la base. Al restaurar en otra instancia, la clave maestra no se abre sola: hay que abrirla con su contraseña (`OPEN MASTER KEY DECRYPTION BY PASSWORD`) y volver a protegerla con la clave maestra del servicio de esa instancia (`ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY`). Por eso la contraseña de la clave maestra se guarda junto con el backup del certificado.

## Orden de ejecución y pruebas

1. `00_Ejecutar_PrepararBase.sql`: recrea la base, crea los objetos y los roles (`27`) y carga los datos iniciales (`28`).
2. Las importaciones: `30`, `31`, el scraping, `32`, `33`, `34` y `35` (fotos de las sedes).
3. Los tests de las entregas anteriores (`54` a `76`). Van antes del cifrado: después, los que buscan personas por nombre en las tablas no las encuentran y su limpieza deja datos de prueba (ver "Consecuencias en el diseño").
4. `40_Ejecutar_Cifrado.sql`: cifra los datos personales.
5. Los tests de seguridad.
6. `46_Mostrar_ConsultasToBe.sql`, que lee las vistas descifradas que crea `40`.

Hay un script de test por usuario: `77_Test_Rol_Administrador.sql`, `78_Test_Rol_CargadorResultados.sql`, `79_Test_Rol_GestorPublicidad.sql` y `80_Test_Rol_ConsultaReportes.sql`. Cada uno tiene dos partes:

1. Los permisos declarados del usuario (`HAS_PERMS_BY_NAME`), incluidos los de la clave y el certificado.
2. La ejecución real: cada operación se ejecuta como el usuario (`EXECUTE AS USER`) dentro de una transacción que se deshace, así que no queda nada. El resultado dice si la operación quedó permitida o denegada, y, cuando lee datos personales, si el usuario los ve descifrados o como `NULL`.

El cifrado tiene un script de test por cada script del 41 al 45:

- `91_Test_SP_Cifrado.sql` (41): que existan las claves; que `usp_AbrirClave` y `usp_CerrarClave` abran y cierren la clave, sin cerrarla cuando un SP llama a otro; que las funciones den `NULL` con la clave cerrada; que el mismo texto cifrado dos veces dé resultados distintos y se descifre igual.
- `92_Test_Cifrado_Tablas.sql` (42): que las nueve columnas estén cifradas y no queden restricciones `UNIQUE` sobre ellas; que las vistas de `Seguridad` tengan las columnas de su tabla; que todas las filas se puedan descifrar y lo guardado no sea el texto original; que sin abrir la clave no se pueda guardar una persona; que `usp_CifrarDatosPersonales` no vuelva a cifrar lo que ya está cifrado.
- `93_Test_Cifrado_Torneo.sql` (43): que el alta y la modificación de jugadores y cuerpos técnicos guarden cifrado, se lean descifrados y rechacen los duplicados.
- `94_Test_Cifrado_DesarrolloYArbitraje.sql` (44): lo mismo para los árbitros, y que las vistas y la función de partidos y árbitros devuelvan los nombres descifrados.
- `95_Test_Cifrado_Reportes.sql` (45): que las vistas de `Reportes` y el reporte XML devuelvan los nombres descifrados, también para un jugador recién dado de alta.

Todos comprueban, además, que no queden claves abiertas.

Todos los tests terminan con error si algún control no da lo esperado.
