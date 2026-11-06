"""Génère le kit Excel de démarrage d'un client : kit/Kit_demarrage_Perfora.xlsx.
Usage : python scripts/kit_demarrage.py
Les classes d'équipement sont lues dans docs/CLASSIFICATION_PARC.md (source unique). Une ligne d'exemple par onglet,
en gris italique (ligne 5) : le client peut l'effacer ou la garder ; l'import ignore une ligne dont un code commence par « EX- »."""
import os
import re
from datetime import date

from openpyxl import Workbook
from openpyxl.comments import Comment
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SORTIE = os.path.join(RACINE, 'kit', 'Kit_demarrage_Perfora.xlsx')
NB_LIGNES = 1000  # lignes couvertes par les listes déroulantes

BLEU, ENCRE, GRIS = '1D4ED8', '1C1C1A', '6B6A66'
F_TITRE = Font(name='Arial', size=16, bold=True, color=ENCRE)
F_TXT = Font(name='Arial', size=10, color=ENCRE)
F_GRAS = Font(name='Arial', size=10, bold=True, color=ENCRE)
F_ENTETE = Font(name='Arial', size=10, bold=True, color='FFFFFF')
F_EX = Font(name='Arial', size=10, italic=True, color=GRIS)
F_SAISIE = Font(name='Arial', size=10, color='0000FF')
FOND_OBLIG = PatternFill('solid', start_color='1D4ED8')
FOND_FACULT = PatternFill('solid', start_color='6B6A66')
FOND_AIDE = PatternFill('solid', start_color='F6F5F1')
FOND_JAUNE = PatternFill('solid', start_color='FFF4C2')
BORD = Border(bottom=Side(style='thin', color='E4E2DC'))


def classes():
    """[(code, libellé, catégorie)] depuis docs/CLASSIFICATION_PARC.md, avec une classe « Autre » par catégorie."""
    out, cat = [], None
    for ligne in open(os.path.join(RACINE, 'docs', 'CLASSIFICATION_PARC.md'), encoding='utf-8'):
        m = re.match(r'\*\*([A-Z]{3}) — (.+?)\*\*', ligne)
        if m:
            if cat:
                out.append((cat[0] + '-AUTRE', 'Autre', cat[1]))
            cat = (m.group(1), m.group(2).split(' (')[0])
            continue
        m = re.match(r'\| ([A-Z]{3}-[A-Z]+) \| (.+?) \|', ligne)
        if m and cat:
            out.append((m.group(1), m.group(2), cat[1]))
    out.append((cat[0] + '-AUTRE', 'Autre', cat[1]))
    return out


CLASSES = classes()
LISTES = {
    'classe': [f'{c} · {l}' for c, l, _ in CLASSES],
    'criticite': ['A · critique', 'B · important', 'C · standard'],
    'statut': ['En service', 'En secours', 'À l’arrêt', 'Réformé'],
    'reglementaire': ['Levage', 'Appareil à pression', 'Installation électrique', 'Incendie', 'Ascenseur', 'Visite technique véhicule', 'Autre contrôle'],
    'usage': ['Ressource', 'Équipement'],
    'ressource': ['Électricité', 'Eau', 'Gasoil', 'Fuel', 'Gaz', 'Air comprimé', 'Froid', 'Autre'],
    'unite_cpt': ['kWh', 'm³', 'L', 'kg', 'Nm³', 'h', 'cycles', 'km', 't', '°C', 'bar'],
    'mode': ['Cumulatif (index)', 'Non cumulatif (quantité)'],
    'unite_art': ['u', 'L', 'kg', 'm', 'm²', 'jeu', 'paire', 'boîte', 'rouleau'],
    'ouinon': ['Oui', 'Non'],
    'type_prev': ['Entretien', 'Inspection', 'Test', 'Vérification externe', 'Autre'],
    'regle': ['Échéance fixe', 'Après réalisation'],
    'role': ['Responsable', 'Technicien', 'Prestataire', 'Magasinier', 'Achats', 'Exploitation', 'Pilote'],
}

# Onglets : (nom, titre, aide, colonnes). Colonne : (en-tête, largeur, obligatoire, liste, commentaire, exemple, format)
J = 'JJ/MM/AAAA'
ONGLETS = [
    ('Lieux', 'Lieux : où se trouvent les équipements',
     'Un lieu par ligne, du plus grand au plus petit : bâtiment ou zone, puis ligne ou atelier. Le site lui-même est créé par Perfora.', [
         ('Code site', 12, True, None, 'Code court du site, donné par Perfora (ex. TNG).', 'TNG', None),
         ('Code lieu', 16, True, None, 'Unique dans le site. Lettres, chiffres, tirets.', 'EX-ATL-B', None),
         ('Nom du lieu', 30, True, None, None, 'Atelier B', None),
         ('Code du lieu parent', 18, False, None, 'Vide si le lieu est directement dans le site.', '', None),
         ('Remarques', 30, False, None, None, '', None)]),
    ('Équipements', 'Équipements : le parc à maintenir',
     'Un équipement par ligne. Le code est imprimé dans le QR collé sur la machine : court, unique, jamais réutilisé.', [
         ('Code équipement', 16, True, None, 'Unique dans l’entreprise ; sert au QR (ex. CMP-01).', 'EX-CMP-01', None),
         ('Désignation', 28, True, None, None, 'Compresseur atelier B', None),
         ('Code site', 10, True, None, None, 'TNG', None),
         ('Code lieu', 14, True, None, 'Code de l’onglet Lieux.', 'EX-ATL-B', None),
         ('Code équipement parent', 18, False, None, 'Si c’est un sous-ensemble (ex. moteur d’une pompe).', '', None),
         ('Classe', 34, True, 'classe', 'Choisir dans la liste (catalogue Perfora).', 'ROT-COMPR · Compresseur', None),
         ('Sous-type', 22, False, None, 'Précision libre (ex. à vis lubrifié).', 'À vis lubrifié 15 kW', None),
         ('Criticité', 14, False, 'criticite', 'A : panne grave pour sécurité ou production sans secours. Laisser vide si vous ne savez pas : on la fixera ensemble.', 'A · critique', None),
         ('Statut', 13, False, 'statut', 'En service par défaut.', 'En service', None),
         ('Contrôle réglementaire', 22, False, 'reglementaire', 'Si l’équipement est soumis à un contrôle par un organisme agréé.', 'Appareil à pression', None),
         ('Fabricant', 16, False, None, None, 'Atlas Copco', None),
         ('Modèle', 16, False, None, None, 'GA15', None),
         ('N° de série', 16, False, None, None, 'API123456', None),
         ('Année de mise en service', 12, False, None, None, 2019, '0'),
         ('Fin de garantie', 13, False, None, J, None, 'DD/MM/YYYY'),
         ('Remarques', 30, False, None, None, '', None)]),
    ('Compteurs', 'Compteurs : énergie, eau et heures de marche',
     'Ressource = électricité, eau, gasoil… Équipement = heures de marche, cycles, kilomètres d’une machine (préventif selon l’usage).', [
         ('Code compteur', 14, True, None, 'Unique ; sert au QR du compteur.', 'EX-HRS-CMP01', None),
         ('Libellé', 26, True, None, None, 'Heures de marche compresseur', None),
         ('Usage', 13, True, 'usage', None, 'Équipement', None),
         ('Code site', 10, True, None, None, 'TNG', None),
         ('Code équipement', 16, False, None, 'Obligatoire si usage = Équipement.', 'EX-CMP-01', None),
         ('Ressource', 14, False, 'ressource', 'Obligatoire si usage = Ressource.', '', None),
         ('Unité', 9, True, 'unite_cpt', None, 'h', None),
         ('Type', 22, True, 'mode', 'Cumulatif : on lit un index qui augmente. Non cumulatif : on lit une quantité consommée.', 'Cumulatif (index)', None),
         ('Coefficient', 11, False, None, 'Multiplicateur du compteur (1 par défaut).', 1, None),
         ('Code compteur parent', 18, False, None, 'Pour un sous-compteur : code du compteur principal.', '', None),
         ('Fréquence de relevé (jours)', 14, False, None, None, 7, '0'),
         ('Dernier index connu', 14, False, None, None, 12300, '#,##0.##'),
         ('Date du dernier index', 13, False, None, J, None, 'DD/MM/YYYY'),
         ('Remarques', 30, False, None, None, '', None)]),
    ('Articles', 'Articles : pièces de rechange et consommables',
     'Un article par ligne et par site. Le stock actuel devient l’inventaire de départ, à la date de mise en service.', [
         ('Référence', 16, True, None, 'Votre référence interne, unique.', 'EX-FIL-AIR-15', None),
         ('Désignation', 30, True, None, None, 'Filtre à air compresseur GA15', None),
         ('Unité', 9, True, 'unite_art', None, 'u', None),
         ('Code site', 10, True, None, None, 'TNG', None),
         ('Emplacement', 12, False, None, 'Allée, étagère, casier (ex. A3-02).', 'A3-02', None),
         ('Stock actuel', 11, False, None, 'Quantité comptée. Vide = inconnue (pas zéro).', 4, '#,##0.##'),
         ('Prix unitaire HT (MAD)', 13, False, None, 'Vide si inconnu (jamais 0).', 310, '#,##0.00'),
         ('Article critique', 11, False, 'ouinon', 'Pièce dont l’absence arrête un équipement critique.', 'Oui', None),
         ('Unité d’achat', 12, False, None, 'Si acheté par lot (ex. carton).', '', None),
         ('Contenu de l’unité d’achat', 13, False, None, 'Nombre d’unités de stock dans l’unité d’achat (ex. 10).', None, '0'),
         ('Fournisseur habituel', 20, False, None, 'Nom de l’onglet Fournisseurs.', 'EX-Atlas Copco Maroc', None),
         ('Référence fournisseur', 18, False, None, None, '1613 9001 00', None),
         ('Code équipement concerné', 16, False, None, 'Facultatif : sur quelle machine la pièce est montée.', 'EX-CMP-01', None),
         ('Remarques', 30, False, None, None, '', None)]),
    ('Préventif', 'Préventif : entretiens, inspections, contrôles',
     'Une opération par ligne. Périodicité en jours, ou selon un compteur (ex. toutes les 500 h), ou les deux (« le premier des deux »).', [
         ('Code équipement', 16, True, None, None, 'EX-CMP-01', None),
         ('Opération', 30, True, None, None, 'Vidange et filtre à air', None),
         ('Type', 18, True, 'type_prev', None, 'Entretien', None),
         ('Tous les … jours', 11, False, None, 'Vide si uniquement selon compteur.', 180, '0'),
         ('Code compteur', 14, False, None, 'Pour un préventif selon l’usage.', 'EX-HRS-CMP01', None),
         ('Toutes les … (unité du compteur)', 13, False, None, 'Ex. 500 pour toutes les 500 h.', 500, '#,##0'),
         ('Règle', 16, False, 'regle', 'Échéance fixe : le calendrier ne glisse pas. Après réalisation : on repart de la date réelle.', 'Après réalisation', None),
         ('Dernière réalisation', 13, False, None, J, None, 'DD/MM/YYYY'),
         ('Index à la dernière réalisation', 14, False, None, None, 12000, '#,##0.##'),
         ('Instructions', 40, False, None, 'Étapes, consignes de sécurité.', '1. Consigner 2. Vidanger 3. Remplacer le filtre 4. Essai', None),
         ('Organisme (contrôle externe)', 20, False, None, 'Pour une vérification externe.', '', None),
         ('Remarques', 30, False, None, None, '', None)]),
    ('Fournisseurs', 'Fournisseurs', 'Un fournisseur par ligne.', [
         ('Nom', 26, True, None, 'Unique.', 'EX-Atlas Copco Maroc', None),
         ('Contact', 20, False, None, None, 'Service après-vente', None),
         ('Téléphone', 16, False, None, None, '+212 5 22 00 00 00', None),
         ('E-mail', 26, False, None, None, 'sav@exemple.ma', None),
         ('Délai habituel (jours)', 12, False, None, None, 10, '0'),
         ('Remarques', 30, False, None, None, '', None)]),
    ('Personnes', 'Personnes : qui utilisera Perfora',
     'Chaque personne avec un e-mail reçoit une invitation (rôle et sites ci-dessous). Données personnelles : uniquement le nécessaire.', [
         ('Nom', 22, True, None, None, 'EX-Karim Alaoui', None),
         ('E-mail', 26, False, None, 'Pour recevoir l’invitation. Vide = pas de compte (personne citée seulement).', 'karim.alaoui@exemple.ma', None),
         ('Rôle', 14, True, 'role', None, 'Technicien', None),
         ('Codes sites', 14, True, None, 'Un ou plusieurs, séparés par une virgule (ex. TNG, CAS).', 'TNG', None),
         ('Société (prestataire)', 20, False, None, 'Pour un prestataire extérieur.', '', None),
         ('Téléphone', 16, False, None, None, '', None),
         ('Remarques', 30, False, None, None, '', None)]),
]


def lisez_moi(wb):
    ws = wb.active
    ws.title = 'Lisez-moi'
    ws.sheet_view.showGridLines = False
    ws.column_dimensions['A'].width = 3
    ws.column_dimensions['B'].width = 26
    ws.column_dimensions['C'].width = 90
    ws['B2'] = 'Perfora · Kit de démarrage'
    ws['B2'].font = F_TITRE
    ws['B3'] = f'Version du {date.today().strftime("%d/%m/%Y")} · à renvoyer à contact@perfora.ma'
    ws['B3'].font = Font(name='Arial', size=10, color=GRIS)
    lignes = [
        ('À quoi sert ce fichier', 'Il décrit votre site pour que Perfora soit prêt le jour du démarrage : vos équipements, compteurs, pièces et entretiens. Nous l’importons pour vous.'),
        ('Comment remplir', 'Un onglet par sujet, une ligne par élément. Remplissez ce que vous avez : un onglet vide n’est pas un problème, on le complétera ensemble.'),
        ('Colonnes', 'En-tête BLEU = obligatoire. En-tête GRIS = facultatif. Survolez un en-tête pour voir l’aide. Ne renommez pas les colonnes.'),
        ('Listes', 'Certaines colonnes ont une liste déroulante (classe, criticité, unité…) : choisissez dans la liste.'),
        ('Ligne d’exemple', 'La première ligne de chaque onglet (gris, en italique, code « EX-… ») est un exemple : remplacez-la ou laissez-la, elle ne sera pas importée.'),
        ('Codes', 'Les codes (lieu, équipement, compteur, article) sont uniques et ne changent plus : ils relient les onglets entre eux et sont imprimés dans les QR.'),
        ('Valeurs inconnues', 'Laissez la case vide. Ne mettez jamais 0 pour « je ne sais pas » (un stock ou un prix à 0 serait faux).'),
        ('Dates', 'Format JJ/MM/AAAA.'),
        ('Ordre conseillé', '1. Lieux  2. Équipements  3. Compteurs  4. Articles  5. Préventif  6. Fournisseurs  7. Personnes.'),
        ('Vous avez déjà une liste ?', 'Envoyez-nous votre fichier existant (Excel, export d’un logiciel) : nous faisons la correspondance avec vous.'),
        ('Données personnelles', 'L’onglet Personnes contient des noms et des e-mails : ils servent uniquement à créer les accès à Perfora, conformément à la loi 09-08 (CNDP).'),
    ]
    for i, (a, b) in enumerate(lignes):
        r = 5 + i
        ws.cell(r, 2, a).font = F_GRAS
        c = ws.cell(r, 3, b)
        c.font = F_TXT
        c.alignment = Alignment(wrap_text=True, vertical='top')
        ws.cell(r, 2).alignment = Alignment(vertical='top')
        ws.row_dimensions[r].height = 30
    r = 6 + len(lignes)
    ws.cell(r, 2, 'Légende').font = F_GRAS
    for j, (txt, fill, font) in enumerate([('Obligatoire', FOND_OBLIG, F_ENTETE), ('Facultatif', FOND_FACULT, F_ENTETE),
                                            ('Exemple (non importé)', None, F_EX), ('Vos saisies (texte bleu)', None, F_SAISIE)]):
        c = ws.cell(r + 1 + j, 2, txt)
        c.font = font
        if fill:
            c.fill = fill


def feuille_listes(wb):
    ws = wb.create_sheet('Listes')
    plages = {}
    for j, (nom, valeurs) in enumerate(LISTES.items(), start=1):
        col = get_column_letter(j)
        ws.cell(1, j, nom).font = F_GRAS
        for i, v in enumerate(valeurs, start=2):
            ws.cell(i, j, v).font = F_TXT
        ws.column_dimensions[col].width = max(14, max(len(str(v)) for v in valeurs) + 2)
        plages[nom] = f"=Listes!${col}$2:${col}${len(valeurs) + 1}"
    # Catalogue lisible : code, classe, catégorie
    k = len(LISTES) + 2
    for t, h in enumerate(['Code classe', 'Classe', 'Catégorie']):
        ws.cell(1, k + t, h).font = F_GRAS
    for i, (c, l, cat) in enumerate(CLASSES, start=2):
        for t, v in enumerate([c, l, cat]):
            ws.cell(i, k + t, v).font = F_TXT
    for t, w in enumerate([14, 40, 34]):
        ws.column_dimensions[get_column_letter(k + t)].width = w
    ws.sheet_state = 'visible'
    return plages


def onglet(wb, nom, titre, aide, cols, plages):
    ws = wb.create_sheet(nom)
    ws['A1'] = titre
    ws['A1'].font = Font(name='Arial', size=13, bold=True, color=ENCRE)
    ws['A2'] = aide
    ws['A2'].font = Font(name='Arial', size=10, color=GRIS)
    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=min(len(cols), 10))
    ws.row_dimensions[2].height = 28
    ws['A2'].alignment = Alignment(wrap_text=True, vertical='top')
    for j, (h, w, oblig, liste, com, ex, fmt) in enumerate(cols, start=1):
        col = get_column_letter(j)
        c = ws.cell(4, j, h + (' *' if oblig else ''))
        c.font = F_ENTETE
        c.fill = FOND_OBLIG if oblig else FOND_FACULT
        c.alignment = Alignment(wrap_text=True, vertical='center')
        if com:
            c.comment = Comment(com, 'Perfora')
        ws.column_dimensions[col].width = w
        e = ws.cell(5, j, ex if ex not in ('',) else None)
        e.font = F_EX
        if fmt:
            e.number_format = fmt
        for r in range(6, 6 + 200):
            cell = ws.cell(r, j)
            cell.font = F_SAISIE
            if fmt:
                cell.number_format = fmt
        if liste:
            dv = DataValidation(type='list', formula1=plages[liste], allow_blank=True, showErrorMessage=True,
                                errorTitle='Valeur hors liste', error='Choisissez une valeur dans la liste déroulante.')
            ws.add_data_validation(dv)
            dv.add(f'{col}5:{col}{NB_LIGNES}')
        if fmt == 'DD/MM/YYYY':
            dv = DataValidation(type='date', operator='greaterThan', formula1='1', allow_blank=True, showErrorMessage=True,
                                errorTitle='Date', error='Saisissez une date au format JJ/MM/AAAA.')
            ws.add_data_validation(dv)
            dv.add(f'{col}5:{col}{NB_LIGNES}')
    ws.row_dimensions[4].height = 42
    ws.freeze_panes = 'B5'
    ws.auto_filter.ref = f'A4:{get_column_letter(len(cols))}{NB_LIGNES}'


def main():
    wb = Workbook()
    lisez_moi(wb)
    plages = feuille_listes(wb)
    for nom, titre, aide, cols in ONGLETS:
        onglet(wb, nom, titre, aide, cols, plages)
    wb.move_sheet('Listes', offset=len(wb.sheetnames))  # en dernier
    os.makedirs(os.path.dirname(SORTIE), exist_ok=True)
    wb.save(SORTIE)
    print(SORTIE, '·', len(CLASSES), 'classes ·', wb.sheetnames)


if __name__ == '__main__':
    main()
