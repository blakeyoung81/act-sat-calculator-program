import urllib.request
import json

with open("IvyTutoring_ACT_SAT_Calculator_Guide.tex", "r") as f:
    text = f.read()

data = json.dumps({"latex": text}).encode('utf-8')
req = urllib.request.Request("https://pdf.mathcha.io/api/latex/pdf", data=data, headers={"Content-Type": "application/json"})

try:
    with urllib.request.urlopen(req) as response:
        with open("IvyTutoring_ACT_SAT_Calculator_Guide.pdf", "wb") as f:
            f.write(response.read())
    print("Success")
except Exception as e:
    print("Error:", e)
