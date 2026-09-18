"""Fixture python module — guards the python half of the graph."""

import json


def load_payload(text):
    return json.loads(text)
