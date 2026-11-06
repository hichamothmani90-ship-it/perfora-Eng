"""Lance GMAO terrain en local : python serveur.py [port]
Aucune dépendance. Les données restent dans le navigateur de chaque appareil."""
import functools, http.server, os, socket, sys, webbrowser

PORT = next((int(a) for a in sys.argv[1:] if a.isdigit()), 8080)
RACINE = os.path.dirname(os.path.abspath(__file__))


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".webmanifest": "application/manifest+json", ".js": "text/javascript", ".svg": "image/svg+xml"}

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, *args):
        pass


def ip_locale():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))  # aucun paquet envoyé
            return s.getsockname()[0]
    except OSError:
        return None


if __name__ == "__main__":
    srv = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), functools.partial(Handler, directory=RACINE))
    print(f"GMAO terrain  ->  http://localhost:{PORT}/")
    ip = ip_locale()
    if ip:
        print(f"Depuis un téléphone sur le même Wi-Fi  ->  http://{ip}:{PORT}/")
    print("Ctrl+C pour arrêter.")
    if "--no-browser" not in sys.argv:
        webbrowser.open(f"http://localhost:{PORT}/")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
