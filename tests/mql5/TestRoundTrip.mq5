#property strict
#define FARM_TEST

#include <Farm/FarmMessages.mqh>

input string InpTestGitSha = "unknown";
input string InpTestResultFile = "ea-farm-TestRoundTrip-result.json";
input string InpRoundTripManifest = "ea-farm-rt-manifest.json";

int    g_total = 0;
int    g_failed = 0;
int    g_cases_processed = 0;
string g_ran_names[];
string g_failed_names[];
string g_case_failures[];

void PushString(string &items[], const string value)
{
   const int count = ArraySize(items);
   ArrayResize(items, count + 1);
   items[count] = value;
}

void RecordRan(const string name)
{
   PushString(g_ran_names, name);
}

void RecordFailure(const string name)
{
   PushString(g_failed_names, name);
}

void RecordCaseFailure(const string value)
{
   PushString(g_case_failures, value);
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

bool ReadCommonUtf8(const string filename, string &out)
{
   out = "";
   const int handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return false;

   const int size = (int)FileSize(handle);
   if(size < 0 || size > 65536)
   {
      FileClose(handle);
      return false;
   }

   uchar bytes[];
   ArrayResize(bytes, size + 1);
   const uint read = FileReadArray(handle, bytes, 0, size);
   FileClose(handle);
   if(read != (uint)size)
      return false;
   bytes[size] = 0;
   out = CharArrayToString(bytes, 0, size, CP_UTF8);
   return true;
}

bool WriteCommonUtf8(const string filename, const string content)
{
   uchar bytes[];
   int n = StringToCharArray(content, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   if(n < 0)
      return false;
   if(n > 0 && bytes[n - 1] == 0)
      n--;

   const int handle = FileOpen(filename, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return false;
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

bool ParseAndSerializePayload(const ENUM_FARM_MSG_TYPE msg_type, const string in_json, string &out_json)
{
   if(msg_type == FARM_MSG_HELLO)
   {
      FarmHelloPayload p;
      return FarmParseHello(in_json, p) && FarmSerializeHello(p, out_json);
   }
   if(msg_type == FARM_MSG_HELLO_ACK)
   {
      FarmHelloAckPayload p;
      return FarmParseHelloAck(in_json, p) && FarmSerializeHelloAck(p, out_json);
   }
   if(msg_type == FARM_MSG_HEARTBEAT)
   {
      FarmHeartbeatPayload p;
      return FarmParseHeartbeat(in_json, p) && FarmSerializeHeartbeat(p, out_json);
   }
   if(msg_type == FARM_MSG_HEARTBEAT_ACK)
   {
      FarmHeartbeatAckPayload p;
      return FarmParseHeartbeatAck(in_json, p) && FarmSerializeHeartbeatAck(p, out_json);
   }
   if(msg_type == FARM_MSG_BAR)
   {
      FarmBarPayload p;
      return FarmParseBar(in_json, p) && FarmSerializeBar(p, out_json);
   }
   if(msg_type == FARM_MSG_STATE)
   {
      FarmStatePayload p;
      return FarmParseState(in_json, p) && FarmSerializeState(p, out_json);
   }
   if(msg_type == FARM_MSG_INTENT)
   {
      FarmIntentPayload p;
      return FarmParseIntent(in_json, p) && FarmSerializeIntent(p, out_json);
   }
   if(msg_type == FARM_MSG_INTENT_ACK)
   {
      FarmIntentAckPayload p;
      return FarmParseIntentAck(in_json, p) && FarmSerializeIntentAck(p, out_json);
   }
   if(msg_type == FARM_MSG_EXEC_REPORT)
   {
      FarmExecReportPayload p;
      return FarmParseExecReport(in_json, p) && FarmSerializeExecReport(p, out_json);
   }
   if(msg_type == FARM_MSG_RISK_DIRECTIVE)
   {
      FarmRiskDirectivePayload p;
      return FarmParseRiskDirective(in_json, p) && FarmSerializeRiskDirective(p, out_json);
   }
   if(msg_type == FARM_MSG_CONFIG_UPDATE)
   {
      FarmConfigUpdatePayload p;
      return FarmParseConfigUpdate(in_json, p) && FarmSerializeConfigUpdate(p, out_json);
   }
   if(msg_type == FARM_MSG_ERROR)
   {
      FarmErrorPayload p;
      return FarmParseError(in_json, p) && FarmSerializeError(p, out_json);
   }
   FarmJsonSetError("UNKNOWN_TYPE", FarmMsgTypeToString(msg_type));
   return false;
}

bool ProcessCase(CFarmJsonValue *item)
{
   if(item == NULL || item.type != FARM_JSON_OBJECT)
   {
      RecordCaseFailure("manifest case is not object");
      return false;
   }

   CFarmJsonValue *id = item.Get("id");
   CFarmJsonValue *in_file = item.Get("in");
   CFarmJsonValue *out_file = item.Get("out");
   if(id == NULL || in_file == NULL || out_file == NULL
      || id.type != FARM_JSON_NUMBER || in_file.type != FARM_JSON_STRING || out_file.type != FARM_JSON_STRING)
   {
      RecordCaseFailure("manifest case missing id/in/out");
      return false;
   }

   const string label = "case " + IntegerToString((int)id.integer_value) + " " + in_file.string_value;
   string raw = "";
   if(!ReadCommonUtf8(in_file.string_value, raw))
   {
      RecordCaseFailure(label + ": read input failed");
      return false;
   }

   FarmEnvelope env;
   if(!FarmParseEnvelope(raw, env))
   {
      RecordCaseFailure(label + ": parse envelope failed: " + FarmJsonLastError());
      return false;
   }

   string payload = "";
   if(!ParseAndSerializePayload(env.type, env.payload_json, payload))
   {
      RecordCaseFailure(label + ": parse payload failed: " + FarmJsonLastError());
      return false;
   }

   env.payload_json = payload;
   string encoded = "";
   if(!FarmSerializeEnvelope(env, encoded))
   {
      RecordCaseFailure(label + ": serialize envelope failed");
      return false;
   }
   if(!WriteCommonUtf8(out_file.string_value, encoded))
   {
      RecordCaseFailure(label + ": write output failed");
      return false;
   }
   return true;
}

void test_manifest_roundtrip_cases()
{
   string manifest_raw = "";
   if(!ReadCommonUtf8(InpRoundTripManifest, manifest_raw))
   {
      AssertTrue(false, "test_manifest_roundtrip_cases");
      return;
   }

   CFarmJsonDoc doc;
   if(!doc.Parse(manifest_raw))
   {
      AssertTrue(false, "test_manifest_roundtrip_cases");
      doc.Free();
      return;
   }

   CFarmJsonValue *root = doc.Root();
   CFarmJsonValue *cases = (root == NULL ? NULL : root.Get("cases"));
   if(cases == NULL || cases.type != FARM_JSON_ARRAY)
   {
      AssertTrue(false, "test_manifest_roundtrip_cases");
      doc.Free();
      return;
   }

   for(int i = 0; i < cases.Size(); i++)
   {
      g_cases_processed++;
      ProcessCase(cases.At(i));
   }

   AssertTrue(true, "test_manifest_roundtrip_cases");
   doc.Free();
}

void RunAllTests()
{
   RecordRan("test_manifest_roundtrip_cases"); test_manifest_roundtrip_cases();
}

void WriteJsonResult()
{
   string json = "{";
   json += "\"suite\":\"TestRoundTrip\",";
   json += "\"git_sha\":" + FarmJsonQuoteUtf8(InpTestGitSha) + ",";
   json += "\"status\":" + FarmJsonQuoteUtf8(g_failed == 0 ? "PASS" : "FAIL") + ",";
   json += "\"started_at\":\"tester\",";
   json += "\"total\":" + IntegerToString(g_total) + ",";
   json += "\"passed\":" + IntegerToString(g_total - g_failed) + ",";
   json += "\"failed\":" + IntegerToString(g_failed) + ",";
   json += "\"cases_processed\":" + IntegerToString(g_cases_processed) + ",";
   json += "\"case_failures\":" + JsonStringArray(g_case_failures) + ",";
   json += "\"ran_names\":" + JsonStringArray(g_ran_names) + ",";
   json += "\"failed_names\":" + JsonStringArray(g_failed_names);
   json += "}";
   WriteCommonUtf8(InpTestResultFile, json);
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
