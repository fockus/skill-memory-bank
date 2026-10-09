"""Extract subprocess dependencies from static, repository-local Python paths."""

from __future__ import annotations

import ast
from collections import Counter
from pathlib import Path


def _path(expr: ast.AST, constants: dict[str, Path], constructors: set[str]) -> Path | None:
    if isinstance(expr, ast.Name):
        return constants.get(expr.id)
    if isinstance(expr, ast.Constant) and isinstance(expr.value, str):
        return Path(expr.value) if Path(expr.value).is_absolute() else None
    if isinstance(expr, ast.BinOp) and isinstance(expr.op, ast.Div):
        left = _path(expr.left, constants, constructors)
        if left is not None and isinstance(expr.right, ast.Constant) and isinstance(expr.right.value, str):
            return left / expr.right.value
    if isinstance(expr, ast.Attribute) and expr.attr == "parent":
        value = _path(expr.value, constants, constructors)
        return value.parent if value is not None else None
    if isinstance(expr, ast.Subscript) and isinstance(expr.value, ast.Attribute):
        index = expr.slice
        value = _path(expr.value.value, constants, constructors)
        if (expr.value.attr == "parents" and value is not None
                and isinstance(index, ast.Constant) and type(index.value) is int
                and 0 <= index.value < len(value.parents)):
            return value.parents[index.value]
    if isinstance(expr, ast.Call) and not expr.keywords:
        if len(expr.args) == 1 and ast.unparse(expr.func) in constructors:
            return _path(expr.args[0], constants, constructors)
        if not expr.args and isinstance(expr.func, ast.Attribute) and expr.func.attr == "resolve":
            value = _path(expr.func.value, constants, constructors)
            try:
                return value.resolve() if value is not None else None
            except (OSError, RuntimeError, ValueError):
                return None
    return None


def script_invocations(tree: ast.Module, py_path: Path, src_root: Path) -> list[dict[str, str]]:
    """Read a narrow AST whitelist; never evaluate code or guess dynamic paths."""
    constants = {"__file__": py_path.resolve()}
    constructors: set[str] = {"str"}
    subprocess_names: set[str] = set()
    sys_names: set[str] = set()
    for statement in tree.body:
        if isinstance(statement, ast.Import):
            for alias in statement.names:
                if alias.name == "subprocess":
                    subprocess_names.add(alias.asname or alias.name)
                if alias.name == "sys":
                    sys_names.add(alias.asname or alias.name)
                if alias.name == "pathlib":
                    constructors.add(f"{alias.asname or alias.name}.Path")
        if isinstance(statement, ast.ImportFrom) and statement.module == "pathlib":
            constructors.update(alias.asname or alias.name for alias in statement.names if alias.name == "Path")
        if isinstance(statement, ast.Assign):
            assigned = {target.id for target in statement.targets if isinstance(target, ast.Name)}
            constructors = {name for name in constructors if name.split(".")[0] not in assigned}
            value = _path(statement.value, constants, constructors)
            for target in statement.targets:
                if isinstance(target, ast.Name):
                    constants.pop(target.id, None)
                    if value is not None:
                        constants[target.id] = value

    stores = Counter(node.id for node in ast.walk(tree)
                     if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store))
    shadowed = {name for name, count in stores.items() if count > 1}
    shadowed.update(node.arg for node in ast.walk(tree) if isinstance(node, ast.arg))
    for name in shadowed:
        constants.pop(name, None)
    subprocess_names.difference_update(stores.keys() | shadowed)
    sys_names.difference_update(stores.keys() | shadowed)
    constructors = {name for name in constructors if name.split(".")[0] not in stores.keys() | shadowed}

    edges: list[dict[str, str]] = []
    operations = {"run", "Popen", "call", "check_call", "check_output"}
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in subprocess_names and node.func.attr in operations
                and node.args and isinstance(node.args[0], (ast.List, ast.Tuple))):
            continue
        if any(keyword.arg == "shell" and not (isinstance(keyword.value, ast.Constant)
                and keyword.value.value is False) for keyword in node.keywords):
            continue
        argv = node.args[0].elts
        if not argv:
            continue
        first = argv[0]
        python = (isinstance(first, ast.Attribute) and first.attr == "executable"
                  and isinstance(first.value, ast.Name) and first.value.id in sys_names)
        if isinstance(first, ast.Constant) and isinstance(first.value, str):
            binary = Path(first.value).name
            python = binary == "python" or (binary.startswith("python")
                      and binary[6:].replace(".", "").isdigit())
        arg = argv[1] if python and len(argv) > 1 else first
        target = _path(arg, constants, constructors)
        if target is None:
            continue
        try:
            target = target.resolve()
            if target.suffix != ".py" or not target.is_file() or not target.is_relative_to(src_root.resolve()):
                continue
        except (OSError, RuntimeError, ValueError):
            continue
        edges.append({"src": py_path.relative_to(src_root).as_posix(),
                      "dst": target.relative_to(src_root.resolve()).as_posix(),
                      "kind": "import", "via": "invoke"})
    return edges
