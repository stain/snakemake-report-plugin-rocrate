# TODO: RO-Crate completeness of generated crates

Findings from running the plugin (Snakemake 9.27.1, `roc-validator` 0.11.4) on a
small test workflow and inspecting the crate with `rocrate-validator -l OPTIONAL`
and `runcrate report`. The generated crate passes all REQUIRED checks of
`provenance-run-crate-0.5`, but is incomplete or inaccurate in the ways below.

Test workflow used (reproduces every item below):

```python
configfile: "config.yaml"            # samples: [a, b], mode: fast
include: "rules/extra.smk"           # rule extra: ../ext/extra.txt -> results/extra.txt

rule all:
    input: "results/summary.txt", "results/plot.json", "results/extra.txt"

rule count:                          # shell + log + params + wildcards
    input: reads="data/{s}.txt"
    output: "results/{s}.count"
    params: mode=config["mode"]
    log: "logs/count_{s}.log"
    shell: "wc -l {input.reads} > {output} 2> {log}"

rule merge:                          # script:
    input: expand("results/{s}.count", s=config["samples"])
    output: "results/summary.txt"
    script: "scripts/merge.py"

rule plot:                           # conda: + benchmark:
    input: summary="results/summary.txt", ref="data/ref.json"
    output: "results/plot.json"
    conda: "envs/jq.yaml"
    benchmark: "bench/plot.tsv"
    shell: "jq -n --arg s \"$(cat {input.summary})\" '{{summary:$s}}' > {output}"
```

Run `snakemake --cores 1 --sdm conda`, then the same command again with
`--reporter rocrate`, once with `--report-rocrate-metadata-only` and once
without.

Reference documents:

- RO-Crate 1.1: <https://www.researchobject.org/ro-crate/specification/1.1/>
  (current: [1.3](https://www.researchobject.org/ro-crate/specification/1.3/))
- Process Run Crate 0.5: <https://www.researchobject.org/workflow-run-crate/profiles/0.5/process_run_crate/>
- Workflow Run Crate 0.5: <https://www.researchobject.org/workflow-run-crate/profiles/0.5/workflow_run_crate/>
- Provenance Run Crate 0.5: <https://www.researchobject.org/workflow-run-crate/profiles/0.5/provenance_run_crate/>
- Workflow RO-Crate 1.0: <https://about.workflowhub.eu/Workflow-RO-Crate/1.0/>

---

## Part A: Plugin issues

### A1. Metadata-only mode writes data entities outside the crate root (bug)

**Observed:** With `--report-rocrate-metadata-only`, an input outside the working
directory is recorded as `"@id": "../ext/extra.txt"` and listed in the root's
`hasPart`. `roc-validator` does not detect this.

**Spec:** In RO-Crate 1.1 a [File data entity](https://www.researchobject.org/ro-crate/specification/1.1/data-entities.html#file-data-entity)
`@id` "MUST be either a URI Path relative to the RO Crate root, or an absolute
URI". RO-Crate 1.3 says that a locally packaged file's `@id` "MUST be a URI Path
relative to the RO Crate Root" ([1.3 data entities](https://www.researchobject.org/ro-crate/specification/1.3/data-entities.html#file-data-entity)).
A path starting with `../` points outside the root, so the crate breaks when it is
moved, zipped or published.

**Code:** `provenance_files.py:187` (the `os.path.relpath` fallback in
`_copy_external_relative_files`).

**Suggested fixes (pick one):**
- Use an absolute `file://` URI (or a real `https://` URL if one is known) for
  external files, as a Web-based data entity. Do not add it to `hasPart` as a
  local file, and note that `file://` URIs are not portable.
- In RO-Crate 1.3, use a local identifier (`#external-extra.txt`) typed `File`
  with `localPath` (see the 1.3 note on `File` entities with `#` identifiers).
  It is then not a data entity, but it can still be the `object` of an action.
- Fail, or warn, in metadata-only mode when inputs lie outside the working
  directory, and tell the user to use ZIP mode.

**Considerations:** Whichever option is chosen, test it explicitly: add a
check to `validator.py` or a unit test that asserts no data entity `@id` starts
with `../` or `/`.

### A2. Workflow definition is incomplete: only the main Snakefile is packaged

**Observed:** These are missing from the crate:
- `include:` files (`rules/extra.smk`)
- `script:` files (`scripts/merge.py`)
- the `configfile:` (`config.yaml`)
- `notebook:` files and `wrapper:` sources (not tested, but there is no code
  path for them)

Scripts are found only by heuristically parsing shell commands for an
interpreter (`provenance_files.py:98`), so `script:` rules get the action
description "Execute rule merge" (`provenance.py:153`).

**Spec:** [Workflow RO-Crate 1.0](https://about.workflowhub.eu/Workflow-RO-Crate/1.0/)
expects the crate to contain the workflow so that it can be re-run. For engine
configuration files, the [Provenance Run Crate](https://www.researchobject.org/workflow-run-crate/profiles/0.5/provenance_run_crate/#engine-configuration-files)
says the config file "SHOULD be added to the `object` attribute of the
corresponding `OrganizeAction`".

**Suggested fixes:**
- Package every Snakefile module from Snakemake's workflow object (e.g.
  `workflow.included`/the source cache), and list them in the main workflow's
  `hasPart`. Type them `["File", "SoftwareSourceCode"]` with
  `programmingLanguage` Snakemake.
- For `script:`/`notebook:` rules, take the path from the rule object
  (`rule.script`, `rule.notebook`), not from the shell command. Package the
  file as `["File", "SoftwareSourceCode"]` with its `programmingLanguage`.
  Link it from the rule's tool, either as the tool's `@id` or through
  `mainEntity`/`hasPart` (see
  [Tool wrapper dependencies](https://www.researchobject.org/workflow-run-crate/profiles/0.5/provenance_run_crate/#tool-wrapper-dependencies)).
- Add each `configfile:` and `--configfile` file to the crate, and put it in
  the `OrganizeAction`'s `object`.
- For `wrapper:`, record the wrapper URL/version as the tool `@id`/`url`.

**Considerations:** Some `include:`/`module:` sources are remote (GitHub,
`github()` objects). For those, use web-based data entities rather than copying.
Keep the plain-text `HowToStep.description` (rule source) as it is.

### A3. Non-file parameters are not recorded (params, config, wildcards, resources)

**Observed:** Only files appear as `object`/`result`. `params: mode=fast`, the
config values, wildcards (`s=a`), `threads` and `resources` are absent.

**Spec:** The [Workflow Run Crate](https://www.researchobject.org/workflow-run-crate/profiles/0.5/workflow_run_crate/)
and the [Process Run Crate](https://www.researchobject.org/workflow-run-crate/profiles/0.5/process_run_crate/)
represent non-file values as `PropertyValue` entities in `object`, linked to
their `FormalParameter` through `exampleOfWork`. The plugin already has the
`PropertyValue` code path (`_link_action_value_to_parameter`), but nothing
feeds it.

**Suggested fixes:**
- For each job, add one `PropertyValue` per `params` entry, wildcard and
  (optionally) `threads`/`resources` entry. Link each to a tool-level
  `FormalParameter`, e.g. `#parameter/tool/count/params/named/mode`.
- At workflow level, flatten the effective `config` into `PropertyValue`s for
  the workflow `CreateAction`, or just reference the config file (A2).
- Use `additionalType` `Text`/`Integer`/`Float`/`Boolean`/`Collection` as in the
  profile examples.

**Considerations:** Params can be callables or large objects, so serialise
conservatively (`str()`, with a length cap). Config may contain secrets: add
an opt-out or an exclude list before recording config values.

### A4. Default tool modelling: every Conda package becomes an instrument

**Observed:** When `--report-rocrate-main-tool` is not given, the `plot` action
has six instruments: `jq` plus `_openmp_mutex`, `libgcc`, `libgcc-ng`, `libgomp`
and `oniguruma`. Each of these gets the rule's `input`/`output` FormalParameters
(so `libgcc` "takes" `summary`), and all of them appear in the `HowToStep`'s
`workExample` and the workflow's `hasPart`. Rules without Conda get a rule-tool
entity instead, so the two kinds of rule are modelled differently.

**Code:** `rocrate_builder.py:403` (`if not preferred_package and package_ids:`).

**Spec:** In the [Process Run Crate](https://www.researchobject.org/workflow-run-crate/profiles/0.5/process_run_crate/#specifying-software-dependencies),
`instrument` is *the* tool that was run, and its dependencies go in
`softwareRequirements`. The [Provenance Run Crate](https://www.researchobject.org/workflow-run-crate/profiles/0.5/provenance_run_crate/#tool-wrapper-dependencies)
uses `mainEntity` to highlight the wrapped tool.

**Suggested fix:** Always create the rule tool (`#rule-tool-…`) as the single
instrument, and list the Conda packages in its `softwareRequirements`. Turn
`--main-tool` into a way to set `mainEntity` on the rule tool, rather than a
switch between two models.

**Considerations:**
- Consider listing only the packages explicitly named in the environment YAML
  in `softwareRequirements`. The full resolved list would still be available
  through the packaged environment file or an exported lock file (see A9).
- Package `@id`s are `#tool_N`. For conda-forge/bioconda packages, absolute
  IDs are more reusable, e.g. a purl (`pkg:conda/conda-forge/jq@1.7.1`) or the
  package URL. They would also satisfy the RECOMMENDED "SoftwareApplication id
  SHOULD be an absolute URI".
- The fallback package URL `https://anaconda.org/search?q=…` is a search page,
  not the package. Prefer `https://anaconda.org/<channel>/<name>`.

### A5. Conda environment linked with `subjectOf` instead of `buildInstructions`

**Observed:** The rule tool links its environment YAML with `subjectOf`
(`rocrate_builder.py:423`). Nothing links it when no main tool is set (A4).

**Spec:** [Tool runtime environment](https://www.researchobject.org/workflow-run-crate/profiles/0.5/provenance_run_crate/#tool-runtime-environment):
"environment files are indicated as `buildInstructions` for either the
`HowToStep` (for a given step) or the `HowTo` (for the whole workflow)."

**Suggested fix:** Set `buildInstructions` on the `HowToStep` of each rule that
has `conda:`, and on the workflow for a global `conda:` directive. Give the
YAML `encodingFormat` `application/yaml`, and ideally `conformsTo` a Conda
environment-file identifier. Keep `subjectOf` only if it is still wanted for
backwards compatibility.

**Considerations:** Do the same for `container:` and `apptainer:` directives
using [`containerImage`](https://www.researchobject.org/workflow-run-crate/profiles/0.5/process_run_crate/#representing-container-images)
on the `CreateAction`.

### A6. Workflow outputs are inferred from the job graph, not from the targets

**Observed:** Only files that are produced and never consumed become workflow
outputs (`rocrate_builder.py:508-519`). `results/summary.txt`, a target of
`rule all`, is not a workflow output, because `plot` consumes it.

**Suggested fix:** Use the requested targets (the inputs of the default target
rule, or the CLI targets, e.g. `dag.targetfiles`) as the workflow outputs, and
fall back to the current heuristic when they are unavailable.

### A7. Workflow input parameters are created per file, not per slot

**Observed:** The two samples gave workflow parameters `reads` and `reads_2`
(`rocrate_builder.py:521-534`). With 1,000 samples there would be 1,000
`FormalParameter`s, and the names depend on the order of the files.

**Suggested fix:** Create one workflow-level `FormalParameter` per rule input
slot, e.g. `count.reads`, and attach all matching files to it through
`exampleOfWork`. The profiles do not define a "multiple values" flag for
`FormalParameter`; schema.org's `multipleValues` is a candidate, but needs
agreement (see B3). Alternatively, model each slot's files as a single
`Collection` value (see
[multi-file objects](https://www.researchobject.org/workflow-run-crate/profiles/0.5/process_run_crate/#representing-multi-file-objects)).

**Considerations:** Snakemake has no declared workflow interface, which is why
this is heuristic. See also B3.

### A8. Logs and benchmarks are not captured

**Observed:** `log:` (`logs/count_*.log`) and `benchmark:` (`bench/plot.tsv`)
files are not in the crate.

**Suggested fixes:**
- Add log files to the crate and to the job `CreateAction`'s `result`, or link
  them through `subjectOf`, so they are not confused with data outputs. The
  same could be done for the main Snakemake log
  (`.snakemake/log/*.snakemake.log`) on the `OrganizeAction`.
- Parse the benchmark TSV into
  [`resourceUsage`](https://www.researchobject.org/workflow-run-crate/profiles/0.5/provenance_run_crate/#representing-resource-usage)
  `PropertyValue`s with `propertyID` and `unitCode` (e.g. `s`, `max_rss` in MB)
  on the job `CreateAction`.

**Considerations:** Logs can be large or contain paths and usernames, so make
including them optional.

### A9. File entities lack fixity and size

**Observed:** Files have only `name`, `encodingFormat` and `exampleOfWork`.

**Suggested fix:** Add `contentSize`, `dateModified` (from the file's mtime) and
a checksum (`sha256` in RO-Crate 1.2+; or `identifier`/`sha256` from the
workflow-run context). This lets consumers detect whether a file changed after
the run (see B1). Set `encodingFormat` to more specific types where known.
Snakefiles currently get `text/plain`; `text/x-snakemake` or the language
entity could be used instead.

### A10. Missing provenance detail that the profile defines

These are all OPTIONAL in the profile, but cheap to add:

- `actionStatus` (`http://schema.org/CompletedActionStatus`) on `ControlAction`s
  and `CreateAction`s. Snakemake only reports successful jobs, so this is always
  "completed" ([Provenance Run Crate, ControlAction](https://www.researchobject.org/workflow-run-crate/profiles/0.5/provenance_run_crate/#requirements)).
- `position` on each `HowToStep`, from a topological order of the rule graph.
  The rule ordering is already computed in `_add_precedes_relations`
  (`provenance_graph.py:25`), but the builder never writes it out.
- `startTime`/`endTime` on `ControlAction`s.
- [`connection` / `ParameterConnection`](https://www.researchobject.org/workflow-run-crate/profiles/0.5/provenance_run_crate/#representing-parameter-connections)
  between rule output and input parameters, which can be derived from the same
  shared-file analysis.

### A11. Missing contextual metadata (RECOMMENDED validator findings)

- `CreateAction`s have no `agent` unless `agent-*` is set. Root `author` is
  missing unless `researcher-*` is set, and `publisher` falls back to a Person,
  although the validator wants an Organization (`rocrate_builder.py:135-186`).
  Suggestion: when `researcher-*` is given and `agent-*` is not, use the
  researcher as the agent. Document that these options are needed for
  RECOMMENDED compliance. Do not fall back to a Person as publisher.
- The workflow (`Snakefile`) lacks `version`, `license`, `author`/`creator` and
  `url`. Suggestion: add plugin options (`workflow-version`, `workflow-url`,
  `workflow-license`), or read them from a git checkout (commit SHA as
  `version`, remote URL as `url`), without making them up.
- Rule tools (`#rule-tool-*`) lack `url` and `version`. They could point back
  into the workflow (`url` = workflow URL plus a rule anchor), or carry the
  workflow version.
- No `README.md`. Package the workflow's README when one exists next to the
  Snakefile. `_add_supplemental_files` already handles `about` and
  `encodingFormat` for it, but nothing adds the file.
- Singleton arrays: `_compact_single_value_properties`
  (`rocrate_builder.py:277`) only compacts `result`/`output`, so `object`/`input`
  still trigger "SHOULD be represented as a single value" warnings
  ([1.1 JSON-LD appendix](https://www.researchobject.org/ro-crate/specification/1.1/appendix/jsonld.html)).
  Apply it to every property, or rely on `ro-crate-py`'s own compaction.
- The workflow-run `CreateAction` reuses the crate `description` and has the
  generic `name` "workflow run". Give it a description of its own, e.g. the
  Snakemake command line and targets.

### A12. Engine version and invocation not recorded faithfully

**Observed:** `#snakemake` and the language entity carry the version of
Snakemake that generated the report, not necessarily the one that ran the jobs
(documented in the README). The Snakemake command line, the targets and the
profile are not recorded.

**Suggested fixes:** Read the version recorded in `.snakemake/metadata` if a
future Snakemake version stores it, and raise this upstream with Snakemake.
Record the report-generation command (`sys.argv`) as the `OrganizeAction`
`description`, and add the `--profile` config files to its `object` (A2).

### A13. Profile and spec versions are outdated

**Observed:** The crate declares RO-Crate 1.1 (`rocrate_builder.py:55`) and
Workflow Run Crate 0.5, and validation is pinned to `provenance-run-crate-0.5`
(`validator.py:29`, `roc-validator==0.11.4`). The current versions are
[RO-Crate 1.3](https://www.researchobject.org/ro-crate/specification/1.3/) and
[Provenance Run Crate 0.6](https://w3id.org/ro/wfrun/provenance/0.6).

**Suggested fix:** Add an option to choose the output version (1.1/0.5 for
WorkflowHub compatibility, 1.3/0.6 as the future default). Move to 1.3/0.6
once `roc-validator` ships those profiles.

**Considerations:** Workflow RO-Crate 1.0 is defined on RO-Crate 1.1, and the
validator's `workflow-ro-crate-1.0` rules fail on 1.3 crates because of version
mismatches, not real errors. Keep 1.1 as long as WorkflowHub deposit is a main
use case. Also consider naming the ZIP `*.crate.zip`, as WorkflowHub expects.

### A14. Validator noise to filter or report upstream

These `roc-validator` 0.11.4 findings are false positives on this crate:
- "README.md SHOULD be about the crate / have text/markdown", reported although
  the crate has no README
- "SoftwareApplication id SHOULD be an absolute URI", reported for type IRIs
  such as `http://schema.org/SoftwareApplication`

Report them upstream at <https://github.com/crs4/rocrate-validator/issues>
rather than suppressing them in `validator.py`.

---

## Part B: Issues that may need changes or clarification in the profiles

These cannot be solved cleanly within the current Workflow Run Crate profiles.
Raise them with the WRROC community
(<https://github.com/ResearchObject/workflow-run-crate/issues>) before
implementing a plugin-specific workaround.

### B1. A "workflow run" assembled from several engine invocations

**Observed:** Snakemake's report covers every output that currently exists,
using the persistent `.snakemake/metadata`. Two invocations about 1.5 minutes
apart (the second added `rule extra`) became one workflow-run `CreateAction`
spanning 13:31:43 to 13:33:18, and one `OrganizeAction`
(`provenance_graph.py:12`). This is how Snakemake is designed to be used:
incremental runs, reruns of single rules, and `--until`/`--forcerun`. Each job
action is correct, but the single workflow run and single engine run are not
what happened.

**Profile gap:** The [Workflow Run Crate](https://www.researchobject.org/workflow-run-crate/profiles/0.5/workflow_run_crate/)
and the [Provenance Run Crate](https://www.researchobject.org/workflow-run-crate/profiles/0.5/provenance_run_crate/)
assume one workflow execution (one `CreateAction` with the workflow as
`instrument`) driven by one engine run (one `OrganizeAction`). They have no
pattern for:
- several `OrganizeAction`s (engine invocations) that together produced the
  current state
- a run in which some outputs were reused from a previous run instead of being
  recomputed (caching or memoisation, also relevant for Nextflow `-resume`,
  Snakemake `--cache` and Galaxy job caching)

**Possible directions to propose:**
- Allow several `OrganizeAction`s, each with its own time span and `object`
  (the `ControlAction`s it ran), all with `result` the same workflow-level
  `CreateAction` (or with `result`s that build on each other).
- A way to mark a step or tool execution as reused from an earlier run, e.g.
  `actionStatus` with a reused/cached status, or `sameAs`/`isBasedOn` pointing
  to the earlier action.

**Interim plugin options:**
- Group jobs into invocations using Snakemake's per-run log files, or by gaps
  in job start/end times, and emit one `OrganizeAction` per group.
- Document that the workflow `CreateAction`'s time span covers several
  invocations.

### B2. Files may have changed since the actions that used them

**Observed:** Files are packaged as they are when the report is generated. An
input edited after its consuming job ran, or an output overwritten by a later
partial rerun, is recorded as if it were the file that was used.

**Profile gap:** The profiles do not say how to record the state of a file at
the time of use (checksums, or distinguishing the file entity from the file
version used by an action).

**Possible directions:**
- Recommend checksums (A9) on data entities.
- Allow an action-specific value entity (a `PropertyValue`, or a `File` with a
  `#` identifier and checksum) when the packaged file differs from the one that
  was used.
- Snakemake's metadata records input checksums for some files, which could be
  compared against the packaged files at report time, with a warning on
  mismatch.

### B3. Workflows without a declared interface (Snakemake, Make-like engines)

**Observed:** Snakemake has no formal workflow-level inputs or outputs. Inputs
and outputs are concrete files expanded from wildcards and config, so the
plugin has to invent workflow `FormalParameter`s (A6, A7).

**Profile gap:** The Workflow Run Crate expects the workflow's `input`/`output`
`FormalParameter`s to describe the workflow's interface. It does not say what
to do for engines whose "interface" is a set of target files plus a config
file.

**Possible directions:**
- Accept a config file (or its keys) as the workflow's parameter interface,
  with `FormalParameter`s derived from config keys and a schema if
  `validate(config, schema)` is used.
- Define how a `FormalParameter` accepts a wildcard-expanded set of files,
  either through `Collection` values (as in the Process Run Crate's
  multi-file objects) or a flag such as schema.org `multipleValues`, and
  document this as the recommended pattern.

### B4. One ControlAction per job, or per rule?

**Observed:** The plugin emits one `ControlAction` per job (`#control-action_2`
and `#control-action_3` for the two `count` jobs), each pointing to the same
`HowToStep`.

**Profile gap:** The [Provenance Run Crate](https://www.researchobject.org/workflow-run-crate/profiles/0.5/provenance_run_crate/#requirements)
says a `ControlAction` represents "a step execution" whose `object` is the
`CreateAction`(s) of the corresponding tool runs. The plural suggests that one
step execution may cover several tool runs, as with CWL scatter. In Snakemake,
a rule expanded over wildcards is close to a scatter, but each job is also
scheduled independently.

**Suggestion:** Ask the community which modelling is intended for wildcard and
scatter expansions, and document it in the profile. Until then, the current
per-job modelling is valid.

### B5. Tool identity for rules with inline shell commands

**Observed:** A rule's "tool" is the rule itself plus its environment. It has no
URL or version of its own (A11), which triggers the RECOMMENDED
`url`/`version` findings for every rule tool.

**Profile gap:** The profiles' SHOULDs for tool `url`/`version` assume tools
that are independently identifiable (a CWL `CommandLineTool`, a Galaxy tool).
For engines where steps are defined inline in the workflow source, there is no
natural separate identity.

**Possible direction:** Allow a tool to be identified as a part of the workflow
(e.g. `@id` `Snakefile#rule-count`, with `isPartOf` the workflow), and treat
the workflow's `version`/`url` as satisfying the tool's recommendation.
