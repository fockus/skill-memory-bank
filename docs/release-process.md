# Release process

Publishing a new version to PyPI + Homebrew + GitHub Releases.

## Prerequisites (one-time setup)

### 1. PyPI account + trusted publisher

1. Create a PyPI account: https://pypi.org/account/register/
2. (Recommended) Enable 2FA: https://pypi.org/manage/account/
3. Register the project name (creates an empty placeholder):
   - Go to https://pypi.org/manage/account/publishing/
   - Click **Add a new pending publisher**
   - **PyPI Project Name:** `memory-bank-skill`
   - **Owner:** `fockus`
   - **Repository name:** `skill-memory-bank`
   - **Workflow name:** `publish.yml`
   - **Environment name:** `pypi`
   - Submit.
4. The **first** successful `publish.yml` run will create the actual project.

### 2. GitHub environment `pypi`

`.github/workflows/publish.yml` references `environment: pypi`. Create it once
to gate deploys:

1. Repo → Settings → Environments → **New environment** → name: `pypi`.
2. Optional: add required reviewers for manual approval before publish.

### 3. Homebrew tap (already live)

- Tap repo: [fockus/homebrew-tap](https://github.com/fockus/homebrew-tap)
- Formula path: `Formula/memory-bank.rb`
- First release: the `url`/`sha256` fields are placeholders — update them after
  the first PyPI publish via:

  ```bash
  brew bump-formula-pr fockus/tap/memory-bank \
    --url "https://files.pythonhosted.org/packages/source/m/memory-bank-skill/memory_bank_skill-X.Y.Z.tar.gz"
  ```

## Release steps

### Cutting a release (stable or RC)

```bash
# 1. Ensure main is clean + tests green
git status
bats tests/bats/ tests/e2e/
python3 -m pytest tests/pytest/
ruff check .
shellcheck -x --source-path=SCRIPTDIR scripts/*.sh adapters/*.sh hooks/*.sh install.sh uninstall.sh

# 2. Update VERSION + memory_bank_skill/__init__.py + CHANGELOG
#    (all three must match the tag exactly)
echo "3.0.0" > VERSION
# ...edit memory_bank_skill/__init__.py __version__...
# ...add CHANGELOG section...

# 3. Commit
git add VERSION memory_bank_skill/__init__.py CHANGELOG.md
git commit -m "release: v3.0.0"

# 4. Tag + push — triggers publish.yml workflow
git tag v3.0.0
git push origin main
git push origin v3.0.0
```

### What the workflow does

On every pushed `v*` tag:

1. **Build job**
   - Verifies tag version === VERSION file === `__init__.__version__`
   - Builds sdist + wheel via `python -m build`
   - Uploads artifact for downstream jobs
2. **publish-pypi job** (needs build)
   - Downloads artifact
   - Uses `pypa/gh-action-pypi-publish@release/v1` with OIDC
   - No secrets needed — identity verified via GitHub OIDC trusted publisher
3. **github-release job** (needs publish-pypi)
   - Extracts the CHANGELOG section matching the tag version
   - Runs `gh release create` with wheel + sdist attached

### Post-release checklist

- [ ] Verify PyPI page: https://pypi.org/project/memory-bank-skill/
- [ ] Verify GitHub Release: https://github.com/fockus/skill-memory-bank/releases
- [ ] Smoke test:
  ```bash
  pipx install --pip-args='--pre' memory-bank-skill   # use --pre for rc versions
  memory-bank version
  memory-bank doctor
  memory-bank uninstall -y
  ```
- [ ] Update Homebrew formula if stable release:
  ```bash
  brew bump-formula-pr fockus/tap/memory-bank --url "<new-pypi-sdist-url>"
  ```
- [ ] Announcement (optional): Twitter/blog — user decides, not required for Gate.

### Release candidate vs stable

- **RC:** `v3.0.0-rc1`, `v3.0.0-rc2` — will publish as PyPI pre-release. Users
  must `pipx install --pip-args='--pre' memory-bank-skill` to pick it up.
- **Stable:** `v3.0.0` — default install target, picked up by `pipx upgrade`.

Both trigger the same workflow. PyPI auto-detects pre-release suffixes per
PEP 440.

## Rollback

If a release has a critical bug:

1. **Yank from PyPI** (does not delete; prevents fresh installs):
   - https://pypi.org/project/memory-bank-skill/<version>/ → **Yank release**
2. **Delete GitHub Release** (keeps git tag):
   ```bash
   gh release delete v3.0.0
   ```
3. Fix bug on `main`, cut new version (`v3.0.1`), push tag — workflow re-runs.

Do **not** force-push / delete tags from the public repo — existing installations
rely on immutable tag URLs.
