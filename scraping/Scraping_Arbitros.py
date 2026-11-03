"""
================================================================================
 Universidad Nacional de La Matanza
 Materia: 3641 - Bases de Datos Aplicada
 Comisión: 01    Grupo: 2
 Integrantes:
   Caruso Dellisanti, Carolina Belen - CarolinaCaruso
   D'Ambrosio, Rodrigo - rodrigoDambrosio
   Tavella, Tomás - TomasTavella
   Venier, Agustin - AgustinVenier

 Fecha: 02/11/2026
 Archivo: Scraping_Arbitros.py
 Objetivo: Obtener por scraping el equipo arbitral de cada partido del
           Mundial 2026 publicado en Wikipedia y guardarlo en
           designaciones_arbitrales.csv, una fila por árbitro designado:
           fecha y selecciones del partido (código FIFA), rol, nombre,
           apellido y país del árbitro (código FIFA). El archivo lo importa
           Arbitraje.usp_ImportarDesignacionesCSV (23_SP_Importar_Mundial2026.sql),
           después de los partidos.
================================================================================

 Páginas de origen (Wikipedia en inglés, licencia CC BY-SA 4.0):
   - 2026 FIFA World Cup Group A ... Group L: los partidos de cada grupo.
   - 2026 FIFA World Cup round of 32: los dieciseisavos de final.
   - 2026 FIFA World Cup knockout stage: de octavos a la final. También
     tiene los dieciseisavos, pero sin el equipo arbitral: de esos partidos
     se toma la página anterior.
   - List of FIFA country codes: el código FIFA de cada selección y del país
     de cada árbitro, para asociarlos a la base sin tablas de traducción
     escritas a mano.

 Técnica: scraping de HTML estático, igual que Scraping_Jugadores.py. Se
 descarga el HTML de cada página con requests y se recorre con BeautifulSoup
 (parser lxml), buscando los elementos por su estructura:
   - Partido: cada <div class="footballbox">. La fecha sale del
     <span class="dtstart"> (formato ISO), las selecciones de las celdas
     .fhome y .faway, y el árbitro principal de la línea "Referee: Nombre
     (País)" de la celda .fright.
   - El resto del equipo arbitral: el párrafo que sigue al partido, con un
     <b> por rol ("Assistant referees:", "Fourth official:", ...) y debajo
     una línea "Nombre (País)" por árbitro.
 El rol se guarda como lo publica la página ("Referee", "Fourth official"),
 salvo los dos asistentes, que se numeran por su orden ("Assistant referee
 1" y "Assistant referee 2"): lo traduce Arbitraje.usp_ImportarDesignaciones.
 La página no marca el apellido: el nombre es la primera palabra y el
 apellido, el resto. Algunos árbitros están escritos de dos formas en
 distintos partidos ("Hamza El-Fariq" y "Hamza El Fariq"): se unifican en la
 forma que más se repite (ver misma_persona), para que sean un solo árbitro.

 Límites de uso: Wikipedia no pide clave, pero exige un User-Agent que
 identifique al cliente y pide no hacer muchos pedidos seguidos. El script
 hace 15 pedidos por ejecución, uno detrás de otro, por una misma conexión
 (requests.Session) y con un segundo de pausa entre cada uno. Si Wikipedia
 responde 429 (demasiados pedidos), espera lo que indique el encabezado
 Retry-After y reintenta, hasta tres veces.

 Uso:
   pip install requests beautifulsoup4 lxml
   python Scraping_Arbitros.py [--salida CARPETA]
 Si no se indica, el CSV se guarda en la carpeta "datos", junto al script.
 Se escribe en UTF-8, separado por comas y con encabezado.
 La documentación completa (fuente, técnica, límites y formato) está en
 README.md, en esta misma carpeta.
"""

import argparse
import csv
import re
import sys
import time
from collections import Counter
from difflib import SequenceMatcher
from pathlib import Path

import requests

# La descarga (User-Agent y reintentos ante un 429), los códigos FIFA y la comparación de nombres
# son los del scraping de jugadores.
from Scraping_Jugadores import USER_AGENT, URL_CODIGOS, descargar, leer_codigos_fifa, plegar

URL_WIKI = 'https://en.wikipedia.org/wiki/'
PAGINAS = ([f'2026_FIFA_World_Cup_Group_{g}' for g in 'ABCDEFGHIJKL']
           + ['2026_FIFA_World_Cup_round_of_32', '2026_FIFA_World_Cup_knockout_stage'])
PAUSA = 1   # segundos entre pedidos

# Roles del párrafo de cada partido, en el orden en que se escriben en el CSV.
ROLES = ['Assistant referees', 'Fourth official', 'Reserve assistant referee', 'Video assistant referee',
         'Assistant video assistant referee', 'Support video assistant referee']


def limpiar(texto):
    """Sin notas ("[14]"), enlaces a otros idiomas ("[de]") ni espacios de más."""
    return ' '.join(re.sub(r'\[[^\]]*\]', '', texto.replace('\xa0', ' ')).split())


def arbitro(linea):
    """"Wilton Sampaio (Brazil)" -> ("Wilton Sampaio", "Brazil")."""
    m = re.fullmatch(r'(.+?)\s*\(([^()]+)\)', limpiar(linea))
    return (m.group(1), m.group(2).strip()) if m else (limpiar(linea), '')


def separar_arbitro(completo):
    """
    La página no marca el apellido: el nombre es la primera palabra y el
    apellido, el resto ("Carlos del Cerro Grande" -> "Carlos", "del Cerro
    Grande"). Con una sola palabra, va en los dos.
    """
    palabras = completo.split()
    if len(palabras) == 1:
        return palabras[0], palabras[0]
    return palabras[0], ' '.join(palabras[1:])


def leer_oficiales(parrafo):
    """Rol -> lista de (nombre completo, país), del párrafo con un <b> por rol."""
    roles, rol = {}, None
    for br in parrafo.find_all('br'):
        br.replace_with('\n')
    for linea in parrafo.get_text().split('\n'):
        linea = limpiar(linea)
        if not linea:
            continue
        if linea.endswith(':'):
            rol = linea[:-1]
            roles[rol] = []
        elif rol is not None:
            roles[rol].append(arbitro(linea))
    return roles


def leer_partidos(contenido):
    """Cada partido de la página, con su equipo arbitral (vacío si la página no lo tiene)."""
    partidos = []
    es_partido = lambda t: t.name == 'div' and 'footballbox' in (t.get('class') or [])
    es_oficiales = lambda t: t.name == 'p' and any('Fourth official' in b.get_text() for b in t.find_all('b'))
    for elemento in contenido.find_all(lambda t: es_partido(t) or es_oficiales(t)):
        if es_partido(elemento):
            principal = re.search(r'Referee:\s*(.+)', elemento.select_one('.fright').get_text(' ', strip=True))
            partidos.append({
                'fecha': elemento.select_one('.dtstart').get_text(strip=True),
                'local': limpiar(elemento.select_one('.fhome').get_text(' ')),
                'visitante': limpiar(elemento.select_one('.faway').get_text(' ')),
                'principal': arbitro(principal.group(1)) if principal else None,
                'oficiales': {},
            })
        elif partidos and not partidos[-1]['oficiales']:
            partidos[-1]['oficiales'] = leer_oficiales(elemento)
    return partidos


def misma_persona(a, b):
    """
    Dos formas de escribir a un árbitro del mismo país: iguales sin tildes ni
    signos ("El-Fariq" y "El Fariq"); con la misma primera y última palabra y
    una dentro de la otra ("Katia García" y "Katia Itzel García"); o casi
    iguales y con la misma última palabra ("Masimiliano" y "Maximiliano Del Yesso").
    """
    pa, pb = a.split(), b.split()
    if plegar(a) == plegar(b):
        return True
    if plegar(pa[-1]) != plegar(pb[-1]):
        return False
    cortas, largas = sorted(([plegar(p) for p in pa], [plegar(p) for p in pb]), key=len)
    if cortas[0] == largas[0] and set(cortas) <= set(largas):
        return True
    return SequenceMatcher(None, plegar(a), plegar(b)).ratio() >= 0.85


def unificar(designados):
    """
    (nombre completo, país) -> la forma que se usa para esa persona: la que
    más veces aparece (y si empatan, la más larga).
    """
    veces = Counter(designados)
    formas = {}
    for completo, pais in sorted(veces, key=lambda f: (-veces[f], -len(f[0]))):
        elegida = next((e for e in formas.values() if e[1] == pais and misma_persona(e[0], completo)), None)
        formas[(completo, pais)] = elegida or (completo, pais)
    return formas


def armar_filas(partidos, codigos):
    filas, avisos = [], []
    # Un partido puede estar en dos páginas (los dieciseisavos): se queda el que tiene el equipo arbitral.
    unicos = {}
    for p in partidos:
        clave = (p['fecha'], p['local'], p['visitante'])
        if clave not in unicos or (p['oficiales'] and not unicos[clave]['oficiales']):
            unicos[clave] = p

    designados = {}
    for (fecha, local, visitante), p in sorted(unicos.items()):
        lista = designados[(fecha, local, visitante)] = []
        if p['principal']:
            lista.append(('Referee', p['principal']))
        for rol in ROLES:
            if rol == 'Assistant referees':
                lista += [(f'Assistant referee {i}', a) for i, a in enumerate(p['oficiales'].get(rol, []), 1)]
            else:
                lista += [(rol, a) for a in p['oficiales'].get(rol, [])]
        if not p['oficiales']:
            avisos.append(f'{fecha} {local} - {visitante}: la página no tiene el equipo arbitral; solo va el principal.')
        for nombre_equipo in (local, visitante):
            if nombre_equipo not in codigos:
                avisos.append(f'{fecha} {local} - {visitante}: no se encontró el código FIFA de "{nombre_equipo}".')

    # Un árbitro escrito de dos formas en distintos partidos queda con una sola.
    formas = unificar([a for lista in designados.values() for _, a in lista])
    for forma, elegida in sorted(formas.items()):
        if forma != elegida:
            avisos.append(f'{forma[0]} ({forma[1]}) se toma como {elegida[0]}.')

    for (fecha, local, visitante), lista in designados.items():
        for rol, arbitro_partido in lista:
            completo, pais = formas[arbitro_partido]
            nombre, apellido = separar_arbitro(completo)
            if pais not in codigos:
                avisos.append(f'{completo}: no se encontró el código FIFA de "{pais}"; se guarda el nombre del país.')
            filas.append({
                'fecha': fecha,
                'local': codigos.get(local, local),
                'visitante': codigos.get(visitante, visitante),
                'rol': rol,
                'nombre': nombre,
                'apellido': apellido,
                'pais': codigos.get(pais, pais),
            })
    return len(unicos), filas, avisos


def guardar(ruta, filas):
    with open(ruta, 'w', encoding='utf-8', newline='') as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=list(filas[0]), quoting=csv.QUOTE_MINIMAL)
        escritor.writeheader()
        escritor.writerows(filas)


def main():
    parser = argparse.ArgumentParser(description='Scraping del equipo arbitral de los partidos del Mundial 2026 (Wikipedia).')
    parser.add_argument('--salida', default=str(Path(__file__).resolve().parent / 'datos'),
                        help='carpeta donde se guarda designaciones_arbitrales.csv')
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding='utf-8')

    # Una sola sesión: los pedidos reusan la conexión y el User-Agent.
    partidos = []
    with requests.Session() as sesion:
        sesion.headers['User-Agent'] = USER_AGENT
        codigos = leer_codigos_fifa(descargar(sesion, URL_CODIGOS))
        for pagina in PAGINAS:
            time.sleep(PAUSA)
            partidos += leer_partidos(descargar(sesion, URL_WIKI + pagina))

    cantidad, filas, avisos = armar_filas(partidos, codigos)
    if not filas:
        sys.exit('No se encontró ningún partido: puede haber cambiado la estructura de las páginas.')

    salida = Path(args.salida)
    salida.mkdir(parents=True, exist_ok=True)
    guardar(salida / 'designaciones_arbitrales.csv', filas)

    arbitros = {(f['nombre'], f['apellido'], f['pais']) for f in filas}
    print(f'Partidos: {cantidad}  Designaciones: {len(filas)}  Árbitros: {len(arbitros)}')
    print(f'Archivo: {salida / "designaciones_arbitrales.csv"}')
    for aviso in avisos:
        print('Aviso:', aviso)


if __name__ == '__main__':
    main()
