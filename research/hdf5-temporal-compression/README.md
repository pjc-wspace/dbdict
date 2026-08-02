# probe: `hdf5-temporal-compression`

Settles one `Inferred:` claim carried by the dbdict v0.3.0 type system.

## the claim under test

From `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md` §8:

> **`Inferred:`** that ISO-8601 columns compress to well under the integer
> encoding's raw size. Not measured. **Probe `hdf5-temporal-compression`**:
> write 10⁶ timestamps both ways, apply gzip/szip, compare on-disk bytes and
> read throughput. Worth running before the encoding is frozen in the spec.

dbdict stores temporals on HDF5 in **lexical** (fixed-width ASCII RFC 3339)
form rather than as integers, because *canonical ≠ physical* — see the
decisions note. The honest cost is 27–61 bytes/row against 8 for an `int64`
microsecond encoding. The claim is that compression closes that gap.

**Falsification test, fixed before measuring:** the claim holds iff a lexical
temporal column compresses below **8.0 bytes/row**.

The probe also reports a second comparison the original claim did not make —
lexical against **compressed** `int64`, not raw. The decisions note concedes
the integer encoding *"would also have needed chunking to beat"*, so the raw
baseline alone is not a fair test.

## re-run

```bash
uv run probe.py
```

Nothing is installed into the project: dependencies are pinned in the script's
[inline metadata](https://docs.astral.sh/uv/guides/scripts/#declaring-script-dependencies)
and resolved into an ephemeral, cached environment.

## design notes

- **Both orderings.** Every column is written twice, sorted and shuffled. The
  decisions note justifies the claim with *"consecutive values share long
  prefixes"* — a property of sorted data only. Testing sorted alone would
  confirm the claim by construction; the shuffled figure is the honest worst
  case.
- **The integer baselines are compressed too**, for the reason above.
- **Same chunk row-count for every encoding** so the comparison is
  apples-to-apples.
- **Per-type verdict, not a global best.** A single "best lexical" number is
  dominated by `date` (`S10`), the easiest case. The binding constraint is
  `timestamp`.

## sourced APIs

Every external API used here is quoted from official documentation rather than
written from memory, per the project's evidence standard.

| API / behaviour | quote | source |
|---|---|---|
| `Dataset.id` | "The dataset's low-level identifier; an instance of DatasetID." | [h5py dataset](https://docs.h5py.org/en/stable/high/dataset.html) |
| `DatasetID.get_storage_size()` | "Report the size of storage, in bytes, that is allocated in the file for the dataset's raw data." | [h5py h5d](https://api.h5py.org/h5d.html) |
| `chunks=` | "To enable chunked storage, set the keyword `chunks` to a tuple indicating the chunk shape" | [h5py dataset](https://docs.h5py.org/en/stable/high/dataset.html) |
| gzip level | "`compression_opts` sets the compression level and may be an integer from 0 to 9, default is 4." | [h5py dataset](https://docs.h5py.org/en/stable/high/dataset.html) |
| `shuffle=` | "Enable by setting `Group.create_dataset()` keyword `shuffle` to True." | [h5py dataset](https://docs.h5py.org/en/stable/high/dataset.html) |
| szip availability | "Patent-encumbered filter used in the NASA community. Not available with all installations of HDF5 due to legal reasons." | [h5py dataset](https://docs.h5py.org/en/stable/high/dataset.html) |
| `h5py.h5z.filter_avail()` | "Determine if the given filter is available to the library." | [h5py h5z](https://api.h5py.org/h5z.html) |
| fixed-length strings | "ds = f.create_dataset('fixed_strings2', shape=4, dtype=h5py.string_dtype(length=6))" | [h5py strings](https://docs.h5py.org/en/stable/strings.html) |
| chunking required for compression | "HDF5 requires you to use chunking to create a compressed dataset." | [HDF5 compressed datasets](https://support.hdfgroup.org/documentation/hdf5/latest/_l_b_com_dset.html) |
| szip datatype restriction | "SZIP compression can only be used with atomic datatypes that are integer, float, or char. It cannot be applied to compound, array, variable-length, enumerations, or other user-defined datatypes." | [HDF5 compressed datasets](https://support.hdfgroup.org/documentation/hdf5/latest/_l_b_com_dset.html) |
| szip failure timing | "The call to H5Dcreate will fail if attempting to create an SZIP compressed dataset with a non-allowed datatype. The conflict can only be detected when the property list is used." | [HDF5 compressed datasets](https://support.hdfgroup.org/documentation/hdf5/latest/_l_b_com_dset.html) |

## result — claim holds, decision stands

Lexical temporals reach **4.52–4.63 bytes/row sorted, 7.43–7.51 shuffled**
with `shuffle+gzip(9)`, clearing the 8.0 threshold in every case. Two
refinements: *"well under"* is true of sorted data only (shuffled clears by
6–7%), and against **compressed** `int64` lexical costs 1.14–1.27× the disk but
**6.6–15.8× the read time** — size was never the real cost. Separately, szip is
inapplicable to fixed-width string columns even though `filter_avail()` reports
it present.

Full matrix, environment, and verdict:
[`.claude-work/notes/20260802-1146-hdf5-temporal-compression.md`](../../.claude-work/notes/20260802-1146-hdf5-temporal-compression.md)
