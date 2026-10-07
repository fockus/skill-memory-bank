"""Print each requirement (argv) the running interpreter does not satisfy.

Run by hooks/mb-semantic-bootstrap.sh under the venv python: a requirement is
unmet when its distribution is absent, its version falls outside the specifier
(AGR-054: an import-only check let networkx 3.7 pass a ``<3.7`` pin), or its
module does not import. Stdlib + pip's vendored ``packaging``; without either
``packaging`` the version half is skipped (presence + import only). Exit 0.
"""

from __future__ import annotations

import importlib
import importlib.metadata as md
import re
import sys

try:
    from packaging.requirements import Requirement
except ImportError:  # pragma: no cover - venvs normally carry pip's copy
    try:
        from pip._vendor.packaging.requirements import Requirement
    except ImportError:
        Requirement = None  # type: ignore[assignment,misc]


def _unmet(req: str) -> bool:
    name = re.split(r"[<>=!~;\[ ]", req, maxsplit=1)[0]
    try:
        version = md.version(name)
    except md.PackageNotFoundError:
        return True
    if Requirement is not None and not Requirement(req).specifier.contains(
        version, prereleases=True
    ):
        return True
    try:
        importlib.import_module(name.replace("-", "_"))
    except Exception:
        return True
    return False


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        if _unmet(arg):
            print(arg)
