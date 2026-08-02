#property strict
#define FARM_TEST

#include <Farm/FarmMessages.mqh>

input string InpTestGitSha = "unknown";
input string InpTestResultFile = "ea-farm-TestFarmMessages-result.json";
input string InpFixtureDir = "ea-farm-fixtures";

int    g_total = 0;
int    g_failed = 0;
string g_ran_names[];
string g_failed_names[];

void RecordRan(const string name)
{
   const int count = ArraySize(g_ran_names);
   ArrayResize(g_ran_names, count + 1);
   g_ran_names[count] = name;
}

void RecordFailure(const string name)
{
   const int count = ArraySize(g_failed_names);
   ArrayResize(g_failed_names, count + 1);
   g_failed_names[count] = name;
}

void AssertTrue(const bool condition, const string name)
{
   g_total++;
   if(condition)
      Print("PASS ", name);
   else
   {
      Print("FAIL ", name, " err=", FarmJsonLastError());
      g_failed++;
      RecordFailure(name);
   }
}

void AssertEqualString(const string actual, const string expected, const string name)
{
   AssertTrue(actual == expected, name + " actual=" + actual + " expected=" + expected);
}

bool ReadCommonUtf8(const string filename, string &out)
{
   out = "";
   const int handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return false;
   const int size = (int)FileSize(handle);
   uchar bytes[];
   ArrayResize(bytes, size + 1);
   const uint read = FileReadArray(handle, bytes, 0, size);
   FileClose(handle);
   if(read != (uint)size)
      return false;
   bytes[size] = 0;
   out = CharArrayToString(bytes, 0, size, CP_UTF8);
   while(StringLen(out) > 0)
   {
      const ushort ch = StringGetCharacter(out, StringLen(out) - 1);
      if(ch != '\n' && ch != '\r')
         break;
      out = StringSubstr(out, 0, StringLen(out) - 1);
   }
   return true;
}

string FixturePath(const string filename)
{
   return InpFixtureDir + "\\" + filename;
}

bool ValidateEnvelopeAndPayload(const string json)
{
   FarmEnvelope env;
   if(!FarmParseEnvelope(json, env))
      return false;
   CFarmJsonDoc doc;
   if(!doc.Parse(env.payload_json))
      return false;
   const bool ok = FarmValidatePayload(env.type, doc.Root());
   doc.Free();
   return ok;
}

bool RoundTripEnvelope(const string json)
{
   FarmEnvelope first;
   FarmEnvelope second;
   string encoded = "";
   if(!FarmParseEnvelope(json, first))
      return false;
   if(!FarmSerializeEnvelope(first, encoded))
      return false;
   if(!FarmParseEnvelope(encoded, second))
      return false;
   return first.v == second.v
          && first.type == second.type
          && first.type_raw == second.type_raw
          && first.msg_id == second.msg_id
          && first.session_id == second.session_id
          && first.ts_server == second.ts_server
          && first.ts_sent == second.ts_sent
          && first.payload_json == second.payload_json;
}

void test_roundtrip_all_valid_fixtures()
{
   string names[] = {
      "bar.valid.extra.json","bar.valid.json","bar.valid.min.json",
      "config_update.valid.extra.json","config_update.valid.json","config_update.valid.min.json",
      "error.valid.extra.json","error.valid.json","error.valid.min.json",
      "exec_report.valid.extra.json","exec_report.valid.json","exec_report.valid.min.json",
      "heartbeat.valid.extra.json","heartbeat.valid.json","heartbeat.valid.min.json",
      "heartbeat_ack.valid.extra.json","heartbeat_ack.valid.json","heartbeat_ack.valid.min.json",
      "hello.valid.extra.json","hello.valid.json","hello.valid.min.json",
      "hello_ack.valid.extra.json","hello_ack.valid.json","hello_ack.valid.min.json",
      "intent.valid.extra.json","intent.valid.json","intent.valid.min.json",
      "intent_ack.valid.extra.json","intent_ack.valid.json","intent_ack.valid.min.json",
      "risk_directive.valid.extra.json","risk_directive.valid.json","risk_directive.valid.min.json",
      "state.valid.extra.json","state.valid.json","state.valid.min.json"
   };

   bool ok = true;
   int read_count = 0;
   for(int i = 0; i < ArraySize(names); i++)
   {
      string raw = "";
      if(!ReadCommonUtf8(FixturePath(names[i]), raw))
      {
         ok = false;
         continue;
      }
      read_count++;
      if(!RoundTripEnvelope(raw) || !ValidateEnvelopeAndPayload(raw))
         ok = false;
   }
   string invalid_names[] = {
      "invalid__bar.is_final_false.json",
      "invalid__config_update.unknown_setting.json",
      "invalid__envelope.msgid_18digits.json",
      "invalid__envelope.session_period_prefix.json",
      "invalid__envelope.ts_offset_not_z.json",
      "invalid__hello.margin_mode_lowercase.json",
      "invalid__risk_directive.scale_above_one.json",
      "invalid__state.owned_net_bad_symbol_key.json",
      "invalid__state.sl_zero.json"
   };
   int invalid_read_count = 0;
   for(int i = 0; i < ArraySize(invalid_names); i++)
   {
      string raw = "";
      if(!ReadCommonUtf8(FixturePath(invalid_names[i]), raw))
      {
         ok = false;
         continue;
      }
      invalid_read_count++;
      if(ValidateEnvelopeAndPayload(raw))
         ok = false;
   }
   AssertTrue(read_count == 36 && invalid_read_count == 9 && ok, "test_roundtrip_all_valid_fixtures");
}

void test_parse_state_with_nested_positions()
{
   const string p = "{\"balance\":1.0,\"equity\":1.0,\"margin_used\":0.0,\"margin_free\":1.0,\"margin_level_pct\":null,\"equity_hwm\":1.0,\"day_start_equity\":1.0,\"day_pl\":0.0,\"day_pl_pct\":0.0,\"positions\":[{\"ticket\":1,\"symbol\":\"EURUSD.iux\",\"side\":\"BUY\",\"volume\":0.1,\"price_open\":1.1,\"sl\":1.0,\"tp\":null,\"profit\":0.0,\"swap\":0.0,\"magic\":770001,\"time_open\":\"2026-07-26T14:30:00Z\"},{\"ticket\":2,\"symbol\":\"EURUSD.iux\",\"side\":\"SELL\",\"volume\":0.1,\"price_open\":1.2,\"sl\":1.3,\"tp\":null,\"profit\":0.0,\"swap\":0.0,\"magic\":770001,\"time_open\":\"2026-07-26T14:30:00Z\"},{\"ticket\":3,\"symbol\":\"XAUUSD\",\"side\":\"BUY\",\"volume\":0.1,\"price_open\":2000.0,\"sl\":1990.0,\"tp\":null,\"profit\":0.0,\"swap\":0.0,\"magic\":770001,\"time_open\":\"2026-07-26T14:30:00Z\"}],\"pending_orders\":[],\"owned_net\":{\"EURUSD.iux\":0.0},\"owned_ticket_count\":{\"EURUSD.iux\":2},\"foreign_positions\":{\"count\":0,\"symbols\":[],\"total_volume\":0.0,\"margin_estimate\":0.0},\"account_margin_mode\":\"RETAIL_HEDGING\",\"guard\":{\"halted\":false,\"mode\":\"NORMAL\",\"current_spread_points\":1,\"internal_hedge_detected\":true}}";
   FarmStatePayload state;
   AssertTrue(FarmParseState(p, state), "test_parse_state_with_nested_positions");
}

bool ReadFixturePayload(const string filename, string &payload_json)
{
   string raw = "";
   FarmEnvelope env;
   payload_json = "";
   if(!ReadCommonUtf8(FixturePath(filename), raw))
      return false;
   if(!FarmParseEnvelope(raw, env))
      return false;
   payload_json = env.payload_json;
   return true;
}

void test_typed_parse_all_payload_fixtures_reads_fields()
{
   bool ok = true;
   string p = "";

   FarmHelloPayload hello;
   ok = ok && ReadFixturePayload("hello.valid.json", p)
        && FarmParseHello(p, hello)
        && hello.token == "demo-token"
        && hello.account.login == 8123456
        && hello.symbol.name == "EURUSD.iux"
        && hello.broker_time_present
        && hello.broker_time.utc_offset_sec == 10800;

   FarmHelloAckPayload hello_ack;
   ok = ok && ReadFixturePayload("hello_ack.valid.json", p)
        && FarmParseHelloAck(p, hello_ack)
        && hello_ack.accepted
        && hello_ack.brain_version == "1.0.0"
        && hello_ack.initial_directive_present
        && hello_ack.initial_directive.scale_factor == 1.0;

   FarmHeartbeatPayload heartbeat;
   ok = ok && ReadFixturePayload("heartbeat.valid.json", p)
        && FarmParseHeartbeat(p, heartbeat)
        && heartbeat.seq == 1
        && heartbeat.wire.send_queue_depth == 1
        && heartbeat.wire.pump_p99_us == 1;

   FarmHeartbeatAckPayload heartbeat_ack;
   ok = ok && ReadFixturePayload("heartbeat_ack.valid.json", p)
        && FarmParseHeartbeatAck(p, heartbeat_ack)
        && heartbeat_ack.seq == 1
        && heartbeat_ack.brain_healthy;

   FarmBarPayload bar;
   ok = ok && ReadFixturePayload("bar.valid.json", p)
        && FarmParseBar(p, bar)
        && bar.symbol == "EURUSD.iux"
        && bar.close == 1.16901
        && bar.is_final;

   FarmStatePayload state;
   ok = ok && ReadFixturePayload("state.valid.json", p)
        && FarmParseState(p, state)
        && state.balance == 10000.0
        && ArraySize(state.positions) == 1
        && state.positions[0].symbol == "EURUSD.iux"
        && ArraySize(state.owned_net_keys) == 1
        && state.guard.current_spread_points == 12;

   FarmIntentPayload intent;
   ok = ok && ReadFixturePayload("intent.valid.json", p)
        && FarmParseIntent(p, intent)
        && intent.intent_id == "01J8X4K2P9QZ7M3N4R5T6V7W8X"
        && intent.symbol == "EURUSD.iux"
        && intent.provenance.strategy_id == "trend_v1";

   FarmIntentAckPayload intent_ack;
   ok = ok && ReadFixturePayload("intent_ack.valid.json", p)
        && FarmParseIntentAck(p, intent_ack)
        && intent_ack.intent_id == "01J8X4K2P9QZ7M3N4R5T6V7W8X"
        && intent_ack.overshoot_volume == 1.0
        && ArraySize(intent_ack.actions_planned) == 1
        && intent_ack.actions_planned[0].ticket == 1;

   FarmExecReportPayload exec_report;
   ok = ok && ReadFixturePayload("exec_report.valid.json", p)
        && FarmParseExecReport(p, exec_report)
        && exec_report.retcode == 10009
        && exec_report.ticket_present
        && IntegerToString(exec_report.ticket) == "9007199254740993"
        && exec_report.volume_filled == 0.1;

   FarmRiskDirectivePayload risk_directive;
   ok = ok && ReadFixturePayload("risk_directive.valid.json", p)
        && FarmParseRiskDirective(p, risk_directive)
        && risk_directive.directive_id == "01J8X4K2P9QZ7M3N4R5T6V7W8X"
        && risk_directive.scale_factor == 1.0
        && ArraySize(risk_directive.flatten_symbols) == 1;

   FarmConfigUpdatePayload config_update;
   ok = ok && ReadFixturePayload("config_update.valid.json", p)
        && FarmParseConfigUpdate(p, config_update)
        && config_update.config_id == "01J8X4K2P9QZ7M3N4R5T6V7W8X"
        && config_update.settings.heartbeat_sec_present
        && config_update.settings.heartbeat_sec == 2;

   FarmErrorPayload error;
   ok = ok && ReadFixturePayload("error.valid.json", p)
        && FarmParseError(p, error)
        && error.code == "BAD_REQUEST"
        && error.message == "value"
        && !error.fatal
        && ArraySize(error.context_keys) == 0;

   AssertTrue(ok, "test_typed_parse_all_payload_fixtures_reads_fields");
}

void test_parse_duplicate_key_in_nested_object()
{
   CFarmJsonDoc doc;
   const bool ok = doc.Parse("{\"symbol\":\"outer\",\"nested\":{\"symbol\":\"inner\"}}");
   CFarmJsonValue *root = doc.Root();
   CFarmJsonValue *nested = (root == NULL ? NULL : root.Get("nested"));
   CFarmJsonValue *inner = (nested == NULL ? NULL : nested.Get("symbol"));
   AssertTrue(ok && root.Get("symbol").string_value == "outer" && inner.string_value == "inner", "test_parse_duplicate_key_in_nested_object");
   doc.Free();
}

void test_parse_string_containing_key_like_text()
{
   CFarmJsonDoc doc;
   const bool ok = doc.Parse("{\"comment\":\"sl:1.0800\",\"sl\":1.1}");
   CFarmJsonValue *root = doc.Root();
   AssertTrue(ok && root.Get("comment").string_value == "sl:1.0800" && root.Get("sl").number_value == 1.1, "test_parse_string_containing_key_like_text");
   doc.Free();
}

void test_parse_ignores_unknown_field()
{
   string raw = "";
   AssertTrue(ReadCommonUtf8(FixturePath("hello.valid.extra.json"), raw) && ValidateEnvelopeAndPayload(raw), "test_parse_ignores_unknown_field");
}

void test_parse_fails_on_missing_required_names_field()
{
   const string p = "{\"balance\":1.0,\"equity\":1.0}";
   FarmStatePayload state;
   const bool ok = FarmParseState(p, state);
   AssertTrue(!ok && StringFind(FarmJsonLastError(), "positions") >= 0, "test_parse_fails_on_missing_required_names_field");
}

void test_unknown_envelope_type_yields_UNKNOWN_not_error()
{
   const string json = "{\"v\":1,\"type\":\"FUTURE\",\"msg_id\":\"01J8X4K2P9QZ7M3N4R5T6V7W8X\",\"session_id\":\"acct-8123456-EURUSD.iux-H1\",\"ts_server\":\"2026-07-26T14:30:00Z\",\"ts_sent\":\"2026-07-26T14:30:00Z\",\"payload\":{}}";
   FarmEnvelope env;
   AssertTrue(FarmParseEnvelope(json, env) && env.type == FARM_MSG_UNKNOWN && env.type_raw == "FUTURE", "test_unknown_envelope_type_yields_UNKNOWN_not_error");
}

void test_null_vs_value_vs_absent()
{
   FarmStatePayload state_null;
   FarmStatePayload state_value;
   const string base1 = "{\"balance\":1.0,\"equity\":1.0,\"margin_used\":0.0,\"margin_free\":1.0,\"margin_level_pct\":null,\"equity_hwm\":1.0,\"day_start_equity\":1.0,\"day_pl\":0.0,\"day_pl_pct\":0.0,\"positions\":[],\"pending_orders\":[],\"owned_net\":{},\"owned_ticket_count\":{},\"foreign_positions\":{\"count\":0,\"symbols\":[],\"total_volume\":0.0,\"margin_estimate\":0.0},\"account_margin_mode\":\"RETAIL_HEDGING\",\"guard\":{\"halted\":false,\"mode\":\"NORMAL\",\"current_spread_points\":1,\"internal_hedge_detected\":false}}";
   const string base2 = "{\"balance\":1.0,\"equity\":1.0,\"margin_used\":0.0,\"margin_free\":1.0,\"margin_level_pct\":100.0,\"equity_hwm\":1.0,\"day_start_equity\":1.0,\"day_pl\":0.0,\"day_pl_pct\":0.0,\"positions\":[],\"pending_orders\":[],\"owned_net\":{},\"owned_ticket_count\":{},\"foreign_positions\":{\"count\":0,\"symbols\":[],\"total_volume\":0.0,\"margin_estimate\":0.0},\"account_margin_mode\":\"RETAIL_HEDGING\",\"guard\":{\"halted\":false,\"mode\":\"NORMAL\",\"current_spread_points\":1,\"internal_hedge_detected\":false}}";
   const string absent = "{\"balance\":1.0,\"equity\":1.0,\"positions\":[]}";
   FarmStatePayload state_absent;
   AssertTrue(FarmParseState(base1, state_null)
              && state_null.margin_level_pct_is_null
              && FarmParseState(base2, state_value)
              && !state_value.margin_level_pct_is_null
              && state_value.margin_level_pct == 100.0
              && !FarmParseState(absent, state_absent), "test_null_vs_value_vs_absent");
}

void test_serialize_null_emits_null_not_zero()
{
   FarmStatePayload state;
   string out = "";
   const string json = "{\"balance\":1.0,\"equity\":1.0,\"margin_used\":0.0,\"margin_free\":1.0,\"margin_level_pct\":null,\"equity_hwm\":1.0,\"day_start_equity\":1.0,\"day_pl\":0.0,\"day_pl_pct\":0.0,\"positions\":[],\"pending_orders\":[],\"owned_net\":{},\"owned_ticket_count\":{},\"foreign_positions\":{\"count\":0,\"symbols\":[],\"total_volume\":0.0,\"margin_estimate\":0.0},\"account_margin_mode\":\"RETAIL_HEDGING\",\"guard\":{\"halted\":false,\"mode\":\"NORMAL\",\"current_spread_points\":1,\"internal_hedge_detected\":false}}";
   AssertTrue(FarmParseState(json, state) && FarmSerializeState(state, out) && StringFind(out, "\"margin_level_pct\":null") >= 0, "test_serialize_null_emits_null_not_zero");
}

void test_serialize_no_scientific_notation()
{
   const string a = FarmJsonFormatDouble(0.00001);
   const string b = FarmJsonFormatDouble(100000.0);
   AssertTrue(a == "0.00001" && b == "100000.0" && StringFind(a, "e") < 0 && StringFind(a, "E") < 0, "test_serialize_no_scientific_notation");
}

void test_serialize_escapes_and_utf8_thai_roundtrip()
{
   const string text = "ไทย \"quote\" \\ slash";
   const string json = FarmJsonQuoteUtf8(text);
   CFarmJsonDoc doc;
   AssertTrue(doc.Parse(json) && doc.Root().string_value == text && StringFind(json, "\\u0E") < 0, "test_serialize_escapes_and_utf8_thai_roundtrip");
   doc.Free();
}

void test_depth_limit_rejected_at_33()
{
   string json = "";
   for(int i = 0; i < 33; i++) json += "[";
   json += "null";
   for(int i = 0; i < 33; i++) json += "]";
   CFarmJsonDoc doc;
   AssertTrue(!doc.Parse(json) && StringFind(FarmJsonLastError(), "DEPTH_LIMIT") >= 0, "test_depth_limit_rejected_at_33");
   doc.Free();
}

void RunAllTests()
{
   RecordRan("test_roundtrip_all_valid_fixtures"); test_roundtrip_all_valid_fixtures();
   RecordRan("test_parse_state_with_nested_positions"); test_parse_state_with_nested_positions();
   RecordRan("test_typed_parse_all_payload_fixtures_reads_fields"); test_typed_parse_all_payload_fixtures_reads_fields();
   RecordRan("test_parse_duplicate_key_in_nested_object"); test_parse_duplicate_key_in_nested_object();
   RecordRan("test_parse_string_containing_key_like_text"); test_parse_string_containing_key_like_text();
   RecordRan("test_parse_ignores_unknown_field"); test_parse_ignores_unknown_field();
   RecordRan("test_parse_fails_on_missing_required_names_field"); test_parse_fails_on_missing_required_names_field();
   RecordRan("test_unknown_envelope_type_yields_UNKNOWN_not_error"); test_unknown_envelope_type_yields_UNKNOWN_not_error();
   RecordRan("test_null_vs_value_vs_absent"); test_null_vs_value_vs_absent();
   RecordRan("test_serialize_null_emits_null_not_zero"); test_serialize_null_emits_null_not_zero();
   RecordRan("test_serialize_no_scientific_notation"); test_serialize_no_scientific_notation();
   RecordRan("test_serialize_escapes_and_utf8_thai_roundtrip"); test_serialize_escapes_and_utf8_thai_roundtrip();
   RecordRan("test_depth_limit_rejected_at_33"); test_depth_limit_rejected_at_33();
}

bool WriteUtf8File(const string filename, const string content)
{
   uchar bytes[];
   int n = StringToCharArray(content, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   if(n < 0)
      return false;
   if(n > 0 && bytes[n - 1] == 0)
      n--;

   const int handle = FileOpen(filename, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      Print("FAIL could_not_write_result_file err=", GetLastError(), " file=", filename);
      return false;
   }

   const uint written = FileWriteArray(handle, bytes, 0, n);
   FileClose(handle);
   return (written == (uint)n);
}

string JsonStringArray(string &items[])
{
   string out = "[";
   for(int i = 0; i < ArraySize(items); i++)
   {
      if(i > 0)
         out += ",";
      out += FarmJsonQuoteUtf8(items[i]);
   }
   out += "]";
   return out;
}

void WriteJsonResult()
{
   string json = "{";
   json += "\"suite\":\"TestFarmMessages\",";
   json += "\"git_sha\":" + FarmJsonQuoteUtf8(InpTestGitSha) + ",";
   json += "\"status\":" + FarmJsonQuoteUtf8(g_failed == 0 ? "PASS" : "FAIL") + ",";
   json += "\"started_at\":\"tester\",";
   json += "\"total\":" + IntegerToString(g_total) + ",";
   json += "\"passed\":" + IntegerToString(g_total - g_failed) + ",";
   json += "\"failed\":" + IntegerToString(g_failed) + ",";
   json += "\"ran_names\":" + JsonStringArray(g_ran_names) + ",";
   json += "\"failed_names\":" + JsonStringArray(g_failed_names);
   json += "}";
   WriteUtf8File(InpTestResultFile, json);
}

int OnInit()
{
   RunAllTests();
   WriteJsonResult();
   if(g_failed > 0)
      Print("FAILED tests=", g_failed);
   else
      Print("ALL TESTS PASSED");
   ExpertRemove();
   return INIT_SUCCEEDED;
}
