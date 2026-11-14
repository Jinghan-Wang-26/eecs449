"""Static assets compatibility for the pinned Jac 0.16.7 / jac-client 0.3.25.

The client's void static-file hook sends a response, then hook dispatch falls
through to core's NotImplementedError, appending a second HTTP response. Use
one response writer for this app's public assets without changing site-packages.
The generated client bundle and CSS retain Jac's dedicated response handlers.
"""
import mimetypes;
import from pathlib { Path }
import from jaclang { JacRuntime as Jac }
import from jaclang.runtimelib.server { ResponseBuilder }

glob ASSETS_ROOT = (Path(__file__).resolve().parent.parent / "assets").resolve();


def serve_public_asset(handler: any, file_path: any, content_type: str | None = None) -> None {
    path = Path(file_path).resolve();
    # The runtime also searches dist and basename aliases. Only files inside
    # this project's deliberately public assets directory belong on this route.
    if not path.is_relative_to(ASSETS_ROOT) or not path.is_file() {
        ResponseBuilder.send_json(handler, 404, {"error": "Public asset not found"}); return;
    }
    try { body = path.read_bytes(); }
    except OSError {
        ResponseBuilder.send_json(handler, 404, {"error": "Public asset not found"}); return;
    }
    media_type = content_type or mimetypes.guess_type(str(path))[0] or "application/octet-stream";
    handler.send_response(200);
    handler.send_header("Content-Type", media_type);
    handler.send_header("Content-Length", str(len(body)));
    handler.send_header("Cache-Control", "no-cache");
    handler.send_header("X-Content-Type-Options", "nosniff");
    ResponseBuilder._add_custom_headers(handler);
    handler.end_headers();
    handler.wfile.write(body);
}

with entry {
    Jac.send_static_file = staticmethod(serve_public_asset);
}
