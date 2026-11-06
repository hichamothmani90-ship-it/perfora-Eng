"""Remplit une copie du kit de démarrage avec une petite usine fictive (tests de la page Mise en service).
Usage : python tests/fabriquer_kit_exemple.py [CODE_SITE]  →  tests/kit_exemple_rempli.xlsx"""
import os
import sys
from datetime import datetime

from openpyxl import load_workbook

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = sys.argv[1] if len(sys.argv) > 1 else 'TNG'
D = lambda s: datetime.strptime(s, '%d/%m/%Y')
DONNEES = {
    'Lieux': [[SITE, 'BAT-1', 'Bâtiment production', None], [SITE, 'ATL-B', 'Atelier B', 'BAT-1'], [SITE, 'UTIL', 'Local utilités', 'BAT-1']],
    'Équipements': [
        ['CMP-01', 'Compresseur à vis', SITE, 'UTIL', None, 'ROT-COMPR · Compresseur', 'À vis lubrifié 15 kW', 'A · critique', 'En service', 'Appareil à pression', 'Atlas Copco', 'GA15', 'API123456', 2019, D('31/12/2026')],
        ['MOT-CMP-01', 'Moteur du compresseur', SITE, 'UTIL', 'CMP-01', 'ELE-MOTEUR · Moteur électrique', None, 'B · important', 'En service'],
        ['PRS-01', 'Presse hydraulique 60 t', SITE, 'ATL-B', None, 'PRO-PRESSE · Presse', None, 'A · critique', 'En service'],
        ['PONT-01', 'Pont roulant 5 t', SITE, 'ATL-B', None, 'MAN-PONT · Pont roulant, portique', None, 'B · important', 'En service', 'Levage'],
        ['EXT-ATL-01', 'Extincteur CO2 atelier', SITE, 'ATL-B', None, 'SEC-EXTINCT · Extincteur', None, 'C · standard', 'En service', 'Incendie'],
    ],
    'Compteurs': [
        ['HRS-CMP01', 'Heures de marche compresseur', 'Équipement', SITE, 'CMP-01', None, 'h', 'Cumulatif (index)', 1, None, 7, 12300, D('05/11/2026')],
        ['EL-GEN', 'Électricité arrivée générale', 'Ressource', SITE, None, 'Électricité', 'kWh', 'Cumulatif (index)', 40, None, 7, 1250, D('01/11/2026')],
        ['EL-ATL', 'Électricité atelier B', 'Ressource', SITE, None, 'Électricité', 'kWh', 'Cumulatif (index)', 1, 'EL-GEN', 7],
        ['EAU-GEN', 'Eau générale', 'Ressource', SITE, None, 'Eau', 'm³', 'Cumulatif (index)', 1, None, 30],
    ],
    'Articles': [
        ['FIL-AIR-15', 'Filtre à air GA15', 'u', SITE, 'A3-02', 4, 310, 'Oui', None, None, 'Atlas Copco Maroc', '1613 9001 00', 'CMP-01'],
        ['HUILE-CMP', 'Huile compresseur', 'L', SITE, 'B1-01', 20, 85, 'Non', 'bidon', 20, 'Atlas Copco Maroc'],
        ['JOINT-80', 'Joint de vérin Ø80', 'u', SITE, 'A1-04', 2, None, 'Oui', None, None, None, None, 'PRS-01'],
        ['GANT-NIT', 'Gants nitrile', 'paire', SITE, 'C2-01', None, None, 'Non', 'boîte', 50],
    ],
    'Préventif': [
        ['CMP-01', 'Vidange et filtre à air', 'Entretien', 180, 'HRS-CMP01', 500, 'Après réalisation', D('01/09/2026'), 12000, '1. Consigner 2. Vidanger 3. Remplacer le filtre 4. Essai'],
        ['CMP-01', 'Requalification appareil à pression', 'Vérification externe', 365, None, None, 'Échéance fixe', D('15/03/2026'), None, None, 'Organisme agréé (à préciser)'],
        ['PRS-01', 'Contrôle niveau et fuites hydrauliques', 'Inspection', 30, None, None, 'Après réalisation', D('20/10/2026')],
        ['PONT-01', 'Vérification périodique levage', 'Vérification externe', 182, None, None, 'Échéance fixe', None, None, None, 'Organisme agréé (à préciser)'],
    ],
    'Fournisseurs': [['Atlas Copco Maroc', 'Service après-vente', '+212 5 22 00 00 00', 'sav@exemple.ma', 10]],
    'Personnes': [['Karim Test', 'karim.test@exemple.ma', 'Technicien', SITE], ['FroidPlus', None, 'Prestataire', SITE, 'FroidPlus SARL']],
}
wb = load_workbook(os.path.join(RACINE, 'kit', 'Kit_demarrage_Perfora.xlsx'))
for onglet, lignes in DONNEES.items():
    ws = wb[onglet]
    for i, l in enumerate(lignes):
        for j, v in enumerate(l):
            ws.cell(6 + i, 1 + j, v)
sortie = os.path.join(RACINE, 'tests', 'kit_exemple_rempli.xlsx')
wb.save(sortie)
print(sortie)
