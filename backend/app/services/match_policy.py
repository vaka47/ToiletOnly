from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable
from uuid import UUID

from sqlalchemy import select, and_, or_
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import Match, MatchParticipantState, MatchStatus


@dataclass(frozen=True)
class ParticipantState:
    sessions_left: int
    is_kept: bool


def consume_one_session(state: ParticipantState) -> ParticipantState:
    if state.is_kept:
        return state
    return ParticipantState(sessions_left=max(0, state.sessions_left - 1), is_kept=False)


def resolve_match_status(a: ParticipantState, b: ParticipantState) -> MatchStatus:
    if a.is_kept and b.is_kept:
        return MatchStatus.kept
    if (not a.is_kept and a.sessions_left <= 0) or (not b.is_kept and b.sessions_left <= 0):
        return MatchStatus.expired
    return MatchStatus.active if a.is_kept or b.is_kept else MatchStatus.pending


async def ensure_participant_states(db: AsyncSession, match: Match) -> list[MatchParticipantState]:
    rows = await db.execute(
        select(MatchParticipantState).where(MatchParticipantState.match_id == match.id)
    )
    states = rows.scalars().all()
    if len(states) == 2:
        return states

    by_user: dict[UUID, MatchParticipantState] = {s.user_id: s for s in states}
    created = False
    for user_id in (match.user_a_id, match.user_b_id):
        if user_id not in by_user:
            item = MatchParticipantState(match_id=match.id, user_id=user_id, sessions_left=2, is_kept=False)
            db.add(item)
            by_user[user_id] = item
            created = True

    if created:
        await db.flush()
    return [by_user[match.user_a_id], by_user[match.user_b_id]]


async def apply_status_from_states(db: AsyncSession, match: Match, states: Iterable[MatchParticipantState]) -> MatchStatus:
    by_user = {s.user_id: s for s in states}
    a = by_user[match.user_a_id]
    b = by_user[match.user_b_id]
    status = resolve_match_status(
        ParticipantState(sessions_left=a.sessions_left, is_kept=a.is_kept),
        ParticipantState(sessions_left=b.sessions_left, is_kept=b.is_kept),
    )
    if match.status != status:
        match.status = status
        db.add(match)
    return status


async def consume_sessions_on_start(db: AsyncSession, user_id: UUID) -> int:
    rows = await db.execute(
        select(MatchParticipantState, Match)
        .join(Match, Match.id == MatchParticipantState.match_id)
        .where(MatchParticipantState.user_id == user_id)
        .where(Match.status != MatchStatus.expired)
        .where(MatchParticipantState.is_kept.is_(False))
    )
    pairs = rows.all()
    touched = 0
    for state, match in pairs:
        if state.sessions_left > 0:
            state.sessions_left = max(0, state.sessions_left - 1)
            db.add(state)
            touched += 1

        states = await ensure_participant_states(db, match)
        await apply_status_from_states(db, match, states)

    return touched


async def find_match_between(db: AsyncSession, user_a: UUID, user_b: UUID) -> Match | None:
    rows = await db.execute(
        select(Match)
        .where(
            or_(
                and_(Match.user_a_id == user_a, Match.user_b_id == user_b),
                and_(Match.user_a_id == user_b, Match.user_b_id == user_a),
            )
        )
        .order_by(Match.created_at.desc())
    )
    return rows.scalars().first()


def build_match_out(match: Match, states: Iterable[MatchParticipantState], viewer_id: UUID | str) -> dict:
    viewer_str = str(viewer_id)
    state_list = list(states)
    my_state = next((item for item in state_list if str(item.user_id) == viewer_str), None)
    other_state = next((item for item in state_list if str(item.user_id) != viewer_str), None)
    if my_state is None or other_state is None:
        raise ValueError("match states are incomplete")
    return {
        "id": str(match.id),
        "user_a_id": str(match.user_a_id),
        "user_b_id": str(match.user_b_id),
        "status": match.status,
        "my_is_kept": bool(my_state.is_kept),
        "other_is_kept": bool(other_state.is_kept),
        "my_sessions_left": my_state.sessions_left,
        "other_sessions_left": other_state.sessions_left,
    }
