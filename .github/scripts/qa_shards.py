"""Split simulator QA passes into short shards (one runner each), for qa.yml's matrix.

usage: qa_shards.py "<apps>" [<map args regex> [skip]]   ->  prints {"apps": [...], "shards": [{...}, ...]} as JSON

An app whose .github/qa/<app>.json has "shard_size" is split: its iPhone screens in groups of shard_size, the
screens whose launch arguments match <map args regex> (live 3D map, the heaviest) in groups of "map_shard_size"
(default 2) of their own, and the Watch screens as one more shard. With "skip" (the map screens are being skipped)
they go into the first shard instead, where they are only listed as SKIPPED. Every other app is one shard
("all"), as before. Each shard: {"app", "shard", "shots" (comma-separated names, "" = none), "watch" ("1"/"0"),
"sharded" ("1"/"0"), "timeout" (job minutes), "budget" (capture budget minutes), "capture_timeout" (capture step
minutes)}.
"""
import json, re, sys

apps = sys.argv[1].split()
maps = re.compile(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].strip() else None
skip_maps = len(sys.argv) > 3 and sys.argv[3] == "skip"
shards = []
for app in apps:
    try:
        cfg = json.load(open(f".github/qa/{app}.json"))
    except (OSError, ValueError):
        cfg = {}
    size = int(cfg.get("shard_size") or 0)
    if not size:
        shards.append({"app": app, "shard": "all", "shots": "", "watch": "1", "sharded": "0",
                       "timeout": 105, "budget": 50, "capture_timeout": 60})
        continue
    names = [s["name"] for s in cfg.get("shots", [])]
    heavy = [s["name"] for s in cfg.get("shots", []) if maps and maps.search(s.get("args", ""))]
    light = [n for n in names if n not in heavy]
    groups = [light[i:i + size] for i in range(0, len(light), size)] or [[]]
    if skip_maps:
        groups[0] += heavy
    else:
        msize = int(cfg.get("map_shard_size") or 2)
        groups += [heavy[i:i + msize] for i in range(0, len(heavy), msize)]
    for i, g in enumerate(groups, 1):
        shards.append({"app": app, "shard": f"s{i}", "shots": ",".join(g), "watch": "0", "sharded": "1",
                       # build is done once per app; a shard boots (up to 15 min on a loaded runner) and takes
                       # its few screens, so it gets a short job and a short capture budget
                       "timeout": 40, "budget": 20, "capture_timeout": 30})
    if (cfg.get("watch") or {}).get("shots"):
        shards.append({"app": app, "shard": "watch", "shots": "", "watch": "1", "sharded": "1",
                       "timeout": 40, "budget": 20, "capture_timeout": 30})
print(json.dumps({"apps": apps, "shards": shards}))
