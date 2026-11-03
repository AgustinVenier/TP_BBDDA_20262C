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

 Fecha: 03/11/2026
 Archivo: Scraping_Arbitros.py
 Objetivo: Obtener por scraping las designaciones arbitrales del Mundial 2026
           publicadas en Wikipedia y guardarlas en designaciones.csv, una fila
           por partido y rol: partido (fecha y selecciones), rol, nombre,
           apellido y país del árbitro. Los roles son los de
           Arbitraje.DESIGNACION_ARBITRAL: PRINCIPAL, ASISTENTE_1, ASISTENTE_2,
           CUARTO y VAR.
================================================================================

 Páginas de origen (Wikipedia en inglés, licencia CC BY-SA 4.0):
   - 2026 FIFA World Cup Group A ... Group L: los 72 partidos de la fase de grupos.
   - 2026 FIFA World Cup round of 32: los 16 partidos de dieciseisavos.
   - 2026 FIFA World Cup knockout stage: octavos, cuartos, semifinales, tercer
     puesto y final (los dieciseisavos también aparecen, sin designaciones).
   - List of FIFA country codes: el código FIFA de cada selección y país, con el
     que el partido y el árbitro se asocian a la base.
   Wikipedia escribe cada país con el mismo nombre en todas las páginas, así que
   se cruzan por nombre sin tablas de traducción escritas a mano.

 Técnica: scraping de HTML estático (requests + BeautifulSoup con lxml).
   - Partido: cada <div class="footballbox">. De ahí salen la fecha
     (<span class="bday">), las dos selecciones (.fhome y .faway) y el árbitro
     principal ("Referee: Nombre (País)").
   - Asistentes, cuarto árbitro y VAR: el bloque con las etiquetas en negrita
     ("Assistant referees:", "Fourth official:", "Video assistant referee:"), que
     sigue a cada partido. Cada línea es "Nombre (País)".
   Los árbitros de reserva, el asistente de VAR y el VAR de apoyo se descartan
   porque DESIGNACION_ARBITRAL solo tiene cinco roles.

 Límites de uso: Wikipedia no pide clave, pero exige un User-Agent que
 identifique al cliente y pide no hacer muchos pedidos seguidos. El script hace
 16 pedidos por ejecución, uno detrás de otro y por una misma conexión
 (requests.Session). Si Wikipedia responde 429 (demasiados pedidos), espera lo que
 indique el encabezado Retry-After y reintenta, hasta tres veces.

 Uso:
   pip install requests beautifulsoup4 lxml
   python Scraping_Arbitros.py [--salida CARPETA]
 Si no se indica, el CSV se guarda en la carpeta "datos", junto al script.
 Se escribe en UTF-8, separado por comas y con encabezado.
================================================================================
"""

import argparse
import csv
import re
import sys
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

import requests
from bs4 import BeautifulSoup

BASE = 'https://en.wikipedia.org/wiki/'
PAGINAS = ([f'2026_FIFA_World_Cup_Group_{g}' for g in 'ABCDEFGHIJKL']
           + ['2026_FIFA_World_Cup_round_of_32', '2026_FIFA_World_Cup_knockout_stage'])
URL_CODIGOS = BASE + 'List_of_FIFA_country_codes'
USER_AGENT = ('TP-BBDDA-UNLaM-Grupo2/1.0 '
              '(trabajo práctico; https://github.com/AgustinVenier/TP_BBDDA_20262C)')
REINTENTOS_429 = 3       # reintentos si Wikipedia responde 429 (demasiados pedidos)
ESPERA_POR_DEFECTO = 5   # segundos, si la respuesta 429 no trae Retry-After
PAUSA = 1                # segundos entre pedidos

# Etiqueta del bloque de Wikipedia -> rol de DESIGNACION_ARBITRAL. El VAR de apoyo y el
# asistente de VAR tienen su propia etiqueta y quedan fuera.
ROLES = {'Fourth official': 'CUARTO', 'Video assistant referee': 'VAR'}
PERSONA = re.compile(r'^(?P<nombre>.+?)\s*\((?P<pais>[^()]+)\)$')

# Países que Wikipedia escribe distinto en la página de árbitros y en la de códigos FIFA.
# Se completa solo si el script avisa que un país no encontró su código.
ALIAS_PAIS = {}


def segundos_de_espera(respuesta, intento):
    """Lo que pide Retry-After (en segundos o como fecha); si no viene, 5, 10 y 20 s."""
    valor = respuesta.headers.get('Retry-After', '').strip()
    if valor.isdigit():
        return int(valor)
    try:
        return max(0, (parsedate_to_datetime(valor) - datetime.now(timezone.utc)).total_seconds())
    except (TypeError, ValueError):
        return ESPERA_POR_DEFECTO * 2 ** intento


def descargar(sesion, url):
    for intento in range(REINTENTOS_429 + 1):
        respuesta = sesion.get(url, timeout=60)
        if respuesta.status_code != 429 or intento == REINTENTOS_429:
            break
        espera = segundos_de_espera(respuesta, intento)
        print(f'Wikipedia pidió esperar (429): reintento en {espera:.0f} s.')
        time.sleep(espera)
    respuesta.raise_for_status()
    return BeautifulSoup(respuesta.text, 'lxml').select_one('#mw-content-text .mw-parser-output')


def leer_codigos_fifa(contenido):
    """Nombre -> código, solo de la sección "FIFA member codes" (después hay códigos viejos)."""
    codigos = {}
    fin = contenido.find(lambda t: t.name == 'h2' and t.get_text(strip=True) == 'Non-FIFA member codes')
    for tabla in contenido.select('table.wikitable'):
        if fin is not None and tabla.find_previous('h2') is fin:
            break
        for fila in tabla.find_all('tr')[1:]:
            celdas = [re.sub(r'\[.*?\]', '', c.get_text(' ', strip=True)).strip()
                      for c in fila.find_all(['th', 'td'])]
            for i in range(0, len(celdas) - 1, 2):
                if re.fullmatch(r'[A-Z]{3}', celdas[i + 1]):
                    codigos[celdas[i]] = celdas[i + 1]
    return codigos


def separar_persona(texto):
    """"Wilton Sampaio (Brazil)" -> ("Wilton", "Sampaio", "Brazil"). La primera palabra es el
    nombre y el resto el apellido: la fuente no distingue nombre de apellido."""
    texto = re.sub(r'\[[^\]]*\]', '', texto)   # nota al pie pegada al nombre ("[ A ]")
    coincidencia = PERSONA.match(re.sub(r'\s+', ' ', texto).strip())
    if not coincidencia:
        return None
    palabras = coincidencia['nombre'].split(' ')
    nombre, apellido = (palabras[0], ' '.join(palabras[1:])) if len(palabras) > 1 else (palabras[0], palabras[0])
    return nombre, apellido, coincidencia['pais'].strip()


def lineas_por_etiqueta(bloque):
    """{etiqueta: [líneas]} del bloque, que separa cada dato con <br>."""
    for br in bloque.find_all('br'):
        br.replace_with('\n')
    for referencia in bloque.find_all('sup'):
        referencia.decompose()
    resultado, actual = {}, None
    for linea in bloque.get_text().split('\n'):
        linea = re.sub(r'\s+', ' ', linea).strip()
        if linea.endswith(':'):
            actual = linea[:-1]
            resultado[actual] = []
        elif linea and actual:
            resultado[actual].append(linea)
    return resultado


def leer_partidos(contenido, codigos, avisos):
    cajas = contenido.select('div.footballbox')
    filas = []
    for i, caja in enumerate(cajas):
        # El bloque de oficiales es el primero con "Assistant referees:" antes del
        # siguiente partido; si no está, el partido no tiene designaciones en esta página.
        limite = cajas[i + 1] if i + 1 < len(cajas) else None
        bloque = None
        for etiqueta in caja.find_all_next('b'):
            if limite is not None and limite in etiqueta.find_all_previous('div', class_='footballbox'):
                break
            if etiqueta.get_text(strip=True).startswith('Assistant referees'):
                bloque = etiqueta.parent
                break
        if bloque is None:
            continue

        local = caja.select_one('.fhome').get_text(' ', strip=True)
        visitante = caja.select_one('.faway').get_text(' ', strip=True)
        fecha = caja.select_one('span.bday').get_text(strip=True)
        principal = re.search(r'Referee:\s*(.+?)\s*$', caja.select_one('.fright').get_text(' ', strip=True))
        designados = lineas_por_etiqueta(bloque)

        personas = [('PRINCIPAL', principal.group(1).replace(' (', '(').replace('( ', '(').replace(' )', ')'))] \
            if principal else []
        asistentes = designados.get('Assistant referees', [])
        personas += [(f'ASISTENTE_{n}', texto) for n, texto in enumerate(asistentes[:2], start=1)]
        for etiqueta, rol in ROLES.items():
            if designados.get(etiqueta):
                personas.append((rol, designados[etiqueta][0]))

        roles_vistos = {rol for rol, _ in personas}
        faltan = {'PRINCIPAL', 'ASISTENTE_1', 'ASISTENTE_2', 'CUARTO', 'VAR'} - roles_vistos
        if faltan:
            avisos.append(f'{fecha} {local} - {visitante}: sin {", ".join(sorted(faltan))}.')

        for rol, texto in personas:
            persona = separar_persona(texto)
            if persona is None:
                avisos.append(f'{fecha} {local} - {visitante}: no se pudo leer "{texto}" ({rol}).')
                continue
            nombre, apellido, pais = persona
            filas.append({
                'fecha': fecha,
                'codigo_local': codigos.get(local, ''),
                'codigo_visitante': codigos.get(visitante, ''),
                'rol': rol,
                'nombre': nombre,
                'apellido': apellido,
                'pais': pais,
                'codigo_pais': codigos.get(ALIAS_PAIS.get(pais, pais), ''),
            })
            for campo, equipo in (('codigo_local', local), ('codigo_visitante', visitante)):
                if not filas[-1][campo]:
                    avisos.append(f'{equipo}: no se encontró su código FIFA.')
    return filas


def unificar_apellidos(filas):
    """Una misma persona puede figurar con el apellido completo en una página y abreviado en
    otra ("Katia Itzel García" y "Katia García"): se deja la forma más larga, para que la
    base no registre dos árbitros."""
    apellidos = {(f['codigo_pais'], f['nombre'], f['apellido']) for f in filas}
    forma_larga = {}
    for pais, nombre, apellido in apellidos:
        for otro in apellidos:
            if otro[:2] == (pais, nombre) and otro[2].endswith(' ' + apellido):
                forma_larga[(pais, nombre, apellido)] = otro[2]
    for fila in filas:
        fila['apellido'] = forma_larga.get((fila['codigo_pais'], fila['nombre'], fila['apellido']), fila['apellido'])


def guardar(ruta, filas):
    with open(ruta, 'w', encoding='utf-8', newline='') as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=list(filas[0]), quoting=csv.QUOTE_MINIMAL)
        escritor.writeheader()
        escritor.writerows(filas)


def main():
    parser = argparse.ArgumentParser(description='Scraping de las designaciones arbitrales del Mundial 2026 (Wikipedia).')
    parser.add_argument('--salida', default=str(Path(__file__).resolve().parent / 'datos'),
                        help='carpeta donde se guarda designaciones.csv')
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding='utf-8')

    filas, avisos, vistos = [], [], set()
    with requests.Session() as sesion:
        sesion.headers['User-Agent'] = USER_AGENT
        codigos = leer_codigos_fifa(descargar(sesion, URL_CODIGOS))
        for pagina in PAGINAS:
            time.sleep(PAUSA)
            for fila in leer_partidos(descargar(sesion, BASE + pagina), codigos, avisos):
                # La página de eliminatorias repite los partidos de la ronda anterior.
                clave = (fila['fecha'], fila['codigo_local'], fila['codigo_visitante'], fila['rol'])
                if clave not in vistos:
                    vistos.add(clave)
                    filas.append(fila)
    if not filas:
        sys.exit('No se encontró ninguna designación: puede haber cambiado la estructura de la página.')

    unificar_apellidos(filas)
    salida = Path(args.salida)
    salida.mkdir(parents=True, exist_ok=True)
    guardar(salida / 'designaciones.csv', filas)

    partidos = {(f['fecha'], f['codigo_local'], f['codigo_visitante']) for f in filas}
    oficiales = {(f['codigo_pais'] or f['pais'], f['apellido'], f['nombre']) for f in filas}
    print(f'Partidos: {len(partidos)}  Designaciones: {len(filas)}  Oficiales distintos: {len(oficiales)}')
    print(f'Archivo: {salida / "designaciones.csv"}')
    for pais in sorted({f['pais'] for f in filas if not f['codigo_pais']}):
        avisos.append(f'{pais}: no se encontró su código FIFA (completar ALIAS_PAIS).')
    for aviso in avisos:
        print('Aviso:', aviso)


if __name__ == '__main__':
    main()
