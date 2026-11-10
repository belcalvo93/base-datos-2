"""armar_informe.py — Arma el informe técnico del TPI Parcial II a partir de las secciones.

Toma la plantilla informe_tpi.html (no la modifica), reemplaza cada recuadro "COMPLETAR"
por la sección en Markdown de su autor (secciones/*.md) y escribe informe_tpi_completo.html.
El PDF se genera después con Edge sin interfaz (ver el final de este archivo).

Uso (desde la raíz del repo):  python docs/tpi_parcial2/armar_informe.py
Requiere: pip install markdown
"""
import re
from pathlib import Path

import markdown

DIR = Path(__file__).resolve().parent
SEC = DIR / "secciones"


def leer(nombre):
    return (SEC / nombre).read_text(encoding="utf-8").replace("\r\n", "\n")


def partir(texto, separador):
    """Divide un archivo con dos secciones en el título indicado."""
    i = texto.index(separador)
    return texto[:i], texto[i:]


def sin_titulo(md):
    """Quita el primer título (### o ##): la plantilla ya trae el suyo."""
    return re.sub(r"^\s*#{2,3} [^\n]*\n", "", md, count=1).strip().rstrip("-").strip()


# La notación LaTeX ($R_1 \bowtie R_2$, \rightarrow, \text{...}) no se dibuja en un PDF
# hecho desde HTML: se pasa a caracteres comunes. Solo fuera de `código`, para no tocar
# los $ de MongoDB ($jsonSchema, $setUnion) ni los $$ de PL/pgSQL.
LATEX = [(r"\text{", ""), (r"\_", "_"), (r"\{", "{"), (r"\}", "}"),
         (r"\rightarrow", "→"), (r"\bowtie", "⋈"), ("_1", "₁"), ("_2", "₂")]


def latex_a_texto(md):
    partes = re.split(r"(`[^`]*`)", md)
    for i, p in enumerate(partes):
        if p.startswith("`"):
            continue

        def conv(m):
            s = m.group(1)
            for a, b in LATEX:
                s = s.replace(a, b)
            s = re.sub(r"(?<=[A-Za-z_])}", "", s)   # cierre de \text{...}
            return s.replace("  ", " ").strip()

        partes[i] = re.sub(r"\$([^$\n]+)\$", conv, p)
    return "".join(partes)


def html(md):
    return markdown.markdown(latex_a_texto(md), extensions=["tables"])


hernan = leer("hernan_u4_u5.md")
u4, u5 = partir(hernan, "### Unidad 5")
belen = leer("belen_u7_u8.md")
u7, u8 = partir(belen, "### Unidad 8")
elias = leer("elias_u6_como_se_probo.md")
u6, prueba = partir(elias, "## 2.")
bruno = leer("bruno_ia_codereview.md")

# Los recuadros de la plantilla, en orden de aparición
contenidos = [u4, u5, u6, u7, u8, prueba, bruno]

plantilla = (DIR / "informe_tpi.html").read_text(encoding="utf-8")
huecos = re.findall(r'<div class="hueco">.*?</div>', plantilla, re.S)
assert len(huecos) == len(contenidos), f"la plantilla tiene {len(huecos)} huecos y hay {len(contenidos)} secciones"
salida = plantilla
for hueco, md in zip(huecos, contenidos):
    salida = salida.replace(hueco, html(sin_titulo(md)), 1)

# Índice: los objetivos 8 y 13 se cerraron después de armar la plantilla
salida = salida.replace(
    "R: <code>mantenimiento/restore_test.sh</code>, R: <code>mantenimiento/evidencias/restore_test_20261108_034017.txt</code>",
    "R: <code>mantenimiento/simulacro_desastre.sh</code>, R: <code>mantenimiento/informe_post_incidente.md</code>")
salida = salida.replace(
    "M: <code>food-store/docs/3c_code_review_ia.md</code>, R: <code>mantenimiento/revision_opencode.md</code>",
    "M: <code>food-store/docs/3c_code_review_ia.md</code>, R: <code>docs/tpi_parcial2/review/review_u1.md</code> a <code>review_u8.md</code>")

# Las rutas largas en cursiva no se pueden cortar y, con el texto justificado, abren
# huecos grandes entre palabras: se permite cortarlas en cualquier punto.
salida = salida.replace("</style>", "em, code { overflow-wrap: anywhere; }\n</style>", 1)

assert 'class="hueco"' not in salida.split("</style>")[1], "quedó un recuadro COMPLETAR sin reemplazar"
(DIR / "informe_tpi_completo.html").write_text(salida, encoding="utf-8")
print("Escrito:", DIR / "informe_tpi_completo.html")

# PDF (Git Bash, desde la raíz del repo):
# "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" --headless=new --disable-gpu \
#   --no-pdf-header-footer --print-to-pdf="$(pwd -W)/docs/tpi_parcial2/informe_tpi.pdf" \
#   "file:///$(pwd -W | sed 's/ /%20/g')/docs/tpi_parcial2/informe_tpi_completo.html"
