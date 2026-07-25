import pytest

import app as app_module


@pytest.fixture
def client():
    app_module.app.testing = True
    # The real Limiter instance is a module-level singleton with in-memory
    # storage shared across every test in this process — disable it here so
    # test order/count can never trip a real "10 per minute" limit.
    app_module.app.config["RATELIMIT_ENABLED"] = False
    return app_module.app.test_client()


@pytest.fixture(autouse=True)
def reset_keys(monkeypatch):
    # Every test starts from a known-clean slate for the module-level
    # secrets/toggles app.py reads at request time, regardless of what's
    # actually set in this machine's real environment.
    monkeypatch.setattr(app_module, "BACKEND_API_KEY", "")
    monkeypatch.setattr(app_module, "GEMINI_API_KEY", "")
    monkeypatch.setattr(app_module, "OPENAI_API_KEY", "")


class TestApiKeyGate:
    def test_unprotected_when_no_backend_key_configured(self, client):
        r = client.post("/api/summarize", json={"text": "hello"})
        # Falls through the auth gate; fails later for lack of AI keys, not auth.
        assert r.status_code != 401

    def test_rejects_missing_header_when_key_configured(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")
        r = client.post("/api/summarize", json={"text": "hello"})
        assert r.status_code == 401

    def test_rejects_wrong_header_when_key_configured(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")
        r = client.post(
            "/api/summarize", json={"text": "hello"},
            headers={"X-API-Key": "wrong"},
        )
        assert r.status_code == 401

    def test_accepts_correct_header(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")
        r = client.post(
            "/api/summarize", json={"text": "hello"},
            headers={"X-API-Key": "secret123"},
        )
        assert r.status_code != 401

    def test_root_health_check_always_open(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")
        r = client.get("/")
        assert r.status_code == 200


class TestSummarizeFallback:
    def test_no_keys_configured_returns_clear_error(self, client):
        r = client.post("/api/summarize", json={"text": "Some article body."})
        assert r.status_code == 502
        assert "GEMINI_API_KEY" in r.get_json()["error"]

    def test_missing_text_is_a_400_before_any_ai_call_is_attempted(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "GEMINI_API_KEY", "fake-key")
        called = []
        monkeypatch.setattr(app_module, "_try_gemini_summarize", lambda t: called.append(t))
        r = client.post("/api/summarize", json={"text": ""})
        assert r.status_code == 400
        assert called == []

    def test_prefers_gemini_when_both_keys_present(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "GEMINI_API_KEY", "fake-gemini")
        monkeypatch.setattr(app_module, "OPENAI_API_KEY", "fake-openai")
        monkeypatch.setattr(
            app_module, "_try_gemini_summarize",
            lambda text: {"summary": "from gemini", "sentiment": "Neutral", "triangle_hint": "hint"},
        )
        openai_called = []
        monkeypatch.setattr(app_module, "_try_openai_summarize", lambda t: openai_called.append(t))

        r = client.post("/api/summarize", json={"text": "Some article."})
        assert r.status_code == 200
        assert r.get_json()["summary"] == "from gemini"
        assert openai_called == []

    def test_falls_back_to_openai_when_gemini_fails(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "GEMINI_API_KEY", "fake-gemini")
        monkeypatch.setattr(app_module, "OPENAI_API_KEY", "fake-openai")

        def broken_gemini(text):
            raise RuntimeError("quota exceeded")

        monkeypatch.setattr(app_module, "_try_gemini_summarize", broken_gemini)
        monkeypatch.setattr(
            app_module, "_try_openai_summarize",
            lambda text: {"summary": "from openai", "sentiment": "Neutral", "triangle_hint": "hint"},
        )

        r = client.post("/api/summarize", json={"text": "Some article."})
        assert r.status_code == 200
        assert r.get_json()["summary"] == "from openai"

    def test_returns_502_when_gemini_fails_and_no_openai_key(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "GEMINI_API_KEY", "fake-gemini")

        def broken_gemini(text):
            raise RuntimeError("quota exceeded")

        monkeypatch.setattr(app_module, "_try_gemini_summarize", broken_gemini)

        r = client.post("/api/summarize", json={"text": "Some article."})
        assert r.status_code == 502


class TestParseSummaryJson:
    def test_parses_plain_json(self):
        result = app_module._parse_summary_json(
            '{"summary": "s", "sentiment": "Bullish", "triangle_hint": "h"}'
        )
        assert result == {"summary": "s", "sentiment": "Bullish", "triangle_hint": "h"}

    def test_strips_markdown_json_fence(self):
        result = app_module._parse_summary_json(
            '```json\n{"summary": "s", "sentiment": "Bearish", "triangle_hint": "h"}\n```'
        )
        assert result["summary"] == "s"
        assert result["sentiment"] == "Bearish"

    def test_missing_keys_fall_back_to_defaults(self):
        result = app_module._parse_summary_json('{}')
        assert result["sentiment"] == "Neutral"
        assert "Return" in result["triangle_hint"]


class TestAssistantFallback:
    def test_missing_prompt_is_400(self, client):
        r = client.post("/api/assistant", json={})
        assert r.status_code == 400

    def test_falls_back_to_gemini_when_ollama_unreachable(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "GEMINI_API_KEY", "fake-gemini")

        def broken_ollama(prompt):
            raise ConnectionError("no ollama running")

        monkeypatch.setattr(app_module, "_try_ollama", broken_ollama)
        monkeypatch.setattr(app_module, "_try_gemini", lambda prompt: "gemini says hi")

        r = client.post("/api/assistant", json={"prompt": "hello"})
        assert r.status_code == 200
        assert r.get_json()["response"] == "gemini says hi"

    def test_no_backend_configured_gives_actionable_error(self, client, monkeypatch):
        def broken_ollama(prompt):
            raise ConnectionError("no ollama running")

        monkeypatch.setattr(app_module, "_try_ollama", broken_ollama)

        r = client.post("/api/assistant", json={"prompt": "hello"})
        assert r.status_code == 502
        assert "GEMINI_API_KEY" in r.get_json()["error"]


class TestAdminSeed:
    def test_rejects_when_backend_key_not_configured_at_all(self, client):
        r = client.post("/api/admin/seed", json={"collections": {"academy_scenarios": {}}})
        assert r.status_code == 503

    def test_rejects_wrong_key_even_though_endpoint_is_configured(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")
        r = client.post(
            "/api/admin/seed", json={"collections": {"academy_scenarios": {}}},
            headers={"X-API-Key": "wrong"},
        )
        assert r.status_code == 401

    def test_rejects_when_firebase_admin_not_initialized(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")
        monkeypatch.setattr(app_module, "_firestore_admin", None)
        r = client.post(
            "/api/admin/seed", json={"collections": {"academy_scenarios": {"a": {}}}},
            headers={"X-API-Key": "secret123"},
        )
        assert r.status_code == 503

    def test_seeds_each_collection_with_the_admin_sdk_batch(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")

        committed_batches = []

        class FakeBatch:
            def __init__(self):
                self.sets = []

            def set(self, doc_ref, data):
                self.sets.append((doc_ref, data))

            def commit(self):
                committed_batches.append(self.sets)

        class FakeCollectionRef:
            def __init__(self, name):
                self.name = name

            def document(self, doc_id):
                return (self.name, doc_id)

        class FakeFirestoreAdmin:
            def batch(self):
                return FakeBatch()

            def collection(self, name):
                return FakeCollectionRef(name)

        monkeypatch.setattr(app_module, "_firestore_admin", FakeFirestoreAdmin())

        payload = {
            "collections": {
                "academy_scenarios": {"scn_001": {"title": "A"}},
                "academy_quizzes": {"qz_001": {"q": "B"}},
            }
        }
        r = client.post(
            "/api/admin/seed", json=payload, headers={"X-API-Key": "secret123"}
        )
        assert r.status_code == 200
        assert r.get_json()["seeded_collections"] == 2
        assert len(committed_batches) == 2

    def test_rejects_empty_collections_payload(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")
        monkeypatch.setattr(app_module, "_firestore_admin", object())
        r = client.post(
            "/api/admin/seed", json={"collections": {}},
            headers={"X-API-Key": "secret123"},
        )
        assert r.status_code == 400
