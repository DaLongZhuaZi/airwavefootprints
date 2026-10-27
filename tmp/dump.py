import io, json
p = 'tmp/layB.json'
d = json.load(io.open(p, encoding='utf-8'))
out = []
def walk(n):
    a = n.get('attributes') if isinstance(n, dict) else None
    if a:
        t = a.get('text')
        if t:
            out.append((t, a.get('bounds'), a.get('clickable')))
    for c in (n.get('children') or []):
        walk(c)
walk(d)
for t, b, c in out:
    print(repr(t), b, c)
print('total', len(out))