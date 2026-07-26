import pytest

import app as app_module


@pytest.fixture
def client():
    app_module.app.testing = True
    # The real Limiter instance is a module-level singleton with in-memory
    # storage shared across every test in this process. Setting
    # RATELIMIT_ENABLED=False alone doesn't actually stop counters from
    # accumulating across tests (discovered when TestAdminSeed grew past 6
    # requests to its "5 per minute" route and started getting real 429s) —
    # explicitly reset the limiter's storage too, so test order/count can
    # never trip a real limit.
    app_module.app.config["RATELIMIT_ENABLED"] = False
    app_module.limiter.reset()
    return app_module.app.test_client()


@pytest.fixture(autouse=True)
def reset_keys(monkeypatch):
    # Every test starts from a known-clean slate for the module-level
    # secrets/toggles app.py reads at request time, regardless of what's
    # actually set in this machine's real environment.
    monkeypatch.setattr(app_module, "BACKEND_API_KEY", "")
    monkeypatch.setattr(app_module, "GEMINI_API_KEY", "")
    monkeypatch.setattr(app_module, "OPENAI_API_KEY", "")
    # Firebase Admin defaults to "not configured" so existing tests exercise
    # the AI-fallback/auth logic without also needing a Firebase ID token —
    # matches the real graceful-degradation behavior on a dev machine
    # without serviceAccountKey.json. Tests for the token gate itself
    # override this back to a truthy sentinel.
    monkeypatch.setattr(app_module, "_firestore_admin", None)


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


class TestFirebaseAuthGate:
    """Covers _require_firebase_user()/_verified_uid_or_none() — the layer
    added on top of the static BACKEND_API_KEY for /api/summarize,
    /api/assistant and /api/admin/seed, since the API key ships inside the
    app and isn't a real secret against a determined actor."""

    def test_skipped_entirely_when_firebase_admin_not_configured(self, client, monkeypatch):
        # _firestore_admin is None by default via the reset_keys fixture —
        # matches a dev machine without serviceAccountKey.json.
        monkeypatch.setattr(
            app_module, "_try_gemini_summarize",
            lambda text: {"summary": "ok", "sentiment": "Neutral", "triangle_hint": "h"},
        )
        monkeypatch.setattr(app_module, "GEMINI_API_KEY", "fake-gemini")
        r = client.post("/api/summarize", json={"text": "Some article."})
        assert r.status_code == 200

    def test_summarize_rejects_missing_token_when_firebase_admin_configured(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "_firestore_admin", object())
        monkeypatch.setattr(app_module, "GEMINI_API_KEY", "fake-gemini")
        r = client.post("/api/summarize", json={"text": "Some article."})
        assert r.status_code == 401

    def test_assistant_rejects_missing_token_when_firebase_admin_configured(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "_firestore_admin", object())
        r = client.post("/api/assistant", json={"prompt": "hello"})
        assert r.status_code == 401

    def test_rejects_malformed_authorization_header(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "_firestore_admin", object())
        r = client.post(
            "/api/assistant", json={"prompt": "hello"},
            headers={"Authorization": "NotBearer sometoken"},
        )
        assert r.status_code == 401

    def test_rejects_invalid_token(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "_firestore_admin", object())

        def broken_verify(token):
            raise ValueError("invalid token")

        monkeypatch.setattr(app_module.admin_auth, "verify_id_token", broken_verify)
        r = client.post(
            "/api/assistant", json={"prompt": "hello"},
            headers={"Authorization": "Bearer bad-token"},
        )
        assert r.status_code == 401

    def test_accepts_a_valid_token(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "_firestore_admin", object())
        monkeypatch.setattr(app_module, "GEMINI_API_KEY", "fake-gemini")

        def fake_verify(token):
            assert token == "good-token"
            return {"uid": "user-123"}

        monkeypatch.setattr(app_module.admin_auth, "verify_id_token", fake_verify)
        monkeypatch.setattr(app_module, "_try_ollama", lambda p: (_ for _ in ()).throw(ConnectionError()))
        monkeypatch.setattr(app_module, "_try_gemini", lambda p: "hi there")

        r = client.post(
            "/api/assistant", json={"prompt": "hello"},
            headers={"Authorization": "Bearer good-token"},
        )
        assert r.status_code == 200
        assert r.get_json()["response"] == "hi there"


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
        monkeypatch.setattr(app_module, "_verified_uid_or_none", lambda: "test-uid")
        monkeypatch.setattr(app_module, "ADMIN_UIDS", {"test-uid"})

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
        monkeypatch.setattr(app_module, "_verified_uid_or_none", lambda: "test-uid")
        monkeypatch.setattr(app_module, "ADMIN_UIDS", {"test-uid"})
        r = client.post(
            "/api/admin/seed", json={"collections": {}},
            headers={"X-API-Key": "secret123"},
        )
        assert r.status_code == 400

    def test_rejects_when_no_valid_firebase_token_even_with_correct_api_key(self, client, monkeypatch):
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")
        monkeypatch.setattr(app_module, "_firestore_admin", object())
        r = client.post(
            "/api/admin/seed", json={"collections": {"academy_scenarios": {"a": {}}}},
            headers={"X-API-Key": "secret123"},
        )
        assert r.status_code == 401

    def test_rejects_a_valid_but_non_admin_user(self, client, monkeypatch):
        # A real, signed-in user who is simply not in ADMIN_UIDS — this is
        # the exact gap being closed: previously any signed-in user passed.
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")
        monkeypatch.setattr(app_module, "_firestore_admin", object())
        monkeypatch.setattr(app_module, "_verified_uid_or_none", lambda: "random-user-uid")
        monkeypatch.setattr(app_module, "ADMIN_UIDS", {"the-actual-admin-uid"})
        r = client.post(
            "/api/admin/seed", json={"collections": {"academy_scenarios": {"a": {}}}},
            headers={"X-API-Key": "secret123"},
        )
        assert r.status_code == 403

    def test_rejects_when_admin_uids_not_configured(self, client, monkeypatch):
        # Valid token, but the server has no ADMIN_UIDS set at all — fail
        # closed rather than silently treating everyone as an admin.
        monkeypatch.setattr(app_module, "BACKEND_API_KEY", "secret123")
        monkeypatch.setattr(app_module, "_firestore_admin", object())
        monkeypatch.setattr(app_module, "_verified_uid_or_none", lambda: "test-uid")
        monkeypatch.setattr(app_module, "ADMIN_UIDS", set())
        r = client.post(
            "/api/admin/seed", json={"collections": {"academy_scenarios": {"a": {}}}},
            headers={"X-API-Key": "secret123"},
        )
        assert r.status_code == 503
