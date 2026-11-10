# Política de respaldo de la base MundialFutbol

## Aclaraciones generales

Los días sin partidos la base casi no cambia: se cargan o corrigen datos de selecciones, plantillas, sedes o publicidad, recuperables a mano en caso de pérdida. Los días de partido concentran la mayor parte de las escrituras, casi todas en vivo: inicio y final de cada partido, formaciones, cambios, goles y tarjetas. Perderlas obliga a reconstruirlas desde las planillas y, mientras tanto, los reportes muestran resultados y suspensiones incorrectos, por lo que esos días se respalda con mayor frecuencia.

La base corre sobre dos servidores sincronizados mediante un grupo de disponibilidad: si uno cae, el otro lo reemplaza en segundos sin pérdida de datos. Esto no sustituye a los backups, ya que el segundo servidor replica todo, incluidos los errores, y un borrado equivocado o un ataque que cifre los datos afecta a ambos a la vez. Los backups cubren esos casos y la pérdida de los dos servidores.

## RPO

| Tipo de día | RPO máximo |
|---|---|
| Día con partidos | 5 minutos |
| Día sin partidos | 15 minutos |

Un día se considera "con partidos" hasta las 06:00 del día siguiente, para cubrir los partidos que terminan después de medianoche.

## Plan de backups

| Backup | Días con partidos | Días sin partidos |
|---|---|---|
| Completo | Diario, 01:00 | Diario, 01:00 |
| Diferencial | Cada 6 horas, y uno al terminar el último partido del día | Cada 12 horas |
| Log de transacciones | Cada 5 minutos | Cada 15 minutos |

- El backup del log es el que fija el RPO: lo que se puede perder es lo escrito desde el último [1].
- El diferencial acorta la recuperación, porque evita aplicar todos los logs desde las 01:00. El del final de la jornada deja todos los resultados del día en un solo archivo.
- Los backups se hacen en el servidor que esté activo en ese momento [2], así que siguen funcionando aunque uno de los dos se caiga.

## Dónde se guardan y por cuánto tiempo

Se sigue la regla 3-2-1 [3]: tres copias de los datos, en dos medios distintos, con una de ellas fuera del sitio.

| Copia | Dónde | Para qué | Se conserva |
|---|---|---|---|
| Local | Un disco del servidor distinto del de la base | Restaurar rápido | 7 días |
| Fuera del sitio | Almacenamiento en la nube (Backblaze B2) | Recuperar la base si se pierden los servidores | 35 días |
| En frío | Almacenamiento desconectado o que no se puede modificar ni borrar | Guardar a largo plazo y protegerse de un ataque que borre o cifre las otras copias | 1 año (el backup final del torneo, siempre) |

- Al almacenamiento en frío va el backup completo de cada domingo y, al terminar el torneo, un backup completo final.
- Solo los operadores de backup tienen acceso a esas ubicaciones.
- El certificado que cifra los datos personales se respalda aparte, junto con su contraseña, y se instala en los dos servidores. Sin él, una base restaurada no puede mostrar los nombres de jugadores, cuerpos técnicos y árbitros.

## Verificaciones sobre los backups

| Qué se verifica | Cada cuánto |
|---|---|
| Que cada backup se haya hecho bien y se pueda leer, y que haya llegado la copia fuera del sitio | En cada backup, con aviso al DBA si alguno falla |
| Que la base no tenga datos dañados | Una vez por semana, antes del completo del domingo |
| Que se pueda restaurar la base, incluidos los datos cifrados | Una vez por semana durante el torneo; una vez por mes el resto del año |
| Que se pueda restaurar desde la copia en frío | Una vez por trimestre |
| Que el cambio al segundo servidor funcione | Antes del torneo y una vez por mes, en un día sin partidos |

Antes del inicio del torneo se hace además una prueba completa de recuperación, para medir cuánto tarda y corregir lo que falle.

Referencias:

1. Microsoft. (s.f.). Recovery models (SQL Server). Microsoft Learn. https://learn.microsoft.com/sql/relational-databases/backup-restore/recovery-models-sql-server
2. Microsoft. (s.f.). Offload supported backups to secondary replicas of an availability group. https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/active-secondaries-backup-on-secondary-replicas-always-on-availability-groups
3. Cybersecurity and Infrastructure Security Agency. (s.f.). Back up business data. https://www.cisa.gov/back-business-data
