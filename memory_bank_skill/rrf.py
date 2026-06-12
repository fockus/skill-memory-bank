"""Reciprocal Rank Fusion (RRF) merge module.

Rank convention
---------------
Rankings are **ordered lists of keys** where the *first element has rank 1*.
The RRF contribution of a key at position ``i`` (0-based index) in a ranking
is ``1 / (k + (i + 1))``.  This means the element at index 0 contributes
``1 / (k + 1)``, the element at index 1 contributes ``1 / (k + 2)``, and so on.

References
----------
Cormack, G. V., Clarke, C. L. A., & Buettcher, S. (2009).
Reciprocal rank fusion outperforms Condorcet and individual rank learning
methods.  SIGIR 2009.
"""

from __future__ import annotations


def rrf_merge(
    rankings: list[list[str]],
    k: int = 60,
) -> list[tuple[str, float]]:
    """Fuse multiple ranked lists into a single list using Reciprocal Rank Fusion.

    Parameters
    ----------
    rankings:
        A list of ranked lists.  Each inner list is an ordered sequence of
        string keys; the first key has rank 1.  Duplicates within a single
        ranking are treated as distinct positions (the caller should deduplicate
        before passing in if that matters).  An empty outer list or empty inner
        lists are handled gracefully.
    k:
        The RRF smoothing constant (default 60, following the original paper).
        Smaller values amplify the advantage of top-ranked items.

    Returns
    -------
    list of (key, score) tuples
        Sorted by score **descending**; ties broken by key **ascending**
        (lexicographic).  All scores are strictly positive floats.

    Examples
    --------
    >>> rrf_merge([["A", "B"], ["B", "C"]])
    [('B', ...), ('A', ...), ('C', ...)]
    """
    scores: dict[str, float] = {}

    for ranking in rankings:
        for rank_zero, key in enumerate(ranking):
            rank_one = rank_zero + 1  # rank of the first element = 1
            scores[key] = scores.get(key, 0.0) + 1.0 / (k + rank_one)

    return sorted(scores.items(), key=lambda item: (-item[1], item[0]))
