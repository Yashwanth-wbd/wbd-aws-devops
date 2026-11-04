"""Post-checks on the answer: citations must name supplied sources and numbers must appear in them."""

import re
from dataclasses import dataclass

from app.bedrock import Source

_CITATION = re.compile(r"\[([A-Za-z0-9_.-]+)\]")
_NUMBER = re.compile(r"(?<![A-Za-z0-9_])-?\d[\d,]*(?:\.\d+)?")


def _numbers(text: str) -> set[str]:
    found = set()
    for raw in _NUMBER.findall(_CITATION.sub(" ", text)):
        value = raw.replace(",", "")
        if "." in value:
            value = value.rstrip("0").rstrip(".")
        found.add(value)
    return found


@dataclass(frozen=True)
class GroundingResult:
    citations: list[str]
    unknown_citations: list[str]
    unverified_numbers: list[str]

    @property
    def grounded(self) -> bool:
        return bool(self.citations) and not self.unknown_citations and not self.unverified_numbers


def check(answer: str, sources: list[Source]) -> GroundingResult:
    known = {s.id for s in sources}
    cited = list(dict.fromkeys(_CITATION.findall(answer)))
    source_numbers: set[str] = set()
    for s in sources:
        source_numbers |= _numbers(s.text)
    return GroundingResult(
        citations=[c for c in cited if c in known],
        unknown_citations=[c for c in cited if c not in known],
        unverified_numbers=sorted(_numbers(answer) - source_numbers),
    )
