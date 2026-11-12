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

 Fecha: 12/11/2026
 Archivo: pestanas_xml.py
 Objetivo: Pestaña de la aplicación para los reportes XML: ejecuta
           Reportes.usp_TarjetasXML o Reportes.usp_SeleccionesYPlantillasXML,
           muestra el XML en paralelo (a la izquierda el texto tal cual y a la
           derecha un árbol con los atributos de cada elemento) y lo guarda en
           un archivo .xml. La aplicación no arma el XML: lo genera el SP y acá
           solo se muestra y se guarda.
================================================================================
"""

import xml.etree.ElementTree as ET
from datetime import datetime, time
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from xml.dom import minidom

import customtkinter as ctk
from tkcalendar import DateEntry

CARPETA_XML = Path(__file__).resolve().parent.parent / "datos" / "salidas"

REPORTES = {
    "Tarjetas y suspensiones activas": "tarjetas",
    "Selecciones y plantillas": "plantillas",
}


def formatear_xml(texto):
    """El XML del SP viene en una sola línea; se indenta para leerlo y guardarlo."""
    lindo = minidom.parseString(texto.encode("utf-8")).toprettyxml(indent="  ", encoding="utf-8")
    return lindo.decode("utf-8")


# ---------------------------------------------------------------------------
# Panel: el XML como texto y como árbol, uno al lado del otro
# ---------------------------------------------------------------------------
class PanelXML(ctk.CTkFrame):
    def __init__(self, padre, estilo_tabla):
        super().__init__(padre, fg_color="transparent")
        self.grid_columnconfigure((0, 1), weight=1, uniform="mitades")
        self.grid_rowconfigure(1, weight=1)

        titulo = ctk.CTkFont(size=14, weight="bold")
        ctk.CTkLabel(self, text="XML (texto)", font=titulo, anchor="w").grid(
            row=0, column=0, sticky="ew", padx=(0, 6), pady=(0, 4))
        cabecera = ctk.CTkFrame(self, fg_color="transparent")
        cabecera.grid(row=0, column=1, sticky="ew", padx=(6, 0), pady=(0, 4))
        cabecera.grid_columnconfigure(0, weight=1)
        ctk.CTkLabel(cabecera, text="Vista con formato", font=titulo, anchor="w").grid(row=0, column=0, sticky="w")
        estilo_boton = dict(height=26, fg_color="transparent", border_width=1, text_color=("gray20", "gray85"))
        ctk.CTkButton(cabecera, text="Expandir todo", width=110, command=lambda: self._expandir(True),
                      **estilo_boton).grid(row=0, column=1, padx=(0, 6))
        ctk.CTkButton(cabecera, text="Contraer", width=90, command=lambda: self._expandir(False),
                      **estilo_boton).grid(row=0, column=2)

        self.caja = ctk.CTkTextbox(self, font=ctk.CTkFont(family="Consolas", size=12), wrap="none")
        self.caja.grid(row=1, column=0, sticky="nsew", padx=(0, 6))
        self.caja.configure(state="disabled")

        contenedor = ctk.CTkFrame(self, fg_color="transparent")
        contenedor.grid(row=1, column=1, sticky="nsew", padx=(6, 0))
        contenedor.grid_columnconfigure(0, weight=1)
        contenedor.grid_rowconfigure(0, weight=1)
        self.arbol = ttk.Treeview(contenedor, columns=("detalle",), style=estilo_tabla, selectmode="browse")
        self.arbol.heading("#0", text="Elemento")
        self.arbol.heading("detalle", text="Atributos y texto")
        self.arbol.column("#0", width=260, stretch=False)
        self.arbol.column("detalle", width=600, stretch=True)
        self.arbol.grid(row=0, column=0, sticky="nsew")
        vertical = ctk.CTkScrollbar(contenedor, command=self.arbol.yview)
        vertical.grid(row=0, column=1, sticky="ns")
        horizontal = ctk.CTkScrollbar(contenedor, orientation="horizontal", command=self.arbol.xview)
        horizontal.grid(row=1, column=0, sticky="ew")
        self.arbol.configure(yscrollcommand=vertical.set, xscrollcommand=horizontal.set)

    def mostrar(self, texto):
        """Pone el XML en las dos vistas. Devuelve la cantidad de elementos."""
        raiz = ET.fromstring(texto.encode("utf-8"))  # si no es XML válido, falla antes de borrar nada
        self.caja.configure(state="normal")
        self.caja.delete("1.0", "end")
        self.caja.insert("1.0", texto)
        self.caja.configure(state="disabled")
        self.arbol.delete(*self.arbol.get_children())
        self._agregar("", raiz)
        self._expandir(False)
        self.arbol.item(self.arbol.get_children()[0], open=True)
        return sum(1 for _ in raiz.iter())

    def limpiar(self):
        self.caja.configure(state="normal")
        self.caja.delete("1.0", "end")
        self.caja.configure(state="disabled")
        self.arbol.delete(*self.arbol.get_children())

    def _agregar(self, padre, elemento):
        # Si el elemento tiene un atributo identificador, va junto al nombre: "Seleccion - Argentina".
        etiqueta = elemento.tag
        for clave in ("nombre", "apellido", "codigo_fifa", "id"):
            if clave in elemento.attrib:
                etiqueta = f"{elemento.tag} - {elemento.attrib[clave]}"
                break
        partes = [f"{k} = {v}" for k, v in elemento.attrib.items()]
        texto = (elemento.text or "").strip()
        if texto:
            partes.append(texto)
        nodo = self.arbol.insert(padre, "end", text=etiqueta, values=("   ".join(partes),))
        for hijo in elemento:
            self._agregar(nodo, hijo)

    def _expandir(self, abrir):
        def recorrer(nodo):
            self.arbol.item(nodo, open=abrir)
            for hijo in self.arbol.get_children(nodo):
                recorrer(hijo)
        for nodo in self.arbol.get_children():
            recorrer(nodo)


# ---------------------------------------------------------------------------
# Pestaña: generar y guardar el XML de un reporte
# ---------------------------------------------------------------------------
class ReportesXML(ctk.CTkFrame):
    def __init__(self, padre, repo, estilo_tabla):
        super().__init__(padre, fg_color="transparent")
        self.repo = repo
        self.xml_actual = None
        self.reporte_actual = None
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(2, weight=1)

        ctk.CTkLabel(self, text="Reportes en XML", font=ctk.CTkFont(size=20, weight="bold")).grid(
            row=0, column=0, sticky="w", padx=12, pady=(10, 0))

        barra = ctk.CTkFrame(self)
        barra.grid(row=1, column=0, sticky="ew", padx=12, pady=10)

        ctk.CTkLabel(barra, text="Reporte").grid(row=0, column=0, padx=(12, 6), pady=10)
        self.cbo_reporte = ctk.CTkComboBox(barra, values=list(REPORTES), width=260, state="readonly",
                                           command=lambda _: self._reporte_elegido())
        self.cbo_reporte.set(next(iter(REPORTES)))
        self.cbo_reporte.grid(row=0, column=1, padx=(0, 16))

        ctk.CTkLabel(barra, text="Selección").grid(row=0, column=2, padx=(0, 6))
        self.selecciones = {"Todas": None}
        try:
            for f in repo.selecciones():
                self.selecciones[f.pais] = f.id_seleccion
        except Exception as e:  # sin permiso: queda solo "Todas"
            messagebox.showwarning("Selecciones", f"No se pudo cargar la lista de selecciones.\n\n{e}")
        self.cbo_seleccion = ctk.CTkComboBox(barra, values=list(self.selecciones), width=180, state="readonly")
        self.cbo_seleccion.set("Todas")
        self.cbo_seleccion.grid(row=0, column=3, padx=(0, 16))

        # Opción propia de cada reporte (solo se muestra la del reporte elegido).
        self.marco_fecha = ctk.CTkFrame(barra, fg_color="transparent")
        ctk.CTkLabel(self.marco_fecha, text="Tarjetas hasta el").grid(row=0, column=0, padx=(0, 6))
        self.fecha_corte = DateEntry(self.marco_fecha, date_pattern="dd/mm/yyyy", locale="es_ES",
                                     font=("Segoe UI", 11), width=11, state="readonly")
        self.fecha_corte.grid(row=0, column=1)
        self.var_bajas = ctk.BooleanVar(value=False)
        self.chk_bajas = ctk.CTkCheckBox(barra, text="Incluir bajas", variable=self.var_bajas)
        self.marco_fecha.grid(row=0, column=4, padx=(0, 16))

        ctk.CTkButton(barra, text="Generar", width=100, command=self.generar).grid(row=0, column=6, padx=(0, 8))
        self.btn_guardar = ctk.CTkButton(barra, text="Guardar .xml…", width=130, state="disabled",
                                         command=self.guardar)
        self.btn_guardar.grid(row=0, column=7, padx=(0, 12))
        barra.grid_columnconfigure(5, weight=1)

        self.panel = PanelXML(self, estilo_tabla)
        self.panel.grid(row=2, column=0, sticky="nsew", padx=12)
        self.lbl_estado = ctk.CTkLabel(self, text="Elegí un reporte y apretá Generar.", anchor="w",
                                       text_color=("gray35", "gray65"))
        self.lbl_estado.grid(row=3, column=0, sticky="ew", padx=12, pady=(6, 10))

    def _reporte_elegido(self):
        if REPORTES[self.cbo_reporte.get()] == "tarjetas":
            self.chk_bajas.grid_remove()
            self.marco_fecha.grid(row=0, column=4, padx=(0, 16))
        else:
            self.marco_fecha.grid_remove()
            self.chk_bajas.grid(row=0, column=4, padx=(0, 16))

    def _sin_datos(self, mensaje):
        self.xml_actual = None
        self.btn_guardar.configure(state="disabled")
        self.panel.limpiar()
        self.lbl_estado.configure(text=mensaje)

    def generar(self):
        reporte = REPORTES[self.cbo_reporte.get()]
        id_seleccion = self.selecciones[self.cbo_seleccion.get()]
        try:
            if reporte == "tarjetas":
                # El día elegido entra completo: el corte es a las 23:59:59.
                corte = datetime.combine(self.fecha_corte.get_date(), time(23, 59, 59))
                crudo = self.repo.reporte_tarjetas(id_seleccion, corte)
            else:
                crudo = self.repo.reporte_plantillas(id_seleccion, self.var_bajas.get())
        except Exception as e:
            self._sin_datos("")
            messagebox.showerror("No se pudo generar el reporte", str(e))
            return
        # Un FOR XML sin filas devuelve NULL: no hay nada que mostrar ni guardar.
        if crudo is None:
            self._sin_datos("El reporte no devolvió datos (no hay filas para ese filtro).")
            return
        self.xml_actual = formatear_xml(crudo)
        self.reporte_actual = reporte  # el que se generó: el combo puede cambiar antes de guardar
        elementos = self.panel.mostrar(self.xml_actual)
        self.btn_guardar.configure(state="normal")
        self.lbl_estado.configure(text=f"{elementos} elementos generados por el SP.")

    def guardar(self):
        CARPETA_XML.mkdir(parents=True, exist_ok=True)
        nombre = "tarjetas.xml" if self.reporte_actual == "tarjetas" else "selecciones_plantillas.xml"
        ruta = filedialog.asksaveasfilename(title="Guardar el XML", initialdir=CARPETA_XML, initialfile=nombre,
                                            defaultextension=".xml", filetypes=[("XML", "*.xml")])
        if not ruta:
            return
        Path(ruta).write_text(self.xml_actual, encoding="utf-8")
        self.lbl_estado.configure(text=f"Guardado en {ruta}")
