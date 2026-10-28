# Snakemake feature coverage

A small, fast workflow that exercises the Snakemake features that matter for
the RO-Crate reporter. It is meant for testing the reporter and for
inspecting how each feature appears in the generated crate. See
[`TODO.md`](../../TODO.md) for the known gaps it demonstrates.

| Rule | Features |
|---|---|
| (top level) | `configfile:`, `include:` (`rules/extra.smk`) |
| `count` | `shell:`, named input, wildcards (`{s}`), `params:` from config, `log:` |
| `merge` | `script:` (`scripts/merge.py`), unnamed inputs from `expand()` |
| `plot` | `conda:` (`envs/jq.yaml`), `benchmark:`, named inputs |
| `stats` | `run:` (inline Python with imports) |
| `extra` | input outside the workflow directory (`../external/extra.txt`) |

The only software needed besides Snakemake and the plugin is `jq`, which
Snakemake installs from conda-forge for the `plot` rule.

## Example crate

[`workflow/feature-coverage-workflow-run.zip`](workflow/feature-coverage-workflow-run.zip)
is a crate generated with `profiles/rocrate/config.yaml`. The workflow's
outputs, logs and `.snakemake/metadata` are committed too, so the reporter
can be re-run without re-running the workflow. The `ro-crate-preview.html`
inside the ZIP was added afterwards with
[`rochtml`](https://www.npmjs.com/package/ro-crate-html) 0.1.6, because the
plugin does not generate a preview yet (see A15 in the TODO).

## Running

From this `workflow/` directory, run the workflow and then generate the crate:

```bash
snakemake --software-deployment-method conda --cores 1
bash run_snakemake.sh
```

This writes `feature-coverage-workflow-run.zip`, using the settings in
`profiles/rocrate/config.yaml`. `run_snakemake_metadata_only.sh` writes only
`ro-crate-metadata.json` next to the `Snakefile` instead.

The profile sets every reporter option that does not identify a person or an
organization. Add `report-rocrate-researcher-*`, `report-rocrate-agent-*` and
`report-rocrate-organization-*` with your own details to try those as well.
