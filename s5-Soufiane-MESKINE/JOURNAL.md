# Journal — Séance 5, optimiser et surveiller

Soufiane Meskine, M2 YNOV Campus Montpellier, Industrialisation de l'IA dans le Cloud 2026-2027.

## Tableau de décisions

Rempli et figé le **17/11/2026 à 15:05** (heure de Paris), avant toute mesure de la séance : aucun export, aucune comparaison, aucun PSI n'avait encore été calculé.

| Décision | Contrainte | Ma valeur |
|---|---|---|
| Suffixe personnel | identique à S1 | **`sm26`** |
| Écart max. de probabilité, « même modèle » | ONNX contre PyTorch | **1e-5** (la tolérance de concordance de S4, mesure 16) |
| Rappel minimal d'une variante | au seuil servi | **0,88** (52 malignes sur 59 en validation) : le rappel visé de 0,90, moins une maligne de marge, car à 59 positifs une maligne vaut 1,7 point de rappel |
| Décisions changées max., même version | entier | **0** : une seule décision qui change, c'est un patient orienté autrement, donc un autre modèle |
| Covariable surveillée en priorité | reçue par l'API | **`tbp_tile_type`** (l'éclairage : mesure 20 de S4, et le scénario du centre partenaire) |
| Statistique de dérive | calculée par `derive.py` | **PSI** |
| Seuil d'alerte du PSI | avant la mesure | **0,25** (seuil usuel de « changement important de population ») |
| Seuil de surveillance du PSI | sous l'alerte | **0,10** (seuil usuel de « changement modéré, à surveiller ») |
| Fenêtre glissante | en inférences | **200** inférences |
| Levier de dérive provoquée | `eclairage`, `age`, `site` | **`eclairage`** ; second levier : **`age`** |

**Question 0.1** — Un seuil fixé après avoir vu les courbes est ajusté sur ce qu'on vient de voir : l'analyste le place, sans le vouloir, juste au-dessus du bruit du flux conforme et juste en dessous du pic de la dérive. Il fabrique donc une détection parfaite sur **ce** rejeu (zéro fausse alerte, délai minimal), qui ne dit rien de ce qui se passera sur un flux nouveau. C'est le même biais qu'un seuil de décision choisi sur le jeu de test.

**Question 0.2** — La quantization ne protège que le **coût** et la latence (un plan plus petit, des réponses plus rapides), alors que la surveillance protège les **patients** : sans elle, un flux qui ne ressemble plus à l'entraînement produit des décisions fausses, servies en 200, que personne ne voit.
