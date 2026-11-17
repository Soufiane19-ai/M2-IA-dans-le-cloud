"""Petits utilitaires de la seance 5 (evite les guillemets imbriques de PowerShell 5.1).
python outils_s5.py versions | extraire_meta
"""
import sys
import zipfile

if sys.argv[1] == "versions":
    import PIL, numpy, onnx, onnxruntime, pandas, torch  # noqa: E401
    print(sys.version.split()[0], "torch", torch.__version__, "onnx", onnx.__version__,
          "onnxruntime", onnxruntime.__version__, "numpy", numpy.__version__,
          "pillow", PIL.__version__, "pandas", pandas.__version__)
elif sys.argv[1] == "extraire_meta":
    z = zipfile.ZipFile("donnees/train-metadata.csv.zip")
    nom = [x for x in z.namelist() if x.endswith(".csv")][0]
    open("donnees/train-metadata.csv", "wb").write(z.read(nom))
    print(nom, "extrait")
elif sys.argv[1] == "meta":
    # partie 4.2 : meta de l'image S5 = meta de S4, version et variante de la decision 3.3
    import json
    m = json.load(open("model/modele_meta.json"))
    m["version"], m["variante"] = sys.argv[2], sys.argv[3]
    json.dump(m, open("api-s5/model/modele_meta.json", "w"), indent=2, ensure_ascii=False)
    print("version", m["version"], "variante", m["variante"])
