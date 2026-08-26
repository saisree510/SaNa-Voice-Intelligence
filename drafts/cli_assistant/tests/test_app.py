from src.cli_assistant.app import build_summary

def test_build_summary_mentions_generated_scaffold():
    summary = build_summary()
    assert "SaNa generated scaffold" in summary
