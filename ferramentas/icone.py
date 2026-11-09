"""Desenha o ícone do Páginas (o mesmo do programa do Windows) e salva os PNGs do app Android e do site.
Uso: python ferramentas/icone.py   (precisa do Pillow: pip install pillow)"""
import math, os
from PIL import Image, ImageDraw

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def logo(s, fundo_cheio=False):
    k = 4  # desenha maior e reduz: bordas suaves
    S = s * k
    grad = Image.new("RGBA", (S, S))
    a = math.radians(55)
    dx, dy = math.cos(a), math.sin(a)
    c1, c2 = (224, 138, 92), (160, 64, 30)
    px = grad.load()
    n = abs(dx) * S + abs(dy) * S
    for y in range(S):
        for x in range(S):
            t = min(1, max(0, (x * dx + y * dy) / n))
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)
    masc = Image.new("L", (S, S), 0)
    if fundo_cheio: masc.paste(255, (0, 0, S, S))
    else: ImageDraw.Draw(masc).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.22), fill=255)
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    im.paste(grad, (0, 0), masc)
    d = ImageDraw.Draw(im)
    P = lambda x, y: (x * S, y * S)
    d.polygon([P(.16, .34), P(.48, .43), P(.48, .80), P(.16, .71)], fill=(255, 252, 246, 255))
    d.polygon([P(.52, .43), P(.84, .34), P(.84, .71), P(.52, .80)], fill=(246, 232, 212, 255))
    if s >= 48:
        w = max(1, int(S * 0.018))
        for (a1, a2) in [((.22, .50), (.43, .55)), ((.22, .58), (.43, .63)), ((.57, .55), (.78, .50)), ((.57, .63), (.78, .58))]:
            d.line([P(*a1), P(*a2)], fill=(180, 83, 42, 150), width=w)
    return im.resize((s, s), Image.LANCZOS)


if __name__ == "__main__":
    res = os.path.join(RAIZ, "android", "app", "src", "main", "res")
    for nome, t in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        os.makedirs(os.path.join(res, "mipmap-" + nome), exist_ok=True)
        logo(t).save(os.path.join(res, "mipmap-" + nome, "ic_launcher.png"))
    os.makedirs(os.path.join(RAIZ, "docs"), exist_ok=True)
    logo(256).save(os.path.join(RAIZ, "docs", "icone.png"))
    logo(512).save(os.path.join(RAIZ, "docs", "icone-512.png"))
    logo(128).save(os.path.join(RAIZ, "icone.png"))
    print("ícones gerados")
