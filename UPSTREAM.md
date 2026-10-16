# Upstream provenance

ScaleBench was selected from the RTL-PP dataset:

- Dataset: `makyash/RTL-PP`
- Dataset page: <https://huggingface.co/datasets/makyash/RTL-PP>
- Upstream fields used: RTL `code` and natural-language `instruction`
- Local preparation: Markdown code fences were stripped, selected top modules were initially assigned unique internal `rtlpp_XXXXX` identifiers, and designs passing the SEC/LEC preparation flow were eligible for selection.

The local RTL-PP dataset card declares `license: mit`. This extraction does not independently establish the license or attribution requirements of every original HDL source represented in RTL-PP. Those requirements should be reviewed before public release.

ScaleBench adds the 200-design selection, curated specifications, semantic public task identifiers, LoC and sequential/combinational metadata, and formal-equivalence collateral. The internal identifiers remain in the manifest solely to trace each released case back to its upstream RTL-PP row.
