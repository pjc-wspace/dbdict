#!/usr/bin/env python3
"""verify every numeric claim in reference.md §7 against raw/*.json.

§7 is the one section of a document declared "audit-clean" that no audit
covered. runblocks.py checks that code runs, citations.py that source cites
resolve, anchors.py that links resolve, vruns.py that no claim was lost — none
of them checks a NUMBER against a MEASUREMENT. §7 is entirely hand-transcribed
tables and hand-computed ratios.

what is checked:
  §7.2  write table   median, rows/s, allocations per cell; and that every
                      ❌ / n/a / excluded marker matches a skipped raw cell
  §7.3  read table    medians
  §7.4  thread table  both values per row, and the stated change
  §7.1  coverage      cells per run, runs, measured/skipped/failed tallies
  prose               the derived ratios (3.4x, 538x, ...) recomputed from cells
  restatements        the same figures where §1, §8.1 and appendix A repeat them

comparison is numeric within last-displayed-digit tolerance, never string
equality — see bench.py, which owns the loader and the rationale.

coverage is reported as a breakdown, not a total. a claim that is parsed but
never compared inflates a total while verifying nothing, which is the failure
mode that made two previous audit tools report clean while broken.

  --selftest   mutation test. for every claim the checker says it verified,
               perturb the claimed value and require a FAIL. a claim whose
               mutation survives was never really compared, and is reported as
               a CHECKER bug rather than a document result.

usage: python3 numbers.py REFERENCE_MD RAWDIR [--selftest]
exit status is 1 if any claim fails, or if --selftest finds an uncompared claim.
"""

import re
import sys

import bench

# ---------------------------------------------------------------------------
# parsing helpers
# ---------------------------------------------------------------------------

SCALE_WORDS = {"10k": 10000, "100k": 100000, "1M": 1000000}
# rows/s and alloc counts are written with magnitude suffixes in §7 but not in
# results.md, so this is a §7-only spelling
MAGNITUDE = {"": 1.0, "k": 1e3, "M": 1e6, "G": 1e9}

NUM = r"([0-9][0-9,]*(?:\.[0-9]+)?)"


def clean(cell):
  """strip markdown emphasis and whitespace from a table cell."""
  return cell.replace("**", "").replace("`", "").strip()


def half_ulp_of(numeral):
  return bench.half_ulp(numeral.replace(",", ""))


def parse_magnitude(text):
  """'4.9M/s' -> (4900000.0, 50000.0); '76,936' -> (76936.0, 0.5).

  tolerance is half a unit in the last displayed place, scaled by the suffix —
  so '4.9M/s' permits +-50k, which is what one displayed decimal of millions
  actually promises. treating it as exact would produce false failures; treating
  it as loose would let a wrong number through.
  """
  text = clean(text).replace("/s", "").strip()
  if text in ("", "—", "-"):
    return None
  m = re.fullmatch(NUM + r"\s*([kMG]?)", text)
  if not m:
    return bench.UNPARSEABLE
  numeral, suffix = m.group(1), m.group(2)
  scale = MAGNITUDE[suffix]
  return (float(numeral.replace(",", "")) * scale, half_ulp_of(numeral) * scale)


def parse_ratio(text):
  """'3.4×' -> (3.4, 0.05). also accepts '304x' and bare '1.9'."""
  m = re.search(NUM + r"\s*[×x]", clean(text))
  if not m:
    return None
  return (float(m.group(1).replace(",", "")), half_ulp_of(m.group(1)))


def section(lines, heading):
  """1-based [start, end) of a '## ' section, fences excluded from the scan."""
  start = end = None
  fence = False
  for i, line in enumerate(lines, 1):
    if line.lstrip().startswith("```"):
      fence = not fence
      continue
    if fence:
      continue
    if start is None and line.startswith(heading):
      start = i
    elif start is not None and line.startswith("## "):
      end = i
      break
  if start is None:
    sys.exit(f"section not found: {heading!r}")
  return start, (end or len(lines) + 1)


def table_rows(lines, start, end):
  """yield (lineno, [cells]) for pipe-table body rows in a line range."""
  for n in range(start, end):
    line = lines[n - 1]
    if not line.startswith("|"):
      continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if not cells or set("".join(cells)) <= {"-", " ", ":"}:
      continue
    yield n, cells


# ---------------------------------------------------------------------------
# claims
# ---------------------------------------------------------------------------

class Claim:
  """one verifiable assertion lifted out of the document.

  `compare` is a function of the claimed value returning (ok, detail). keeping
  the claimed value separate from the comparison is what makes the mutation
  self-test possible: perturb `value`, re-run `compare`, require failure.
  """

  def __init__(self, lineno, label, value, compare, kind):
    self.lineno = lineno
    self.label = label
    self.value = value
    self.compare = compare
    self.kind = kind

  def check(self, value=None):
    return self.compare(self.value if value is None else value)


# a claim where the document says "—" and the raw data has nothing either. it
# agrees, truthfully, while verifying nothing — and no mutation can make it
# fail, because there is no value to perturb. counting it as verified is the
# exact inflation this tool exists to avoid, so it gets its own bucket.
VACUOUS = "vacuous"


def approx(truth, tol_floor=0.0):
  """build a comparison against a known truth, using the claim's own tolerance."""
  def cmp(claimed):
    if claimed is bench.UNPARSEABLE:
      return False, "unparseable"
    if claimed is None:
      if truth is None:
        return VACUOUS, "both absent — nothing verified"
      return False, f"claimed nothing, truth {truth!r}"
    if truth is None:
      return False, f"claimed {claimed[0]:.6g}, truth absent"
    value, tol = claimed
    ok = abs(float(truth) - value) <= max(tol, tol_floor)
    return ok, f"claimed {value:.6g}±{tol:g}, truth {float(truth):.6g}"
  return cmp


def exact(truth):
  def cmp(claimed):
    return claimed == truth, f"claimed {claimed!r}, truth {truth!r}"
  return cmp


# ---------------------------------------------------------------------------
# extraction
# ---------------------------------------------------------------------------

WRITE_PATHS = ["appender", "register", "register_flat", "literal"]
READ_PATHS = ["materialized", "streaming", "stream_first"]


def cell_lookup(collapsed, threads, kind, profile, scale, path):
  return collapsed.get((threads, kind, profile, scale, path))


def extract_write_table(lines, start, end, collapsed, claims):
  """§7.2 — 'Median · rows/s · allocations', 1 thread."""
  for lineno, cells in table_rows(lines, start, end):
    if len(cells) != 6 or cells[0] in ("Profile", "profile"):
      continue
    profile, scale_word = clean(cells[0]), clean(cells[1])
    if scale_word not in SCALE_WORDS:
      continue
    scale = SCALE_WORDS[scale_word]
    for path, raw_cell in zip(WRITE_PATHS, cells[2:]):
      text = clean(raw_cell)
      found = cell_lookup(collapsed, 1, "write", profile, scale, path)
      if found is None:
        claims.append(Claim(lineno, f"§7.2 {profile}/{scale_word}/{path} exists",
                            text, exact(None), "cell"))
        continue
      _, cell = found
      # a marker cell asserts the path was NOT measured
      if "❌" in text or text in ("n/a", "—") or text.startswith("excluded"):
        claims.append(Claim(
          lineno, f"§7.2 {profile}/{scale_word}/{path} is not measured",
          "skipped", exact(cell["status"]), "marker"))
        continue
      parts = [p.strip() for p in text.split("·")]
      if parts:
        claims.append(Claim(
          lineno, f"§7.2 {profile}/{scale_word}/{path} median",
          bench.parse_time(parts[0]), approx(cell.get("median_ns")), "cell"))
      if len(parts) > 1:
        claims.append(Claim(
          lineno, f"§7.2 {profile}/{scale_word}/{path} rows/s",
          parse_magnitude(parts[1]), approx(cell.get("rows_per_sec")), "cell"))
      if len(parts) > 2:
        # the column convention is "median · rows/s · allocations", but at least
        # one cell (struct/1M/literal) puts a MEMORY figure third instead, to
        # support a prose claim about gigabytes. verify what is actually written
        # rather than rejecting it — the inconsistency is a document defect,
        # recorded separately, not a parse failure
        if re.search(r"[KMG]iB|bytes?", parts[2]):
          claims.append(Claim(
            lineno, f"§7.2 {profile}/{scale_word}/{path} memory (allocs column)",
            bench.parse_bytes(parts[2]), approx(cell.get("memory_bytes")), "cell"))
        else:
          claims.append(Claim(
            lineno, f"§7.2 {profile}/{scale_word}/{path} allocs",
            parse_magnitude(parts[2]), approx(cell.get("allocs")), "cell"))


def extract_read_table(lines, start, end, collapsed, claims):
  """§7.3 — medians only, 1 thread."""
  for lineno, cells in table_rows(lines, start, end):
    if len(cells) != 5 or clean(cells[0]) in ("Profile", "profile"):
      continue
    profile, scale_word = clean(cells[0]), clean(cells[1])
    if scale_word not in SCALE_WORDS:
      continue
    scale = SCALE_WORDS[scale_word]
    for path, raw_cell in zip(READ_PATHS, cells[2:]):
      found = cell_lookup(collapsed, 1, "read", profile, scale, path)
      truth = None if found is None else found[1].get("median_ns")
      claims.append(Claim(
        lineno, f"§7.3 {profile}/{scale_word}/{path} median",
        bench.parse_time(clean(raw_cell)), approx(truth), "cell"))


THREAD_LABEL = re.compile(
  r"(?P<profile>flat|rich|struct|list)\s+(?P<scale>10k|100k|1M)\s*·\s*"
  r"(?:(?P<read>read)\s+)?(?P<path>[a-z_]+)")


def extract_thread_table(lines, start, end, collapsed, claims, hi_threads):
  """§7.4 — 1-thread value, many-thread value, and the stated change.

  hi_threads comes from the data, not a constant. it is 64 here only because
  `-t auto` on this box is 64; hardcoding it would make every §7.4 claim fail
  on any other machine, and report that as a document defect rather than an
  environment mismatch.
  """
  for lineno, cells in table_rows(lines, start, end):
    if len(cells) != 4 or clean(cells[0]) in ("Cell", "cell"):
      continue
    m = THREAD_LABEL.search(clean(cells[0]))
    if not m:
      continue
    profile, scale = m.group("profile"), SCALE_WORDS[m.group("scale")]
    kind = "read" if m.group("read") else "write"
    path = m.group("path")
    label = f"§7.4 {profile}/{m.group('scale')}/{kind}/{path}"

    truths = {}
    for threads, col in ((1, cells[1]), (hi_threads, cells[2])):
      found = cell_lookup(collapsed, threads, kind, profile, scale, path)
      truths[threads] = None if found is None else found[1].get("median_ns")
      claims.append(Claim(
        lineno, f"{label} @{threads}t",
        bench.parse_time(clean(col)), approx(truths[threads]), "cell"))

    # the change column: a ratio, "~unchanged", or "N% faster"
    change = clean(cells[3])
    if truths[1] and truths[hi_threads]:
      ratio = truths[hi_threads] / truths[1]
      claimed = parse_ratio(change)
      if claimed is not None:
        # "N× slower" means 64t/1t; "N× faster" the reciprocal
        expected = ratio if "slower" in change else 1.0 / ratio
        claims.append(Claim(lineno, f"{label} change", claimed,
                            approx(expected), "derived"))
      elif "%" in change:
        pct = re.search(NUM + r"\s*%", change)
        if pct:
          # "64 threads is X% faster" is measured against the 1-thread time —
          # (t1 - t64) / t1 — not against t64. the other denominator gives 7.6%
          # where the document says 7%, and would have reported a correct
          # document as wrong
          moved = (1.0 - ratio) if "faster" in change else (ratio - 1.0)
          claims.append(Claim(
            lineno, f"{label} change %",
            (float(pct.group(1)), max(half_ulp_of(pct.group(1)), 0.5)),
            approx(moved * 100.0), "derived"))


def extract_coverage(lines, start, end, runs, claims):
  """§7.1 — the sweep's shape: cells per run, run count, status tallies."""
  per_run = len(runs[0]["cells"]) if runs else 0
  measured = sum(1 for c in runs[0]["cells"] if c["status"] == "ok") if runs else 0
  # all four tallies describe ONE run. deriving `skipped` by subtraction while
  # summing `failed` across runs would let a failure in run 3 be counted as a
  # skip in run 0, and the document sentence is per-run ("84 cells per run")
  failed = sum(1 for c in runs[0]["cells"]
               if c["status"] not in ("ok", "skipped")) if runs else 0
  skipped = sum(1 for c in runs[0]["cells"]
                if c["status"] == "skipped") if runs else 0
  notapp = sum(1 for c in runs[0]["cells"]
               if c["status"] == "skipped" and "not applicable" in c.get("reason", ""))

  for n in range(start, end):
    line = lines[n - 1]
    m = re.search(r"\*\*Coverage\*\*:\s*" + NUM + r"\s*cells per run\s*×\s*" + NUM +
                  r"\s*runs;\s*" + NUM + r"\s*measured,\s*" + NUM +
                  r"\s*skipped,\s*\*\*" + NUM + r"\s*failed\*\*", line)
    if m:
      for i, (what, truth) in enumerate(
          [("cells per run", per_run), ("runs", len(runs)),
           ("measured", measured), ("skipped", skipped), ("failed", failed)]):
        claims.append(Claim(n, f"§7.1 coverage: {what}",
                            (float(m.group(i + 1).replace(",", "")), 0.5),
                            approx(truth), "count"))
    m = re.search(r"the\s+" + NUM + r"\s*`register_flat`\s*cells per run", line)
    if m:
      claims.append(Claim(n, "§7.1 register_flat not-applicable skips per run",
                          (float(m.group(1)), 0.5), approx(notapp), "count"))


def extract_ratios(lines, start, end, collapsed, claims, doc_end):
  """the derived ratios in §7's prose, and their restatements elsewhere.

  each is recomputed from the cells it cites rather than trusted. the
  restatements matter as much as the originals: every defect found in this
  document across three sessions has been in a summary construct, never in an
  evidence section.
  """
  def med(kind, profile, scale, path, threads=1):
    found = cell_lookup(collapsed, threads, kind, profile, scale, path)
    return None if found is None else found[1]

  reg = med("write", "flat", 1000000, "register")
  app = med("write", "flat", 1000000, "appender")
  lit = med("write", "flat", 1000000, "literal")
  if not (reg and app and lit):
    return

  speedup = app["median_ns"] / reg["median_ns"]
  allocs = app["allocs"] / reg["allocs"]
  memory = app["memory_bytes"] / reg["memory_bytes"]
  litratio = lit["median_ns"] / reg["median_ns"]

  # scan the whole document: §1, §8.1 and appendix A restate these
  patterns = [
    (r"\*\*3\.4×\*\*|3\.4×", speedup, "register vs appender speedup at flat/1M"),
    (r"\*\*538×\*\*|538×", allocs, "allocation ratio at flat/1M"),
    (r"\*\*328×\*\*|328×", memory, "memory ratio at flat/1M"),
    (r"304×", litratio, "literal vs register at flat/1M"),
  ]
  for n in range(1, doc_end):
    line = lines[n - 1]
    for pattern, truth, what in patterns:
      for m in re.finditer(pattern, line):
        claimed = parse_ratio(m.group(0))
        if claimed is not None:
          claims.append(Claim(n, f"ratio: {what}", claimed, approx(truth), "derived"))


def extract_stability(lines, start, end, runs, claims):
  """§7.5 — how many orderings reproduced across repeats, and the named flips.

  reproduces run_all.jl's rule (run_all.jl:155-160): within a
  (threads, kind, profile, scale), sort the ok cells by median_ns. an ordering
  "reproduced" when every run at that thread count agrees.
  """
  groups = {}
  for run in runs:
    for cell in run["cells"]:
      if cell["status"] != "ok":
        continue
      key = (run["threads"], cell["kind"], cell["profile"], cell["scale"])
      groups.setdefault(key, {}).setdefault(run["tag"], []).append(
        (cell["median_ns"], cell["path"]))

  tally = {"write": [0, 0], "read": [0, 0]}      # [reproduced, total]
  for key, bytag in groups.items():
    kind = key[1]
    ords = [[p for _, p in sorted(v)] for v in bytag.values()]
    tally[kind][1] += 1
    if len(ords) >= 2 and all(o == ords[0] for o in ords):
      tally[kind][0] += 1

  for n in range(start, end):
    line = lines[n - 1]
    m = re.search(r"\*\*Writes:\s*all\s*" + NUM + r"\s*orderings reproduced", line)
    if m:
      claims.append(Claim(n, "§7.5 write orderings total",
                          (float(m.group(1)), 0.5), approx(tally["write"][1]), "order"))
      claims.append(Claim(n, "§7.5 write orderings reproduced",
                          (float(m.group(1)), 0.5), approx(tally["write"][0]), "order"))
    m = re.search(r"\*\*Reads:\s*" + NUM + r"\s*of\s*" + NUM + r"\s*reproduced", line)
    if m:
      claims.append(Claim(n, "§7.5 read orderings reproduced",
                          (float(m.group(1)), 0.5), approx(tally["read"][0]), "order"))
      claims.append(Claim(n, "§7.5 read orderings total",
                          (float(m.group(2)), 0.5), approx(tally["read"][1]), "order"))


# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------

def collect(refpath, rawdir):
  lines = open(refpath, encoding="utf-8").read().splitlines()
  runs = bench.load_runs(rawdir)
  collapsed = bench.index_collapsed(runs)

  s7, e7 = section(lines, "## 7. Benchmarks")
  claims = []
  extract_coverage(lines, s7, e7, runs, claims)
  extract_write_table(lines, s7, e7, collapsed, claims)
  extract_read_table(lines, s7, e7, collapsed, claims)
  hi = sorted({r["threads"] for r in runs} - {1})
  extract_thread_table(lines, s7, e7, collapsed, claims,
                       hi[-1] if hi else 1)
  extract_stability(lines, s7, e7, runs, claims)
  extract_ratios(lines, s7, e7, collapsed, claims, len(lines) + 1)
  return lines, claims


def main(argv):
  args = [a for a in argv[1:] if not a.startswith("--")]
  flags = {a for a in argv[1:] if a.startswith("--")}
  if len(args) != 2:
    sys.exit("usage: python3 numbers.py REFERENCE_MD RAWDIR [--selftest]")
  refpath, rawdir = args

  lines, claims = collect(refpath, rawdir)

  failures = []
  by_kind = {}
  n_vacuous = 0
  for c in claims:
    ok, detail = c.check()
    if ok is VACUOUS:
      n_vacuous += 1
      continue
    by_kind[c.kind] = by_kind.get(c.kind, 0) + 1
    if not ok:
      failures.append(f"{refpath}:{c.lineno}: {c.label}: {detail}")

  print(f"claims verified: {sum(by_kind.values())}   (real comparisons)")
  for kind in sorted(by_kind):
    print(f"  {kind:<10} {by_kind[kind]}")
  print(f"vacuous:         {n_vacuous}   (both sides absent — verifies nothing)")
  print(f"claims failed:   {len(failures)}")

  if "--selftest" in flags:
    print("\nmutation self-test — every verified claim must fail when perturbed")
    uncompared = []
    for c in claims:
      ok, _ = c.check()
      if ok is VACUOUS or not ok:
        continue          # vacuous or already failing; mutation proves nothing
      mutated = mutate(c.value)
      if mutated is None:
        continue
      still_ok, _ = c.check(mutated)
      if still_ok:
        uncompared.append(f"{refpath}:{c.lineno}: {c.label}")
    print(f"  claims mutated:        {sum(1 for c in claims if c.check()[0] is True)}")
    print(f"  survived mutation:     {len(uncompared)}   (each is a CHECKER bug)")
    for u in uncompared:
      print(f"    UNCOMPARED: {u}")
    if uncompared:
      failures.extend(f"selftest: {u} parsed but never compared" for u in uncompared)

  if failures:
    print(f"\nFAIL — {len(failures)} problem(s):\n")
    for f in failures:
      print("  " + f)
    return 1
  print("\nOK — every parsed claim in §7 agrees with raw/*.json")
  return 0


def mutate(value):
  """perturb a claimed value past its own tolerance."""
  if value is None or value is bench.UNPARSEABLE:
    return None
  if isinstance(value, tuple):
    magnitude, tol = value
    return (magnitude + max(tol * 4, abs(magnitude) * 0.5 + 1.0), tol)
  if isinstance(value, str):
    return value + "_mutated"
  return None


if __name__ == "__main__":
  sys.exit(main(sys.argv))
