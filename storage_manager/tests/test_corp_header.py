"""CORP header middleware (#1314): responses are embeddable by cross-origin isolated pages."""

from fastapi import FastAPI
from fastapi.responses import Response
from fastapi.testclient import TestClient

from storage_manager.middleware import CrossOriginResourcePolicyMiddleware


def _app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(CrossOriginResourcePolicyMiddleware)

    @app.get("/plain")
    def plain():
        return {"ok": True}

    @app.get("/own-policy")
    def own_policy():
        return Response("x", headers={"Cross-Origin-Resource-Policy": "same-site"})

    return app


def test_adds_cross_origin_resource_policy():
    response = TestClient(_app()).get("/plain")
    assert response.status_code == 200
    assert response.headers["cross-origin-resource-policy"] == "cross-origin"


def test_keeps_a_route_specific_policy():
    response = TestClient(_app()).get("/own-policy")
    assert response.headers["cross-origin-resource-policy"] == "same-site"
