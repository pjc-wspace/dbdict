# probe `hdf5-temporal-compression` — measured

**Date:** 2026-08-02
**Session:** `20260801-1257-v0.3.0-direction-doc-and-repositioning`, phase 1
**Script:** `research/hdf5-temporal-compression/probe.py` (committed, re-runnable)
**Supersedes:** the `Inferred:` paragraph in
`.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md` §8

---

## verdict

**The claim holds.** Every lexical temporal encoding compresses below
8.0 bytes/row — the raw size of the `int64` µs encoding dbdict rejected —
in both sorted and shuffled orderings. The *canonical ≠ physical* decision
**stands**; nothing reopens.

Two refinements, both of which the direction document should carry rather
than repeating the original phrasing:

1. **"Well under" is true for sorted data only.** Shuffled timestamps land at
   **7.43–7.51 bytes/row** against the 8.0 threshold — a 6–7% margin, not a
   comfortable one. Sorted timestamps land at 4.52–4.63.
2. **Size was never the real cost — read time is.** Against a compressed
   `int64` column, lexical costs only **1.14–1.27×** the disk. But it costs
   **6–16× the read time**. The decisions note asked for read throughput and
   this is where the answer actually lives.

---

## environment [measured]

| | |
|---|---|
| h5py | 3.16.0 |
| HDF5 library | 2.0.0 |
| Python | 3.14 (ephemeral `uv` env; system Python is 3.10.12) |
| numpy | 2.5.1 |
| filters available | `deflate/gzip` ✓ · `shuffle` ✓ · `szip` ✓ · `lzf` ✓ |
| rows | 1,000,000 |
| chunk | 16,384 rows (same for every encoding) |
| seed | 20260801 |
| data span | 3.80 years, exponential inter-arrival, mean gap 120 s |

Storage measured with `DatasetID.get_storage_size()` — *"Report the size of
storage, in bytes, that is allocated in the file for the dataset's raw data"*
([h5py h5d](https://api.h5py.org/h5d.html)) — which excludes HDF5 metadata and
is therefore the fair per-column number. `Dataset.nbytes` is explicitly **not**
this: *"This may not be the amount of disk space occupied by the dataset"*
([h5py dataset](https://docs.h5py.org/en/stable/high/dataset.html)).

**Every h5py and HDF5 API used by the probe is quoted and linked** in the
sourced-APIs table of
[`research/hdf5-temporal-compression/README.md`](../../research/hdf5-temporal-compression/README.md)
— eleven entries covering `Dataset.id`, `get_storage_size`, `chunks=`,
`compression=` / `compression_opts=`, `shuffle=`, `string_dtype`,
`h5z.filter_avail`, and the two HDF5 szip restrictions. That table is the
single home for the API citations; this note is the single home for the
measurements, so neither claim lives in two files.

---

## bytes per row, on-disk raw data [measured]

| encoding | ordering | none | gzip(4) | gzip(9) | shuffle+gzip(9) | szip |
|---|---|---|---|---|---|---|
| `date` lexical (S10) | sorted | 10.16 | 0.03 | 0.03 | **0.02** | n/a |
| `date` lexical (S10) | shuffled | 10.16 | 2.60 | 2.12 | **1.87** | n/a |
| `timestamp` lexical, no zone (S27) | sorted | 27.43 | 7.97 | 7.57 | **4.52** | n/a |
| `timestamp` lexical, no zone (S27) | shuffled | 27.43 | 11.02 | 9.98 | **7.43** | n/a |
| `timestamp` lexical, zoned (S61) | sorted | 61.96 | 8.51 | 8.05 | **4.63** | n/a |
| `timestamp` lexical, zoned (S61) | shuffled | 61.96 | 12.28 | 10.86 | **7.51** | n/a |
| `timestamp` int64 µs | sorted | 8.13 | 4.77 | 4.82 | 4.06 | **3.97** |
| `timestamp` int64 µs | shuffled | 8.13 | 6.97 | 6.97 | **5.94** | 6.37 |
| `date` int32 days | sorted | 4.06 | **0.01** | 0.01 | 0.01 | 0.02 |
| `date` int32 days | shuffled | 4.06 | 1.92 | 1.83 | **1.41** | 1.52 |

Bold = best filter for that row.

**`shuffle+gzip(9)` wins for every lexical encoding.** Not obvious in advance —
`shuffle` is a byte-transposition filter usually associated with numeric types.
It helps fixed-width ASCII because transposing groups each character *position*
together across rows, and in RFC 3339 text most positions are near-constant
(the century digits, the separators, the leading digits of the month). `Inferred:`
as to mechanism — the *measurement* is that it beats plain gzip(9) by 34–43% on
the timestamp encodings.

---

## read time, seconds, best of 3, full column [measured]

| encoding | ordering | none | gzip(4) | gzip(9) | shuffle+gzip(9) | szip |
|---|---|---|---|---|---|---|
| `date` lexical (S10) | sorted | 0.001 | 0.005 | 0.005 | 0.018 | n/a |
| `date` lexical (S10) | shuffled | 0.001 | 0.016 | 0.016 | 0.023 | n/a |
| `timestamp` lexical, no zone (S27) | sorted | 0.003 | 0.049 | 0.050 | 0.052 | n/a |
| `timestamp` lexical, no zone (S27) | shuffled | 0.003 | 0.059 | 0.061 | 0.059 | n/a |
| `timestamp` lexical, zoned (S61) | sorted | 0.016 | 0.076 | 0.077 | 0.136 | n/a |
| `timestamp` lexical, zoned (S61) | shuffled | 0.016 | 0.089 | 0.090 | 0.142 | n/a |
| `timestamp` int64 µs | sorted | 0.001 | 0.017 | 0.017 | 0.012 | 0.026 |
| `timestamp` int64 µs | shuffled | 0.001 | 0.020 | 0.022 | 0.009 | 0.038 |
| `date` int32 days | sorted | 0.000 | 0.003 | 0.003 | 0.007 | 0.005 |
| `date` int32 days | shuffled | 0.000 | 0.009 | 0.009 | 0.007 | 0.012 |

At each encoding's best-compression filter, shuffled:

| | lexical | int64 | ratio |
|---|---|---|---|
| `timestamp`, no zone | 0.059 s | 0.009 s | **6.6×** |
| `timestamp`, zoned | 0.142 s | 0.009 s | **15.8×** |

**Read this fairly.** 0.142 s for a million-row column is not a crisis in
absolute terms, and dbdict's V1 workloads are not read-throughput-bound. The
ratio is what carries forward: whatever the column size, decoding fixed-width
ASCII costs roughly an order of magnitude more than reading `int64`, and that
does not improve with scale.

---

## szip cannot be applied to lexical temporals at all [measured + cited]

`h5py.h5z.filter_avail(FILTER_SZIP)` returns **True** on this machine — the
filter is present in the build. Every attempt to *use* it on a fixed-width
string column nonetheless fails:

```
ValueError: Unable to synchronously create dataset (invalid datatype size)
```

for all three of `S10`, `S27`, `S61`. This is documented behaviour, not a
local defect ([HDF5 — Compressed
Datasets](https://support.hdfgroup.org/documentation/hdf5/latest/_l_b_com_dset.html)):

> "SZIP compression can only be used with atomic datatypes that are integer,
> float, or char. It cannot be applied to compound, array, variable-length,
> enumerations, or other user-defined datatypes."

> "The call to H5Dcreate will fail if attempting to create an SZIP compressed
> dataset with a non-allowed datatype. The conflict can only be detected when
> the property list is used."

**Availability and applicability are different questions**, and `filter_avail`
answers only the first. Consequence for dbdict: the integer encodings have a
filter option the lexical ones do not — and szip is in fact `int64`'s best
sorted result (3.97 bytes/row). The lexical encodings are confined to
gzip/shuffle. This slightly narrows the lexical form's advantage and belongs in
the capability matrix.

---

## the comparison the original claim did not make

The `Inferred:` claim tested compressed lexical against **raw** `int64` (8
bytes/row). But the integer encoding compresses too — the decisions note
concedes it *"would also have needed chunking to beat"*. Against compressed
`int64`:

| lexical type | ordering | best lexical | best int | ratio |
|---|---|---|---|---|
| `timestamp`, no zone | sorted | 4.52 | 3.97 (szip) | 1.14× |
| `timestamp`, no zone | shuffled | 7.43 | 5.94 | 1.25× |
| `timestamp`, zoned | sorted | 4.63 | 3.97 (szip) | 1.17× |
| `timestamp`, zoned | shuffled | 7.51 | 5.94 | 1.27× |
| `date` | sorted | 0.02 | 0.01 | 1.79× |
| `date` | shuffled | 1.87 | 1.41 | 1.32× |

**This is the honest number: lexical costs 14–27% more disk than the integer
encoding it replaced, not the 3.4–7.6× the uncompressed figures implied.** That
is a far better result for *canonical ≠ physical* than the raw comparison
suggested, and it is the figure the direction document should quote.

---

## caveat on the `date` rows

The `date` results (0.02 sorted, 1.87 shuffled) are a **low-cardinality
artifact** and should not be generalised. The generator spreads 10⁶ rows over
3.80 years, so roughly 1,387 distinct dates each repeat ~721 times. A table
where `date` is closer to unique per row would compress far less well. The
`timestamp` rows, which are near-unique by construction, are the trustworthy
ones — and they are the binding constraint anyway.

---

## what changes

- §8 of `20260731-1552-dbdict-type-system-decisions.md`: the `Inferred:`
  paragraph is replaced by `[measured]` pointing here. **The decision stands.**
- The direction document (phase 2) quotes **4.52–7.51 bytes/row** for lexical
  temporals and the **1.14–1.27×** compressed-vs-compressed ratio, not
  "compression closes the gap". It also states the read-time ratio, because
  that is the actual cost being accepted.
- The capability matrix gains a row: **szip is inapplicable to lexical
  temporal columns on HDF5**, with the citation above.
- `max_bytes:` as HDF5's compression switch is **reinforced** — fixed-width is
  what makes any of this possible, and the earlier finding that
  variable-length HDF5 strings get neither chunking nor filters is what makes
  fixed-width mandatory rather than merely preferable.

## still open

Unchanged by this probe: `sqlitejl-temporal`, `pg-type-oracle` (V2),
`sqlite-comment-durability`, `jld2-h5-crosscheck`.
