from app.models import MatchStatus
from app.services.match_policy import ParticipantState, consume_one_session, resolve_match_status


def test_consume_session_decrements_only_for_unkept():
    assert consume_one_session(ParticipantState(sessions_left=2, is_kept=False)).sessions_left == 1
    assert consume_one_session(ParticipantState(sessions_left=1, is_kept=False)).sessions_left == 0
    assert consume_one_session(ParticipantState(sessions_left=0, is_kept=False)).sessions_left == 0
    assert consume_one_session(ParticipantState(sessions_left=2, is_kept=True)).sessions_left == 2


def test_resolve_match_status_pending_before_keep():
    a = ParticipantState(sessions_left=2, is_kept=False)
    b = ParticipantState(sessions_left=2, is_kept=False)
    assert resolve_match_status(a, b) == MatchStatus.pending


def test_resolve_match_status_active_when_one_kept():
    a = ParticipantState(sessions_left=0, is_kept=True)
    b = ParticipantState(sessions_left=2, is_kept=False)
    assert resolve_match_status(a, b) == MatchStatus.active


def test_resolve_match_status_kept_when_both_kept():
    a = ParticipantState(sessions_left=0, is_kept=True)
    b = ParticipantState(sessions_left=1, is_kept=True)
    assert resolve_match_status(a, b) == MatchStatus.kept


def test_resolve_match_status_expired_after_two_sessions_without_keep():
    # User A did not keep and exhausted both sessions.
    a = ParticipantState(sessions_left=0, is_kept=False)
    b = ParticipantState(sessions_left=2, is_kept=False)
    assert resolve_match_status(a, b) == MatchStatus.expired
