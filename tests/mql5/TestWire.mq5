#property strict
#define FARM_TEST

#include <Farm/Wire.mqh>
#include <Farm/Json.mqh>

input string InpTestGitSha = "unknown";
input string InpTestResultFile = "ea-farm-TestWire-result.json";

int    g_total = 0;
int    g_failed = 0;
string g_failed_names[];

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
   test_framing_multiple_in_one_read();
   test_framing_split_across_reads();
   test_framing_crlf_tolerance();
   test_framing_empty_line_skipped();
   test_framing_oversize_frame_rejected();
   test_json_unknown_field_ignored();
   test_json_unknown_type_ignored();
   test_json_parse_malformed_skips_line();
   test_receive_application_message_queued();
   test_hello_ack_accepted_sets_ready();
   test_hello_ack_rejected_sets_failed_auth();
   test_queue_full_drops_oldest();
   test_send_before_ready_queues();
   test_partial_send_resumes();
   test_utf8_multibyte_drop_counts_bytes();
   test_utf8_multibyte_not_split();
}

void WriteJsonResult()
{
   const int handle = FileOpen(InpTestResultFile, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_UTF8);
   if(handle == INVALID_HANDLE)
   {
      Print("FAIL could_not_write_result_file err=", GetLastError(), " file=", InpTestResultFile);
      return;
   }

   FileWriteString(handle, "{");
   FileWriteString(handle, "\"suite\":\"TestWire\",");
   FileWriteString(handle, "\"git_sha\":" + FarmJsonQuote(InpTestGitSha) + ",");
   FileWriteString(handle, "\"status\":" + FarmJsonQuote(g_failed == 0 ? "PASS" : "FAIL") + ",");
   FileWriteString(handle, "\"total\":" + IntegerToString(g_total) + ",");
   FileWriteString(handle, "\"passed\":" + IntegerToString(g_total - g_failed) + ",");
   FileWriteString(handle, "\"failed\":" + IntegerToString(g_failed) + ",");
   FileWriteString(handle, "\"failed_names\":[");
   for(int i = 0; i < ArraySize(g_failed_names); i++)
   {
      if(i > 0)
         FileWriteString(handle, ",");
      FileWriteString(handle, FarmJsonQuote(g_failed_names[i]));
   }
   FileWriteString(handle, "]");
   FileWriteString(handle, "}");
   FileClose(handle);
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
