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
 Archivo: abm_jugadores.py
 Objetivo: Plantillas del Mundial: alta de jugadores y reemplazos de ultima
           hora. Se elige una seleccion, se ve su plantilla por posicion y se
           agrega un jugador (Torneo.usp_JUGADOR_Alta). Al hacer clic en un
           jugador de la plantilla, el formulario pasa a modo reemplazo y usa
           Torneo.usp_ReemplazarJugador (baja con motivo + alta del
           reemplazante en una sola transaccion). Las validaciones las hacen
           los SP; la aplicacion solo muestra lo que informan.
================================================================================

Usa la misma conexion que abm_paises.py (variables MUNDIAL_SERVER,
MUNDIAL_DATABASE y MUNDIAL_DRIVER).
"""

import csv
import datetime as dt
import tkinter as tk
from pathlib import Path
from tkinter import messagebox

import customtkinter as ctk
import pyodbc

from abm_paises import DATABASE, DRIVER, SERVER, ErrorBD, _limpiar

POSICIONES = [
    # (valor en la base, etiqueta corta, titulo de columna, color)
    ("ARQUERO", "Arq", "Arqueros", "#d4a017"),
    ("DEFENSOR", "Def", "Defensores", "#2f7fd1"),
    ("MEDIOCAMPISTA", "Med", "Mediocampistas", "#2e9e5b"),
    ("DELANTERO", "Del", "Delanteros", "#d1503a"),
]
COLOR_POS = {p[0]: p[3] for p in POSICIONES}
ETIQUETA_A_POS = {p[1]: p[0] for p in POSICIONES}
POS_A_ETIQUETA = {p[0]: p[1] for p in POSICIONES}

TARJETA = ("#ffffff", "#2b2b2b")
BORDE = ("#d5dae3", "#3a3a3a")
TEXTO_SUAVE = ("gray35", "gray65")


# ---------------------------------------------------------------------------
# Acceso a datos
# ---------------------------------------------------------------------------
class Repositorio:
    def __init__(self):
        self.cn = pyodbc.connect(
            f"DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={DATABASE};"
            "Trusted_Connection=yes;TrustServerCertificate=yes;",
            autocommit=True,
            timeout=5,
        )

    def _ejecutar(self, sql, params=()):
        try:
            cur = self.cn.cursor()
            cur.execute(sql, params)
            return cur
        except pyodbc.Error as e:
            raise ErrorBD(_limpiar(e)) from e

    def selecciones(self):
        cur = self._ejecutar(
            """SELECT s.id_seleccion, p.nombre, s.confederacion, s.grupo,
                      l.id_lista, p.id_pais, p.codigo_fifa
               FROM Torneo.SELECCION s
               JOIN DatosGenerales.PAIS p ON p.id_pais = s.id_pais
               LEFT JOIN Torneo.LISTA_CONVOCADOS l ON l.id_seleccion = s.id_seleccion
               ORDER BY p.nombre""")
        return cur.fetchall()

    def jugadores(self, id_seleccion):
        # Lee la vista Reportes.vw_Plantillas (una lista por seleccion): con los datos
        # personales cifrados (Entrega 8), la vista los devuelve descifrados.
        cur = self._ejecutar(
            """SELECT id_jugador, dorsal, nombre, apellido, posicion_habitual,
                      club_origen, fecha_baja
               FROM Reportes.vw_Plantillas WHERE id_seleccion = ?
               ORDER BY dorsal""", (id_seleccion,))
        return cur.fetchall()

    def max_convocados(self):
        cur = self._ejecutar(
            "SELECT valor FROM DatosGenerales.PARAMETRO_REGLAMENTO WHERE codigo = 'MAX_CONVOCADOS'")
        fila = cur.fetchone()
        return int(fila[0]) if fila else 26

    def paises(self):
        cur = self._ejecutar("SELECT id_pais, nombre FROM DatosGenerales.PAIS ORDER BY nombre")
        return cur.fetchall()

    def alta(self, id_lista, d):
        cur = self._ejecutar(
            """SET NOCOUNT ON;
               DECLARE @id INT;
               EXEC Torneo.usp_JUGADOR_Alta
                    @id_lista=?, @nombre=?, @apellido=?, @posicion_habitual=?,
                    @dorsal=?, @fecha_nacimiento=?, @club_origen=?,
                    @id_pais_nacimiento=?, @motivo_alta=?, @id_jugador=@id OUTPUT;
               SELECT @id;""",
            (id_lista, d["nombre"], d["apellido"], d["posicion"], d["dorsal"],
             d["nacimiento"], d["club"], d["id_pais"], d["motivo"]))
        return cur.fetchone()[0]

    def reemplazo(self, id_saliente, fecha, d):
        cur = self._ejecutar(
            """SET NOCOUNT ON;
               DECLARE @id INT;
               EXEC Torneo.usp_ReemplazarJugador
                    @id_jugador_baja=?, @motivo=?, @fecha_cambio=?, @nombre=?,
                    @apellido=?, @posicion_habitual=?, @dorsal=?,
                    @fecha_nacimiento=?, @club_origen=?, @id_pais_nacimiento=?,
                    @id_jugador_alta=@id OUTPUT, @mostrar=0;
               SELECT @id;""",
            (id_saliente, d["motivo"], fecha, d["nombre"], d["apellido"], d["posicion"],
             d["dorsal"], d["nacimiento"], d["club"], d["id_pais"]))
        return cur.fetchone()[0]


CSV_JUGADORES = Path(__file__).resolve().parent.parent / "scraping" / "datos" / "jugadores.csv"
POS_CSV = {"GK": "ARQUERO", "DF": "DEFENSOR", "MF": "MEDIOCAMPISTA", "FW": "DELANTERO"}


def cargar_pool():
    """Jugadores del scraping por codigo FIFA: de ahi salen los no convocados."""
    pool = {}
    try:
        with open(CSV_JUGADORES, encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                pool.setdefault(r["codigo_fifa"], []).append(r)
    except OSError:
        pass
    return pool


def parsear_fecha(texto, campo):
    texto = texto.strip()
    if not texto:
        return None
    try:
        return dt.datetime.strptime(texto, "%d/%m/%Y").date()
    except ValueError:
        raise ErrorBD(f"- {campo}: usá el formato dd/mm/aaaa (por ejemplo 25/12/1998).")


# ---------------------------------------------------------------------------
# Interfaz
# ---------------------------------------------------------------------------
class App(ctk.CTk):
    def __init__(self, repo: Repositorio):
        super().__init__()
        self.repo = repo
        ctk.set_appearance_mode("system")
        ctk.set_default_color_theme("blue")
        self.title("Mundial 2026 - Plantillas")
        self.geometry("1500x860")
        self.minsize(1300, 760)

        self.pool = cargar_pool()
        self.max_conv = repo.max_convocados()
        self.paises = repo.paises()
        self.pais_por_nombre = {n: i for i, n in self.paises}
        self.pais_por_id = {i: n for i, n in self.paises}

        self.sel = None              # fila de la seleccion elegida
        self.jugadores = []          # filas de la plantilla
        self.saliente = None         # fila del jugador a reemplazar (modo reemplazo)
        self.dorsal = None
        self.cards = {}
        self.ghosts = {}
        self.botones_sel = {}
        self.botones_dorsal = {}
        self.ocupados = {}

        self.columnconfigure(1, weight=1)
        self.rowconfigure(0, weight=1)
        self._panel_selecciones()
        self._panel_plantilla()
        self._panel_formulario()
        self._estado = ctk.CTkLabel(self, text="", anchor="w", text_color=TEXTO_SUAVE)
        self._estado.grid(row=1, column=0, columnspan=3, sticky="ew", padx=20, pady=(0, 8))

        self._poblar_selecciones()
        self._actualizar_formulario()

    # -- panel izquierdo: selecciones ---------------------------------------
    def _panel_selecciones(self):
        marco = ctk.CTkFrame(self, corner_radius=12, width=250)
        marco.grid(row=0, column=0, sticky="ns", padx=(20, 8), pady=20)
        marco.grid_propagate(False)
        marco.columnconfigure(0, weight=1)
        marco.rowconfigure(2, weight=1)
        ctk.CTkLabel(marco, text="Selecciones", anchor="w",
                     font=ctk.CTkFont(size=20, weight="bold")).grid(row=0, column=0, sticky="ew", padx=16, pady=(16, 6))
        self.busca_sel = ctk.StringVar()
        self.busca_sel.trace_add("write", lambda *_: self._filtrar_selecciones())
        ctk.CTkEntry(marco, textvariable=self.busca_sel, height=32,
                     placeholder_text="Buscar…").grid(row=1, column=0, sticky="ew", padx=16, pady=(0, 8))
        self.lista_sel = ctk.CTkScrollableFrame(marco, fg_color="transparent")
        self.lista_sel.grid(row=2, column=0, sticky="nsew", padx=6, pady=(0, 10))
        self.lista_sel.columnconfigure(0, weight=1)

    def _poblar_selecciones(self):
        try:
            self.filas_sel = self.repo.selecciones()
        except ErrorBD as e:
            messagebox.showerror("Error", str(e))
            self.filas_sel = []
        for f in self.filas_sel:
            texto = f"{f[1]}   ·   {f[3] or '-'}"
            b = ctk.CTkButton(self.lista_sel, text=texto, anchor="w", height=34, fg_color="transparent",
                              text_color=("gray15", "gray90"), hover_color=("#dde6f3", "#33415a"),
                              command=lambda fila=f: self.elegir_seleccion(fila))
            self.botones_sel[f[0]] = b
        self._filtrar_selecciones()

    def _filtrar_selecciones(self):
        txt = self.busca_sel.get().strip().lower()
        fila = 0
        for f in self.filas_sel:
            b = self.botones_sel[f[0]]
            if txt in f[1].lower():
                b.grid(row=fila, column=0, sticky="ew", pady=1)
                fila += 1
            else:
                b.grid_forget()

    # -- panel central: plantilla -------------------------------------------
    def _panel_plantilla(self):
        marco = ctk.CTkFrame(self, corner_radius=12)
        marco.grid(row=0, column=1, sticky="nsew", padx=8, pady=20)
        marco.columnconfigure(0, weight=1)
        marco.rowconfigure(2, weight=1)

        cab = ctk.CTkFrame(marco, fg_color="transparent")
        cab.grid(row=0, column=0, sticky="ew", padx=20, pady=(16, 4))
        cab.columnconfigure(0, weight=1)
        self.lbl_sel = ctk.CTkLabel(cab, text="Elegí una selección", anchor="w",
                                    font=ctk.CTkFont(size=24, weight="bold"))
        self.lbl_sel.grid(row=0, column=0, sticky="ew")
        self.lbl_cupo = ctk.CTkLabel(cab, text="", text_color=TEXTO_SUAVE)
        self.lbl_cupo.grid(row=0, column=1, sticky="e")
        self.barra = ctk.CTkProgressBar(marco, height=8)
        self.barra.grid(row=1, column=0, sticky="ew", padx=20, pady=(0, 10))
        self.barra.set(0)

        self.zona = ctk.CTkScrollableFrame(marco, fg_color="transparent")
        self.zona.grid(row=2, column=0, sticky="nsew", padx=10, pady=(0, 12))
        self.columnas = {}
        for i, (pos, _e, titulo, color) in enumerate(POSICIONES):
            self.zona.columnconfigure(i, weight=1, uniform="pos")
            ctk.CTkLabel(self.zona, text=titulo.upper(), text_color=color,
                         font=ctk.CTkFont(size=12, weight="bold")).grid(row=0, column=i, pady=(0, 6))
            col = ctk.CTkFrame(self.zona, fg_color="transparent")
            col.grid(row=1, column=i, sticky="new", padx=5)
            col.columnconfigure(0, weight=1)
            self.columnas[pos] = col

    def _tarjeta(self, padre, dorsal, apellido, nombre, club, color, fantasma=False, click=None, baja=False):
        t = ctk.CTkFrame(padre, corner_radius=10, fg_color=TARJETA, border_width=2 if fantasma else 1,
                         border_color=color if fantasma else BORDE)
        t.columnconfigure(1, weight=1)
        gris = "#8a8f98"
        badge = ctk.CTkLabel(t, text=str(dorsal) if dorsal else "?", width=38, height=38, corner_radius=19,
                             fg_color=gris if baja else color, text_color="white",
                             font=ctk.CTkFont(size=14, weight="bold"))
        badge.grid(row=0, column=0, rowspan=2, padx=(10, 8), pady=8)
        l1 = ctk.CTkLabel(t, text=f"{apellido}, {nombre}" if nombre else apellido, anchor="w",
                          text_color=gris if baja else ("gray10", "gray95"),
                          font=ctk.CTkFont(size=13, weight="bold"))
        l1.grid(row=0, column=1, sticky="ew", padx=(0, 8), pady=(8, 0))
        l2 = ctk.CTkLabel(t, text=club or ("dado de baja" if baja else "—"), anchor="w",
                          text_color=TEXTO_SUAVE, font=ctk.CTkFont(size=11))
        l2.grid(row=1, column=1, sticky="ew", padx=(0, 8), pady=(0, 8))
        t.badge, t.l1, t.l2 = badge, l1, l2
        if click:
            for w in (t, badge, l1, l2):
                w.bind("<Button-1>", lambda _e: click())
                w.configure(cursor="hand2")
        return t

    def _dibujar_plantilla(self, resaltar=None):
        for col in self.columnas.values():
            for w in col.winfo_children():
                w.destroy()
        self.cards, self.ghosts = {}, {}
        activos = [j for j in self.jugadores if j.fecha_baja is None]
        for j in self.jugadores:
            color = COLOR_POS[j.posicion_habitual]
            baja = j.fecha_baja is not None
            t = self._tarjeta(self.columnas[j.posicion_habitual], j.dorsal, j.apellido, j.nombre,
                              j.club_origen, color, baja=baja,
                              click=None if baja else (lambda fila=j: self.elegir_saliente(fila)))
            t.grid(sticky="ew", pady=3)
            self.cards[j.id_jugador] = t
        # Tarjeta "fantasma": vista previa del jugador que se esta cargando.
        for pos, *_r in POSICIONES:
            g = self._tarjeta(self.columnas[pos], None, "", "", "", COLOR_POS[pos], fantasma=True)
            self.ghosts[pos] = g
        n = len(activos)
        self.barra.set(min(n / self.max_conv, 1))
        self.barra.configure(progress_color="#d1503a" if n >= self.max_conv else "#3b8ed0")
        bajas = len(self.jugadores) - n
        extra = f"  ·  {bajas} baja(s)" if bajas else ""
        self.lbl_cupo.configure(text=f"{n} / {self.max_conv} convocados{extra}")
        self._marcar_saliente()
        self._vista_previa()
        if resaltar in self.cards:
            c = self.cards[resaltar]
            c.configure(border_color="#2e9e5b", border_width=2)
            self.after(2200, lambda: c.winfo_exists() and c.configure(border_color=BORDE, border_width=1))

    def _marcar_saliente(self):
        for idj, c in self.cards.items():
            sel = self.saliente is not None and idj == self.saliente.id_jugador
            c.configure(border_color="#e67e22" if sel else BORDE, border_width=3 if sel else 1)

    def _vista_previa(self):
        for g in self.ghosts.values():
            g.grid_forget()
        if self.sel is None or self.sel.id_lista is None:
            return
        ap, nom = self.v_apellido.get().strip(), self.v_nombre.get().strip()
        if not (ap or nom or self.dorsal):
            return
        pos = ETIQUETA_A_POS.get(self.seg_pos.get())
        if pos is None:
            return
        g = self.ghosts[pos]
        g.badge.configure(text=str(self.dorsal) if self.dorsal else "?")
        g.l1.configure(text=(f"{ap}, {nom}" if ap and nom else (ap or nom or "Nuevo jugador")))
        g.l2.configure(text=self.v_club.get().strip() or ("Reemplazo" if self.saliente else "Nuevo ingreso"))
        g.grid(sticky="ew", pady=3)

    # -- panel derecho: formulario ------------------------------------------
    def _panel_formulario(self):
        marco = ctk.CTkFrame(self, corner_radius=12, width=410)
        marco.grid(row=0, column=2, sticky="ns", padx=(8, 20), pady=20)
        marco.grid_propagate(False)
        marco.columnconfigure(0, weight=1)
        marco.rowconfigure(0, weight=1)
        f = ctk.CTkScrollableFrame(marco, fg_color="transparent")
        f.grid(row=0, column=0, sticky="nsew", padx=4, pady=4)
        f.columnconfigure((0, 1), weight=1)
        self.form = f

        self.v_nombre, self.v_apellido = ctk.StringVar(), ctk.StringVar()
        self.v_nac, self.v_club = ctk.StringVar(), ctk.StringVar()
        self.v_motivo = ctk.StringVar()
        self.v_fecha_cambio = ctk.StringVar(value=dt.date.today().strftime("%d/%m/%Y"))
        self.v_pais = ctk.StringVar()

        self.titulo = ctk.CTkLabel(f, text="Nuevo jugador", anchor="w", font=ctk.CTkFont(size=20, weight="bold"))
        self.titulo.grid(row=0, column=0, columnspan=2, sticky="ew", padx=12, pady=(10, 0))
        self.ayuda = ctk.CTkLabel(f, text="", anchor="w", justify="left", wraplength=360, text_color=TEXTO_SUAVE)
        self.ayuda.grid(row=1, column=0, columnspan=2, sticky="ew", padx=12, pady=(0, 4))

        self.zona_top = ctk.CTkFrame(f, fg_color="transparent")
        self.zona_top.grid(row=2, column=0, columnspan=2, sticky="ew")
        self.zona_top.columnconfigure(0, weight=1)
        self.banner = ctk.CTkFrame(self.zona_top, corner_radius=8, fg_color=("#fdebd3", "#5a3a14"))
        self.banner.columnconfigure(0, weight=1)
        self.lbl_banner = ctk.CTkLabel(self.banner, text="", anchor="w", justify="left", wraplength=250)
        self.lbl_banner.grid(row=0, column=0, sticky="ew", padx=10, pady=8)
        ctk.CTkButton(self.banner, text="Cancelar", width=80, height=28, fg_color="transparent", border_width=1,
                      text_color=("gray20", "gray90"), command=self.cancelar_reemplazo).grid(row=0, column=1, padx=8)

        self.btn_pool = ctk.CTkButton(self.zona_top, text="Elegir de no convocados…", height=32, fg_color="transparent",
                                      border_width=1, text_color=("gray20", "gray90"),
                                      command=self.abrir_no_convocados)
        self.btn_pool.grid(row=1, column=0, sticky="ew", padx=12, pady=(6, 0))

        self._campo(f, 3, "Nombre *", self.v_nombre, col=0)
        self._campo(f, 3, "Apellido *", self.v_apellido, col=1)

        ctk.CTkLabel(f, text="Posición *", anchor="w").grid(row=5, column=0, columnspan=2, sticky="ew", padx=12, pady=(8, 0))
        self.seg_pos = ctk.CTkSegmentedButton(f, values=[p[1] for p in POSICIONES], command=lambda _v: self._cambio())
        self.seg_pos.grid(row=6, column=0, columnspan=2, sticky="ew", padx=12)

        self.lbl_dorsal = ctk.CTkLabel(f, text="Dorsal *", anchor="w")
        self.lbl_dorsal.grid(row=7, column=0, columnspan=2, sticky="ew", padx=12, pady=(10, 2))
        grilla = ctk.CTkFrame(f, fg_color="transparent")
        grilla.grid(row=8, column=0, columnspan=2, padx=12)
        for n in range(1, 100):
            b = ctk.CTkButton(grilla, text=str(n), width=34, height=26, corner_radius=6,
                              font=ctk.CTkFont(size=11), command=lambda x=n: self.elegir_dorsal(x))
            b.grid(row=(n - 1) // 10, column=(n - 1) % 10, padx=1, pady=1)
            b.bind("<Enter>", lambda _e, x=n: self._hover_dorsal(x))
            self.botones_dorsal[n] = b

        self._campo(f, 9, "Fecha de nacimiento (dd/mm/aaaa)", self.v_nac, col=0, span=2, ejemplo="25/12/1998")
        self._campo(f, 11, "Club de origen", self.v_club, col=0, span=2)
        ctk.CTkLabel(f, text="País de nacimiento", anchor="w").grid(row=13, column=0, columnspan=2, sticky="ew", padx=12, pady=(8, 0))
        self.cbo_pais = ctk.CTkComboBox(f, values=[n for _i, n in self.paises], variable=self.v_pais, height=32)
        self.cbo_pais.grid(row=14, column=0, columnspan=2, sticky="ew", padx=12)

        self.lbl_motivo = ctk.CTkLabel(f, text="Motivo", anchor="w")
        self.lbl_motivo.grid(row=15, column=0, columnspan=2, sticky="ew", padx=12, pady=(8, 0))
        ctk.CTkEntry(f, textvariable=self.v_motivo, height=32).grid(row=16, column=0, columnspan=2, sticky="ew", padx=12)
        self.lbl_fecha = ctk.CTkLabel(f, text="Fecha del cambio *", anchor="w")
        self.ent_fecha = ctk.CTkEntry(f, textvariable=self.v_fecha_cambio, height=32)

        self.btn_guardar = ctk.CTkButton(f, text="Agregar jugador", height=40, command=self.guardar)
        self.btn_guardar.grid(row=19, column=0, columnspan=2, sticky="ew", padx=12, pady=(18, 4))
        ctk.CTkButton(f, text="Limpiar", height=30, fg_color="transparent", border_width=1,
                      text_color=("gray20", "gray90"), command=self.limpiar).grid(row=20, column=0, columnspan=2, sticky="ew", padx=12, pady=(0, 12))

        for v in (self.v_nombre, self.v_apellido, self.v_club, self.v_motivo, self.v_fecha_cambio):
            v.trace_add("write", lambda *_: self._cambio())

    def _campo(self, padre, fila, etiqueta, var, col, span=1, ejemplo=None):
        ctk.CTkLabel(padre, text=etiqueta, anchor="w").grid(row=fila, column=col, columnspan=span, sticky="ew", padx=12, pady=(8, 0))
        e = ctk.CTkEntry(padre, textvariable=var, height=32, placeholder_text=f"ej. {ejemplo}" if ejemplo else None)
        e.grid(row=fila + 1, column=col, columnspan=span, sticky="ew", padx=12)
        return e

    # -- logica de pantalla -------------------------------------------------
    def elegir_seleccion(self, fila):
        self.sel = fila
        self.saliente = None
        for idf, b in self.botones_sel.items():
            b.configure(fg_color=("#cfe0f7", "#27406b") if idf == fila[0] else "transparent")
        self.lbl_sel.configure(text=f"{fila[1]}")
        self.limpiar()
        self.v_pais.set(self.pais_por_id.get(fila[5], ""))
        if fila.id_lista is None:
            self.jugadores = []
            self._dibujar_plantilla()
            self.lbl_cupo.configure(text="Sin lista de convocados")
        else:
            self._recargar()
        self._estado.configure(
            text=f"{fila[1]}  ·  {fila[2]}  ·  Grupo {fila[3] or '-'}  ·  {SERVER}  ·  {DATABASE}")
        self._actualizar_formulario()

    def _recargar(self, resaltar=None):
        try:
            self.jugadores = self.repo.jugadores(self.sel.id_seleccion)
        except ErrorBD as e:
            messagebox.showerror("Error", str(e))
            return
        self.ocupados = {j.dorsal: f"{j.apellido}, {j.nombre}" for j in self.jugadores if j.fecha_baja is None}
        self._dibujar_plantilla(resaltar)
        self._pintar_dorsales()

    def elegir_saliente(self, fila):
        if self.sel is None:
            return
        self.saliente = fila
        self.dorsal = fila.dorsal                # el reemplazante hereda el dorsal
        self.seg_pos.set(POS_A_ETIQUETA[fila.posicion_habitual])
        self._marcar_saliente()
        self._actualizar_formulario()

    def cancelar_reemplazo(self):
        self.saliente = None
        self.dorsal = None
        self._marcar_saliente()
        self._actualizar_formulario()

    def elegir_dorsal(self, n):
        self.dorsal = None if self.dorsal == n else n
        self._cambio()

    def _hover_dorsal(self, n):
        dueno = self.ocupados.get(n)
        if dueno and not (self.saliente and n == self.saliente.dorsal):
            self._estado.configure(text=f"Dorsal {n}: lo usa {dueno}")
        else:
            self._estado.configure(text=f"Dorsal {n}: libre")

    def _dorsal_ocupado(self, n):
        if n not in self.ocupados:
            return False
        return not (self.saliente is not None and n == self.saliente.dorsal)

    def _pintar_dorsales(self):
        for n, b in self.botones_dorsal.items():
            if self.sel is None or self.sel.id_lista is None:
                b.configure(state="disabled", fg_color=("#e3e6ec", "#3a3a3a"), text_color_disabled=("gray60", "gray45"))
            elif self._dorsal_ocupado(n):
                b.configure(state="disabled", fg_color=("#e3e6ec", "#3a3a3a"), text_color_disabled=("gray60", "gray45"))
            elif n == self.dorsal:
                b.configure(state="normal", fg_color="#1f6aa5", hover_color="#1f6aa5", text_color="white")
            else:
                b.configure(state="normal", fg_color=("#cfe0f7", "#2c3f5e"), hover_color=("#b5d0f2", "#3b5580"),
                            text_color=("gray10", "gray95"))
        self.lbl_dorsal.configure(text=f"Dorsal *   {self.dorsal if self.dorsal else ''}")

    def _actualizar_formulario(self):
        en_reemplazo = self.saliente is not None
        lista = self.sel is not None and self.sel.id_lista is not None
        if en_reemplazo:
            s = self.saliente
            self.titulo.configure(text="Reemplazo")
            self.ayuda.configure(text="Sale un jugador y entra otro. Hereda el dorsal si no elegís otro.")
            self.lbl_banner.configure(text=f"Sale: #{s.dorsal}  {s.apellido}, {s.nombre}\n({s.posicion_habitual.capitalize()})")
            self.banner.grid(row=0, column=0, sticky="ew", padx=12, pady=(4, 2))
            self.lbl_motivo.configure(text="Motivo del cambio *  (ej. lesión)")
            self.lbl_fecha.grid(row=17, column=0, columnspan=2, sticky="ew", padx=12, pady=(8, 0))
            self.ent_fecha.grid(row=18, column=0, columnspan=2, sticky="ew", padx=12)
            self.btn_guardar.configure(text="Registrar reemplazo", fg_color="#e67e22", hover_color="#bf6516")
        else:
            self.titulo.configure(text="Nuevo jugador")
            self.ayuda.configure(
                text="Completá los datos y elegí un dorsal libre. Para reemplazar, hacé clic en un jugador de la plantilla."
                if lista else "Elegí una selección con lista de convocados.")
            self.banner.grid_forget()
            self.lbl_motivo.configure(text="Motivo de alta (opcional)")
            self.lbl_fecha.grid_forget()
            self.ent_fecha.grid_forget()
            self.btn_guardar.configure(text="Agregar jugador", fg_color=("#3b8ed0", "#1f6aa5"), hover_color=("#36719f", "#144870"))
        self._cambio()

    def _cambio(self):
        self._pintar_dorsales()
        self._vista_previa()
        lista = self.sel is not None and self.sel.id_lista is not None
        completo = (lista and self.v_nombre.get().strip() and self.v_apellido.get().strip()
                    and self.seg_pos.get() and self.dorsal)
        if self.saliente is not None:
            completo = completo and self.v_motivo.get().strip() and self.v_fecha_cambio.get().strip()
        self.btn_guardar.configure(state="normal" if completo else "disabled")

    def limpiar(self):
        self.saliente = None
        self.dorsal = None
        for v in (self.v_nombre, self.v_apellido, self.v_nac, self.v_club, self.v_motivo):
            v.set("")
        self.v_fecha_cambio.set(dt.date.today().strftime("%d/%m/%Y"))
        self.seg_pos.set("")
        if self.sel is not None:
            self.v_pais.set(self.pais_por_id.get(self.sel[5], ""))
        if self.cards:
            self._marcar_saliente()
        self._actualizar_formulario()

    def _no_convocados(self):
        """Jugadores del scraping de la seleccion que no figuran en su lista."""
        if self.sel is None:
            return []
        en_lista = {(j.nombre.casefold(), j.apellido.casefold()) for j in self.jugadores}
        return [r for r in self.pool.get(self.sel.codigo_fifa, [])
                if (r["nombre"].casefold(), r["apellido"].casefold()) not in en_lista]

    def abrir_no_convocados(self):
        if self.sel is None or self.sel.id_lista is None:
            messagebox.showinfo("No convocados", "Elegí primero una selección con lista de convocados.")
            return
        candidatos = self._no_convocados()
        if not candidatos:
            messagebox.showinfo("No convocados", f"No hay jugadores no convocados de {self.sel.nombre} "
                                                 f"en {CSV_JUGADORES.name}.")
            return
        dlg = ctk.CTkToplevel(self)
        dlg.title(f"No convocados - {self.sel.nombre}")
        dlg.geometry("560x620")
        dlg.transient(self)
        dlg.columnconfigure(0, weight=1)
        dlg.rowconfigure(2, weight=1)
        ctk.CTkLabel(dlg, text=f"No convocados de {self.sel.nombre}", anchor="w",
                     font=ctk.CTkFont(size=18, weight="bold")).grid(row=0, column=0, sticky="ew", padx=16, pady=(14, 2))
        v_busca = ctk.StringVar()
        cab = ctk.CTkFrame(dlg, fg_color="transparent")
        cab.grid(row=1, column=0, sticky="ew", padx=16, pady=6)
        cab.columnconfigure(0, weight=1)
        ctk.CTkEntry(cab, textvariable=v_busca, height=32, placeholder_text="Buscar por apellido, nombre o club…"
                     ).grid(row=0, column=0, sticky="ew")
        seg = ctk.CTkSegmentedButton(cab, values=["Todos"] + [p[1] for p in POSICIONES])
        seg.grid(row=1, column=0, sticky="ew", pady=(8, 0))
        inicial = POS_A_ETIQUETA[self.saliente.posicion_habitual] if self.saliente else "Todos"
        seg.set(inicial)
        lista = ctk.CTkScrollableFrame(dlg, fg_color="transparent")
        lista.grid(row=2, column=0, sticky="nsew", padx=8, pady=(0, 8))
        lista.columnconfigure(0, weight=1)
        pie = ctk.CTkLabel(dlg, text="", anchor="w", text_color=TEXTO_SUAVE)
        pie.grid(row=3, column=0, sticky="ew", padx=16, pady=(0, 10))

        def elegir(r):
            self.v_nombre.set(r["nombre"])
            self.v_apellido.set(r["apellido"])
            self.seg_pos.set(POS_A_ETIQUETA[POS_CSV[r["posicion"]]])
            try:
                self.v_nac.set(dt.date.fromisoformat(r["fecha_nacimiento"]).strftime("%d/%m/%Y"))
            except ValueError:
                self.v_nac.set("")
            self.v_club.set(r["club"])
            dlg.destroy()
            self._cambio()
            self._estado.configure(text=f"Datos cargados: {r['apellido']}, {r['nombre']}. Elegí el dorsal.")

        def dibujar(*_):
            for w in lista.winfo_children():
                w.destroy()
            txt = v_busca.get().strip().casefold()
            pos = ETIQUETA_A_POS.get(seg.get())
            n = 0
            for r in candidatos:
                p = POS_CSV[r["posicion"]]
                if pos and p != pos:
                    continue
                if txt and txt not in f"{r['apellido']} {r['nombre']} {r['club']}".casefold():
                    continue
                ctk.CTkButton(lista, anchor="w", height=40, fg_color="transparent",
                              text_color=("gray10", "gray95"), hover_color=("#dde6f3", "#33415a"),
                              text=f"{POS_A_ETIQUETA[p]}   {r['apellido']}, {r['nombre']}   ·   {r['club']}",
                              command=lambda fila=r: elegir(fila)).grid(row=n, column=0, sticky="ew", pady=1)
                n += 1
            pie.configure(text=f"{n} de {len(candidatos)} no convocados")

        v_busca.trace_add("write", dibujar)
        seg.configure(command=dibujar)
        dibujar()
        dlg.after(150, lambda: (dlg.winfo_exists() and (dlg.grab_set(), dlg.focus())))

    def _datos(self):
        pais = self.v_pais.get().strip()
        if pais and pais not in self.pais_por_nombre:
            raise ErrorBD(f'- El país "{pais}" no está en la lista: elegilo del desplegable.')
        return {
            "nombre": self.v_nombre.get().strip(),
            "apellido": self.v_apellido.get().strip(),
            "posicion": ETIQUETA_A_POS[self.seg_pos.get()],
            "dorsal": self.dorsal,
            "nacimiento": parsear_fecha(self.v_nac.get(), "Fecha de nacimiento"),
            "club": self.v_club.get().strip() or None,
            "id_pais": self.pais_por_nombre.get(pais),
            "motivo": self.v_motivo.get().strip() or None,
        }

    def guardar(self):
        try:
            d = self._datos()
            if self.saliente is None:
                nuevo = self.repo.alta(self.sel.id_lista, d)
                msg = f"Se agregó a {d['apellido']}, {d['nombre']} (#{d['dorsal']})."
            else:
                fecha = parsear_fecha(self.v_fecha_cambio.get(), "Fecha del cambio")
                nuevo = self.repo.reemplazo(self.saliente.id_jugador, fecha, d)
                msg = (f"Reemplazo registrado: sale {self.saliente.apellido}, "
                       f"entra {d['apellido']}, {d['nombre']} (#{d['dorsal']}).")
        except ErrorBD as e:
            messagebox.showwarning("No se pudo guardar", str(e))
            return
        self.limpiar()
        self._recargar(resaltar=nuevo)
        self._estado.configure(text=msg)


def main():
    raiz = tk.Tk()
    raiz.withdraw()
    try:
        repo = Repositorio()
    except pyodbc.Error as e:
        messagebox.showerror("Sin conexión", f"No se pudo conectar a {SERVER} / {DATABASE}.\n\n{_limpiar(e)}")
        return
    finally:
        raiz.destroy()
    App(repo).mainloop()


if __name__ == "__main__":
    main()
