#!/usr/bin/env python3
"""Copy a LeRobot v2.1 dataset and give every episode the same task instruction.

The physical_ai_server multi-task recording stores each sub-task (move to block, pick up, ...) as its
own episode with its own instruction, but inference sends a single instruction for the whole run. This
makes a copy where all episodes share one instruction, so the policy learns the full sequence from
images + state. The source dataset is only read, never modified.

Run inside the physical_ai_server container (dataset folders are owned by root, needs pyarrow):
  python3 relabel_single_task.py "<src dataset dir>" "<dst dataset dir>" "<instruction>"
"""
import json
import shutil
import sys
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def write_jsonl(path, rows):
    path.write_text(''.join(json.dumps(row) + '\n' for row in rows))


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    src, dst, instruction = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]

    info = json.loads((src / 'meta/info.json').read_text())
    if info.get('codebase_version') != 'v2.1':
        sys.exit(f'Only LeRobot v2.1 datasets are supported, got {info.get("codebase_version")}')
    if dst.exists():
        sys.exit(f'{dst} already exists, not overwriting it')

    shutil.copytree(src, dst)

    # Frames: task_index -> 0, keeping the schema (incl. the huggingface features metadata)
    for parquet in sorted((dst / 'data').rglob('*.parquet')):
        table = pq.read_table(parquet)
        idx = table.schema.get_field_index('task_index')
        zeros = pa.array([0] * table.num_rows, type=table.schema.field(idx).type)
        table = table.set_column(idx, table.schema.field(idx), zeros)
        pq.write_table(table, parquet)

    write_jsonl(dst / 'meta/tasks.jsonl', [{'task_index': 0, 'task': instruction}])

    episodes = read_jsonl(dst / 'meta/episodes.jsonl')
    for episode in episodes:
        episode['tasks'] = [instruction]
    write_jsonl(dst / 'meta/episodes.jsonl', episodes)

    episodes_stats = read_jsonl(dst / 'meta/episodes_stats.jsonl')
    for episode in episodes_stats:
        task_stats = episode['stats']['task_index']
        task_stats.update({'min': [0], 'max': [0], 'mean': [0.0], 'std': [0.0]})
    write_jsonl(dst / 'meta/episodes_stats.jsonl', episodes_stats)

    info['total_tasks'] = 1
    (dst / 'meta/info.json').write_text(json.dumps(info, indent=4))

    print(f'Wrote {dst}: {len(episodes)} episodes, all with task "{instruction}"')


if __name__ == '__main__':
    main()
