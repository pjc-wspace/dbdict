# /// script
# requires-python = ">=3.10"
# dependencies = ["h5py", "numpy"]
# ///
"""
probe `hdf5-temporal-compression` — dbdict v0.3.0

settles one `Inferred:` claim from
.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md §8:

  "Inferred: that ISO-8601 columns compress to well under the integer
   encoding's raw size. Not measured."

falsification test, fixed before measuring: the claim HOLDS iff compressed
fixed-width ASCII temporals land below 8.0 bytes/row — the raw size of the
int64 microsecond encoding that dbdict rejected.

h5py APIs used here, each sourced from official docs (see README.md):
  Dataset.id                  https://docs.h5py.org/en/stable/high/dataset.html
  DatasetID.get_storage_size  https://api.h5py.org/h5d.html
  chunks= / compression= /
  compression_opts= / shuffle= https://docs.h5py.org/en/stable/high/dataset.html
  h5py.h5z.filter_avail       https://api.h5py.org/h5z.html
  h5py.string_dtype           https://docs.h5py.org/en/stable/strings.html
"""

import os
import tempfile
import time

import h5py
import numpy as np

N_ROWS = 1_000_000
SEED = 20260801

# same row-count chunk for every encoding so the comparison is apples-to-apples.
# at 16384 rows the widest column (S61) is ~1.0 MiB per chunk, which keeps every
# chunk in the same order of magnitude as HDF5's default 1 MiB chunk cache.
CHUNK_ROWS = 16384

# the number the claim is tested against: raw bytes/row of the int64 µs encoding
INT64_RAW_BYTES_PER_ROW = 8.0


def build_timestamps():
  """1e6 timestamps spread over a realistic multi-year range.

  returns (sorted_us, shuffled_us) as int64 microseconds since the unix epoch.
  the two arrays hold the SAME values — only the order differs. that is the
  whole point: the decisions note justifies the compression claim with
  "consecutive values share long prefixes", which is a property of sorted data
  only. testing sorted alone would confirm the claim by construction.
  """
  rng = np.random.default_rng(SEED)
  start_us = np.datetime64("2020-01-01T00:00:00.000000", "us").astype("int64")
  # mean gap ~120s, exponential — bursty like real event data, and spreads
  # 1e6 rows over roughly 3.8 years
  gaps_us = rng.exponential(scale=120e6, size=N_ROWS).astype("int64")
  sorted_us = start_us + np.cumsum(gaps_us)
  shuffled_us = rng.permutation(sorted_us)
  return sorted_us, shuffled_us


def encode(us):
  """build every candidate column encoding from int64 microseconds."""
  dt = us.astype("datetime64[us]")

  # RFC 3339 full-date — "2026-08-02"
  date_lex = np.datetime_as_string(dt.astype("datetime64[D]")).astype("S10")

  # RFC 3339 date-time, µs, Z — "2026-08-02T12:34:56.123456Z" (27 bytes)
  ts_lex = np.char.add(np.datetime_as_string(dt, unit="us"), "Z").astype("S27")

  # RFC 9557 with IXDTF zone suffix, padded to the note's worst case (61 bytes)
  ts_zoned = np.char.add(
    np.datetime_as_string(dt, unit="us"), "+12:00[Pacific/Auckland]"
  ).astype("S61")

  # the rejected alternatives
  ts_int64 = us
  date_int32 = (us // 86_400_000_000).astype("int32")

  return {
    "date lexical (S10)": date_lex,
    "timestamp lexical, no zone (S27)": ts_lex,
    "timestamp lexical, zoned (S61)": ts_zoned,
    "timestamp int64 µs": ts_int64,
    "date int32 days": date_int32,
  }


def filter_specs():
  """(label, create_dataset kwargs) per filter, skipping unavailable ones."""
  specs = [
    ("none", {}),
    ("gzip(4)", {"compression": "gzip", "compression_opts": 4}),
    ("gzip(9)", {"compression": "gzip", "compression_opts": 9}),
    ("shuffle+gzip(9)", {"compression": "gzip", "compression_opts": 9, "shuffle": True}),
  ]
  # szip is "Not available with all installations of HDF5 due to legal reasons"
  # — check, never assume
  if h5py.h5z.filter_avail(h5py.h5z.FILTER_SZIP):
    specs.append(("szip", {"compression": "szip"}))
  return specs


class Unsupported(Exception):
  """this (encoding, filter) pair is rejected by the HDF5 filter pipeline.

  not a probe failure — an result. szip in particular reports available via
  filter_avail() but refuses fixed-width string datatypes, which is exactly
  the encoding dbdict proposes for temporals.
  """


def measure(tmpdir, label, data, filt_label, filt_kwargs):
  """write one column one way; return on-disk bytes/row and read seconds."""
  path = os.path.join(tmpdir, "probe.h5")
  try:
    f = h5py.File(path, "w")
  except OSError as exc:
    raise Unsupported(str(exc)) from exc
  with f:
    try:
      ds = f.create_dataset(
        "col", data=data, chunks=(CHUNK_ROWS,), **filt_kwargs
      )
    except (ValueError, OSError) as exc:
      raise Unsupported(f"{label} + {filt_label}: {exc}") from exc
    # "Report the size of storage, in bytes, that is allocated in the file for
    # the dataset's raw data" — excludes HDF5 metadata, so this is the fair
    # per-column number
    storage = ds.id.get_storage_size()

  # read throughput: best of 3, full-column read, file reopened each time so a
  # warm HDF5 chunk cache does not flatter later runs
  best = float("inf")
  for _ in range(3):
    t0 = time.perf_counter()
    with h5py.File(path, "r") as f:
      f["col"][()]
    best = min(best, time.perf_counter() - t0)

  file_bytes = os.path.getsize(path)
  os.remove(path)
  return storage / N_ROWS, best, file_bytes


def main():
  print(f"h5py {h5py.__version__} | HDF5 {h5py.version.hdf5_version}")
  avail = {
    name: bool(h5py.h5z.filter_avail(code))
    for name, code in [
      ("deflate/gzip", h5py.h5z.FILTER_DEFLATE),
      ("shuffle", h5py.h5z.FILTER_SHUFFLE),
      ("szip", h5py.h5z.FILTER_SZIP),
      ("lzf", h5py.h5z.FILTER_LZF),
    ]
  }
  print("filters available:", ", ".join(f"{k}={v}" for k, v in avail.items()))
  print(f"N={N_ROWS:,} rows | chunk={CHUNK_ROWS:,} rows | seed={SEED}")
  print()

  sorted_us, shuffled_us = build_timestamps()
  span = (sorted_us[-1] - sorted_us[0]) / 86_400_000_000 / 365.25
  print(f"data spans {span:.2f} years\n")

  orderings = {"sorted": encode(sorted_us), "shuffled": encode(shuffled_us)}
  specs = filter_specs()

  unsupported = {}
  results = {}
  header = ["encoding", "ordering"] + [lbl for lbl, _ in specs]
  print("## bytes per row (on-disk raw data)\n")
  print("| " + " | ".join(header) + " |")
  print("|" + "---|" * len(header))

  read_rows = []
  for enc_label in orderings["sorted"]:
    for ordering, cols in orderings.items():
      data = cols[enc_label]
      cells, reads = [], {}
      with tempfile.TemporaryDirectory() as tmpdir:
        for filt_label, kwargs in specs:
          try:
            bpr, secs, _ = measure(tmpdir, enc_label, data, filt_label, kwargs)
          except Unsupported as exc:
            # a rejected (encoding, filter) pair is a result, not a crash
            cells.append("n/a")
            reads[filt_label] = None
            unsupported.setdefault((enc_label, filt_label), str(exc))
            continue
          cells.append(f"{bpr:.2f}")
          reads[filt_label] = secs
          results[(enc_label, ordering, filt_label)] = bpr
      print(f"| {enc_label} | {ordering} | " + " | ".join(cells) + " |")
      read_rows.append((enc_label, ordering, reads))

  print()
  print("## read time, seconds (best of 3, full column)\n")
  print("| " + " | ".join(header) + " |")
  print("|" + "---|" * len(header))
  for enc_label, ordering, reads in read_rows:
    cells = [
      "n/a" if reads[lbl] is None else f"{reads[lbl]:.3f}" for lbl, _ in specs
    ]
    print(f"| {enc_label} | {ordering} | " + " | ".join(cells) + " |")

  if unsupported:
    print()
    print("## rejected (encoding, filter) pairs\n")
    for (enc_label, filt_label), msg in unsupported.items():
      print(f"- **{enc_label}** + **{filt_label}** — `{msg.splitlines()[0]}`")

  # verdict, computed rather than eyeballed. the claim under test is about the
  # LEXICAL encodings only; the integer rows are the baseline they must beat.
  def best_for(enc_label, ordering):
    """(bytes_per_row, filter_label) for the best filter, or None."""
    subset = {
      k: v for k, v in results.items() if k[0] == enc_label and k[1] == ordering
    }
    if not subset:
      return None
    k = min(subset, key=subset.get)
    return subset[k], k[2]

  print()
  print("## verdict\n")
  print(
    f"Test fixed before measuring: the claim holds iff a lexical temporal "
    f"column compresses below **{INT64_RAW_BYTES_PER_ROW} bytes/row**, the raw "
    f"size of the rejected int64 µs encoding.\n"
  )
  print(
    "Reported per type and per ordering. A single 'best lexical' figure would "
    "be dominated by `date` (S10), the easiest case — the binding constraint "
    "is `timestamp`.\n"
  )
  print("| lexical type | ordering | best bytes/row | filter | vs 8.0 raw int64 | vs compressed int64 |")
  print("|---|---|---|---|---|---|")
  for enc_label in (
    "date lexical (S10)",
    "timestamp lexical, no zone (S27)",
    "timestamp lexical, zoned (S61)",
  ):
    # date compares against int32 days; timestamps against int64 µs
    int_label = "date int32 days" if enc_label.startswith("date") else "timestamp int64 µs"
    for ordering in ("sorted", "shuffled"):
      got = best_for(enc_label, ordering)
      int_got = best_for(int_label, ordering)
      if got is None:
        continue
      bpr, filt = got
      raw_verdict = "HOLDS" if bpr < INT64_RAW_BYTES_PER_ROW else "FAILS"
      if int_got is None:
        fair = "—"
      else:
        ratio = bpr / int_got[0]
        fair = f"{ratio:.2f}× ({int_got[0]:.2f}, {int_got[1]})"
      print(
        f"| {enc_label} | {ordering} | {bpr:.2f} | {filt} | "
        f"**{raw_verdict}** | {fair} |"
      )

  print()
  print(
    "> The second comparison is the one the original `Inferred:` claim did not "
    "make. It tested compressed lexical against *raw* int64; the integer "
    "encoding compresses too, and the decisions note itself concedes it "
    '"would also have needed chunking to beat".'
  )


if __name__ == "__main__":
  main()
