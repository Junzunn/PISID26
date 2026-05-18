import json
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent


def load_config():
    path = BASE_DIR / "config.json"
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)
