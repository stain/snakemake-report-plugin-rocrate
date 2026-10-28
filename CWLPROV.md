# Lessons from CWLProv

CWLProv was an earlier approach to the same problem this plugin addresses:
packaging a workflow run with its retrospective provenance. It predates
RO-Crate, and the Workflow Run Crate profiles grew out of it (`runcrate
convert` turns a CWLProv research object into a Provenance Run Crate). This
note collects its design decisions and the experience reported with it, and
relates them to this plugin and to [`TODO.md`](TODO.md). It is input for
revising the plan, not part of it yet.

Sources:

- Khan, Soiland-Reyes, Sinnott, Lonie, Goble, Crusoe (2019): *Sharing
  interoperable workflow provenance: A review of best practices and their
  practical application in CWLProv*. GigaScience 8(11), giz095.
  <https://doi.org/10.1093/gigascience/giz095>
  ([preprint PDF](https://pure.manchester.ac.uk/ws/portalfiles/portal/99565220/CWLProv.pdf))
- CWLProv profile: <https://w3id.org/cwl/prov>, maintained at
  <https://github.com/common-workflow-language/cwlprov>. It has three parts:
  [BagIt](https://github.com/common-workflow-language/cwlprov/blob/master/bagit.md),
  [Research Object](https://github.com/common-workflow-language/cwlprov/blob/master/ro.md)
  and [PROV](https://github.com/common-workflow-language/cwlprov/blob/master/prov.md).

## What CWLProv is

A CWLProv research object is a BagIt bag:

| Path | Content |
|---|---|
| `bagit.txt`, `bag-info.txt`, `manifest-*.txt`, `tagmanifest-*.txt` | BagIt structure, with checksums of every file; `External-Identifier` gives the bag an `arcp://uuid,…/` base URI |
| `data/` | the payload: all input, intermediate and output files, stored under content-addressed names (`data/97/97fe1b…`) |
| `workflow/packed.cwl`, `workflow/primary-job.json` | a runnable copy of the workflow, packed into one file, and the job's input parameters with paths rewritten to point into `data/` |
| `snapshot/` | the workflow files exactly as they were at run time, without rewriting; paths inside may be broken |
| `metadata/manifest.json` | the RO Bundle manifest (JSON-LD): file types, `conformsTo`, `createdBy`, `authoredBy`, annotations |
| `metadata/provenance/primary.cwlprov.*` | the PROV trace of the top-level run (PROV-N required, other serialisations optional), plus one trace per nested workflow run |
| `metadata/logs/` | raw engine logs |

The PROV trace uses W3C PROV with the `wfprov`/`wfdesc` vocabularies:
- a `wfprov:WorkflowRun` activity, started and ended by the engine agent
  (`wfprov:WorkflowEngine`, labelled with its version);
- `wfprov:ProcessRun` activities for the step runs, each associated with the
  step's plan (`wfdesc:Process`);
- `used` and `wasGeneratedBy` relations, with `prov:role` pointing to the
  input or output parameter.

## The levels of provenance

The paper defines four cumulative levels and maps 19 recommendations (R1–R19)
from the literature onto them. Where this plugin stands today:

| Level | What it requires | This plugin today |
|---|---|---|
| **0** | Workflow and tool definitions, parameter configuration, raw logs, outputs | Partly. Only the main Snakefile is packaged, without includes, scripts or config (A6, A7). Logs are not packaged (A12). |
| **1** | Structured retrospective provenance of the run; content-addressable data; an executable workflow with its software environment; resource usage for the whole run | Partly. Provenance is structured, but there are no checksums (A2). The crate cannot be re-run (A1, A6). The environment is described only by package lists (A4, A5). No resource usage (A12). |
| **2** | White-box provenance per step and nested workflow; resolved container versions; inspecting and re-running single steps; permalinks for workflows and steps | Per-step actions exist, and intermediates are included. Missing: modules as nested workflows (A6), container digests (A5), stable identifiers (lesson 3). |
| **3** | Domain-specific annotations (EDAM, Bioschemas), a researcher-centric view | Not addressed. |

The paper mentions Snakemake directly when discussing partial re-runs
(Level 2): make-like systems "support partial re-enactments but typically
rely on fixed file paths for input data and require manual intervention to
provide the specific directory structure". The same issue shows up here as
`_EXTERNAL/` (A1).

## Recommendations R1–R19 against this plugin

| Rec. | Meaning | Status here | TODO |
|---|---|---|---|
| R1 parameters | All parameters, including defaults | Files only | A10 |
| R2 automate | No manual steps outside the workflow | Up to the workflow author | — |
| R3 intermediate | Include intermediate results | Done (ZIP mode) | — |
| R4 sw-version | Exact software versions | Conda packages: yes. Snakemake: report-time version | A4, A7 |
| R5 data-version | Versions of reference data | Not recorded | A2 (checksums) |
| R6 annotation | Described and annotated workflow | Minimal | A13 |
| R7 identifier | Stable identifiers for all artefacts | Local `#action_N` IDs from Snakemake job IDs | lesson 3 |
| R8 environment | Computational environment | Package lists | A5 |
| R9 workflow | Share the workflow definition | Main Snakefile only | A6 |
| R10 software | Aggregate the software | Conda YAML only | A5 |
| R11 raw-data | Share raw input data | Yes in ZIP mode; broken outside the workflow directory | A1 |
| R12 attribution | Who ran it | Options exist | A13 |
| R13 provenance | Provenance trace | Yes | — |
| R14 diagram | Data-flow diagram | None | lesson 13 |
| R15 open-source | Open licences | Crate licence option | — |
| R16 format | System-neutral formats | JSON-LD, RO-Crate | — |
| R17 executable | Easy re-execution | Not possible from the crate | A1, A6 |
| R18 resource-use | Compute and storage usage | None | A12 |
| R19 example | Example input and output data | Inputs and outputs included | — |

## Lessons

Each lesson says what CWLProv did, what applies to this plugin, and which
`TODO.md` items it affects. Lessons marked **new** are not covered by
`TODO.md` yet.

### 1. Keep a runnable copy and an as-is snapshot, and say which is which

CWLProv stores the workflow twice:
- `workflow/` holds a runnable copy, packed into one file, with a job file
  whose input paths are rewritten to point into the bag;
- `snapshot/` holds untouched copies, for inspection only. Consumers "SHOULD
  NOT assume that snapshot files have valid relative paths".

This plugin stores only one, unchanged, copy of the Snakefile, and moves
external inputs to `_EXTERNAL/` without changing anything that refers to
them. The result is neither a faithful snapshot (files are moved) nor
runnable (paths don't match).

*For this plugin:*
- Decide which kind the packaged Snakefile is, and describe it accordingly.
  Snakemake has no job file to rewrite, so a runnable copy needs the input
  files at the paths the Snakefile expects. That is only possible if those
  paths are inside the crate root.
- Snakemake's own `--archive FILE` already builds a re-executable tarball of
  the workflow: all git-tracked files, inputs not produced by the workflow,
  and the Conda environments. Reusing that logic, or recording its archive in
  the crate, may be simpler than re-implementing it.

Affects A1 and A6.

### 2. Content addressing and checksums as identity

CWLProv identifies data by checksum (`urn:hash:sha1:…`) and stores payload
files under content-addressed names. A file *as seen by a step* is a separate
entity that is a `specializationOf` the content entity, with its basename as
an attribute. This makes the same bytes recognisable across steps, runs and
platforms. The paper's evaluation compared outputs across executors and
platforms purely by these checksums.

*For this plugin:*
- Snakemake already records `input_checksums` (SHA-256) per job in
  `.snakemake/metadata`. For example, the `summary` job of the linear-elastic
  example records checksums for all four of its inputs. These are checksums
  *at the time the job ran*, which is exactly what B2 needs. They can be
  compared with the packaged files at report time, and copied into the crate
  (`sha256`) without re-hashing.
- Content-addressed paths would make the crate unreadable to people and
  would break the Snakefile's paths, so keep the real paths. The checksums
  provide the identity.

Affects A2 and B2.

### 3. Globally unique identifiers for the run and its parts

CWLProv bases all identifiers on the run's UUID. The bag's
`External-Identifier` is `arcp://uuid,<run UUID>/`, and activities are
`urn:uuid:` identifiers. Identifiers therefore stay unique when traces from
many runs are combined.

This plugin uses `#action_<jobid>`, `#control-action_<jobid>` and similar.
Snakemake job IDs are only meaningful within one DAG, and they are
recomputed at report time, so two crates of different runs use the same
identifiers for unrelated actions. The Process Run Crate recommends a
random UUID for action identifiers.

*For this plugin* (**new**):
- Identify the workflow run by Snakemake's own run UUID: every run log
  header contains `Workflow ID: <uuid>` (see A7).
- Derive action identifiers deterministically from that UUID and the job, as
  UUID v5 (`urn:uuid:` or `#<uuid>`). Deterministic identifiers keep golden
  test files (A0) stable.
- Consider setting the root dataset's `identifier` to the run's
  `arcp://uuid,…/` URI, as described in the RO-Crate notes on
  [base URIs in BagIt](https://www.researchobject.org/ro-crate/specification/1.1/appendix/implementation-notes.html#base-uri-in-bagit).

### 4. Attribution needs consent

`cwltool` records who ran the workflow only with `--enable-user-provenance`.
The local account (user name, host name) is kept separate from the person,
linked with `actedOnBehalfOf`. A person is identified only by an explicit
`--orcid`/`--full-name`, or by the `ORCID` environment variable. Engines
"SHOULD propagate the value of the `ORCID` shell environment variable".

*For this plugin:* the explicit `researcher-*` and `agent-*` options already
follow the consent principle. Never fall back to the local user name or host
name. Consider reading the `ORCID` environment variable as a default for
`agent-orcid`, which would also match `cwltool`. Affects A13.

### 5. Record which software made the package

The CWLProv manifest has `createdBy` with the generating software and
version (`cwltool 1.0.2018…`), separate from the workflow engine agent in the
PROV trace.

This crate records neither the plugin nor its version, so a crate made by a
buggy plugin version cannot be recognised later.

*For this plugin* (**new**): record crate generation as its own action, e.g. a
`CreateAction` with `instrument` → `SoftwareApplication`
"snakemake-report-plugin-rocrate" with its version, and `result` →
`ro-crate-metadata.json`, following RO-Crate's
[Software used to create files](https://www.researchobject.org/ro-crate/specification/1.1/provenance.html#software-used-to-create-files)
and
[Recording changes to RO-Crates](https://www.researchobject.org/ro-crate/specification/1.1/provenance.html#recording-changes-to-ro-crates).
Keep it separate from the Snakemake `OrganizeAction`.

### 6. Nested workflows get their own traces

CWLProv writes a separate trace per nested workflow run, linked from the
parent step with `prov:has_provenance`, with a separate plan per nested
workflow.

Snakemake's equivalents are `module:` / `use rule … from …` (reused
workflows) and `include:` (source split across files).

*For this plugin:* treat imported modules as nested `ComputationalWorkflow`s
in the main workflow's `hasPart`, with their own `HowToStep`s. Treat
`include:` files as plain parts of one workflow. Affects A6.

### 7. Directories and multi-file outputs are first-class

CWLProv models:
- directories as PROV dictionaries, with file names as keys and `hadMember`
  links to the files;
- CWL `secondaryFiles` (for example `.bam.bai` next to `.bam`) as a
  `cwlprov:SecondaryFile` derivation from the primary file.

This plugin drops any input or output that is not a regular file when the
report is generated (`provenance_files.py:51`: `if not self._is_file(file_path):
continue`; `_is_file` is `Path.is_file()`). From the code:
- `directory()` outputs are never recorded;
- `temp()` outputs, deleted by Snakemake after use, disappear from the
  provenance;
- in both cases the actions that used or produced them lose those links
  without any warning.

The README asks workflow authors to declare every component as an output,
which does not help for these two cases.

*For this plugin* (**new**):
- Record `directory()` outputs as `Dataset` entities with `hasPart` for their
  content, or as a
  [multi-file object](https://www.researchobject.org/workflow-run-crate/profiles/0.5/process_run_crate/#representing-multi-file-objects).
- Record deleted `temp()` files as entities that are not in the crate, using
  the A1 "reference, don't include" mechanism (a `#` identifier, and later
  `localPath`). Use the checksums Snakemake recorded for them, where it did.
- Warn about anything else that is skipped.

### 8. Small values inline

CWLProv stores small, non-file parameter values directly as `prov:value`.
This is the same as the `PropertyValue` approach in A10.

### 9. Raw logs are Level 0, and stay unstructured

CWLProv puts engine logs in `metadata/logs/` without trying to structure
them, and notes that logs are engine-specific and hard to process elsewhere.
Structured summaries were planned separately (CWL-metrics, GFD.204 usage
records).

*For this plugin:* package the Snakemake run logs and job logs as files
(A7, A12), and parse only what is well defined: the run log header and the
benchmark TSVs.

### 10. Resource usage: per run at Level 1, per task at Level 2

The paper asks for a whole-run resource summary at Level 1 and per-task
usage at Level 2. It warns that per-task figures are noisy and depend on
scheduling, so they need statistical treatment before they can predict
requirements. It cites Nextflow's trace report as a per-task example.

*For this plugin:* map benchmark TSVs to `resourceUsage` per job (A12).
Consider adding run totals on the workflow `CreateAction`, and recording the
declared `threads`/`resources` next to the measured values (A10), since a
measurement is meaningless without knowing what was allocated.

### 11. Non-determinism shows up only if you compare checksums

In the paper's evaluation, the alignment workflow produced different outputs
on every run. BWA-MEM's output depends on its thread count, which varied with
the available hardware.

*For this plugin:* record `threads` and `resources` (A10) and output checksums
(A2). Together they let someone explain differing results between runs.

### 12. Large data, selective capture and declaring incompleteness

CWLProv's discussion proposes:
- referencing large data by persistent identifier plus checksum instead of
  copying it, as BDBag does with `fetch.txt`;
- options to skip "boring" steps (shims, diagnostics) or files above a size
  threshold.

A bag made this way is "incomplete", and the paper says this should be
declared, as a variant of the profile identifier, so that consumers know
what to expect.

*For this plugin* (**new**, and input to B6):
- Add a size threshold option for packaging, reusing the A1 reference
  mechanism.
- When anything is referenced instead of included (outside the working
  directory, too large, `temp()`, excluded logs or config), state it in the
  crate. Options: a summary in the root `description`, a `conformsTo` value
  that marks the crate as a partial run crate, or listing the referenced
  entities in `mentions` rather than `hasPart`. The Workflow Run Crate
  profiles have no way to say this today.

### 13. A workflow diagram is cheap and expected

R14 asks for a data-flow diagram. Workflow RO-Crate recommends one (the
workflow's `image`), and `roc-validator` reports it as missing (OPTIONAL).

*For this plugin* (**new**):
- Generate the rule graph with Snakemake's own `--rulegraph` support (DOT
  or Mermaid), and package it as `ImageObject` `about` the workflow, linked
  with `image`.
- If Graphviz is not available to render SVG, include the DOT or Mermaid
  source and let the preview (A15) render it.

### 14. Record what was actually used, not just what was declared

The paper's example: a workflow may name a container image without a version,
but the provenance can still record the version actually used, satisfying R4
"retrospectively by computation rather than relying on a prospective
declaration".

*For this plugin:*
- container digests of the cached image (A5);
- installed Conda versions rather than YAML version ranges (A4);
- the Snakemake version from the run log rather than the report-time version
  (A7).

### 15. Test by re-running from the package only

The paper evaluated CWLProv by re-running each workflow on another operating
system and with another engine, using only the files in the research object,
and comparing output checksums.

*For this plugin* (extends A0): once A1 and A6 are done, the `feature-coverage`
end-to-end test can check that the crate is runnable:
1. Unpack the ZIP into an empty directory.
2. Run Snakemake there with `--forceall`.
3. Compare the output checksums with the crate's `sha256` values.

Until then, such a test would document the gap as an expected failure.

### 16. Design for consumers' questions

`cwlprov-py` answered:
- which runs are in this package;
- who ran it;
- what a given step used and produced;
- how long each step took;
- which inputs an output was derived from;
- how to build an input file to re-run just one step.

The paper stresses capturing enough at run time "so that post-processing
(potentially by a third-party) can support unforeseen queries", which
requires consistent identifiers.

*For this plugin:* make these questions acceptance tests for A0, answered with
`runcrate report` or a short script over the crate. Partial re-runs map onto
Snakemake's `--until`/`--forcerun` plus the packaged intermediate files.

### 17. Fixity of the whole package

BagIt manifests give fixity for every file in the bag, and can be checked with
standard tools independent of the metadata. The RO-Crate specification
describes how to
[combine RO-Crate with BagIt](https://www.researchobject.org/ro-crate/specification/1.1/appendix/implementation-notes.html#combining-with-other-packaging-schemes).

*For this plugin* (**new**, low priority): an option to write the ZIP as a
BagIt bag with the crate as its payload. A2 (per-file `sha256` in the
metadata) covers most of the need, so this is mainly for archives that
expect BagIt.

### 18. One serialisation is enough

CWLProv emitted the trace in six PROV serialisations, and the authors
concluded that "requiring all of these … would be an unnecessary burden" on
other implementations. RO-Crate's single JSON-LD file plus an HTML preview
(A15) already learns this lesson. Don't add other formats.

## Candidate additions to the plan

These have been added to `TODO.md`: lesson 7 as A18, lesson 3 as A19,
lesson 5 as A20, lesson 13 as A21, lesson 12 as A22 and lesson 17 as A23.
The rest were folded into existing items (A0, A2, A6, A13, B2 and B6).

| Lesson | Candidate item | Likely position in the plan |
|---|---|---|
| 7 | Record `directory()` outputs and deleted `temp()` files; warn about skipped inputs and outputs | Early, after A1 (reuses its mechanism). This is a correctness bug. |
| 3 | Run identity from Snakemake's workflow ID; deterministic UUID action identifiers | Early, before A0's golden files are fixed |
| 5 | Record the plugin and its version as the crate's creator | Any time, small |
| 13 | Workflow diagram from `--rulegraph` | Any time, small |
| 12 | Size threshold, and declaring a partial crate | After A1, together with B6 |
| 17 | Optional BagIt output | Low priority, after A2 |
| 1 | Decide snapshot versus runnable; evaluate Snakemake `--archive` | Part of A6 |
| 2 | Take `sha256` from Snakemake's recorded `input_checksums` | Part of A2 and B2 |
| 15, 16 | Re-run-from-crate test and consumer-question tests | Part of A0, as expected failures until A1 and A6 |
| 4 | `ORCID` environment variable as default agent | Part of A13 |
