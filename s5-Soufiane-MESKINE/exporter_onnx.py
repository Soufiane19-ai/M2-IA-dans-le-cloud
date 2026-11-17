"""Seance 5 — export ONNX du ResNet18 de S4, puis quantization dynamique int8.

Fichier distribue en debut de seance : lisez-le avant de le lancer. Entree : le paquet de S4 (model/modele.pt + model/modele_meta.json).
Sorties, dans le meme dossier :
  modele.onnx        float32, meme calcul que PyTorch, execute par ONNX Runtime
  modele_int8.onnx   poids en int8 (quantization dynamique) ; QUANTIFIER=0 pour sauter l'etape

Usage :  python exporter_onnx.py [dossier_modele]      (defaut : model)
"""
import hashlib
import json
import os
import sys
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import torch
import torchvision
from onnxruntime.quantization import QuantType, quantize_dynamic
from onnxruntime.quantization.shape_inference import quant_pre_process

DOSSIER = Path(sys.argv[1] if len(sys.argv) > 1 else "model")
META = json.loads((DOSSIER / "modele_meta.json").read_text())
T = META["taille_entree"]

# Meme construction qu'en S4 : weights=None, aucun telechargement, les poids viennent du paquet.
reseau = torchvision.models.resnet18(weights=None)
reseau.fc = torch.nn.Linear(reseau.fc.in_features, 1)
reseau.load_state_dict(torch.load(DOSSIER / "modele.pt", map_location="cpu", weights_only=True))
reseau.eval()

exemple = torch.randn(1, 3, T, T)   # la forme compte, pas les valeurs
fp32 = DOSSIER / "modele.onnx"
torch.onnx.export(
    reseau, (exemple,), fp32,
    input_names=["entree"], output_names=["logit"],
    dynamic_shapes={"x": {0: torch.export.Dim("lot")}},   # taille de lot libre, 3 x T x T fixes
    opset_version=18,
    external_data=False,            # un seul fichier .onnx, poids inclus (sinon un .onnx.data a cote)
)
onnx.checker.check_model(onnx.load(fp32))

# Parite immediate sur une entree aleatoire de lot 4 : meme logit a 1e-4 pres.
x = np.random.default_rng(0).standard_normal((4, 3, T, T), dtype=np.float32)
with torch.no_grad():
    attendu = reseau(torch.from_numpy(x)).numpy()
obtenu = ort.InferenceSession(fp32, providers=["CPUExecutionProvider"]).run(None, {"entree": x})[0]
ecart = float(np.abs(attendu - obtenu).max())
assert ecart < 1e-4, f"export non conforme : ecart de logit {ecart:.2e}"


def decrire(chemin):
    empreinte = hashlib.sha256(chemin.read_bytes()).hexdigest()[:16]
    return f"{chemin.name:18s} {chemin.stat().st_size / 1e6:6.1f} Mo  sha256 {empreinte}"


print(decrire(DOSSIER / "modele.pt"))
print(decrire(fp32), f" ecart max de logit (lot de 4) : {ecart:.1e}")

if os.environ.get("QUANTIFIER", "1") != "0":
    # Dynamique : poids convertis une fois en int8, activations quantifiees a la volee,
    # sans jeu de calibration. QUInt8 : le seul type d'activation que ConvInteger accepte sur CPU.
    # Pre-traitement recommande : il recalcule les formes. Sans lui, sur l'export dynamo,
    # quantize_dynamic echoue (ShapeInferenceError : (512) vs (1)).
    pre = DOSSIER / "_pretraite.onnx"
    quant_pre_process(fp32, pre)
    int8 = DOSSIER / "modele_int8.onnx"
    quantize_dynamic(pre, int8, weight_type=QuantType.QUInt8)
    pre.unlink()
    print(decrire(int8))
