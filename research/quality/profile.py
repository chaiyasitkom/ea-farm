from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timedelta

TRADED_RATIO = 0.90
CLOSED_RATIO = 0.10
MIN_PROFILE_DAYS = 28

Slot = tuple[int, int]


@dataclass(frozen=True)
class SlotProfile:
    slot: Slot
    observed: int
    possible: int

    @property
    def ratio(self) -> float:
        if self.possible == 0:
            return 0.0
        return self.observed / self.possible

    @property
    def state(self) -> str:
        ratio = self.ratio
        if ratio > TRADED_RATIO:
            return "traded"
        if ratio < CLOSED_RATIO:
            return "closed"
        return "ambiguous"


@dataclass(frozen=True)
class SessionProfile:
    slots: dict[Slot, SlotProfile]
    first: datetime
    last: datetime
    days: int

    def state_for(self, timestamp: datetime) -> str:
        slot = (timestamp.weekday(), timestamp.hour * 60 + timestamp.minute)
        profile = self.slots.get(slot)
        if profile is None:
            return "closed"
        return profile.state

    def ratio_for(self, dow: int, minute_of_day: int) -> float:
        profile = self.slots.get((dow, minute_of_day))
        if profile is None:
            return 0.0
        return profile.ratio

    def closed_minutes(self) -> list[Slot]:
        return sorted(slot for slot, profile in self.slots.items() if profile.state == "closed")

    def ambiguous_minutes(self) -> list[Slot]:
        return sorted(slot for slot, profile in self.slots.items() if profile.state == "ambiguous")


def minute_slot(timestamp: datetime) -> Slot:
    return timestamp.weekday(), timestamp.hour * 60 + timestamp.minute


def build_session_profile(timestamps: list[datetime]) -> SessionProfile | None:
    if not timestamps:
        return None
    unique = sorted(set(timestamps))
    first = unique[0].replace(second=0, microsecond=0)
    last = unique[-1].replace(second=0, microsecond=0)
    days = (last.date() - first.date()).days + 1
    if days < MIN_PROFILE_DAYS:
        return None

    observed = Counter(minute_slot(ts) for ts in unique)
    possible: Counter[Slot] = Counter()
    day = first.date()
    end = last.date()
    while day <= end:
        for minute in range(24 * 60):
            possible[(day.weekday(), minute)] += 1
        day += timedelta(days=1)

    slots = {
        slot: SlotProfile(slot=slot, observed=observed.get(slot, 0), possible=count)
        for slot, count in sorted(possible.items())
    }
    return SessionProfile(slots=slots, first=first, last=last, days=days)

