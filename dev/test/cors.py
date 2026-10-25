import http.server, sys, os
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a): pass
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin','*'); super().end_headers()
os.chdir(sys.argv[1]); http.server.ThreadingHTTPServer(('127.0.0.1',8765),H).serve_forever()
