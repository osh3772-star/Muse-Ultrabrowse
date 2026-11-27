#!/usr/bin/env python3
import http.server, socketserver

LONG = ("Cloudflare errors explained: an Access Denied page appears when a rule blocks a request. "
        "A visitor may see 'Attention Required' or a challenge that asks 'verify you are human'. "
        "The phrase 'Just a moment' is the title of the interstitial. Site owners should check "
        "firewall events, bot fight mode and rate limiting rules before changing DNS settings. ") * 12
PUB = ("Welcome to our public documentation portal. Read guides, release notes and API references. "
       "All articles are public and no account is required to read them. ") * 20

PAGES = {
 "/longdoc": (200, f"<html><head><title>Understanding Cloudflare errors</title></head><body><h1>Error guide</h1><p>{LONG}</p></body></html>"),
 "/challenge": (200, "<html><head><title>Just a moment...</title></head><body><h1>Just a moment...</h1><p>Verifying you are human. This may take a few seconds. Please enable JavaScript and cookies to continue. Your browser will redirect you automatically once the verification is complete. Ray ID: abc123</p></body></html>"),
 "/login": (200, '<html><head><title>Sign in</title></head><body><h1>Sign in</h1><form action="/login" method="post"><input type="text" name="id"><input type = "password" name="pw"><button>Log in</button></form><p>Please sign in to continue to your account dashboard. Members can view orders, invoices, saved addresses, payment methods and subscription settings after authentication. New here? Create an account instead.</p></body></html>'),
 "/public": (200, f'<html><head><title>Docs</title></head><body><nav><a href="/login">Login</a></nav><p>{PUB}</p></body></html>'),
 "/401": (401, "<html><body><h1>Authentication required</h1></body></html>"),
 "/403": (403, "<html><body><h1>Forbidden</h1></body></html>"),
}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        code, body = PAGES.get(self.path, (404, "<html><body>not found</body></html>"))
        b = body.encode()
        self.send_response(code); self.send_header("Content-Type","text/html"); self.send_header("Content-Length",str(len(b))); self.end_headers()
        self.wfile.write(b)
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("127.0.0.1", 8937), H).serve_forever()
