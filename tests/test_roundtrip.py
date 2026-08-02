from __future__ import annotations

import importlib
import json
import re
import subprocess
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast

import pytest
from pydantic import BaseModel

from brain.common.canonical_json import dumps_canonical_json

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "contracts" / "fixtures"
COMMON_FILES = Path(r"C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files")
MANIFEST_NAME = "ea-farm-rt-manifest-pytest.json"
RESULT_NAME = "ea-farm-IUX-TestRoundTrip-result.json"
OBSERVED_NAME = "ea-farm-IUX-TestRoundTrip-result-observed.json"
ROUNDTRIP_TEST_NAMES = [
    "test_roundtrip_all_types_full",
    "test_roundtrip_all_types_minimal",
    "test_canonical_json_identical_after_roundtrip",
    "test_no_scientific_notation_in_mql5_output",
    "test_null_value_absent_three_states_survive",
    "test_unknown_field_dropped_at_envelope",
    "test_unknown_field_dropped_in_payload",
    "test_unknown_field_dropped_in_nested_object",
    "test_large_int64_ticket_survives",
    "test_small_float_point_not_sci_notation",
    "test_thai_comment_survives_both_ways",
    "test_negative_zero_normalized",
    "test_stale_output_detected_when_ea_missing",
    "test_all_manifest_cases_processed",
    "test_git_sha_matches_head",
    "test_deterministic_across_two_runs",
    "test_malformed_input_fails_case_not_suite",
]
CONTRACTS: Any = importlib.import_module("farm_contracts")


pytestmark = pytest.mark.mql5


@dataclass(frozen=True)
class RoundTripCase:
    case_id: int
    name: str
    msg_type: str
    canonical: str
    input_name: str
    output_name: str
    input_json: str = ""
    expect_output: bool = True
    unknown_path: tuple[str, ...] = ()


@dataclass(frozen=True)
class RoundTripRun:
    cases: list[RoundTripCase]
    result: dict[str, Any]
    outputs: dict[int, str]
    stdout: str


def _payload_model(msg_type: str) -> type[BaseModel]:
    model = CONTRACTS.PAYLOAD_MODELS[msg_type]
    return cast(type[BaseModel], model)


def _load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(data, dict)
    return cast(dict[str, Any], data)


def _canonical_json(raw: str | dict[str, Any]) -> str:
    data = json.loads(raw) if isinstance(raw, str) else raw
    assert isinstance(data, dict)
    envelope = CONTRACTS.FarmEnvelope.model_validate(data)
    msg_type = str(envelope.type.value)
    payload = _payload_model(msg_type).model_validate(envelope.payload)
    canonical = {
        "v": envelope.v,
        "type": msg_type,
        "msg_id": envelope.msg_id,
        "session_id": envelope.session_id,
        "ts_server": envelope.ts_server,
        "ts_sent": envelope.ts_sent,
        "payload": payload.model_dump(mode="json", exclude_unset=True),
    }
    return dumps_canonical_json(canonical, sort_keys=True)


def _write_common_utf8(name: str, content: str) -> None:
    COMMON_FILES.mkdir(parents=True, exist_ok=True)
    (COMMON_FILES / name).write_text(content, encoding="utf-8", newline="\n")


def _read_common_utf8(name: str) -> str:
    return (COMMON_FILES / name).read_text(encoding="utf-8")


def _case_from_fixture(case_id: int, fixture: Path, *, prefix: str = "base") -> RoundTripCase:
    raw = fixture.read_text(encoding="utf-8")
    data = _load_json(fixture)
    msg_type = str(data["type"])
    input_name = f"ea-farm-rt-in-{prefix}-{case_id}.json"
    output_name = f"ea-farm-rt-out-{prefix}-{case_id}.json"
    canonical = _canonical_json(raw)
    _write_common_utf8(input_name, canonical)
    return RoundTripCase(
        case_id=case_id,
        name=fixture.name,
        msg_type=msg_type,
        canonical=canonical,
        input_name=input_name,
        output_name=output_name,
        input_json=canonical,
    )


def _with_nested_update(data: dict[str, Any], path: tuple[str, ...], value: Any) -> dict[str, Any]:
    updated = json.loads(dumps_canonical_json(data))
    target: Any = updated
    for key in path[:-1]:
        if key.endswith("]"):
            name, raw_index = key[:-1].split("[", maxsplit=1)
            target = target[name][int(raw_index)]
        else:
            target = target[key]
    target[path[-1]] = value
    return cast(dict[str, Any], updated)


def _special_cases(start_id: int) -> list[RoundTripCase]:
    cases: list[RoundTripCase] = []
    state = _load_json(FIXTURE_DIR / "state.valid.json")
    exec_report = _load_json(FIXTURE_DIR / "exec_report.valid.json")
    hello = _load_json(FIXTURE_DIR / "hello.valid.json")

    variants: list[tuple[str, dict[str, Any], dict[str, Any], tuple[str, ...]]] = [
        (
            "unknown-envelope",
            json.loads(_canonical_json(hello)),
            {**json.loads(_canonical_json(hello)), "__probe_unknown__": 12345},
            ("__probe_unknown__",),
        ),
        (
            "unknown-payload",
            json.loads(_canonical_json(hello)),
            _with_nested_update(
                json.loads(_canonical_json(hello)),
                ("payload", "__probe_unknown__"),
                12345,
            ),
            ("payload", "__probe_unknown__"),
        ),
        (
            "unknown-nested",
            json.loads(_canonical_json(hello)),
            _with_nested_update(
                json.loads(_canonical_json(hello)),
                ("payload", "account", "__probe_unknown__"),
                12345,
            ),
            ("payload", "account", "__probe_unknown__"),
        ),
        (
            "large-ticket",
            _with_nested_update(
                json.loads(_canonical_json(state)),
                ("payload", "positions[0]", "ticket"),
                9007199254740993,
            ),
            _with_nested_update(
                json.loads(_canonical_json(state)),
                ("payload", "positions[0]", "ticket"),
                9007199254740993,
            ),
            (),
        ),
        (
            "thai-comment",
            _with_nested_update(
                json.loads(_canonical_json(state)),
                ("payload", "positions[0]", "comment"),
                "ทดสอบคำสั่ง",
            ),
            _with_nested_update(
                json.loads(_canonical_json(state)),
                ("payload", "positions[0]", "comment"),
                "ทดสอบคำสั่ง",
            ),
            (),
        ),
        (
            "negative-zero",
            _with_nested_update(
                json.loads(_canonical_json(exec_report)),
                ("payload", "swap"),
                -0.0,
            ),
            _with_nested_update(
                json.loads(_canonical_json(exec_report)),
                ("payload", "swap"),
                -0.0,
            ),
            (),
        ),
    ]
    for offset, (name, expected_data, input_data, unknown_path) in enumerate(variants):
        case_id = start_id + offset
        canonical = _canonical_json(expected_data)
        input_json = dumps_canonical_json(input_data, sort_keys=True)
        input_name = f"ea-farm-rt-in-special-{case_id}.json"
        output_name = f"ea-farm-rt-out-special-{case_id}.json"
        _write_common_utf8(input_name, input_json)
        cases.append(
            RoundTripCase(
                case_id=case_id,
                name=name,
                msg_type=str(json.loads(canonical)["type"]),
                canonical=canonical,
                input_name=input_name,
                output_name=output_name,
                input_json=input_json,
                unknown_path=unknown_path,
            )
        )
    malformed_id = start_id + len(variants)
    malformed_in = f"ea-farm-rt-in-special-{malformed_id}.json"
    malformed_out = f"ea-farm-rt-out-special-{malformed_id}.json"
    _write_common_utf8(malformed_in, '{"v":1,"type":"HELLO","payload":')
    cases.append(
        RoundTripCase(
            case_id=malformed_id,
            name="malformed-input",
            msg_type="HELLO",
            canonical="",
            input_name=malformed_in,
            output_name=malformed_out,
            input_json='{"v":1,"type":"HELLO","payload":',
            expect_output=False,
        )
    )
    return cases


def _all_cases(prefix: str) -> list[RoundTripCase]:
    full = sorted(FIXTURE_DIR.glob("*.valid.json"))
    minimal = sorted(FIXTURE_DIR.glob("*.valid.min.json"))
    fixtures = [*full, *minimal]
    cases = [_case_from_fixture(i + 1, path, prefix=prefix) for i, path in enumerate(fixtures)]
    cases.extend(_special_cases(len(cases) + 1))
    return cases


def _prepare_manifest(cases: list[RoundTripCase]) -> None:
    stale_names = [RESULT_NAME, OBSERVED_NAME, *[case.output_name for case in cases]]
    for name in stale_names:
        path = COMMON_FILES / name
        if path.exists():
            path.unlink()
    manifest = {
        "cases": [
            {
                "id": case.case_id,
                "type": case.msg_type,
                "in": case.input_name,
                "out": case.output_name,
            }
            for case in cases
        ]
    }
    _write_common_utf8(MANIFEST_NAME, dumps_canonical_json(manifest))


def _run_mql5_roundtrip(prefix: str) -> RoundTripRun:
    cases = _all_cases(prefix)
    _prepare_manifest(cases)
    completed = subprocess.run(
        [
            "powershell",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "tools/run-mql5-tests.ps1",
            "-RoundTripManifest",
            MANIFEST_NAME,
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=7200,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    result = json.loads(_read_common_utf8(RESULT_NAME))
    outputs = {
        case.case_id: _read_common_utf8(case.output_name)
        for case in cases
        if case.expect_output and (COMMON_FILES / case.output_name).exists()
    }
    return RoundTripRun(
        cases=cases,
        result=cast(dict[str, Any], result),
        outputs=outputs,
        stdout=completed.stdout,
    )


@pytest.fixture(scope="session")
def roundtrip_run() -> Iterator[RoundTripRun]:
    yield _run_mql5_roundtrip("run1")


def _valid_cases(run: RoundTripRun, suffix: str) -> list[RoundTripCase]:
    return [case for case in run.cases if case.name.endswith(suffix)]


def _assert_case_output(run: RoundTripRun, case: RoundTripCase) -> str:
    if not case.expect_output:
        assert case.case_id not in run.outputs, f"{case.name}: unexpected output {case.output_name}"
        pytest.fail(f"{case.name}: test requested output from no-output case")
    assert case.case_id in run.outputs, f"{case.name}: missing output {case.output_name}"
    return run.outputs[case.case_id]


def _assert_canonical_match(run: RoundTripRun, case: RoundTripCase) -> None:
    raw = _assert_case_output(run, case)
    actual = _canonical_json(raw)
    assert actual == case.canonical, _field_diff(case.canonical, actual, case.name)
    _assert_business_invariants(json.loads(actual), case.name)


def _assert_business_invariants(data: dict[str, Any], label: str) -> None:
    payload = cast(dict[str, Any], data["payload"])
    msg_type = data["type"]
    if msg_type == "BAR":
        assert payload["low"] <= payload["open"] <= payload["high"], label
        assert payload["low"] <= payload["close"] <= payload["high"], label
        assert payload["spread_points_avg"] <= payload["spread_points_max"], label
    if msg_type == "STATE":
        positions = cast(list[dict[str, Any]], payload["positions"])
        owned_net: dict[str, float] = {}
        ticket_count: dict[str, int] = {}
        sides_by_symbol: dict[str, set[str]] = {}
        for pos in positions:
            signed = pos["volume"] if pos["side"] == "BUY" else -pos["volume"]
            owned_net[pos["symbol"]] = owned_net.get(pos["symbol"], 0.0) + signed
            ticket_count[pos["symbol"]] = ticket_count.get(pos["symbol"], 0) + 1
            sides_by_symbol.setdefault(pos["symbol"], set()).add(pos["side"])
        for symbol, volume in cast(dict[str, float], payload["owned_net"]).items():
            assert abs(volume - owned_net.get(symbol, 0.0)) < 1e-9, label
        for symbol, count in cast(dict[str, int], payload["owned_ticket_count"]).items():
            assert count == ticket_count.get(symbol, 0), label
        expected_hedge = any({"BUY", "SELL"} <= sides for sides in sides_by_symbol.values())
        assert payload["guard"]["internal_hedge_detected"] is expected_hedge, label
    if msg_type == "EXEC_REPORT":
        result = payload["result"]
        if result == "FILLED":
            assert payload["volume_filled"] == payload["volume_requested"], label
            assert payload["ticket"] is not None, label
        if result == "REJECTED":
            assert payload["volume_filled"] == 0, label
        if result == "PARTIAL":
            assert 0 < payload["volume_filled"] < payload["volume_requested"], label
    if msg_type == "RISK_DIRECTIVE":
        if payload["mode"] == "SCALED":
            assert payload["scale_factor"] < 1.0, label
        if payload["mode"] == "HALT":
            assert payload["expires_at"] is None, label
    if msg_type == "ERROR":
        assert payload["fatal"] is (payload["severity"] == "FATAL"), label


def _field_diff(expected_json: str, actual_json: str, label: str) -> str:
    expected = json.loads(expected_json)
    actual = json.loads(actual_json)
    diffs: list[str] = []

    def walk(path: str, left: Any, right: Any) -> None:
        if isinstance(left, dict) and isinstance(right, dict):
            for key in sorted(set(left) | set(right)):
                if key not in left:
                    diffs.append(f"{path}.{key}: missing before, after={right[key]!r}")
                elif key not in right:
                    diffs.append(f"{path}.{key}: before={left[key]!r}, missing after")
                else:
                    walk(f"{path}.{key}", left[key], right[key])
        elif isinstance(left, list) and isinstance(right, list):
            if len(left) != len(right):
                diffs.append(f"{path}: before len={len(left)}, after len={len(right)}")
            for index, (l_item, r_item) in enumerate(zip(left, right, strict=False)):
                walk(f"{path}[{index}]", l_item, r_item)
        elif left != right:
            diffs.append(f"{path}: before={left!r}, after={right!r}")

    walk("$", expected, actual)
    return f"{label} round-trip mismatch:\n" + "\n".join(diffs[:20])


def _contains_path(data: dict[str, Any], path: tuple[str, ...]) -> bool:
    target: Any = data
    for key in path:
        if not isinstance(target, dict) or key not in target:
            return False
        target = target[key]
    return True


def _raw_numbers(raw: str) -> list[str]:
    pattern = r"(?<![A-Za-z0-9_])[-]?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"
    return re.findall(pattern, raw)


def test_roundtrip_all_types_full(roundtrip_run: RoundTripRun) -> None:
    cases = _valid_cases(roundtrip_run, ".valid.json")
    assert len(cases) == 12
    assert sorted({case.msg_type for case in cases}) == sorted(CONTRACTS.PAYLOAD_MODELS)
    for case in cases:
        _assert_canonical_match(roundtrip_run, case)


def test_roundtrip_all_types_minimal(roundtrip_run: RoundTripRun) -> None:
    cases = _valid_cases(roundtrip_run, ".valid.min.json")
    assert len(cases) == 12
    assert sorted({case.msg_type for case in cases}) == sorted(CONTRACTS.PAYLOAD_MODELS)
    for case in cases:
        _assert_canonical_match(roundtrip_run, case)


def test_canonical_json_identical_after_roundtrip(roundtrip_run: RoundTripRun) -> None:
    for case in roundtrip_run.cases:
        if case.expect_output and not case.unknown_path:
            _assert_canonical_match(roundtrip_run, case)


def test_no_scientific_notation_in_mql5_output(roundtrip_run: RoundTripRun) -> None:
    for case in roundtrip_run.cases:
        if not case.expect_output:
            continue
        raw = _assert_case_output(roundtrip_run, case)
        bad = [number for number in _raw_numbers(raw) if "e" in number.lower()]
        assert not bad, f"{case.name}: scientific notation in MQL5 output: {bad}"


def test_null_value_absent_three_states_survive(roundtrip_run: RoundTripRun) -> None:
    cases = {
        case.name: json.loads(_assert_case_output(roundtrip_run, case))
        for case in roundtrip_run.cases
        if case.expect_output
    }
    state_full = next(value for name, value in cases.items() if name == "state.valid.json")
    state_min = next(value for name, value in cases.items() if name == "state.valid.min.json")
    position = state_full["payload"]["positions"][0]
    pending = state_full["payload"]["pending_orders"][0]
    assert position["sl"] is None or position["sl"] > 0
    assert "sl" in pending
    assert pending["sl"] is None
    assert "halt_reason" in state_full["payload"]["guard"]
    assert state_full["payload"]["guard"]["halt_reason"] is None
    assert "halt_reason" not in state_min["payload"]["guard"]


def test_unknown_field_dropped_at_envelope(roundtrip_run: RoundTripRun) -> None:
    case = next(case for case in roundtrip_run.cases if case.name == "unknown-envelope")
    raw = json.loads(_assert_case_output(roundtrip_run, case))
    assert not _contains_path(raw, case.unknown_path), f"{case.name}: unknown field survived"


def test_unknown_field_dropped_in_payload(roundtrip_run: RoundTripRun) -> None:
    case = next(case for case in roundtrip_run.cases if case.name == "unknown-payload")
    raw = json.loads(_assert_case_output(roundtrip_run, case))
    assert not _contains_path(raw, case.unknown_path), f"{case.name}: unknown field survived"


def test_unknown_field_dropped_in_nested_object(roundtrip_run: RoundTripRun) -> None:
    case = next(case for case in roundtrip_run.cases if case.name == "unknown-nested")
    raw = json.loads(_assert_case_output(roundtrip_run, case))
    assert not _contains_path(raw, case.unknown_path), f"{case.name}: unknown field survived"


def test_large_int64_ticket_survives(roundtrip_run: RoundTripRun) -> None:
    case = next(case for case in roundtrip_run.cases if case.name == "large-ticket")
    raw = json.loads(_assert_case_output(roundtrip_run, case))
    assert raw["payload"]["positions"][0]["ticket"] == 9007199254740993


def test_small_float_point_not_sci_notation(roundtrip_run: RoundTripRun) -> None:
    case = next(case for case in roundtrip_run.cases if case.name == "hello.valid.json")
    raw = _assert_case_output(roundtrip_run, case)
    assert '"point":0.00001' in raw
    assert "1e-05" not in raw.lower()


def test_thai_comment_survives_both_ways(roundtrip_run: RoundTripRun) -> None:
    case = next(case for case in roundtrip_run.cases if case.name == "thai-comment")
    raw = json.loads(_assert_case_output(roundtrip_run, case))
    assert raw["payload"]["positions"][0]["comment"] == "ทดสอบคำสั่ง"


def test_negative_zero_normalized(roundtrip_run: RoundTripRun) -> None:
    case = next(case for case in roundtrip_run.cases if case.name == "negative-zero")
    raw = _assert_case_output(roundtrip_run, case)
    assert '"swap":0.0' in raw
    assert '"swap":-0.0' not in raw


def test_stale_output_detected_when_ea_missing() -> None:
    case = RoundTripCase(999, "stale", "HELLO", "{}", "stale-in.json", "stale-out.json")
    stale = COMMON_FILES / case.output_name
    COMMON_FILES.mkdir(parents=True, exist_ok=True)
    stale.write_text('{"stale":true}', encoding="utf-8")
    _prepare_manifest([case])
    assert not stale.exists()
    assert not (COMMON_FILES / RESULT_NAME).exists()


def test_all_manifest_cases_processed(roundtrip_run: RoundTripRun) -> None:
    assert roundtrip_run.result["cases_processed"] == len(roundtrip_run.cases)


def test_git_sha_matches_head(roundtrip_run: RoundTripRun) -> None:
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    assert roundtrip_run.result["git_sha"] == head


def test_deterministic_across_two_runs(roundtrip_run: RoundTripRun) -> None:
    second = _run_mql5_roundtrip("run2")
    first_outputs = {
        case.name: roundtrip_run.outputs[case.case_id]
        for case in roundtrip_run.cases
        if case.expect_output
    }
    second_outputs = {
        case.name: second.outputs[case.case_id]
        for case in second.cases
        if case.expect_output
    }
    assert second_outputs == first_outputs


def test_malformed_input_fails_case_not_suite(roundtrip_run: RoundTripRun) -> None:
    malformed = next(case for case in roundtrip_run.cases if case.name == "malformed-input")
    assert malformed.case_id not in roundtrip_run.outputs
    assert not (COMMON_FILES / malformed.output_name).exists()
    failures = roundtrip_run.result["case_failures"]
    assert any("malformed" in item or malformed.input_name in item for item in failures)
    assert roundtrip_run.result["status"] == "PASS"
    assert roundtrip_run.result["failed"] == 0
