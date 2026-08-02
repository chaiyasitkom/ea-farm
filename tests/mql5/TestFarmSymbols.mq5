#property strict
#define FARM_TEST

#include <Farm/FarmSymbols.mqh>
#include <Farm/JsonCore.mqh>

input string InpTestGitSha = "unknown";
input string InpTestResultFile = "ea-farm-TestFarmSymbols-result.json";

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

void test_canonical_gold_to_xauusd()
{
   AssertEqualString(FarmSymbolCanonical("XMGlobal-MT5 6", "GOLD"), "XAUUSD", "test_canonical_gold_to_xauusd");
}

void test_canonical_unknown_returns_empty()
{
   AssertEqualString(FarmSymbolCanonical("XMGlobal-MT5 6", "EURUSDm"), "", "test_canonical_unknown_returns_empty");
}

void test_risk_profile_returns_false_for_unknown()
{
   int spread = 99;
   double sl = 1.0;
   string session = "value";
   const bool ok = FarmSymbolRisk("EURUSDm", spread, sl, session);
   AssertTrue(!ok && spread == -1 && sl == 0.0 && session == "", "test_risk_profile_returns_false_for_unknown");
}

void test_spread_null_encoded_as_minus_one()
{
   int spread = 0;
   double sl = 0.0;
   string session = "";
   const bool ok = FarmSymbolRisk("XAUUSD", spread, sl, session);
   AssertTrue(ok, "test_spread_null_encoded_as_minus_one ok");
   AssertEqualInt(spread, -1, "test_spread_null_encoded_as_minus_one spread");
}

void test_all_canonicals_have_base_and_quote()
{
   string names[] = {"AUDUSD", "EURUSD", "GBPUSD", "USDCAD", "USDJPY", "XAUUSD"};
   bool ok = true;
   for(int i = 0; i < ArraySize(names); i++)
   {
      ok = ok && FarmSymbolBase(names[i]) != "";
      ok = ok && FarmSymbolQuote(names[i]) != "";
   }
   AssertTrue(ok, "test_all_canonicals_have_base_and_quote");
}

void test_production_ready_false_for_uncalibrated()
{
   string names[] = {"AUDUSD", "EURUSD", "GBPUSD", "USDCAD", "USDJPY", "XAUUSD"};
   bool ok = true;
   for(int i = 0; i < ArraySize(names); i++)
      ok = ok && !FarmSymbolProductionReady(names[i]);
   AssertTrue(ok, "test_production_ready_false_for_uncalibrated");
}

void test_correlation_groups_available()
{
   AssertEqualString(FarmSymbolCorrelationGroup("EURUSD"), "EUROPE", "test_correlation_groups_available eurusd");
   AssertEqualString(FarmSymbolCorrelationGroup("USDJPY"), "JPY", "test_correlation_groups_available usdjpy");
   AssertEqualString(FarmSymbolCorrelationGroup("AUDUSD"), "COMMODITY_FX", "test_correlation_groups_available audusd");
   AssertEqualString(FarmSymbolCorrelationGroup("XAUUSD"), "METALS", "test_correlation_groups_available xauusd");
}

void RunAllTests()
{
   RecordRan("test_canonical_gold_to_xauusd"); test_canonical_gold_to_xauusd();
   RecordRan("test_canonical_unknown_returns_empty"); test_canonical_unknown_returns_empty();
   RecordRan("test_risk_profile_returns_false_for_unknown"); test_risk_profile_returns_false_for_unknown();
   RecordRan("test_spread_null_encoded_as_minus_one"); test_spread_null_encoded_as_minus_one();
   RecordRan("test_all_canonicals_have_base_and_quote"); test_all_canonicals_have_base_and_quote();
   RecordRan("test_production_ready_false_for_uncalibrated"); test_production_ready_false_for_uncalibrated();
   RecordRan("test_correlation_groups_available"); test_correlation_groups_available();
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
   json += "\"suite\":\"TestFarmSymbols\",";
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
