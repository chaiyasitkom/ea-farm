#property strict
#define FARM_TEST

#include <Farm/Wire.mqh>
#include <Farm/Json.mqh>

input string InpTestGitSha = "unknown";
input string InpTestResultFile = "ea-farm-TestWire-result.json";

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
      Print("FAIL ", name);
      g_failed++;
      RecordFailure(name);
   }
}

void AssertEqualString(const string actual, const string expected, const string name)
{
   AssertTrue(actual == expected, name + " actual=" + actual + " expected=" + expected);
}

void AssertEqualInt(const int actual, const int expected, const string name)
{
   AssertTrue(actual == expected, name + " actual=" + IntegerToString(actual) + " expected=" + IntegerToString(expected));
}

void test_framing_multiple_in_one_read()
{
   CWire wire;
   string line;
   wire.TestAppendInbound("{\"type\":\"INTENT\"}\n{\"type\":\"CONFIG_UPDATE\"}\n");
   AssertTrue(wire.TestPopFrame(line), "test_framing_multiple_in_one_read first_pop");
   AssertEqualString(line, "{\"type\":\"INTENT\"}", "test_framing_multiple_in_one_read first");
   AssertTrue(wire.TestPopFrame(line), "test_framing_multiple_in_one_read second_pop");
   AssertEqualString(line, "{\"type\":\"CONFIG_UPDATE\"}", "test_framing_multiple_in_one_read second");
}

void test_framing_split_across_reads()
{
   CWire wire;
   string line;
   wire.TestAppendInbound("{\"type\":\"IN");
   AssertTrue(!wire.TestPopFrame(line), "test_framing_split_across_reads waits");
   wire.TestAppendInbound("TENT\"}\n");
   AssertTrue(wire.TestPopFrame(line), "test_framing_split_across_reads emits");
   AssertEqualString(line, "{\"type\":\"INTENT\"}", "test_framing_split_across_reads line");
}

void test_framing_crlf_tolerance()
{
   CWire wire;
   string line;
   wire.TestAppendInbound("{\"type\":\"INTENT\"}\r\n");
   AssertTrue(wire.TestPopFrame(line), "test_framing_crlf_tolerance pop");
   AssertEqualString(line, "{\"type\":\"INTENT\"}", "test_framing_crlf_tolerance trim_cr");
}

void test_framing_empty_line_skipped()
{
   CWire wire;
   string line;
   wire.TestAppendInbound("\n{\"type\":\"INTENT\"}\n");
   AssertTrue(wire.TestPopFrame(line), "test_framing_empty_line_skipped empty_pop");
   AssertEqualString(line, "", "test_framing_empty_line_skipped empty");
   AssertTrue(wire.TestPopFrame(line), "test_framing_empty_line_skipped real_pop");
}

void test_framing_oversize_frame_rejected()
{
   CWire wire;
   string line;
   uchar big[];
   ArrayResize(big, FARM_WIRE_MAX_FRAME_BYTES + 1);
   for(int i = 0; i < ArraySize(big); i++)
      big[i] = 'a';
   wire.TestAppendInboundBytes(big);
   AssertTrue(wire.TestInboundFrameTooLargeNoNewline(), "test_framing_oversize_frame_rejected detects");
   AssertTrue(!wire.TestPopFrame(line), "test_framing_oversize_frame_rejected no_frame");
}

void test_json_unknown_field_ignored()
{
   const string json = "{\"type\":\"HELLO_ACK\",\"accepted\":true,\"extra\":\"ignored\"}";
   AssertEqualString(FarmJsonGetString(json, "type", ""), "HELLO_ACK", "test_json_unknown_field_ignored");
   AssertTrue(FarmJsonGetBool(json, "accepted", false), "test_json_unknown_field_ignored accepted");
}

void test_json_unknown_type_ignored()
{
   CWire wire;
   wire.TestHandleInboundLine("{\"type\":\"FUTURE_MESSAGE\",\"payload\":{\"x\":1}}");
   AssertEqualInt(wire.TestReceivedQueueDepth(), 0, "test_json_unknown_type_ignored");
}

void test_json_parse_malformed_skips_line()
{
   CWire wire;
   wire.TestHandleInboundLine("{bad json");
   AssertEqualInt(wire.TestReceivedQueueDepth(), 0, "test_json_parse_malformed_skips_line");
}

void test_receive_application_message_queued()
{
   CWire wire;
   string msg;
   const string intent = "{\"type\":\"INTENT\",\"payload\":{\"intent_id\":\"abc\"}}";
   wire.TestHandleInboundLine(intent);
   AssertEqualInt(wire.TestReceivedQueueDepth(), 1, "test_receive_application_message_queued depth");
   AssertTrue(wire.Receive(msg), "test_receive_application_message_queued receive");
   AssertEqualString(msg, intent, "test_receive_application_message_queued content");
   AssertTrue(!wire.Receive(msg), "test_receive_application_message_queued empty_after");
}

void test_hello_ack_accepted_sets_ready()
{
   CWire wire;
   wire.TestSetState(WIRE_AUTHENTICATING);
   wire.TestHandleInboundLine("{\"type\":\"HELLO_ACK\",\"payload\":{\"accepted\":true},\"accepted\":true,\"assigned_session_id\":\"acct-test\"}");
   AssertTrue(wire.State() == WIRE_READY, "test_hello_ack_accepted_sets_ready");
}

void test_hello_ack_rejected_sets_failed_auth()
{
   CWire wire;
   wire.TestSetState(WIRE_AUTHENTICATING);
   wire.TestHandleInboundLine("{\"type\":\"HELLO_ACK\",\"accepted\":false,\"reject_reason\":\"BAD_TOKEN\"}");
   AssertTrue(wire.State() == WIRE_FAILED_AUTH, "test_hello_ack_rejected_sets_failed_auth");
}

void test_queue_full_drops_oldest()
{
   CWire wire;
   wire.ConfigureRuntime(2, 2, "trend_v1", 770001, false);
   AssertTrue(wire.TestQueue("one"), "test_queue_full_drops_oldest queue_one");
   AssertTrue(wire.TestQueue("two"), "test_queue_full_drops_oldest queue_two");
   AssertTrue(wire.TestQueue("three"), "test_queue_full_drops_oldest queue_three");
   AssertTrue(wire.SendQueueDepth() == 2, "test_queue_full_drops_oldest depth");
   AssertTrue(wire.BytesDropped() > 0, "test_queue_full_drops_oldest bytes_dropped");
}

void test_send_before_ready_queues()
{
   CWire wire;
   wire.ConfigureRuntime(2, 2, "trend_v1", 770001, false);
   AssertTrue(wire.Send("{\"type\":\"STATE\"}"), "test_send_before_ready_queues send");
   AssertEqualInt(wire.SendQueueDepth(), 1, "test_send_before_ready_queues depth");
}

void test_partial_send_resumes()
{
   CWire wire;
   wire.TestSimulatePartialSend("{\"x\":1}", 4);
   AssertEqualInt(wire.TestPartialSendBytes(), 4, "test_partial_send_resumes bytes");
   AssertEqualString(wire.TestPartialSendAsString(), ":1}\n", "test_partial_send_resumes remaining_only");
}

void test_utf8_multibyte_drop_counts_bytes()
{
   CWire wire;
   wire.ConfigureRuntime(2, 1, "trend_v1", 770001, false);
   AssertTrue(wire.TestQueue("ไทย"), "test_utf8_multibyte_drop_counts_bytes queue_old");
   AssertTrue(wire.TestQueue("new"), "test_utf8_multibyte_drop_counts_bytes queue_new");
   AssertTrue(wire.BytesDropped() > StringLen("ไทย"), "test_utf8_multibyte_drop_counts_bytes bytes");
}

void test_utf8_multibyte_not_split()
{
   CWire wire;
   string line;
   const string frame = "{\"type\":\"INTENT\",\"payload\":{\"comment\":\"ไทย\"}}\n";
   uchar data[];
   const int total = StringToCharArray(frame, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   if(total < 0)
   {
      AssertTrue(false, "test_utf8_multibyte_not_split encode");
      return;
   }

   for(int i = 0; i < total; i++)
   {
      uchar one[];
      ArrayResize(one, 1);
      one[0] = data[i];
      wire.TestAppendInboundBytes(one);
   }

   AssertTrue(wire.TestPopFrame(line), "test_utf8_multibyte_not_split pop");
   AssertEqualString(line, "{\"type\":\"INTENT\",\"payload\":{\"comment\":\"ไทย\"}}", "test_utf8_multibyte_not_split line");
}

void RunAllTests()
{
   RecordRan("test_framing_multiple_in_one_read");
   test_framing_multiple_in_one_read();
   RecordRan("test_framing_split_across_reads");
   test_framing_split_across_reads();
   RecordRan("test_framing_crlf_tolerance");
   test_framing_crlf_tolerance();
   RecordRan("test_framing_empty_line_skipped");
   test_framing_empty_line_skipped();
   RecordRan("test_framing_oversize_frame_rejected");
   test_framing_oversize_frame_rejected();
   RecordRan("test_json_unknown_field_ignored");
   test_json_unknown_field_ignored();
   RecordRan("test_json_unknown_type_ignored");
   test_json_unknown_type_ignored();
   RecordRan("test_json_parse_malformed_skips_line");
   test_json_parse_malformed_skips_line();
   RecordRan("test_receive_application_message_queued");
   test_receive_application_message_queued();
   RecordRan("test_hello_ack_accepted_sets_ready");
   test_hello_ack_accepted_sets_ready();
   RecordRan("test_hello_ack_rejected_sets_failed_auth");
   test_hello_ack_rejected_sets_failed_auth();
   RecordRan("test_queue_full_drops_oldest");
   test_queue_full_drops_oldest();
   RecordRan("test_send_before_ready_queues");
   test_send_before_ready_queues();
   RecordRan("test_partial_send_resumes");
   test_partial_send_resumes();
   RecordRan("test_utf8_multibyte_drop_counts_bytes");
   test_utf8_multibyte_drop_counts_bytes();
   RecordRan("test_utf8_multibyte_not_split");
   test_utf8_multibyte_not_split();
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
      out += FarmJsonQuote(items[i]);
   }
   out += "]";
   return out;
}

void WriteJsonResult()
{
   string json = "{";
   json += "\"suite\":\"TestWire\",";
   json += "\"git_sha\":" + FarmJsonQuote(InpTestGitSha) + ",";
   json += "\"status\":" + FarmJsonQuote(g_failed == 0 ? "PASS" : "FAIL") + ",";
   json += "\"started_at\":" + FarmJsonQuote(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)) + ",";
   json += "\"total\":" + IntegerToString(g_total) + ",";
   json += "\"passed\":" + IntegerToString(g_total - g_failed) + ",";
   json += "\"failed\":" + IntegerToString(g_failed) + ",";
   json += "\"ran_names\":" + JsonStringArray(g_ran_names) + ",";
   json += "\"failed_names\":" + JsonStringArray(g_failed_names);
   json += "}";

   if(!WriteUtf8File(InpTestResultFile, json))
      return;

   Print("TEST_RESULT_JSON file=", InpTestResultFile, " common_files=true status=", (g_failed == 0 ? "PASS" : "FAIL"));
}

int OnInit()
{
   RunAllTests();
   WriteJsonResult();

   if(g_failed > 0)
   {
      Print("FAILED tests=", g_failed);
      ExpertRemove();
      return INIT_SUCCEEDED;
   }

   Print("ALL TESTS PASSED");
   ExpertRemove();
   return INIT_SUCCEEDED;
}
