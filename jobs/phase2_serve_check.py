"""Phase 2 check: one chat completion with an image against the local vLLM endpoint.

Usage: python phase2_serve_check.py <base_url> <served_model_name> <image_path>
"""
import base64
import sys
import time

from openai import OpenAI

base_url, model, image_path = sys.argv[1:4]
client = OpenAI(base_url=base_url, api_key="EMPTY")

with open(image_path, "rb") as f:
    b64 = base64.b64encode(f.read()).decode()

t0 = time.time()
resp = client.chat.completions.create(
    model=model,
    messages=[{
        "role": "user",
        "content": [
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
            {"type": "text", "text": "Which room of a house is this, and name three objects you can see."},
        ],
    }],
    # Same sampling settings MECoBench uses for this model (eval/agents/models.json).
    temperature=0.7,
    top_p=0.8,
    presence_penalty=1.5,
    max_tokens=200,
    extra_body={"top_k": 20},
)
dt = time.time() - t0
text = resp.choices[0].message.content
print(f"reply ({dt:.1f}s, {resp.usage.prompt_tokens} prompt + {resp.usage.completion_tokens} completion tokens):")
print(text)
if not text or not text.strip():
    sys.exit("FAIL: empty reply")
print("PASS: image chat completion succeeded")
