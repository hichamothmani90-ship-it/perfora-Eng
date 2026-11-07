"""Bascule le réseau simulé du serveur factice (tests hors ligne).
Usage : python tests/reseau.py 8093 panne | normal | lent [delai] | coupures | etat"""
import json
import sys
import urllib.request

port, mode = sys.argv[1], sys.argv[2]
corps = {} if mode == "etat" else {"mode": mode}
if mode == "lent" and len(sys.argv) > 3:
    corps["delai"] = float(sys.argv[3])
if mode == "raz":
    corps = {"raz": True}
r = urllib.request.Request(f"http://localhost:{port}/test/reseau", data=json.dumps(corps).encode(), headers={"Content-Type": "application/json"}, method="POST")
print(json.loads(urllib.request.urlopen(r).read()))
