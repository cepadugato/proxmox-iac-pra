#!/usr/bin/env python3
"""API Proxmox factice (feuille 5.6a) : HTTPS sur 127.0.0.1, certificat jetable fourni par le test.
Usage : api-factice.py <port> <cert.pem> <key.pem> <noeud> <journal>
Répond à GET /api2/json/nodes avec {"data":[{"node":"<noeud>"}]} si l'en-tête Authorization commence par PVEAPIToken=.
Journal : une ligne par requête, « GET <chemin> auth=oui|non » (la valeur du jeton n'est jamais écrite)."""
import http.server, ssl, sys, json

port, cert, key, noeud, journal = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        auth = "oui" if (self.headers.get("Authorization") or "").startswith("PVEAPIToken=") else "non"
        with open(journal, "a") as f:
            f.write("GET %s auth=%s\n" % (self.path, auth))
        if self.path == "/api2/json/nodes" and auth == "oui":
            body = json.dumps({"data": [{"node": noeud, "status": "online"}]}).encode()
            self.send_response(200)
        else:
            body = b'{"data":null}'
            self.send_response(401)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

srv = http.server.HTTPServer(("127.0.0.1", port), H)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
print("prêt", flush=True)
srv.serve_forever()
