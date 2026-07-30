#property strict
#define FARM_TEST

#include <Farm/BrokerTime.mqh>
#include <Farm/Json.mqh>

input string InpTestGitSha = "unknown";
input string InpTestResultFile = "ea-farm-TestBrokerTime-result.json";

int    g_total = 0;
int    g_failed = 0;
string g_ran_names[];
string g_failed_names[];

class CFakeClockSource : public CBrokerClockSource
{
public:
   datetime server_time;
   datetime gmt_time;
   datetime local_time;
   int      local_offset;
   int      local_dst;
   int      sleep_calls;
   int      sleep_ms_total;
   int      sleep_remainder_ms;
   int      fail_server_reads;

   CFakeClockSource()
   {
      server_time = 0;
      gmt_time = 0;
      local_time = 0;
      local_offset = 0;
      local_dst = 0;
      sleep_calls = 0;
      sleep_ms_total = 0;
      sleep_remainder_ms = 0;
      fail_server_reads = 0;
   }

   void Set(const datetime server_value, const datetime gmt_value,
            const int local_offset_value = 25200, const int local_dst_value = 0)
   {
      server_time = server_value;
      gmt_time = gmt_value;
      local_time = gmt_value + local_offset_value;
      local_offset = local_offset_value;
      local_dst = local_dst_value;
   }

   void AdvanceSeconds(const int seconds)
   {
      server_time += seconds;
      gmt_time += seconds;
      local_time += seconds;
   }

   virtual datetime ServerTime()
   {
      if(fail_server_reads > 0)
      {
         fail_server_reads--;
         return 0;
      }
      return server_time;
   }
   virtual datetime GmtTime() { return gmt_time; }
   virtual datetime LocalTime() { return local_time; }
   virtual int GmtOffsetLocal() { return local_offset; }
   virtual int DstLocal() { return local_dst; }
   virtual void SleepMs(const int ms)
   {
      sleep_calls++;
      sleep_ms_total += ms;
      sleep_remainder_ms += ms;
      while(sleep_remainder_ms >= 1000)
      {
         AdvanceSeconds(1);
         sleep_remainder_ms -= 1000;
      }
   }
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
      Print("FAIL ", name);
      g_failed++;
      RecordFailure(name);
   }
}

void AssertEqualInt(const int actual, const int expected, const string name)
{
   AssertTrue(actual == expected, name + " actual=" + IntegerToString(actual) + " expected=" + IntegerToString(expected));
}

void AssertEqualDatetime(const datetime actual, const datetime expected, const string name)
{
   AssertTrue(actual == expected, name + " actual=" + IntegerToString((long)actual) + " expected=" + IntegerToString((long)expected));
}

bool InitClock(CBrokerTime &clock, CFakeClockSource &src, const int offset_sec)
{
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   src.Set(utc + offset_sec, utc);
   return clock.Init(GetPointer(src));
}

void test_offset_detect_whole_hour()
{
   CBrokerTime clock;
   CFakeClockSource src;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   src.Set(utc + 10802, utc);
   AssertTrue(clock.Init(GetPointer(src)), "test_offset_detect_whole_hour init");
   AssertEqualInt(clock.OffsetSeconds(), 10800, "test_offset_detect_whole_hour offset");
}

void test_offset_detect_half_hour()
{
   CBrokerTime clock;
   CFakeClockSource src;
   AssertTrue(InitClock(clock, src, 9000), "test_offset_detect_half_hour init");
   AssertEqualInt(clock.OffsetSeconds(), 9000, "test_offset_detect_half_hour offset");
}

void test_offset_detect_negative()
{
   CBrokerTime clock;
   CFakeClockSource src;
   AssertTrue(InitClock(clock, src, -18000), "test_offset_detect_negative init");
   AssertEqualInt(clock.OffsetSeconds(), -18000, "test_offset_detect_negative offset");
}

void test_offset_reject_non_quantized()
{
   CBrokerTime clock;
   CFakeClockSource src;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   src.Set(utc + 10500, utc);
   AssertTrue(!clock.Init(GetPointer(src)), "test_offset_reject_non_quantized");
}

void test_offset_reject_out_of_bounds()
{
   CBrokerTime clock;
   CFakeClockSource src;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   src.Set(utc + 200000, utc);
   AssertTrue(!clock.Init(GetPointer(src)), "test_offset_reject_out_of_bounds");
}

void test_init_fails_when_server_time_zero()
{
   CBrokerTime clock;
   CFakeClockSource src;
   src.Set(0, MakeTime(2026, 7, 27, 9, 15, 2));
   AssertTrue(!clock.Init(GetPointer(src)), "test_init_fails_when_server_time_zero");
}

void test_init_retries_until_deadline()
{
   CBrokerTime clock;
   CFakeClockSource src;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   src.Set(utc + 10800, utc);
   src.fail_server_reads = 100;
   AssertTrue(!clock.Init(GetPointer(src)), "test_init_retries_until_deadline fails");
   AssertTrue(src.sleep_calls >= 10, "test_init_retries_until_deadline sleep_count");
   AssertTrue(src.sleep_ms_total <= 3000, "test_init_retries_until_deadline deadline");
}

void test_init_retries_then_accepts_good_sample()
{
   CBrokerTime clock;
   CFakeClockSource src;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   src.Set(utc + 10800, utc);
   src.fail_server_reads = 4;
   AssertTrue(clock.Init(GetPointer(src)), "test_init_retries_then_accepts_good_sample init");
   AssertEqualInt(src.sleep_calls, 4, "test_init_retries_then_accepts_good_sample sleep_count");
   AssertEqualInt(clock.OffsetSeconds(), 10800, "test_init_retries_then_accepts_good_sample offset");
}

void test_roundtrip_broker_utc_identity()
{
   CBrokerTime clock;
   CFakeClockSource src;
   AssertTrue(InitClock(clock, src, 10800), "test_roundtrip_broker_utc_identity init");
   bool ok = true;
   const datetime base = MakeTime(2026, 1, 1, 0, 0, 0);
   for(int i = 1; i <= 1000; i++)
   {
      const datetime broker = base + i * 713;
      if(clock.UtcToBroker(clock.BrokerToUtc(broker)) != broker)
         ok = false;
   }
   AssertTrue(ok, "test_roundtrip_broker_utc_identity");
}

void test_format_iso_utc_matches_schema()
{
   const string actual = FarmFormatIsoUtc(MakeTime(2026, 7, 27, 9, 15, 2));
   AssertTrue(actual == "2026-07-27T09:15:02Z", "test_format_iso_utc_matches_schema");
}

void test_invalid_returns_zero_not_stale()
{
   CBrokerTime clock;
   AssertEqualDatetime(clock.BrokerToUtc(MakeTime(2026, 7, 27, 9, 15, 2)), 0, "test_invalid_returns_zero_not_stale broker");
   AssertEqualDatetime(clock.UtcToBroker(MakeTime(2026, 7, 27, 9, 15, 2)), 0, "test_invalid_returns_zero_not_stale utc");
}

void test_invalid_after_90s_of_bad_samples()
{
   CBrokerTime clock;
   CFakeClockSource src;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   src.Set(utc + 10800, utc);
   AssertTrue(clock.Init(GetPointer(src)), "test_invalid_after_90s_of_bad_samples init");

   src.Set(utc + 10500, utc);
   AssertTrue(!clock.Refresh(), "test_invalid_after_90s_of_bad_samples first_bad");
   src.AdvanceSeconds(80);
   AssertTrue(!clock.Refresh(), "test_invalid_after_90s_of_bad_samples eighty");
   AssertTrue(clock.IsValid(), "test_invalid_after_90s_of_bad_samples still_valid");

   src.AdvanceSeconds(11);
   AssertTrue(!clock.Refresh(), "test_invalid_after_90s_of_bad_samples ninety_one");
   AssertTrue(!clock.IsValid(), "test_invalid_after_90s_of_bad_samples invalid");
   AssertEqualDatetime(clock.BrokerToUtc(utc + 10800), 0, "test_invalid_after_90s_of_bad_samples no_stale_broker");
   AssertEqualDatetime(clock.UtcToBroker(utc), 0, "test_invalid_after_90s_of_bad_samples no_stale_utc");

   src.Set(utc + 10800 + 100, utc + 100);
   AssertTrue(!clock.Refresh(), "test_invalid_after_90s_of_bad_samples recover");
   AssertTrue(clock.IsValid(), "test_invalid_after_90s_of_bad_samples valid_again");
}

void test_dst_change_needs_three_samples()
{
   CBrokerTime clock;
   CFakeClockSource src;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   AssertTrue(InitClock(clock, src, 7200), "test_dst_change_needs_three_samples init");
   src.Set(utc + 3600 + 1, utc + 1);
   AssertTrue(!clock.Refresh(), "test_dst_change_needs_three_samples first");
   src.Set(utc + 3600 + 2, utc + 2);
   AssertTrue(!clock.Refresh(), "test_dst_change_needs_three_samples second");
   AssertEqualInt(clock.OffsetSeconds(), 7200, "test_dst_change_needs_three_samples unchanged");
}

void test_dst_change_accepted_on_third()
{
   CBrokerTime clock;
   CFakeClockSource src;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   AssertTrue(InitClock(clock, src, 7200), "test_dst_change_accepted_on_third init");
   src.Set(utc + 3600 + 1, utc + 1);
   clock.Refresh();
   src.Set(utc + 3600 + 2, utc + 2);
   clock.Refresh();
   src.Set(utc + 3600 + 3, utc + 3);
   AssertTrue(clock.Refresh(), "test_dst_change_accepted_on_third changed");
   AssertEqualInt(clock.OffsetSeconds(), 3600, "test_dst_change_accepted_on_third offset");
   AssertEqualInt(clock.PreviousOffsetSeconds(), 7200, "test_dst_change_accepted_on_third previous");
}

void test_dst_flap_does_not_change_offset()
{
   CBrokerTime clock;
   CFakeClockSource src;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   AssertTrue(InitClock(clock, src, 7200), "test_dst_flap_does_not_change_offset init");
   src.Set(utc + 3600 + 1, utc + 1);
   clock.Refresh();
   src.Set(utc + 10800 + 2, utc + 2);
   clock.Refresh();
   src.Set(utc + 3600 + 3, utc + 3);
   clock.Refresh();
   AssertEqualInt(clock.OffsetSeconds(), 7200, "test_dst_flap_does_not_change_offset");
}

void test_broker_day_start_normal()
{
   CBrokerTime clock;
   CFakeClockSource src;
   AssertTrue(InitClock(clock, src, 10800), "test_broker_day_start_normal init");
   const datetime t = MakeTime(2026, 7, 27, 23, 59, 58);
   AssertEqualDatetime(clock.BrokerDayStart(t), MakeTime(2026, 7, 27, 0, 0, 0), "test_broker_day_start_normal");
}

void test_broker_day_start_across_dst_23h_and_25h()
{
   CBrokerTime clock;
   CFakeClockSource src;
   AssertTrue(InitClock(clock, src, 7200), "test_broker_day_start_across_dst_23h_and_25h spring_init");
   const datetime spring_d1_utc = clock.BrokerToUtc(clock.BrokerDayStart(MakeTime(2026, 3, 29, 12, 0, 0)));
   src.Set(MakeTime(2026, 3, 29, 10, 0, 1) + 10800, MakeTime(2026, 3, 29, 10, 0, 1));
   clock.Refresh();
   src.Set(MakeTime(2026, 3, 29, 10, 0, 2) + 10800, MakeTime(2026, 3, 29, 10, 0, 2));
   clock.Refresh();
   src.Set(MakeTime(2026, 3, 29, 10, 0, 3) + 10800, MakeTime(2026, 3, 29, 10, 0, 3));
   AssertTrue(clock.Refresh(), "test_broker_day_start_across_dst_23h changed");
   AssertEqualInt(clock.OffsetSeconds(), 10800, "test_broker_day_start_across_dst_23h offset");
   const datetime spring_d2_utc = clock.BrokerToUtc(clock.BrokerDayStart(MakeTime(2026, 3, 30, 12, 0, 0)));
   AssertEqualInt((int)(spring_d2_utc - spring_d1_utc), 23 * 3600, "test_broker_day_start_across_dst_23h");

   CBrokerTime autumn_clock;
   CFakeClockSource autumn_src;
   AssertTrue(InitClock(autumn_clock, autumn_src, 10800), "test_broker_day_start_across_dst_25h autumn_init");
   const datetime autumn_d1_utc = autumn_clock.BrokerToUtc(autumn_clock.BrokerDayStart(MakeTime(2026, 10, 25, 12, 0, 0)));
   autumn_src.Set(MakeTime(2026, 10, 25, 10, 0, 1) + 7200, MakeTime(2026, 10, 25, 10, 0, 1));
   autumn_clock.Refresh();
   autumn_src.Set(MakeTime(2026, 10, 25, 10, 0, 2) + 7200, MakeTime(2026, 10, 25, 10, 0, 2));
   autumn_clock.Refresh();
   autumn_src.Set(MakeTime(2026, 10, 25, 10, 0, 3) + 7200, MakeTime(2026, 10, 25, 10, 0, 3));
   AssertTrue(autumn_clock.Refresh(), "test_broker_day_start_across_dst_25h changed");
   AssertEqualInt(autumn_clock.OffsetSeconds(), 7200, "test_broker_day_start_across_dst_25h offset");
   const datetime autumn_d2_utc = autumn_clock.BrokerToUtc(autumn_clock.BrokerDayStart(MakeTime(2026, 10, 26, 12, 0, 0)));
   AssertEqualInt((int)(autumn_d2_utc - autumn_d1_utc), 25 * 3600, "test_broker_day_start_across_dst_25h");
}

void test_local_time_comes_from_source()
{
   CBrokerTime clock;
   CFakeClockSource src;
   const datetime utc = MakeTime(2026, 7, 27, 9, 15, 2);
   src.Set(utc + 10800, utc, 25200, 0);
   AssertTrue(clock.Init(GetPointer(src)), "test_local_time_comes_from_source init");
   AssertEqualDatetime(clock.LocalTime(), utc + 25200, "test_local_time_comes_from_source");
}

void test_is_same_broker_day_across_utc_midnight()
{
   CBrokerTime clock;
   CFakeClockSource src;
   AssertTrue(InitClock(clock, src, 10800), "test_is_same_broker_day_across_utc_midnight init");
   AssertTrue(clock.IsSameBrokerDay(MakeTime(2026, 7, 28, 1, 0, 0),
                                    MakeTime(2026, 7, 28, 23, 0, 0)),
              "test_is_same_broker_day_across_utc_midnight same");
   AssertTrue(!clock.IsSameBrokerDay(MakeTime(2026, 7, 28, 23, 59, 59),
                                     MakeTime(2026, 7, 29, 0, 0, 0)),
              "test_is_same_broker_day_across_utc_midnight different");
}

void RunAllTests()
{
   RecordRan("test_offset_detect_whole_hour");
   test_offset_detect_whole_hour();
   RecordRan("test_offset_detect_half_hour");
   test_offset_detect_half_hour();
   RecordRan("test_offset_detect_negative");
   test_offset_detect_negative();
   RecordRan("test_offset_reject_non_quantized");
   test_offset_reject_non_quantized();
   RecordRan("test_offset_reject_out_of_bounds");
   test_offset_reject_out_of_bounds();
   RecordRan("test_init_fails_when_server_time_zero");
   test_init_fails_when_server_time_zero();
   RecordRan("test_init_retries_until_deadline");
   test_init_retries_until_deadline();
   RecordRan("test_init_retries_then_accepts_good_sample");
   test_init_retries_then_accepts_good_sample();
   RecordRan("test_roundtrip_broker_utc_identity");
   test_roundtrip_broker_utc_identity();
   RecordRan("test_format_iso_utc_matches_schema");
   test_format_iso_utc_matches_schema();
   RecordRan("test_invalid_returns_zero_not_stale");
   test_invalid_returns_zero_not_stale();
   RecordRan("test_invalid_after_90s_of_bad_samples");
   test_invalid_after_90s_of_bad_samples();
   RecordRan("test_dst_change_needs_three_samples");
   test_dst_change_needs_three_samples();
   RecordRan("test_dst_change_accepted_on_third");
   test_dst_change_accepted_on_third();
   RecordRan("test_dst_flap_does_not_change_offset");
   test_dst_flap_does_not_change_offset();
   RecordRan("test_broker_day_start_normal");
   test_broker_day_start_normal();
   RecordRan("test_broker_day_start_across_dst_23h_and_25h");
   test_broker_day_start_across_dst_23h_and_25h();
   RecordRan("test_is_same_broker_day_across_utc_midnight");
   test_is_same_broker_day_across_utc_midnight();
   RecordRan("test_local_time_comes_from_source");
   test_local_time_comes_from_source();
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
   json += "\"suite\":\"TestBrokerTime\",";
   json += "\"git_sha\":" + FarmJsonQuote(InpTestGitSha) + ",";
   json += "\"status\":" + FarmJsonQuote(g_failed == 0 ? "PASS" : "FAIL") + ",";
   json += "\"started_at\":" + FarmJsonQuote("tester") + ",";
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
