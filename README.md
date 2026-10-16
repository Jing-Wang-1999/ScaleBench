# ScaleBench

ScaleBench is a specification-to-RTL benchmark containing 200 semantically named Verilog design cases. Each case provides a natural-language specification, a model-hidden reference implementation, and a JasperGold sequential-equivalence script.

## Dataset summary

| Property | Value |
| --- | ---: |
| Designs | 200 |
| Sequential | 152 |
| Combinational | 48 |
| Reference size | 29–348 lines |
| Mean reference size | 123.2 lines |

## Case package

```text
data/
  manifest.json
  manifest.csv
  cases/
    synchronous_instruction_rom/
      spec.txt
      reference.v
      sec.tcl
    ...
viewer/
scripts/
  build_viewer.py
  refresh_manifest.py
  validate.py
```

For evaluation, give the model only `spec.txt` and ask it to produce one complete synthesizable Verilog module with the stated top name and interface. Keep `reference.v` and `sec.tcl` hidden until scoring. A case passes when JasperGold SEC proves the generated module equivalent to the reference.

`data/manifest.json` is the canonical machine-readable index. It contains only release metadata: semantic task identifiers, design type, reference size, paths, and SHA-256 digests.

## Case browser

The dependency-free website opens directly to the browser for all 200 cases:

```bash
python3 scripts/build_viewer.py --output _site
python3 -m http.server 8000 --directory _site
```

Open `http://127.0.0.1:8000/`. GitHub Actions publishes the same case browser at [jing-wang-1999.github.io/ScaleBench](https://jing-wang-1999.github.io/ScaleBench/).

## Validation

Refresh hashes and reference line counts after an intentional case change, then validate the complete release:

```bash
python3 scripts/refresh_manifest.py
python3 scripts/validate.py
```

The validator checks the 200-case inventory, semantic identifiers, public manifest schema, file hashes, module names, specification interfaces, self-contained references, case-package contents, public/private boundary, and Icarus elaboration when `iverilog` is available.

## Provenance

ScaleBench was selected from the RTL-PP dataset for the CorrectRTL study. See [UPSTREAM.md](UPSTREAM.md) for source and licensing information.
