# History

Reverse-chronological log of meaningful changes. See `CLAUDE.md` for the entry
format and when to add one.

## 2026-07-16 — Add working framework (CLAUDE.md, history.md, learning.md)
- What: Added `CLAUDE.md` as the repo's working framework, plus this
  `history.md` and `learning.md`.
- Why: Establish an H3-inspired, library-first direction for QDGC and carry
  decisions/lessons across sessions and contributors.
- Impact: Process only; no code or API change.

## 2026-07-16 — PyPI publishing setup for qdgc-py
- What: Added root `LICENSE` (verbatim GPL-3.0 from FSF), a tag-triggered
  release workflow (`.github/workflows/qdgc_py-release.yml`) using PyPI Trusted
  Publishing (OIDC), and Install/Publishing docs in `qdgc_py/README.md`.
- Why: Make `pip install qdgc-py` possible in the H3-style, and automate
  token-free releases from git tags.
- Impact: No code/API change. Manual step remaining: register the repo as a
  trusted publisher on pypi.org (environment `pypi`) and confirm the `qdgc-py`
  name is free.

## 2026-07-16 — Relicense qdgc-py from GPL-3.0 to Apache-2.0
- What: Replaced root `LICENSE` with verbatim Apache-2.0 text and updated
  `qdgc_py/pyproject.toml` license field and classifier accordingly.
- Why: Match H3 (Apache-2.0). The library-first goal needs a permissive license
  so projects under any license (commercial, MIT/Apache) can depend on it; GPL's
  strong copyleft would block that.
- Impact: Licensing only, no code/API change. Supersedes the GPL-3.0 choice from
  the earlier entry today.

## 2026-07-16 — Milestone: qdgc-py 0.1.0 published to PyPI
- What: First public release. Tag `v0.1.0` triggered the release workflow, which
  ran green end to end (tests, build, twine check, Trusted Publishing upload).
  `pip install qdgc-py` now works for everyone.
- Why: Deliver the H3-style goal — QDGC as an open, installable library.
- Impact: Package is public at https://pypi.org/project/qdgc-py/ under
  Apache-2.0. Version `0.1.0` is now permanently reserved on PyPI. Future
  releases follow the same bump-version -> tag -> push flow.

## 2026-07-16 — Announced qdgc-py on LinkedIn
- What: Ragnvald published a LinkedIn post announcing the qdgc-py library,
  tying it back to the 2009 extended-QDGC paper. Post: https://lnkd.in/p/eZCbfgGP
- Why: Public launch / outreach for the library to the GIS and biodiversity
  community.
- Impact: No code change. First external announcement of the package.

## 2026-07-16 — Added qdgc-py note to the ResearchGate article
- What: Posted a short update on the 2009 paper's ResearchGate page pointing to
  the qdgc-py library (used the ~300-char short form due to the field limit).
- Why: Connect the published method to its open-source implementation for
  researchers arriving via the paper.
- Impact: No code change. Second external announcement of the package (after
  LinkedIn).

<!-- Add new entries above this line, newest first. -->
