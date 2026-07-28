#!/usr/bin/env python3
"""ground truth for the benchmark numbers: load raw/results-*.json, and prove
the loader by re-deriving results.md from it.

why this exists: reference.md §7 is hand-transcribed from results.md, and
nothing has ever checked it. before pointing a checker at hand-written prose,
the loader it depends on has to be validated against a target that is already
mechanically correct — results.md, which run_all.jl generates from the same
JSON. if this agrees cell-for-cell, the loader models the data correctly and
the collapse rule is understood.

two views on the data, because different claims need different ones:

  collapsed — one cell per (threads, kind, profile, scale, path), replicating
              run_all.jl's rule: sort raw/*.json by FILENAME, group by
              environment.threads, keep the FIRST occurrence per path
              (run_all.jl:163, 172-174, 288-290). this is what results.md
              reports, hence what §7's absolute numbers were copied from.
  all_runs  — every repeat, needed for ordering-stability claims (§7.5) and
              for any claim about spread between repeats.

comparison is NUMERIC WITH LAST-DIGIT TOLERANCE, never string equality. the
rendered forms come from BenchmarkTools.prettytime and Base.format_bytes;
re-implementing those formatters here would mean guessing at two external
libraries' rounding rules, and string-exactness is not the property under
test. "2.051 ms" is verified as |median_ns - 2_051_000| <= 500.

unicode trap, load-bearing: results.md spells microseconds with U+03BC (greek
mu, what prettytime emits) and reference.md with U+00B5 (micro sign, what a
human types). they render identically and compare unequal. every parser here
accepts both — a parser that accepts only one finds zero microsecond claims
and reports clean while checking nothing.

usage: python3 bench.py RAWDIR RESULTS_MD
exit status is 1 if any cell disagrees, or if the row count does not match.
"""

import json
import os
import re
import sys


# ---------------------------------------------------------------------------
# loading
# ---------------------------------------------------------------------------

def load_runs(rawdir):
  """every raw run, sorted by filename — the order run_all.jl's merge uses."""
  names = sorted(f for f in os.listdir(rawdir) if f.endswith(".json"))
  if not names:
    sys.exit(f"no *.json in {rawdir}")
  runs = []
  for name in names:
    with open(os.path.join(rawdir, name), encoding="utf-8") as fh:
      doc = json.load(fh)
    runs.append({
      "file": name,
      "tag": doc["tag"],
      "threads": doc["environment"]["threads"],
      "environment": doc["environment"],
      "verifications": doc["verifications"],
      "cells": doc["cells"],
    })
  return runs


def cellkey(cell, threads):
  return (threads, cell["kind"], cell["profile"], cell["scale"], cell["path"])


def index_all(runs):
  """key -> list of (tag, cell), in filename order. repeats preserved."""
  out = {}
  for run in runs:
    for cell in run["cells"]:
      out.setdefault(cellkey(cell, run["threads"]), []).append((run["tag"], cell))
  return out


def index_collapsed(runs):
  """key -> (tag, cell) for the first run that reported it.

  this reproduces run_all.jl's dedupe. note the "first" run is the -a repeat
  only because filename sort happens to put it first; renaming a tag would
  silently change which repeat results.md reports.
  """
  out = {}
  for run in runs:
    for cell in run["cells"]:
      key = cellkey(cell, run["threads"])
      if key not in out:
        out[key] = (run["tag"], cell)
  return out


# ---------------------------------------------------------------------------
# parsing rendered quantities back to numbers
# ---------------------------------------------------------------------------

# both micro spellings, deliberately
TIME_UNITS = {"ns": 1.0, "μs": 1e3, "µs": 1e3, "ms": 1e6, "s": 1e9}
BYTE_UNITS = {
  "bytes": 1.0, "byte": 1.0,
  "KiB": 1024.0, "MiB": 1024.0 ** 2, "GiB": 1024.0 ** 3, "TiB": 1024.0 ** 4,
}

NUM = r"([0-9]+(?:\.[0-9]+)?)"


def half_ulp(numeral):
  """half a unit in the last displayed decimal place.

  "2.051" -> 0.0005, "17" -> 0.5. this is the tolerance a correctly rounded
  rendering can differ from the true value by, and comparing against it is
  what lets us skip re-implementing the julia formatters.
  """
  if "." in numeral:
    return 0.5 * 10 ** -len(numeral.split(".", 1)[1])
  return 0.5


# a cell that is neither a value nor the empty marker. this MUST be
# distinguishable from "not reported": if garbage lands in a cell whose raw
# counterpart is absent, treating it as blank makes the pair agree and the
# check passes on a corrupted document
UNPARSEABLE = object()


def parse_scalar(text, units):
  """'2.051 ms' -> (2051000.0, 500.0) in base units (ns, or bytes).

  three outcomes, deliberately distinct: a (value, tolerance) pair, None for
  the generator's empty marker, or UNPARSEABLE for anything else.
  """
  text = text.strip()
  if text in ("", "—", "-"):
    return None
  match = re.fullmatch(NUM + r"\s*([A-Za-zμµ]+)", text)
  if not match:
    return UNPARSEABLE
  numeral, unit = match.group(1), match.group(2)
  if unit not in units:
    return UNPARSEABLE
  scale = units[unit]
  return (float(numeral) * scale, half_ulp(numeral) * scale)


def parse_time(text):
  return parse_scalar(text, TIME_UNITS)


def parse_bytes(text):
  return parse_scalar(text, BYTE_UNITS)


def parse_count(text):
  """a bare integer cell: rows/s, allocs, samples. rendered via round(Int, x),
  so the true value may sit up to half a unit either side."""
  text = text.strip().replace(",", "")
  if text in ("", "—", "-"):
    return None
  if not re.fullmatch(r"[0-9]+", text):
    return UNPARSEABLE
  return (float(text), 0.5)


# ---------------------------------------------------------------------------
# parsing results.md
# ---------------------------------------------------------------------------

RE_THREADS = re.compile(r"^## Results — (\d+) threads?\s*$")
RE_KIND = re.compile(r"^### (Writes|Reads)\s*$")


def parse_results_md(path):
  """rows of results.md's four result tables.

  each row: dict with the key fields plus the rendered cells already parsed
  into (value, tolerance) pairs, or a status/reason for skipped cells.
  """
  rows = []
  threads = None
  kind = None
  with open(path, encoding="utf-8") as fh:
    for lineno, line in enumerate(fh, 1):
      m = RE_THREADS.match(line)
      if m:
        threads = int(m.group(1))
        kind = None
        continue
      m = RE_KIND.match(line)
      if m:
        kind = "write" if m.group(1) == "Writes" else "read"
        continue
      if threads is None or kind is None:
        continue
      if not line.startswith("|"):
        continue
      cols = [c.strip() for c in line.strip().strip("|").split("|")]
      if len(cols) != 8:
        continue
      if cols[0] in ("profile", "---") or set(cols[0]) <= {"-"}:
        continue
      profile, scale_text, pathname = cols[0], cols[1], cols[2]
      if not re.fullmatch(r"[0-9]+", scale_text):
        continue
      row = {
        "lineno": lineno,
        "threads": threads,
        "kind": kind,
        "profile": profile,
        "scale": int(scale_text),
        "path": pathname,
      }
      status_cell = cols[3]
      if status_cell.startswith("_") and status_cell.endswith("_"):
        row["status"] = status_cell.strip("_")
        row["reason"] = cols[7]
      else:
        row["status"] = "ok"
        row["median"] = parse_time(cols[3])
        row["rows_per_sec"] = parse_count(cols[4])
        row["allocs"] = parse_count(cols[5])
        row["memory"] = parse_bytes(cols[6])
        row["samples"] = parse_count(cols[7])
      rows.append(row)
  return rows


# ---------------------------------------------------------------------------
# the check
# ---------------------------------------------------------------------------

def agree(claimed, truth):
  """claimed is a (value, tolerance) pair from the document; truth is a float."""
  if claimed is None:
    return truth is None
  value, tol = claimed
  if truth is None:
    return False
  return abs(float(truth) - value) <= tol


def check_results_md(rawdir, results_md):
  runs = load_runs(rawdir)
  collapsed = index_collapsed(runs)
  rows = parse_results_md(results_md)

  failures = []
  # coverage is reported as a breakdown, never as one total. a check where both
  # sides are absent agrees truthfully but verifies nothing, and folding it into
  # the headline count overstates how much was actually checked. mutation
  # testing cannot catch this — there is no value to perturb.
  #
  # the both-absent cells are exactly the stream_first rows/s: bench_read.jl:86
  # reports rows/sec as `nothing` for stream_first only, because it reads one
  # chunk and a rows/sec figure would be misleading. 4 profiles x 3 scales x
  # 2 thread configs = 24. materialized and streaming DO carry rows_per_sec.
  n_real = 0       # both sides present, values compared
  n_absent = 0     # both sides absent — agreement is vacuous
  n_status = 0     # skipped-cell status/reason comparisons

  for row in rows:
    key = (row["threads"], row["kind"], row["profile"], row["scale"], row["path"])
    found = collapsed.get(key)
    if found is None:
      failures.append(f"{results_md}:{row['lineno']}: no raw cell for {key}")
      continue
    tag, cell = found

    if row["status"] != "ok" or cell["status"] != "ok":
      # a skipped row must be skipped in the raw data too, with the same reason
      if row["status"] != cell["status"]:
        failures.append(
          f"{results_md}:{row['lineno']}: status {row['status']!r} but raw "
          f"({tag}) says {cell['status']!r} for {key}")
      elif row.get("reason", "") != cell.get("reason", ""):
        failures.append(
          f"{results_md}:{row['lineno']}: reason differs for {key}\n"
          f"    md:  {row.get('reason','')!r}\n"
          f"    raw: {cell.get('reason','')!r}")
      n_status += 1
      continue

    fields = [
      ("median", row["median"], cell.get("median_ns")),
      ("rows_per_sec", row["rows_per_sec"], cell.get("rows_per_sec")),
      ("allocs", row["allocs"], cell.get("allocs")),
      ("memory", row["memory"], cell.get("memory_bytes")),
      ("samples", row["samples"], cell.get("samples")),
    ]
    for name, claimed, truth in fields:
      if claimed is UNPARSEABLE:
        n_real += 1
        failures.append(
          f"{results_md}:{row['lineno']}: {name} for {key} is unparseable")
        continue
      if claimed is None and truth is None:
        n_absent += 1
        continue
      n_real += 1
      if not agree(claimed, truth):
        shown = "—" if claimed is None else f"{claimed[0]:.6g}±{claimed[1]:g}"
        failures.append(
          f"{results_md}:{row['lineno']}: {name} for {key}: md {shown} "
          f"vs raw ({tag}) {truth!r}")

  # every raw cell of every collapsed key should appear as a row: results.md
  # must not be missing cells the data has
  rowkeys = [(r["threads"], r["kind"], r["profile"], r["scale"], r["path"]) for r in rows]
  missing = sorted(set(collapsed) - set(rowkeys))
  for key in missing:
    failures.append(f"{results_md}: raw has {key} but no row renders it")

  # ...and must not render a cell twice. a duplicated row maps to the same
  # collapsed key and compares equal, so the `missing` check above cannot see
  # it; without this the counts are printed side by side and never compared
  seen = set()
  for key, row in zip(rowkeys, rows):
    if key in seen:
      failures.append(f"{results_md}:{row['lineno']}: duplicate row for {key}")
    seen.add(key)
  if len(rows) != len(collapsed):
    failures.append(
      f"{results_md}: row count {len(rows)} != collapsed cell count {len(collapsed)}")

  print(f"runs loaded:       {len(runs)} ({', '.join(r['tag'] for r in runs)})")
  print(f"collapsed cells:   {len(collapsed)}")
  print(f"rows parsed:       {len(rows)}")
  print(f"real comparisons:  {n_real}   (both sides present — the coverage that counts)")
  print(f"both-absent:       {n_absent}   (vacuous agreement, verifies nothing)")
  print(f"status/reason:     {n_status}   (skipped cells)")
  if failures:
    print(f"\nFAIL — {len(failures)} disagreement(s):\n")
    for f in failures:
      print("  " + f)
    return 1
  print("\nOK — results.md agrees with raw/*.json on every value")
  return 0


def main(argv):
  if len(argv) != 3:
    sys.exit("usage: python3 bench.py RAWDIR RESULTS_MD")
  return check_results_md(argv[1], argv[2])


if __name__ == "__main__":
  sys.exit(main(sys.argv))
