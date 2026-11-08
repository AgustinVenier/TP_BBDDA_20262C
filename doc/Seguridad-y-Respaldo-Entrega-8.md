# Entrega 8: seguridad y política de respaldos

## Alcance y supuestos

La base `MundialFutbol` contiene datos personales de jugadores, integrantes de cuerpos técnicos y árbitros. Se cifra la base completa en reposo con TDE AES-256, y se limita el acceso por roles de base de datos. El diseño de instalación del TP4 toma como plataforma SQL Server 2022 Standard sobre Windows Server 2022; TDE no está disponible en SQL Server Express. La conexión cifrada en tránsito y el firewall se configuran en la instancia y el sistema operativo, fuera de estos scripts de base.

TDE protege los archivos de datos, el registro de transacciones y los backups de esta base. No reemplaza la autorización: un usuario con permiso para leer un dato lo sigue viendo en texto claro. Por eso los roles de aplicación no tienen SELECT ni DML directo sobre tablas de negocio. Las operaciones se exponen mediante SP y las consultas mediante el esquema `Reportes`.

## Matriz de roles

| Rol | Puede | No puede |
|---|---|---|
| `rol_AdministradorOperativo` | Ejecutar ABM y SP de negocio autorizados, además de reportes; leer reportes e invocar importaciones que no leen rutas del servidor. | Leer o modificar tablas directamente; administrar el servidor o ser `db_owner`. |
| `rol_CargadorResultados` | Iniciar/finalizar partidos y registrar formaciones, cambios, goles y amonestaciones mediante SP. | Gestionar publicidad, ejecutar reportes o leer/modificar tablas directamente. |
| `rol_GestorPublicidad` | Ejecutar el ABM y la asignación de publicidad; consultar ocupación e ingresos publicitarios. | Consultar reportes deportivos y leer/modificar tablas directamente. |
| `rol_ConsultaReportes` | Leer vistas y ejecutar SP del esquema `Reportes`. | Ejecutar operaciones de negocio, importación o modificación. |

`40_Seguridad.sql` crea los roles, otorga permisos por esquema o procedimiento y deniega `SELECT`, `INSERT`, `UPDATE` y `DELETE` directos en los esquemas de datos. Los objetos de aplicación pertenecen a `dbo`, por lo que el encadenamiento de propiedad permite que los SP accedan a las tablas sin conceder esos permisos a quien los invoca.

Los usuarios `usr_test_*` son principals `WITHOUT LOGIN`; solo sirven para impersonación en las pruebas. En el despliegue real, el DBA crea o mapea logins de Windows o de aplicación y los agrega al rol correspondiente. No se deben agregar usuarios de aplicación a `db_owner`, `db_datareader` ni `db_datawriter`. Los loaders con `BULK INSERT` u `OPENROWSET(BULK)` quedan reservados a una sesión de DBA controlada: requieren `ADMINISTER BULK OPERATIONS`, un permiso de servidor que no se otorga a roles de aplicación.

## Alta y resguardo del certificado TDE

Este paso se realiza una vez por instancia, como `sysadmin`, antes de ejecutar `37_Ejecutar_PrepararBase.sql`. El certificado vive en `master` y debe respaldarse **antes** de crear el DEK. Guardar la clave privada y su contraseña fuera del servidor, con acceso restringido; nunca subirlos al repositorio. Reemplazar los textos entre `<...>` en una sesión privada y no guardar la copia completada.

```sql
USE master;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'<contraseña robusta de la clave maestra>';
GO
CREATE CERTIFICATE CertMundialFutbolTDE
    WITH SUBJECT = N'Cifrado TDE de MundialFutbol';
GO
BACKUP CERTIFICATE CertMundialFutbolTDE
    TO FILE = N'<ruta segura fuera del servidor>\CertMundialFutbolTDE.cer'
    WITH PRIVATE KEY (
        FILE = N'<ruta segura fuera del servidor>\CertMundialFutbolTDE.pvk',
        ENCRYPTION BY PASSWORD = N'<contraseña robusta distinta>'
    );
GO
```

Si la clave maestra o el certificado ya existen, no recrearlos: verificar la huella del certificado y exportar su clave privada si aún no hay backup. La pérdida de certificado o clave privada puede volver irrecuperables los backups cifrados. Después de respaldar el certificado, `41_Activar_CifradoTDE.sql` crea el DEK de la base nueva, activa TDE y muestra el estado. Esperar `encryption_state = 3` antes de ejecutar `85_Test_CifradoTDE.sql` o de volver a recrear la base.

## Política de respaldos

El objetivo de punto de recuperación (RPO) se ajusta al volumen de escrituras:

| Situación | Completo | Diferencial | Log de transacciones | RPO máximo |
|---|---|---|---|---|
| Días con partidos | Diario, 01:00 | Cada 6 horas | Cada 5 minutos | 5 minutos |
| Días sin partidos | Diario, 01:00 | Cada 12 horas | Cada 15 minutos | 15 minutos |

La base usa recuperación `FULL`, por lo que los backups del log deben ejecutarse de forma regular. Si se interrumpe esa cadena, no se mantiene el RPO definido hasta realizar un nuevo backup completo y restablecer la secuencia.

- Guardar los backups en un volumen distinto de los archivos `.mdf` y `.ldf`; copiar cada backup a un segundo medio y a una ubicación fuera del servidor. Aplicar la regla 3-2-1 y restringir el acceso a operadores de backup.
- Usar `COMPRESSION` y `CHECKSUM` en cada backup. `RESTORE VERIFYONLY` comprueba legibilidad; además, ejecutar `DBCC CHECKDB` semanalmente y restaurar una copia en un servidor aislado al menos mensualmente.
- Retener completos, diferenciales y logs por 35 días. Borrar una cadena solo cuando ya no se necesite para alcanzar un punto de restauración dentro de la retención.
- Para recuperar a un instante: restaurar el último completo con `NORECOVERY`, el diferencial más reciente posterior a ese completo con `NORECOVERY`, y los backups de log en orden; aplicar `STOPAT` si se requiere un instante puntual y terminar con `RECOVERY`.
- Al restaurar una base protegida con TDE, importar en `master` la clave maestra/certificado y la clave privada respaldados, antes de restaurar la base.
- Registrar resultado, duración, tamaño y ubicación de cada backup. La verificación mensual de restauración sirve para medir el RTO real y detectar fallos que una copia creada pero nunca restaurada no revela.

## Pruebas incluidas

Después de ejecutar `40_Seguridad.sql`, correr un script por usuario: `81_Test_Rol_Administrador.sql`, `82_Test_Rol_CargadorResultados.sql`, `83_Test_Rol_GestorPublicidad.sql` y `84_Test_Rol_ConsultaReportes.sql`. Cada uno muestra los permisos efectivos esperados y lanza error si un control no coincide. `85_Test_CifradoTDE.sql` comprueba que el cifrado terminó con AES-256 y que el DEK está protegido por el certificado previsto.



