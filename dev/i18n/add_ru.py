"""Add Russian translations to RU_DICT inside dev/kotyachyi-prytulok.html.
Usage: put pairs into a JSON file {"укр фрагмент": "рус фрагмент", ...} and run
  python3 dev/i18n/add_ru.py pairs.json
Keys are text fragments exactly as they appear in the source (without trailing punctuation/emoji edges)."""
import json, sys, os
os.chdir(os.path.dirname(os.path.abspath(__file__)) + '/../..')
F = 'dev/kotyachyi-prytulok.html'; s = open(F).read()
add = json.load(open(sys.argv[1]))
i = s.index('const RU_DICT = ') + len('const RU_DICT = '); j = s.index(';\nconst RU_SP = [')
d = json.loads(s[i:j]); n0 = len(d); d.update({k: v for k, v in add.items() if k != v and k not in d})
open(F, 'w').write(s[:i] + json.dumps(d, ensure_ascii=False) + s[j:]); print(n0, '->', len(d))
