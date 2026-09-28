"""Generate src/text_data.glsl: caption token streams and the caption schedule
for Buffer C, which draws them with Shadertoy's SDF font texture.

    python3 tools/gen_text.py

Markup (TeX-like):
    \\i{..} italic   ^{..} superscript   _{..} subscript   \\sqrt{..}
    \\field{NAME}    live number filled in by the shader
    \\pi \\phi \\tau \\Delta \\Sigma \\Pi \\infty \\pm \\times \\cdot \\half
    \\equiv \\to \\cdots (drawn procedurally: not in the font)   \\, thin space
Glyph widths are measured from the font texture at run time (auto spacing),
so no metrics are baked in here.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ITAL_ON, ITAL_OFF, SUP_ON, SUP_OFF, SUB_ON, SUB_OFF, OVER_ON, OVER_OFF = range(256, 264)
THIN, EQUIV, ARROW, CDOTS = 264, 265, 266, 267
FIELD0 = 280
FIELDS = {'N': 1, 'PN': 2, 'HRM': 3, 'HRE': 4, 'ZE': 5, 'FA': 6, 'FB': 7}

SYMBOLS = {
    'pi': 0x89, 'phi': 0x8D, 'tau': 0x8C, 'theta': 0x85, 'sigma': 0x8B, 'mu': 0x87, 'alpha': 0x80,
    'Delta': 0x91, 'Sigma': 0x95, 'Pi': 0x94, 'Omega': 0x98, 'infty': 0x99, 'sqrtsign': 0x9F,
    'pm': 0xB1, 'times': 0xD7, 'cdot': 0xB7, 'half': 0xBD, 'quarter': 0xBC, 'deg': 0xB0,
    'equiv': EQUIV, 'to': ARROW, 'cdots': CDOTS, ',': THIN, 'sim': ord('~'),
}


def tokens(markup):
    out = []
    i = 0
    stack = []
    while i < len(markup):
        c = markup[i]
        if c == '\\':
            m = re.match(r'\\([A-Za-z]+|,)', markup[i:])
            name = m.group(1)
            i += len(m.group(0))
            if name in ('i', 'sqrt', 'field'):
                assert markup[i] == '{'
                if name == 'field':
                    j = markup.index('}', i)
                    out.append(FIELD0 + FIELDS[markup[i + 1:j]])
                    i = j + 1
                    continue
                i += 1
                if name == 'i':
                    out.append(ITAL_ON)
                    stack.append(ITAL_OFF)
                else:
                    out += [SYMBOLS['sqrtsign'], OVER_ON]
                    stack.append(OVER_OFF)
                continue
            out.append(SYMBOLS[name])
            continue
        if c in '^_':
            on, off = (SUP_ON, SUP_OFF) if c == '^' else (SUB_ON, SUB_OFF)
            out.append(on)
            if markup[i + 1] == '{':
                stack.append(off)
                i += 2
            else:
                out += tokens(markup[i + 1])
                out.append(off)
                i += 2
            continue
        if c == '}':
            out.append(stack.pop())
            i += 1
            continue
        if c == '{':
            stack.append(None)
            i += 1
            continue
        code = ord(c)
        assert code < 256, c
        out.append(code)
        i += 1
    assert not [s for s in stack if s is not None], markup
    return [t for t in out if t is not None]


CAPTIONS = {}
SCHEDULE = []


def cap(name, markup):
    CAPTIONS[name] = tokens(markup)
    return name


def at(name, t0, t1, x, y, em=0.03, align=0.0, color=0, anchor=0):
    """x, y: screen-height units from the centre (or offset from an anchor);
    align 0 left / .5 centre / 1 right; colour 0 ivory 1 gold 2 dim 3 peacock
    4 saffron; anchor 0 screen, 1/2/3 the points s = 2, 1, -1 of movement V."""
    if em < 0.03:
        em = min(em * 1.25, 0.03)         # keep the small print legible
    SCHEDULE.append((name, t0, t1, x, y, em, align, color, anchor))


L = -0.84
TOPY = 0.43

# I. p(n)
at(cap('title', 'Ramanujan'), 0.6, 6.0, 0.0, 0.2, 0.11, 0.5, 1)
at(cap('sub', '\\i{notes from the edge of infinity}'), 1.4, 6.0, 0.0, 0.1, 0.032, 0.5, 2)
at(cap('p5', '\\i{p}(5) = 7'), 1.8, 6.2, 0.0, -0.36, 0.05, 0.5, 0)
at(cap('p5b', '\\i{the ways to write 5 as a sum of whole numbers}'), 2.4, 6.2, 0.0, -0.44, 0.026, 0.5, 2)
at(cap('t1', 'I \\cdot Partitions'), 6.4, 22.3, 0.0, 0.445, 0.03, 0.5, 1)
at(cap('rand', '\\i{a random partition of} \\field{N}\\i{, one of}'), 7.0, 21.5, 0.0, 0.385, 0.026, 0.5, 2)
at(cap('pn', '\\i{p}(\\field{N}) = \\field{PN}'), 7.4, 17.4, 0.0, 0.325, 0.03, 0.5, 0)
at(cap('pnx', "\\i{exact, from Euler's pentagonal recurrence on the GPU}"), 8.0, 17.4, 0.0, 0.275, 0.021, 0.5, 2)
at(cap('pna', '\\i{p}(\\field{N}) ~ \\field{HRM} \\times 10^{\\field{HRE}}'), 17.6, 22.4, 0.0, 0.325, 0.03, 0.5, 0)
at(cap('hr', '\\i{p}(\\i{n}) ~ \\i{e}^{\\pi\\sqrt{2\\i{n}/3}} / 4\\i{n}\\sqrt{3}'), 13.0, 22.4, 0.0, 0.19, 0.036, 0.5, 1)
at(cap('hrb', '\\i{Hardy & Ramanujan, 1918}'), 13.4, 22.4, 0.0, 0.14, 0.022, 0.5, 2)
at(cap('shape', '\\i{scaled by} \\sqrt{\\i{n}}\\i{, the shape freezes:} \\i{e}^{-\\pi\\i{x}/\\sqrt{6}} + \\i{e}^{-\\pi\\i{y}/\\sqrt{6}} = 1'),
   18.6, 22.4, 0.0, 0.06, 0.027, 0.5, 0)

# II. congruences (the rose window sits to the right)
A2 = 22.0
at(cap('t2', 'II \\cdot Congruences'), A2 + 1.4, A2 + 20.3, L, TOPY, 0.03, 0.0, 1)
at(cap('c_how', '\\i{p}(\\i{n}) \\i{on a spiral,} \\i{m} \\i{tiles per turn}'), A2 + 1.0, A2 + 8.0, L, 0.34, 0.024, 0.0, 2)
at(cap('c_how2', '\\i{gold where} \\i{m} \\i{divides} \\i{p}(\\i{n})'), A2 + 1.0, A2 + 8.0, L, 0.30, 0.024, 0.0, 2)
at(cap('c5', '\\i{p}(5\\i{k}+4) \\equiv 0 (mod 5)'), A2 + 3.2, A2 + 6.6, L, 0.0, 0.04, 0.0, 1)
at(cap('c7', '\\i{p}(7\\i{k}+5) \\equiv 0 (mod 7)'), A2 + 8.3, A2 + 11.8, L, 0.0, 0.04, 0.0, 1)
at(cap('c11', '\\i{p}(11\\i{k}+6) \\equiv 0 (mod 11)'), A2 + 13.6, A2 + 17.0, L, 0.0, 0.04, 0.0, 1)
at(cap('c24', '\\i{always the class} 24\\i{n} \\equiv 1 (mod \\i{m})'), A2 + 9.0, A2 + 17.0, L, -0.07, 0.024, 0.0, 2)
at(cap('c13', '13: \\i{no golden wedge}'), A2 + 18.8, A2 + 22.4, L, 0.08, 0.04, 0.0, 0)
at(cap('cq1', '\\i{"...there are no equally simple properties}'), A2 + 19.2, A2 + 22.4, L, -0.01, 0.022, 0.0, 2)
at(cap('cq2', '\\i{for any moduli involving primes other}'), A2 + 19.2, A2 + 22.4, L, -0.05, 0.022, 0.0, 2)
at(cap('cq3', '\\i{than these three."}  RAMANUJAN, 1919'), A2 + 19.2, A2 + 22.4, L, -0.09, 0.022, 0.0, 2)
for i, m in enumerate(['5', '7', '11', '13']):
    t0 = [A2 + 1.2, A2 + 7.9, A2 + 13.2, A2 + 18.4][i]
    t1 = [A2 + 6.9, A2 + 12.1, A2 + 17.3, A2 + 22.4][i]
    at(cap('hub' + m, m), t0, t1, 0.30, -0.02, 0.06, 0.5, 1)

# III. the circle method
A3 = 42.0
at(cap('t3', 'III \\cdot The Circle Method'), A3 + 1.4, A3 + 24.3, L, TOPY, 0.03, 0.0, 1)
at(cap('gf', '\\Sigma \\i{p}(\\i{n}) \\i{q}^{\\i{n}} = \\Pi 1/(1 - \\i{q}^{\\i{n}})'), A3 + 1.5, A3 + 9.0, 0.0, -0.37, 0.042, 0.5, 1)
at(cap('gfb', '\\i{height ~ (1 - |q|) log|P(q)|, rescaled}'), A3 + 2.5, A3 + 9.0, 0.0, -0.44, 0.022, 0.5, 2)
at(cap('crown1', '\\i{every root of unity} \\i{e}^{2\\pi\\i{ih}/\\i{k}} \\i{is a singularity; its peak rises to} 1/\\i{k}'), A3 + 8.5, A3 + 14.5, 0.0, -0.40, 0.027, 0.5, 0)
at(cap('hr1', '\\i{Hardy & Ramanujan: one wave from each peak. Enough of them, rounded,}'), A3 + 14.0, A3 + 20.0, 0.0, -0.37, 0.025, 0.5, 0)
at(cap('hr2', '\\i{give} \\i{p}(200) = 3972999029388 \\i{exactly}'), A3 + 14.0, A3 + 20.0, 0.0, -0.42, 0.025, 0.5, 1)
at(cap('ford', '\\i{the lobes are Ford circles, one for every fraction} \\i{h}/\\i{k}'), A3 + 19.5, A3 + 24.4, 0.0, -0.40, 0.027, 0.5, 0)

# IV. the edge
A4 = 66.0
at(cap('t4', 'IV \\cdot The Edge'), A4 + 1.4, A4 + 22.3, L, TOPY, 0.03, 0.0, 1)
at(cap('e1', '\\i{every fraction on the circle is a singularity: the edge cannot be crossed}'), A4 + 2.6, A4 + 8.0, 0.0, -0.34, 0.026, 0.5, 0)
at(cap('eta', '\\i{P}(\\i{q})^{-24} = \\Delta(\\tau)/\\i{q}       \\Delta(-1/\\tau) = \\tau^{12}\\Delta(\\tau)'), A4 + 7.5, A4 + 13.5, 0.0, -0.36, 0.036, 0.5, 1)
at(cap('eta2', "\\i{Ramanujan's} \\Delta \\i{is modular: the same picture at every scale}"), A4 + 8.0, A4 + 13.5, 0.0, -0.43, 0.023, 0.5, 2)
at(cap('zoom', '\\i{falling into} \\i{q} = \\i{e}^{2\\pi\\i{i}/\\phi}  \\times 10^{\\field{ZE}}'), A4 + 4.0, A4 + 22.4, 0.84, TOPY, 0.028, 1.0, 0)
at(cap('fib', '\\field{FA}/\\field{FB} \\to \\phi'), A4 + 9.0, A4 + 22.4, 0.84, 0.375, 0.028, 1.0, 1)
at(cap('e3', '\\i{no end, no loss of precision: each step of} \\i{M} = (2 1; 1 1) \\i{is an exact symmetry}'), A4 + 14.0, A4 + 22.4, 0.0, -0.40, 0.025, 0.5, 0)

# V. -1/12
A5 = 88.0
at(cap('t5', 'V \\cdot -1/12'), A5 + 1.4, A5 + 20.3, L, TOPY, 0.03, 0.0, 1)
at(cap('l1', '\\i{"I told him that the sum of an infinite number of terms of the series}'), A5 + 1.5, A5 + 9.5, 0.0, -0.33, 0.025, 0.5, 0)
at(cap('l2', '1 + 2 + 3 + 4 + \\cdots = -1/12 \\i{under my theory."}'), A5 + 1.5, A5 + 9.5, 0.0, -0.385, 0.03, 0.5, 0)
at(cap('l3', 'RAMANUJAN TO HARDY, 1913'), A5 + 2.0, A5 + 9.5, 0.0, -0.44, 0.02, 0.5, 2)
at(cap('z2', '1 + 1/4 + 1/9 + \\cdots = \\pi\u00b2/6'), A5 + 3.5, A5 + 12.0, -0.02, 0.035, 0.026, 0.5, 1, 1)
at(cap('z1', '1 + 1/2 + 1/3 + \\cdots = \\infty'), A5 + 6.0, A5 + 12.0, 0.0, -0.08, 0.026, 0.5, 0, 2)
at(cap('zm1', '1 + 2 + 3 + \\cdots = -1/12'), A5 + 11.3, A5 + 20.4, 0.0, -0.085, 0.036, 0.5, 1, 3)
at(cap('lk1', "\\i{one function, analytically continued:}  \\pi\u00b2/6 \\i{sets how fast} \\i{p}(\\i{n}) \\i{grows,}"), A5 + 13.0, A5 + 20.4, 0.0, -0.36, 0.027, 0.5, 0)
at(cap('lk2', "\\i{and} -1/12 \\i{gives} \\Delta(\\tau) = \\i{q} \\Pi(1-\\i{q}^{\\i{n}})^{24} \\i{its lone} \\i{q}\\i{:}  24 \\cdot \\half \\cdot 1/12 = 1"), A5 + 13.4, A5 + 20.4, 0.0, -0.42, 0.024, 0.5, 2)

# VI. mock theta (the disk sits to the right)
A6 = 108.0
at(cap('t6', 'VI \\cdot Mock Theta'), A6 + 1.4, A6 + 21.5, L, TOPY, 0.03, 0.0, 1)
at(cap('f1', '\\i{f}(\\i{q}) = 1 + \\i{q}/(1+\\i{q})\u00b2 + \\i{q}^{4}/(1+\\i{q})\u00b2(1+\\i{q}\u00b2)\u00b2 + \\cdots'), A6 + 1.2, A6 + 8.2, L, 0.25, 0.03, 0.0, 1)
at(cap('f2', '\\i{from his last letter to Hardy, 12 January 1920}'), A6 + 1.6, A6 + 8.2, L, 0.19, 0.022, 0.0, 2)
at(cap('f3', '\\i{it erupts at every root of unity of even order:}'), A6 + 3.0, A6 + 8.2, L, 0.08, 0.023, 0.0, 0)
at(cap('f4', '\\i{gold rays: orders 2, 6, 10, ...}'), A6 + 3.0, A6 + 8.2, L, 0.035, 0.023, 0.0, 1)
at(cap('f5', '\\i{peacock rays: orders 4, 8, 12, ...}'), A6 + 3.0, A6 + 8.2, L, -0.01, 0.023, 0.0, 3)
at(cap('b1', '\\i{b}(\\i{q}) = (1-\\i{q})(1-\\i{q}\u00b3)(1-\\i{q}^{5})\\cdots(1-2\\i{q}+2\\i{q}^{4}-\\cdots)'), A6 + 8.2, A6 + 17.5, L, 0.25, 0.026, 0.0, 0)
at(cap('b2', '\\i{a theta function: modular}'), A6 + 8.6, A6 + 17.5, L, 0.19, 0.022, 0.0, 2)
at(cap('fmb', '\\i{f}(\\i{q}) - \\i{b}(\\i{q})'), A6 + 8.8, A6 + 12.6, L, 0.07, 0.05, 0.0, 3)
at(cap('fmb2', '\\i{bounded at orders 4, 8, 12, ...}'), A6 + 9.2, A6 + 12.6, L, 0.005, 0.023, 0.0, 2)
at(cap('fpb', '\\i{f}(\\i{q}) + \\i{b}(\\i{q})'), A6 + 13.4, A6 + 17.3, L, 0.07, 0.05, 0.0, 1)
at(cap('fpb2', '\\i{bounded at orders 2, 6, 10, ...}'), A6 + 13.8, A6 + 17.3, L, 0.005, 0.023, 0.0, 2)
at(cap('mk1', '\\i{each singularity is mimicked by a theta function,}'), A6 + 17.2, A6 + 21.5, L, 0.12, 0.025, 0.0, 0)
at(cap('mk2', '\\i{but no single one mimics them all: "mock" theta}'), A6 + 17.4, A6 + 21.5, L, 0.075, 0.025, 0.0, 0)
at(cap('end', 'Srinivasa Ramanujan'), A6 + 19.8, A6 + 23.8, L, -0.21, 0.05, 0.0, 1)
at(cap('end2', '1887 - 1920'), A6 + 20.3, A6 + 23.8, L, -0.28, 0.028, 0.0, 2)
at(cap('taxi', '1729 = 1\u00b3 + 12\u00b3 = 9\u00b3 + 10\u00b3'), A6 + 21.2, A6 + 23.8, L, -0.34, 0.022, 0.0, 2)


def emit():
    names = list(CAPTIONS)
    idx = {n: i for i, n in enumerate(names)}
    toks, rng = [], []
    for n in names:
        rng.append((len(toks), len(CAPTIONS[n])))
        toks += CAPTIONS[n]

    def f(v):
        s = ('%.4f' % v).rstrip('0')
        return s + '0' if s.endswith('.') else s

    padded = toks + [0] * (-len(toks) % 3)
    packed = [padded[i] | (padded[i + 1] << 10) | (padded[i + 2] << 20) for i in range(0, len(padded), 3)]
    tk = ['// ---- generated by tools/gen_text.py; do not edit ----',
          '// caption token streams (char codes of the font texture + controls)',
          '// three 10-bit tokens per uint',
          'const int N_TOK = %d;' % len(toks),
          'const uint TOKP[%d] = uint[%d](%s);' % (len(packed), len(packed), ','.join('%du' % t for t in packed))]
    open(os.path.join(ROOT, 'src', 'text_tokens.glsl'), 'w').write('\n'.join(tk) + '\n')
    cr = ['// ---- generated by tools/gen_text.py; do not edit ----',
          'const int N_CAP = %d;' % len(rng),
          'const ivec3 CRANGE[%d] = ivec3[%d](%s);   // start, length, has fields' % (len(rng), len(rng), ','.join(
              'ivec3(%d,%d,%d)' % (r[0], r[1], int(any(t >= FIELD0 for t in CAPTIONS[n])))
              for r, n in zip(rng, names)))]
    open(os.path.join(ROOT, 'src', 'text_captions.glsl'), 'w').write('\n'.join(cr) + '\n')
    o = ['// ---- generated by tools/gen_text.py; do not edit ----']
    o.append('const int N_SCHED = %d;' % len(SCHEDULE))
    o.append('const vec4 SCH_T[%d] = vec4[%d](%s);   // t0, t1, x, y' % (len(SCHEDULE), len(SCHEDULE), ','.join(
        'vec4(%s,%s,%s,%s)' % (f(s[1]), f(s[2]), f(s[3]), f(s[4])) for s in SCHEDULE)))
    o.append('const vec4 SCH_S[%d] = vec4[%d](%s);   // em, align, colour, caption + 256*anchor' % (len(SCHEDULE), len(SCHEDULE), ','.join(
        'vec4(%s,%s,%s,%s)' % (f(s[5]), f(s[6]), f(s[7]), f(idx[s[0]] + 256 * s[8])) for s in SCHEDULE)))
    path = os.path.join(ROOT, 'src', 'text_data.glsl')
    open(path, 'w').write('\n'.join(o) + '\n')
    print('wrote src/text_data.glsl: %d captions, %d tokens, %d schedule rows' % (len(names), len(toks), len(SCHEDULE)))


if __name__ == '__main__':
    emit()
