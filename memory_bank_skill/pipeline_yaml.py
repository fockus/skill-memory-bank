"""Strict pipeline YAML loading — duplicate keys rejected when PyYAML is present."""
from __future__ import annotations


class PipelineYamlError(ValueError):
    """Raised when pipeline YAML is invalid or contains duplicate mapping keys."""


def _yaml_dup_loader():
    import yaml

    class DupKeyLoader(yaml.SafeLoader):
        pass

    def construct_mapping(loader, node, deep=False):
        loader.flatten_mapping(node)
        mapping = {}
        for key_node, value_node in node.value:
            key = loader.construct_object(key_node, deep=deep)
            if key in mapping:
                line = key_node.start_mark.line + 1
                raise PipelineYamlError(f"duplicate key '{key}' at line {line}")
            mapping[key] = loader.construct_object(value_node, deep=deep)
        return mapping

    DupKeyLoader.add_constructor(
        yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
        construct_mapping,
    )
    return yaml, DupKeyLoader


def load_text(text: str) -> dict:
    raw = text.strip()
    if not raw:
        return {}
    try:
        import yaml  # noqa: F401
    except ImportError as exc:
        raise PipelineYamlError("PyYAML required for strict pipeline load") from exc
    yaml_mod, loader_cls = _yaml_dup_loader()
    try:
        data = yaml_mod.load(raw, Loader=loader_cls)
    except Exception as exc:
        if isinstance(exc, PipelineYamlError):
            raise
        raise PipelineYamlError(f"YAML parse error: {exc}") from exc
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise PipelineYamlError("top-level must be a mapping")
    return data


def load_file(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return load_text(fh.read())
