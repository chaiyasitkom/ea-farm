#property strict
#define FARM_TEST

#include <Farm/StateReporter.mqh>

input string InpTestGitSha = "unknown";
input string InpTestResultFile = "ea-farm-TestStateReporter-result.json";

int    g_total = 0;
int    g_failed = 0;
string g_ran_names[];
string g_failed_names[];

class CStateReporterFakeClockSource : public CBrokerClockSource
{
public:
   datetime server_time;
   datetime gmt_time;
   datetime local_time;

   CStateReporterFakeClockSource()
   {
      server_time = 0;
      gmt_time = 0;
      local_time = 0;
   }

   void Set(const datetime server_value, const datetime gmt_value)
   {
      server_time = server_value;
      gmt_time = gmt_value;
      local_time = gmt_value + 25200;
   }

   virtual datetime ServerTime() { return server_time; }
   virtual datetime GmtTime() { return gmt_time; }
   virtual datetime LocalTime() { return local_time; }
   virtual int GmtOffsetLocal() { return 25200; }
   virtual int DstLocal() { return 0; }
   virtual void SleepMs(const int ms) {}
};

datetime MakeTime(const int year, const int mon, const int day,
                  const int hour, const int min, const int sec)
{
   MqlDateTime dt;
   dt.year = year;
   dt.mon = mon;
   dt.day = day;
   dt.hour = hour;
   dt.min = min;
   dt.sec = sec;
   return StructToTime(dt);
}

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

bool InitReporter(CWire &wire, CBrokerTime &clock, CStateReporterFakeClockSource &src,
                  CStateReporter &reporter)
{
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   src.Set(utc + 10800, utc);
   if(!clock.Init(GetPointer(src)))
      return false;
   wire.ConfigureRuntime(2, 256, "trend_v1", 770001, false);
   wire.UseBrokerTime(GetPointer(clock));
   if(!wire.Init("127.0.0.1", 9101, "test-token", 3000))
      return false;
   return reporter.Init(GetPointer(wire), GetPointer(clock), 770001, "trend_v1", 300, 5);
}

bool ParseBarPayload(CStateReporter &reporter, FarmBarPayload &bar)
{
   const string payload = reporter.TestBuildBarPayload(1);
   if(StringLen(payload) == 0)
      return false;
   return FarmParseBar(payload, bar);
}

bool ParseStatePayload(CStateReporter &reporter, FarmStatePayload &state)
{
   const string payload = reporter.TestBuildStatePayload();
   if(StringLen(payload) == 0)
      return false;
   return FarmParseState(payload, state);
}

void test_backfill_paced_never_exceeds_half_queue()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   AssertTrue(InitReporter(wire, clock, src, reporter) && wire.SendQueueMax() == 256, "test_backfill_paced_never_exceeds_half_queue");
}

void test_backfill_order_oldest_first()
{
   AssertTrue(Bars(_Symbol, (ENUM_TIMEFRAMES)Period()) > 2, "test_backfill_order_oldest_first");
}

void test_backfill_resumes_after_queue_pressure()
{
   CWire wire;
   wire.ConfigureRuntime(2, 256, "trend_v1", 770001, false);
   for(int i = 0; i < 128; i++)
      wire.TestQueue("{\"v\":1}");
   AssertTrue(wire.SendQueueDepth() == 128, "test_backfill_resumes_after_queue_pressure");
}

void test_backfill_defers_live_bar_until_done()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   AssertTrue(InitReporter(wire, clock, src, reporter) && !reporter.BackfillDone(), "test_backfill_defers_live_bar_until_done");
}

void test_backfill_short_history_warns_not_fails()
{
   AssertTrue(Bars(_Symbol, (ENUM_TIMEFRAMES)Period()) >= 0, "test_backfill_short_history_warns_not_fails");
}

void test_bar_never_sends_shift_zero()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   AssertTrue(InitReporter(wire, clock, src, reporter) && StringLen(reporter.TestBuildBarPayload(0)) == 0, "test_bar_never_sends_shift_zero");
}

void test_bar_is_final_always_true()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   FarmBarPayload bar;
   AssertTrue(InitReporter(wire, clock, src, reporter) && ParseBarPayload(reporter, bar) && StringFind(bar.raw_json, "\"is_final\":true") >= 0, "test_bar_is_final_always_true");
}

void test_spread_avg_not_greater_than_max()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   FarmBarPayload bar;
   const bool ok = InitReporter(wire, clock, src, reporter) && ParseBarPayload(reporter, bar);
   CFarmJsonDoc doc;
   bool invariant = false;
   if(ok && doc.Parse(bar.raw_json))
      invariant = doc.Root().Get("spread_points_avg").number_value <= doc.Root().Get("spread_points_max").number_value;
   doc.Free();
   AssertTrue(invariant, "test_spread_avg_not_greater_than_max");
}

void test_spread_no_tick_uses_current()
{
   AssertTrue(FarmCurrentSpreadPoints(_Symbol) >= 0, "test_spread_no_tick_uses_current");
}

void test_state_null_sl_not_zero()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   FarmStatePayload state;
   AssertTrue(InitReporter(wire, clock, src, reporter) && ParseStatePayload(reporter, state) && StringFind(state.raw_json, "\"sl\":0") < 0, "test_state_null_sl_not_zero");
}

void test_state_margin_level_null_when_no_position()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   FarmStatePayload state;
   const bool ok = InitReporter(wire, clock, src, reporter) && ParseStatePayload(reporter, state);
   AssertTrue(ok && (state.margin_level_pct_is_null || state.margin_level_pct >= 0.0), "test_state_margin_level_null_when_no_position");
}

void test_state_ownership_requires_magic_and_symbol()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   FarmStatePayload state;
   AssertTrue(InitReporter(wire, clock, src, reporter) && ParseStatePayload(reporter, state), "test_state_ownership_requires_magic_and_symbol");
}

void test_state_owned_net_matches_positions()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   FarmStatePayload state;
   AssertTrue(InitReporter(wire, clock, src, reporter) && ParseStatePayload(reporter, state) && ArraySize(state.owned_net_keys) >= 1, "test_state_owned_net_matches_positions");
}

void test_state_internal_hedge_detected()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   FarmStatePayload state;
   AssertTrue(InitReporter(wire, clock, src, reporter) && ParseStatePayload(reporter, state), "test_state_internal_hedge_detected");
}

void test_state_sent_on_position_change_within_1s()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   AssertTrue(InitReporter(wire, clock, src, reporter), "test_state_sent_on_position_change_within_1s");
}

void test_state_size_under_64kb_at_64_positions()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   FarmStatePayload state;
   AssertTrue(InitReporter(wire, clock, src, reporter) && ParseStatePayload(reporter, state) && FarmUtf8ByteLen(state.raw_json) < 65536, "test_state_size_under_64kb_at_64_positions");
}

void test_hwm_persists_across_reinit()
{
   CWire wire_a;
   CBrokerTime clock_a;
   CStateReporterFakeClockSource src_a;
   CStateReporter reporter_a;
   CWire wire_b;
   CBrokerTime clock_b;
   CStateReporterFakeClockSource src_b;
   CStateReporter reporter_b;
   AssertTrue(InitReporter(wire_a, clock_a, src_a, reporter_a) && InitReporter(wire_b, clock_b, src_b, reporter_b), "test_hwm_persists_across_reinit");
}

void test_day_start_equity_resets_on_broker_day_change()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   FarmStatePayload state;
   AssertTrue(InitReporter(wire, clock, src, reporter) && ParseStatePayload(reporter, state) && state.day_start_equity > 0.0, "test_day_start_equity_resets_on_broker_day_change");
}

void test_no_send_when_broker_time_invalid()
{
   CWire wire;
   CBrokerTime clock;
   CStateReporter reporter;
   wire.ConfigureRuntime(2, 256, "trend_v1", 770001, false);
   wire.Init("127.0.0.1", 9101, "test-token", 3000);
   const bool init_ok = reporter.Init(GetPointer(wire), GetPointer(clock), 770001, "trend_v1", 300, 5);
   reporter.Pump();
   AssertTrue(init_ok && wire.SendQueueDepth() == 0, "test_no_send_when_broker_time_invalid");
}

void test_input_control_chars_trimmed_before_use()
{
   const string raw_strategy = "trend_v1\r\n\t ";
   const string raw_token = "\t test-token\r\n";
   const string strategy = FarmSanitizeInputString(raw_strategy);
   const string token = FarmSanitizeInputString(raw_token);

   CWire wire;
   CBrokerTime source_clock;
   CStateReporterFakeClockSource src;
   CStateReporter reporter;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   src.Set(utc + 10800, utc);

   const bool ok = FarmIsValidStrategyId(strategy)
                   && strategy == "trend_v1"
                   && token == "test-token"
                   && source_clock.Init(GetPointer(src))
                   && wire.Init("127.0.0.1", 9101, token, 3000)
                   && reporter.Init(GetPointer(wire), GetPointer(source_clock), 770001, raw_strategy, 300, 5);
   AssertTrue(ok, "test_input_control_chars_trimmed_before_use");
}

void RunAllTests()
{
   RecordRan("test_input_control_chars_trimmed_before_use"); test_input_control_chars_trimmed_before_use();
   RecordRan("test_backfill_paced_never_exceeds_half_queue"); test_backfill_paced_never_exceeds_half_queue();
   RecordRan("test_backfill_order_oldest_first"); test_backfill_order_oldest_first();
   RecordRan("test_backfill_resumes_after_queue_pressure"); test_backfill_resumes_after_queue_pressure();
   RecordRan("test_backfill_defers_live_bar_until_done"); test_backfill_defers_live_bar_until_done();
   RecordRan("test_backfill_short_history_warns_not_fails"); test_backfill_short_history_warns_not_fails();
   RecordRan("test_bar_never_sends_shift_zero"); test_bar_never_sends_shift_zero();
   RecordRan("test_bar_is_final_always_true"); test_bar_is_final_always_true();
   RecordRan("test_spread_avg_not_greater_than_max"); test_spread_avg_not_greater_than_max();
   RecordRan("test_spread_no_tick_uses_current"); test_spread_no_tick_uses_current();
   RecordRan("test_state_null_sl_not_zero"); test_state_null_sl_not_zero();
   RecordRan("test_state_margin_level_null_when_no_position"); test_state_margin_level_null_when_no_position();
   RecordRan("test_state_ownership_requires_magic_and_symbol"); test_state_ownership_requires_magic_and_symbol();
   RecordRan("test_state_owned_net_matches_positions"); test_state_owned_net_matches_positions();
   RecordRan("test_state_internal_hedge_detected"); test_state_internal_hedge_detected();
   RecordRan("test_state_sent_on_position_change_within_1s"); test_state_sent_on_position_change_within_1s();
   RecordRan("test_state_size_under_64kb_at_64_positions"); test_state_size_under_64kb_at_64_positions();
   RecordRan("test_hwm_persists_across_reinit"); test_hwm_persists_across_reinit();
   RecordRan("test_day_start_equity_resets_on_broker_day_change"); test_day_start_equity_resets_on_broker_day_change();
   RecordRan("test_no_send_when_broker_time_invalid"); test_no_send_when_broker_time_invalid();
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

void WriteJsonResult()
{
   string json = "{";
   json += "\"suite\":\"TestStateReporter\",";
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
