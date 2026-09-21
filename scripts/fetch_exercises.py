from pathlib import Path
import requests
import json

page = 1
all_exercises = []

while True:
    response = requests.get(
        "https://api.kinetic.place/v1/exercises",
        params={
            "page": page,
            "limit": 200,
        },
    )

    response.raise_for_status()

    response_data = response.json()
    exercises = response_data["data"]

    all_exercises.extend(exercises)

    if len(all_exercises) >= response_data["total"]:
        break

    page += 1

print(len(all_exercises))

if len(all_exercises) > 0:
    response_data_path = Path.cwd() / "seed_data" / "response.json"
    #json_data = all_exercises.json()

    with response_data_path.open(mode="w", encoding="utf-8") as f:
        json.dump(all_exercises, f, indent=4)