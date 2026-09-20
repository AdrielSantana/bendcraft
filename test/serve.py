import http.server as h, sys
class H(h.SimpleHTTPRequestHandler):
    def end_headers(s):
        s.send_header("Cross-Origin-Opener-Policy", "same-origin"); s.send_header("Cross-Origin-Embedder-Policy", "require-corp"); s.send_header("Cache-Control", "no-store"); super().end_headers()
    def log_message(s, *a): pass
h.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
