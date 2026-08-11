from livekit.agents import llm

from agent import build_restored_chat_context, normalize_restored_messages


def test_normalize_restored_messages_filters_invalid_entries_and_limits_history():
    messages = [
        {"id": "system", "role": "system", "content": "ignore me"},
        {"id": "blank", "role": "user", "content": "   "},
        {"id": "one", "role": "user", "content": "Earlier question"},
        {"id": "two", "role": "assistant", "content": "Earlier answer"},
        {"id": "three", "role": "user", "content": "Latest question"},
    ]

    normalized = normalize_restored_messages(messages, max_messages=2)

    assert normalized == [
        {"id": "two", "role": "assistant", "content": "Earlier answer"},
        {"id": "three", "role": "user", "content": "Latest question"},
    ]


def test_build_restored_chat_context_replaces_old_session_memory():
    existing = llm.ChatContext()
    existing.add_message(role="user", content="Unrelated new-room message")

    restored = build_restored_chat_context(
        existing,
        [
            {"id": "saved-user", "role": "user", "content": "My project uses Flutter"},
            {"id": "saved-agent", "role": "assistant", "content": "We chose Riverpod"},
        ],
    )

    messages = restored.messages()
    assert [message.role for message in messages] == ["user", "assistant"]
    assert [message.text_content for message in messages] == [
        "My project uses Flutter",
        "We chose Riverpod",
    ]
    assert [message.id for message in messages] == ["saved-user", "saved-agent"]
