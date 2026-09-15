import requests

import os

BASE_URL = os.getenv("BACKEND_URL", "http://localhost:8000")


def test_valid_route():
    res = requests.post(
        f"{BASE_URL}/route",
        json={"start": [12.9716, 77.5946], "end": [19.0760, 72.8777], "mode": "normal"},
    )
    print(res.text)
    assert res.status_code == 200


def test_invalid_route_422():
    res = requests.post(f"{BASE_URL}/route", json={"start": None, "end": None})
    print(res.text)
    assert res.status_code == 422 or res.status_code == 400
