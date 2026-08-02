from __future__ import annotations

import importlib
import json
import shutil
import subprocess
import tempfile
import warnings
from pathlib import Path
from typing import Any

import pytest

from brain.common.registry import (
    SymbolRegistry,
    SymbolRegistryValidationError,
    UnknownSymbolError,
    load_symbol_registry_data,
    validate_symbol_registry_data,
)

ROOT = Path(__file__).resolve().parents[1]


def copy_codegen_workspace(temp_repo: Path) -> None:
    contracts_dir = temp_repo / "contracts"
    contracts_dir.mkdir(parents=True)
    shutil.copytree(ROOT / "contracts" / "schema", contracts_dir / "schema")
    shutil.copytree(ROOT / "contracts" / "gen", contracts_dir / "gen")
    shutil.copy2(ROOT / "contracts" / "symbols.json", contracts_dir / "symbols.json")

    shutil.copytree(
        ROOT / "brain",
        temp_repo / "brain",
        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
    )
    tools_dir = temp_repo / "tools"
    tools_dir.mkdir()
    for name in ("codegen.py", "task.py", "__init__.py"):
        shutil.copy2(ROOT / "tools" / name, tools_dir / name)


@pytest.fixture()
def registry() -> SymbolRegistry:
    return SymbolRegistry.load()


def registry_data() -> dict[str, Any]:
    return load_symbol_registry_data(ROOT / "contracts" / "symbols.json")


def write_registry(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, sort_keys=True), encoding="utf-8")


def generated_contracts() -> Any:
    return importlib.import_module("farm_contracts")


def test_gold_maps_to_xauusd(registry: SymbolRegistry) -> None:
    assert registry.to_canonical("XMGlobal-MT5 6", "GOLD") == "XAUUSD"


def test_iux_suffix_maps_to_same_canonical(registry: SymbolRegistry) -> None:
    assert registry.to_canonical("IUXMarkets-Demo", "EURUSD.iux") == "EURUSD"


def test_same_canonical_from_two_brokers(registry: SymbolRegistry) -> None:
    assert registry.to_canonical("IUXMarkets-Demo", "XAUUSD.iux") == "XAUUSD"
    assert registry.to_canonical("XMGlobal-MT5 6", "GOLD") == "XAUUSD"


def test_to_raw_round_trip_all_entries(registry: SymbolRegistry) -> None:
    data = registry_data()
    for broker, mapping in data["brokers"].items():
        for raw, canonical in mapping.items():
            assert registry.to_raw(broker, registry.to_canonical(broker, raw)) == raw
            assert registry.to_raw(broker, canonical) == raw


def test_unknown_raw_raises_not_guesses(registry: SymbolRegistry) -> None:
    with pytest.raises(UnknownSymbolError):
        registry.to_canonical("XMGlobal-MT5 6", "EURUSDm")


def test_unknown_broker_raises(registry: SymbolRegistry) -> None:
    with pytest.raises(UnknownSymbolError):
        registry.to_canonical("XMGlobal-MT5 7", "EURUSD")


def test_base_quote_metals_xau(registry: SymbolRegistry) -> None:
    assert registry.base_quote("XAUUSD") == ("XAU", "USD")


def test_validator_rejects_duplicate_raw() -> None:
    temp_dir = ROOT / ".tmp-pytest" / "duplicate-raw"
    temp_dir.mkdir(parents=True, exist_ok=True)
    path = temp_dir / "symbols.json"
    path.write_text(
        '{"version":1,"brokers":{"B":{"EURUSD":"EURUSD","EURUSD":"GBPUSD"}},'
        '"canonicals":{'
        '"EURUSD":{"base":"EUR","quote":"USD","group":"EUROPE",'
        '"max_spread_points":null,"max_sl_distance_pct":0.5,'
        '"session_policy":"MON_0100_FRI_2000"},'
        '"GBPUSD":{"base":"GBP","quote":"USD","group":"EUROPE",'
        '"max_spread_points":null,"max_sl_distance_pct":0.6,'
        '"session_policy":"MON_0100_FRI_2000"}}}',
        encoding="utf-8",
    )
    with pytest.raises(SymbolRegistryValidationError):
        load_symbol_registry_data(path)


def test_validator_rejects_duplicate_canonical_per_broker() -> None:
    data = registry_data()
    data["brokers"]["IUXMarkets-Demo"]["ALTUSD"] = "EURUSD"
    with pytest.raises(SymbolRegistryValidationError):
        validate_symbol_registry_data(data)


def test_validator_rejects_base_equals_quote() -> None:
    data = registry_data()
    data["canonicals"]["EURUSD"]["quote"] = "EUR"
    with pytest.raises(SymbolRegistryValidationError):
        validate_symbol_registry_data(data)


def test_validator_rejects_canonical_without_definition() -> None:
    data = registry_data()
    data["brokers"]["IUXMarkets-Demo"]["EURUSD.iux"] = "CADJPY"
    with pytest.raises(SymbolRegistryValidationError):
        validate_symbol_registry_data(data)


def test_validator_allows_broker_missing_some_canonicals() -> None:
    data = registry_data()
    del data["brokers"]["IUXMarkets-Demo"]["AUDUSD.iux"]
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        validate_symbol_registry_data(data)


def test_validator_warns_for_unmapped_canonical() -> None:
    data = registry_data()
    del data["brokers"]["IUXMarkets-Demo"]["AUDUSD.iux"]
    with pytest.warns(UserWarning, match="AUDUSD"):
        validate_symbol_registry_data(data)


def test_production_ready_false_when_spread_null(registry: SymbolRegistry) -> None:
    assert all(not registry.is_production_ready(canonical) for canonical in registry.canonicals())


def test_correlation_group_fallback_values(registry: SymbolRegistry) -> None:
    groups = {registry.correlation_group(canonical) for canonical in registry.canonicals()}
    assert groups == {"COMMODITY_FX", "EUROPE", "JPY", "METALS"}


def test_generated_python_symbols_match_registry(registry: SymbolRegistry) -> None:
    data = registry_data()
    contracts = generated_contracts()
    assert contracts.BROKER_TO_CANONICAL == data["brokers"]
    assert sorted(contracts.CANONICALS) == registry.canonicals()
    assert contracts.CANONICALS["XAUUSD"].risk.max_spread_points is None


def test_python_and_mql5_agree_on_every_mapping() -> None:
    data = registry_data()
    mql = (ROOT / "contracts" / "gen" / "mql5" / "FarmSymbols.mqh").read_text(
        encoding="utf-8"
    )
    for broker, mapping in data["brokers"].items():
        for raw, canonical in mapping.items():
            expected = (
                f'if(broker == "{broker}" && raw == "{raw}") '
                f'return "{canonical}";'
            )
            assert expected in mql


def test_codegen_is_deterministic_for_symbol_outputs() -> None:
    subprocess.run(["python", "tools/codegen.py"], cwd=ROOT, check=True, timeout=30)
    paths = [
        ROOT / "contracts" / "gen" / "python" / "symbols.py",
        ROOT / "contracts" / "gen" / "mql5" / "FarmSymbols.mqh",
    ]
    first = {path: path.read_bytes() for path in paths}
    subprocess.run(["python", "tools/codegen.py"], cwd=ROOT, check=True, timeout=30)
    second = {path: path.read_bytes() for path in paths}
    assert second == first


def test_codegen_check_detects_stale_symbols_gen() -> None:
    (ROOT / ".tmp-pytest").mkdir(exist_ok=True)
    temp_root = Path(tempfile.mkdtemp(prefix="symbols-codegen-check-", dir=ROOT / ".tmp-pytest"))
    temp_repo = temp_root / "repo"
    copy_codegen_workspace(temp_repo)
    subprocess.run(["git", "init"], cwd=temp_repo, check=True, capture_output=True, text=True)
    subprocess.run(["python", "tools/codegen.py"], cwd=temp_repo, check=True, timeout=30)
    subprocess.run(["git", "add", "contracts/gen"], cwd=temp_repo, check=True, text=True)
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
        text=True,
    )
    data = json.loads((temp_repo / "contracts" / "symbols.json").read_text(encoding="utf-8"))
    data["canonicals"]["EURUSD"]["max_spread_points"] = 25
    write_registry(temp_repo / "contracts" / "symbols.json", data)
    completed = subprocess.run(
        ["python", "tools/task.py", "codegen-check"],
        cwd=temp_repo,
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert completed.returncode != 0
