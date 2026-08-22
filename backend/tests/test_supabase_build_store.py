from app.models.deepcode_models import BuildRunTurnModel
from app.services.build_project_store import SupabaseBuildProjectStore


def test_supabase_run_row_uses_normalized_run_id_column():
    run = BuildRunTurnModel(
        turn_id='turn-123',
        project_id='proj-123',
        session_id='dc-sess-123',
        user_id='user-11111111-1111-1111-1111-111111111111',
        prompt='Add a triangle canvas',
    )

    row = SupabaseBuildProjectStore._build_run_row(run, run.user_id or '')

    assert row['run_id'] == 'turn-123'
    assert 'turn_id' not in row
    assert row['user_id'] == '11111111-1111-1111-1111-111111111111'
