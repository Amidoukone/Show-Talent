# -*- coding: utf-8 -*-
"""Lecteur/ecrivain PNG minimal, sans dependance externe.

Existe parce que cette machine n'a ni Pillow ni ImageMagick, et que mesurer
des pixels a l'oeil sur une capture d'ecran produit des decalages d'un ou
deux pixels qui se voient dans une image publiee en boutique.
"""
import zlib, struct


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', "pas un PNG"
    pos, idat, w, h, bitdepth, colortype = 8, b'', 0, 0, 0, 0
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+ln]
        if typ == b'IHDR':
            w, h, bitdepth, colortype = struct.unpack('>IIBB', chunk[:10])
        elif typ == b'IDAT':
            idat += chunk
        elif typ == b'IEND':
            break
        pos += 12 + ln
    assert bitdepth == 8, "profondeur %d non geree" % bitdepth
    nch = {0: 1, 2: 3, 4: 2, 6: 4}[colortype]
    raw = zlib.decompress(idat)
    stride = w * nch
    out = bytearray(w * h * nch)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p+stride]); p += stride
        if f == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i-nch]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i-nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i-nch] if i >= nch else 0
                b = prev[i]
                c = prev[i-nch] if i >= nch else 0
                pa, pb, pc = abs(b-c), abs(a-c), abs(a+b-2*c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y*stride:(y+1)*stride] = line
        prev = line
    return {'w': w, 'h': h, 'nch': nch, 'px': out}


def write_png(img, path):
    w, h, nch, px = img['w'], img['h'], img['nch'], img['px']
    colortype = {1: 0, 3: 2, 4: 6}[nch]
    stride = w * nch
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += px[y*stride:(y+1)*stride]

    def chunk(typ, payload):
        return (struct.pack('>I', len(payload)) + typ + payload +
                struct.pack('>I', zlib.crc32(typ + payload) & 0xFFFFFFFF))

    body = (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, colortype, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(bytes(raw), 9)) +
            chunk(b'IEND', b''))
    open(path, 'wb').write(body)


def get(img, x, y):
    i = (y * img['w'] + x) * img['nch']
    return tuple(img['px'][i:i+3])


def put(img, x, y, rgb):
    i = (y * img['w'] + x) * img['nch']
    img['px'][i], img['px'][i+1], img['px'][i+2] = rgb[0], rgb[1], rgb[2]
