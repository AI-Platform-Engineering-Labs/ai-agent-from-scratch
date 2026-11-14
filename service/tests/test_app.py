import sys
from pathlib import Path
from types import SimpleNamespace as NS

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as appmod  # noqa: E402


@pytest.fixture(autouse=True)
def env(monkeypatch, tmp_path):
    (tmp_path / "hello.txt").write_text("hello from the data dir")
    monkeypatch.setattr(appmod, "DATA_DIR", tmp_path.resolve())
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    monkeypatch.setenv("AGENT_API_TOKEN", "secret-token")
    monkeypatch.setattr(appmod, "SECRETS_DIR", tmp_path / "no-secrets")
    monkeypatch.setattr(appmod, "_client", None)


class FakeMessages:
    def __init__(self, script):
        self.script, self.calls = script, 0

    def create(self, **kw):
        r = self.script[self.calls]
        self.calls += 1
        return r


def usage():
    return NS(input_tokens=10, output_tokens=5)


def use_fake(monkeypatch, script):
    fake = NS(messages=FakeMessages(script))
    monkeypatch.setattr(appmod, "get_client", lambda: fake)
    return fake


AUTH = {"Authorization": "Bearer secret-token"}
client = TestClient(appmod.app)


def test_health_endpoints():
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200


def test_auth_required():
    assert client.post("/v1/run", json={"goal": "hi"}).status_code == 401
    assert client.post("/v1/run", json={"goal": "hi"}, headers={"Authorization": "Bearer nope"}).status_code == 401


def test_validation():
    assert client.post("/v1/run", json={"goal": ""}, headers=AUTH).status_code == 422
    assert client.post("/v1/run", json={"goal": "x", "max_steps": 999}, headers=AUTH).status_code == 422


def test_tool_loop(monkeypatch):
    use_fake(monkeypatch, [
        NS(stop_reason="tool_use", usage=usage(), content=[
            NS(type="tool_use", id="t1", name="read_file", input={"path": "hello.txt"})]),
        NS(stop_reason="end_turn", usage=usage(), content=[NS(type="text", text="done")]),
    ])
    r = client.post("/v1/run", json={"goal": "read it"}, headers=AUTH)
    body = r.json()
    assert r.status_code == 200 and body["finished"] and body["answer"] == "done"
    assert len(body["steps"]) == 2 and body["total_input_tokens"] == 20
    assert body["steps"][0]["tool_calls"][0]["name"] == "read_file"


def test_step_limit(monkeypatch):
    loop = NS(stop_reason="tool_use", usage=usage(), content=[
        NS(type="tool_use", id="t", name="list_dir", input={})])
    use_fake(monkeypatch, [loop] * 5)
    r = client.post("/v1/run", json={"goal": "loop", "max_steps": 3}, headers=AUTH)
    assert r.json()["finished"] is False and len(r.json()["steps"]) == 3


@pytest.mark.parametrize("path", ["../etc/passwd", "/etc/passwd", "../../x"])
def test_path_traversal_blocked(path):
    with pytest.raises(PermissionError):
        appmod.read_file(path)
    with pytest.raises(PermissionError):
        appmod.list_dir(path)


def test_tool_error_goes_back_to_model(monkeypatch):
    fake = use_fake(monkeypatch, [
        NS(stop_reason="tool_use", usage=usage(), content=[
            NS(type="tool_use", id="t1", name="read_file", input={"path": "../secret"})]),
        NS(stop_reason="end_turn", usage=usage(), content=[NS(type="text", text="blocked")]),
    ])
    r = client.post("/v1/run", json={"goal": "x"}, headers=AUTH)
    assert r.status_code == 200 and r.json()["answer"] == "blocked"
