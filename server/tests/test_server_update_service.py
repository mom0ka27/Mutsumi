from app.services.server_update_service import ServerUpdateService


def test_updates_include_alembic_assets():
    required = ServerUpdateService._required_files

    assert "alembic.ini" in required
    assert "migrations" in required
