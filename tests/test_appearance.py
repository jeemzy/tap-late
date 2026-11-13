import pytest
from fastapi.testclient import TestClient

from taplate.app import create_app
from taplate.config import Settings


def client_for(path):
    return TestClient(create_app(data_dir=path, settings=Settings(_env_file=None), start_worker=False))


def test_settings_can_be_opened_directly_without_first_loading_home(tmp_path):
    frontend = tmp_path / "ui"
    frontend.mkdir()
    (frontend / "index.html").write_text("<main>tap-late application</main>")
    app = create_app(
        data_dir=tmp_path / "data",
        settings=Settings(_env_file=None),
        start_worker=False,
        frontend_dir=frontend,
    )
    with TestClient(app) as client:
        response = client.get("/settings")
        assert response.status_code == 200
        assert "<main>tap-late application</main>" in response.text


def test_appearance_changes_are_shared_and_partial_edits_do_not_erase_other_devices(tmp_path):
    with client_for(tmp_path) as phone, client_for(tmp_path) as desktop:
        assert phone.get("/api/settings/appearance").status_code == 200
        saved = phone.patch("/api/settings/appearance", json={"frost": 2.3, "refraction_index": 1.8})
        assert saved.status_code == 200
        assert desktop.get("/api/settings/appearance").json()["frost"] == 2.3
        desktop.patch("/api/settings/appearance", json={"gloss": 0.4}).raise_for_status()
        current = phone.get("/api/settings/appearance").json()
        assert current["refraction_index"] == 1.8
        assert current["frost"] == 2.3
        assert current["gloss"] == 0.4


def test_appearance_survives_a_backend_restart(tmp_path):
    with client_for(tmp_path) as first:
        first.patch(
            "/api/settings/appearance", json={"dispersion": 1.4, "resolution": "3x"}
        ).raise_for_status()
    with client_for(tmp_path) as restarted:
        current = restarted.get("/api/settings/appearance").json()
        assert current["dispersion"] == 1.4
        assert current["resolution"] == "3x"


def test_matte_finish_preserves_existing_optics_and_survives_restart(tmp_path):
    with client_for(tmp_path) as client:
        assert client.get("/api/settings/appearance").json()["matte"] == 0
        client.patch("/api/settings/appearance", json={"refraction_strength": 2.2}).raise_for_status()
        response = client.patch("/api/settings/appearance", json={"matte": 0.65})
        assert response.status_code == 200
        assert response.json()["refraction_strength"] == 2.2
    with client_for(tmp_path) as restarted:
        assert restarted.get("/api/settings/appearance").json()["matte"] == 0.65


@pytest.mark.parametrize(
    "change",
    [
        {"frost": -1},
        {"matte": -0.1},
        {"matte": 1.1},
        {"refraction_index": 9},
        {"frost": None},
        {"resolution": "infinite"},
        {"shader_source": "arbitrary code"},
    ],
)
def test_invalid_appearance_cannot_replace_the_saved_configuration(tmp_path, change):
    with client_for(tmp_path) as client:
        before = client.get("/api/settings/appearance").json()
        assert client.patch("/api/settings/appearance", json=change).status_code == 422
        assert client.get("/api/settings/appearance").json() == before


def test_other_websites_cannot_change_global_appearance(tmp_path):
    with client_for(tmp_path) as client:
        before = client.get("/api/settings/appearance").json()
        result = client.patch(
            "/api/settings/appearance", json={"frost": 4}, headers={"Origin": "https://elsewhere.test"}
        )
        assert result.status_code == 403
        assert client.get("/api/settings/appearance").json() == before
