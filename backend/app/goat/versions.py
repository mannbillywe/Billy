"""Central version map for Goat Mode compute artefacts.

Written to goat_mode_jobs.model_versions and goat_mode_snapshots.ai_layer meta
so downstream consumers can tell which code shape produced a given row.
"""

MODEL_VERSIONS: dict[str, str] = {
    "deterministic": "0.1.0",
    "recommendations": "0.2.0",
    "missing_inputs": "0.1.0",
    "forecast": "0.1.0",
    "anomaly": "0.1.0",
    "risk": "0.1.0",
    "ai": "0.1.0",
}
