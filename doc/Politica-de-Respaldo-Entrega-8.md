# Política de respaldo de la base MundialFutbol

## Objetivo

Definir cada cuánto se respalda la base `MundialFutbol` y cuántos datos se pueden perder como máximo si hay que recuperarla. Esa pérdida máxima es el **RPO** (objetivo de punto de recuperación).

## Por qué los días de partido son distintos

Los días sin partidos la base casi no cambia: se cargan o corrigen datos de selecciones, plantillas, sedes o publicidad, y esos cambios se pueden volver a hacer a mano si se pierden.

Los días de partido la base recibe la mayor parte de sus escrituras, y casi todas se registran en vivo: el inicio y el final de cada partido, las formaciones, los cambios, los goles y las tarjetas. Si se pierden, hay que reconstruirlas a partir de las planillas, y mientras tanto los reportes muestran resultados y suspensiones incorrectos. Por eso esos días se respalda con más frecuencia.

## Alta disponibilidad y backups

La base corre en dos servidores que se mantienen sincronizados (grupo de disponibilidad, ver el documento de instalación de la Entrega 4). Si se cae uno, el otro toma su lugar en segundos y sin perder datos.

Eso no reemplaza a los backups: el segundo servidor repite todo lo que pasa en el primero, incluidos los errores. Un borrado equivocado o un ataque que cifre los datos llega a los dos al mismo tiempo. Los backups cubren esos casos y la pérdida de los dos servidores.

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

- El **backup del log** es el que fija el RPO: lo que se puede perder es lo escrito desde el último.
- El **diferencial** acorta la recuperación, porque evita aplicar todos los logs desde las 01:00. El del final de la jornada deja todos los resultados del día en un solo archivo.
- Los backups se hacen en el servidor que esté activo en ese momento, así que siguen funcionando aunque uno de los dos se caiga.

## Dónde se guardan y por cuánto tiempo

Se sigue la regla **3-2-1**: tres copias de los datos, en dos medios distintos, con una de ellas fuera del sitio.

| Copia | Dónde | Para qué | Se conserva |
|---|---|---|---|
| Local | Un disco del servidor distinto del de la base | Restaurar rápido | 7 días |
| Fuera del sitio | Nube u otro centro de datos, apenas termina cada backup | Recuperar la base si se pierden los servidores | 35 días |
| En frío | Almacenamiento desconectado o que no se puede modificar ni borrar | Guardar a largo plazo y protegerse de un ataque que borre o cifre las otras copias | 1 año (el backup final del torneo, siempre) |

- Al almacenamiento en frío va el backup completo de cada domingo y, al terminar el torneo, un backup completo final.
- Solo los operadores de backup tienen acceso a esas ubicaciones.
- El certificado que cifra los datos personales se respalda aparte, junto con su contraseña (ver `Seguridad-y-Respaldo-Entrega-8.md`), y se instala en los dos servidores. Sin él, una base restaurada no puede mostrar los nombres de jugadores, cuerpos técnicos y árbitros.

## Si la base falla durante un partido

| Qué pasa | Qué se pierde | Qué se hace |
|---|---|---|
| Se cae un servidor | Nada | El otro toma su lugar en segundos y la carga del partido sigue. |
| Se pierden los dos servidores | Como máximo, los últimos 5 minutos | Se restaura en otro servidor el último completo, el último diferencial y los logs posteriores. |
| Se carga o se borra algo por error (un gol al jugador equivocado) | Nada de lo cargado bien | Se restaura una copia aparte hasta el instante anterior al error y se recuperan de ahí los datos correctos, sin tocar lo cargado después. |

Si hay que restaurar, el partido sigue y el cargador de resultados anota los eventos en la planilla del partido. Cuando la base vuelve, carga lo que falta y compara los reportes con la planilla. El objetivo es que la base vuelva a funcionar en 30 minutos o menos.

## Verificación

Un backup que nunca se restauró no garantiza que se pueda recuperar la base.

| Qué se verifica | Cada cuánto |
|---|---|
| Que cada backup se haya hecho bien y se pueda leer, y que haya llegado la copia fuera del sitio | En cada backup, con aviso al DBA si alguno falla |
| Que la base no tenga datos dañados | Una vez por semana, antes del completo del domingo |
| Que se pueda restaurar la base, incluidos los datos cifrados | Una vez por semana durante el torneo; una vez por mes el resto del año |
| Que se pueda restaurar desde la copia en frío | Una vez por trimestre |
| Que el cambio al segundo servidor funcione | Antes del torneo y una vez por mes, en un día sin partidos |

Antes del inicio del torneo se hace además una prueba completa de recuperación, para medir cuánto tarda y corregir lo que falle.
