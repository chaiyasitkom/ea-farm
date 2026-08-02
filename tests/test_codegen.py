from __future__ import annotations

import importlib
import json
import shutil
import subprocess
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast

import pytest
from pydantic import BaseModel, ValidationError

from brain.common.wiretime import format_utc, parse_utc

ROOT = Path(__file__).resolve().parents[1]
GEN_DIR = ROOT / "contracts" / "gen" / "python"
FIXTURE_DIR = ROOT / "contracts" / "fixtures"


def run_codegen() -> None:
    completed = subprocess.run(
        ["python", "tools/codegen.py"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
    )
    assert completed.returncode == 0, completed.stderr


def load_fixture(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(data, dict)
    return cast(dict[str, Any], data)


def validate_envelope(data: dict[str, Any]) -> None:
    contracts = importlib.import_module("farm_contracts")

    envelope = contracts.FarmEnvelope.model_validate(data)
    payload_model = contracts.PAYLOAD_MODELS[envelope.type.value]
    payload_model.model_validate(envelope.payload)


def test_codegen_is_deterministic() -> None:
    run_codegen()
    first = {path.relative_to(ROOT): path.read_bytes() for path in GEN_DIR.glob("*.py")}
    first.update(
        {path.relative_to(ROOT): path.read_bytes() for path in FIXTURE_DIR.rglob("*.json")}
    )
    run_codegen()
    second = {path.relative_to(ROOT): path.read_bytes() for path in GEN_DIR.glob("*.py")}
    second.update(
        {path.relative_to(ROOT): path.read_bytes() for path in FIXTURE_DIR.rglob("*.json")}
    )
    assert second == first


def test_codegen_check_detects_stale_gen() -> None:
    (ROOT / ".tmp-pytest").mkdir(exist_ok=True)
    temp_root = Path(tempfile.mkdtemp(prefix="codegen-check-", dir=ROOT / ".tmp-pytest"))
    temp_repo = temp_root / "repo"
    shutil.copytree(
        ROOT,
        temp_repo,
        ignore=shutil.ignore_patterns(
            ".git",
            ".venv",
            ".pytest_cache",
            ".mypy_cache",
            ".ruff_cache",
            ".tmp-pytest",
        ),
    )
    subprocess.run(
        ["git", "init"], cwd=temp_repo, check=True, capture_output=True, encoding="utf-8"
    )
    subprocess.run(
        ["git", "add", "contracts/gen"],
        cwd=temp_repo,
        check=True,
        capture_output=True,
        encoding="utf-8",
    )
    subprocess.run(
        [
            "git",
            "-c",
            "user.name=Codex Test",
            "-c",
            "user.email=codex-test@example.invalid",
            "commit",
            "-m",
            "baseline",
        ],
        cwd=temp_repo,
        check=True,
        capture_output=True,
        encoding="utf-8",
    )
    schema = temp_repo / "contracts" / "schema" / "bar.json"
    content = schema.read_text(encoding="utf-8")
    updated = content.replace(
        '"tick_volume": { "type": "integer", "minimum": 0 }',
        '"tick_volume": { "type": "integer", "minimum": 1 }',
    )
    assert updated != content
    schema.write_text(updated, encoding="utf-8")
    completed = subprocess.run(
        ["python", "tools/task.py", "codegen-check"],
        cwd=temp_repo,
        check=False,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
    )
    assert completed.returncode != 0


def test_every_envelope_type_has_model() -> None:
    contracts = importlib.import_module("farm_contracts")
    schema = json.loads(
        (ROOT / "contracts" / "schema" / "envelope.json").read_text(encoding="utf-8")
    )
    assert sorted(contracts.PAYLOAD_MODELS) == sorted(schema["properties"]["type"]["enum"])


def test_all_classes_ignore_extra() -> None:
    models = importlib.import_module("farm_contracts.models")
    classes = [
        cls
        for cls in vars(models).values()
        if isinstance(cls, type) and issubclass(cls, BaseModel) and cls is not BaseModel
    ]
    forbidden = [cls for cls in classes if cls.model_config.get("extra") == "forbid"]
    ignored = [cls for cls in classes if cls.model_config.get("extra") == "ignore"]
    assert [cls.__name__ for cls in forbidden] == ["ConfigUpdateSettings"]
    assert len(ignored) == len(classes) - 1


def test_models_accept_unknown_field() -> None:
    data = load_fixture(FIXTURE_DIR / "hello.valid.extra.json")
    validate_envelope(data)


def test_models_reject_missing_required() -> None:
    data = load_fixture(FIXTURE_DIR / "hello.valid.json")
    del data["payload"]["token"]
    with pytest.raises(ValidationError):
        validate_envelope(data)


def test_models_reject_ts_with_offset() -> None:
    data = load_fixture(FIXTURE_DIR / "invalid" / "envelope.ts_offset_not_z.json")
    with pytest.raises(ValidationError):
        validate_envelope(data)


def test_models_reject_bad_ulid_18_digits() -> None:
    data = load_fixture(FIXTURE_DIR / "invalid" / "envelope.msgid_18digits.json")
    with pytest.raises(ValidationError):
        validate_envelope(data)


def test_models_reject_period_prefixed_timeframe() -> None:
    data = load_fixture(FIXTURE_DIR / "invalid" / "envelope.session_period_prefix.json")
    with pytest.raises(ValidationError):
        validate_envelope(data)


def test_models_reject_sl_zero_accept_null() -> None:
    data = load_fixture(FIXTURE_DIR / "invalid" / "state.sl_zero.json")
    with pytest.raises(ValidationError):
        validate_envelope(data)
    valid = load_fixture(FIXTURE_DIR / "state.valid.json")
    valid["payload"]["positions"][0]["sl"] = None
    validate_envelope(valid)


def test_models_reject_scale_factor_above_one() -> None:
    data = load_fixture(FIXTURE_DIR / "invalid" / "risk_directive.scale_above_one.json")
    with pytest.raises(ValidationError):
        validate_envelope(data)


def test_config_update_settings_rejects_unknown_key() -> None:
    data = load_fixture(FIXTURE_DIR / "invalid" / "config_update.unknown_setting.json")
    with pytest.raises(ValidationError):
        validate_envelope(data)


def test_all_valid_fixtures_pass() -> None:
    valid_paths = sorted(path for path in FIXTURE_DIR.glob("*.json") if ".valid" in path.name)
    assert len(valid_paths) == 36
    for path in valid_paths:
        validate_envelope(load_fixture(path))


def test_all_invalid_fixtures_fail() -> None:
    invalid_paths = sorted((FIXTURE_DIR / "invalid").glob("*.json"))
    assert len(invalid_paths) >= 8
    for path in invalid_paths:
        with pytest.raises(ValidationError):
            validate_envelope(load_fixture(path))


def test_wiretime_roundtrip_and_rejects_non_z() -> None:
    parsed = parse_utc("2026-07-26T14:30:00.412Z")
    assert parsed == datetime(2026, 7, 26, 14, 30, 0, 412000, tzinfo=UTC)
    assert format_utc(parsed) == "2026-07-26T14:30:00.412Z"
    assert format_utc(datetime(2026, 7, 26, 14, 30, tzinfo=UTC)) == "2026-07-26T14:30:00Z"
    with pytest.raises(ValueError):
        parse_utc("2026-07-26T14:30:00+07:00")
    with pytest.raises(ValueError):
        format_utc(datetime(2026, 7, 26, 14, 30))
