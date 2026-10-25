import http.server, json, os, sys
STORE = {}
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_GET(self):
        if self.path.startswith('/kv/'):
            k=self.path[4:]; b=json.dumps(STORE.get(k)).encode()
            self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(b); return
        return super().do_GET()
    def do_PUT(self):
        if self.path.startswith('/kv/'):
            n=int(self.headers.get('Content-Length',0)); STORE[self.path[4:]]=json.loads(self.rfile.read(n) or b'null')
            self.send_response(204); self.end_headers(); return
os.chdir(sys.argv[1]); http.server.ThreadingHTTPServer(('127.0.0.1',8767),H).serve_forever()
