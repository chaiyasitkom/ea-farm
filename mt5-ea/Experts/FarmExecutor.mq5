#property strict
#property version   "1.00"
#property description "EA Farm executor shell for SPEC-001 wire transport only."

#include <Farm/Wire.mqh>
#include <Farm/StateReporter.mqh>
#include <Farm/Logger.mqh>

input string InpBrainHost        = "127.0.0.1";
input int    InpBrainPort        = 9101;
input string InpBrainToken       = "";
input string InpStrategyId       = "trend_v1";
input int    InpMagic            = 770001;
input int    InpHeartbeatSec     = 2;
input int    InpBrainTimeoutSec  = 10;
input int    InpSendQueueMax     = 256;
input int    InpBackfillBars     = 300;
input int    InpStateIntervalSec = 5;
input bool   InpVerboseLog       = false;

CWire       g_wire;
CBrokerTime g_broker_time;
CStateReporter g_state_reporter;
CFarmLogger g_log;
bool        g_closeby_supported = false;

string MarginModeName(const long mode)
{
   if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return "RETAIL_HEDGING";
   if(mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      return "RETAIL_NETTING";
   if(mode == ACCOUNT_MARGIN_MODE_EXCHANGE)
      return "EXCHANGE";
   return "UNKNOWN";
}

int OnInit()
{
   g_log.Init("FarmExecutor", InpVerboseLog);

   const string brain_host = FarmSanitizeInputString(InpBrainHost);
   const string brain_token = FarmSanitizeInputString(InpBrainToken);
   const string strategy_id = FarmSanitizeInputString(InpStrategyId);

   if(StringLen(brain_host) == 0)
   {
      g_log.Fatal("InpBrainHost is empty after trim");
      return INIT_FAILED;
   }
   if(StringLen(brain_token) == 0)
   {
      g_log.Fatal("InpBrainToken is empty after trim");
      return INIT_FAILED;
   }
   if(!FarmIsValidStrategyId(strategy_id))
   {
      g_log.Fatal("InpStrategyId invalid after trim value=" + FarmJsonQuoteUtf8(strategy_id));
      return INIT_FAILED;
   }

   const long margin_mode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      g_log.Fatal("account_margin_mode_must_be_RETAIL_HEDGING actual=" + MarginModeName(margin_mode));
      return INIT_FAILED;
   }

   if(!SymbolSelect(_Symbol, true))
   {
      g_log.Fatal("symbol_select_failed symbol=" + _Symbol);
      return INIT_FAILED;
   }

   const string timeframe = FarmTimeframeCode((ENUM_TIMEFRAMES)Period());
   if(StringLen(timeframe) == 0)
   {
      g_log.Fatal("unsupported_timeframe actual=" + EnumToString((ENUM_TIMEFRAMES)Period()));
      return INIT_FAILED;
   }

   const long order_mode = SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE);
   g_closeby_supported = ((order_mode & SYMBOL_ORDER_CLOSEBY) == SYMBOL_ORDER_CLOSEBY);
   g_log.Info("symbol_closeby_supported=" + (g_closeby_supported ? "true" : "false"));

   if(!g_broker_time.Init())
   {
      g_log.Fatal("broker_time_init_failed " + g_broker_time.DiagnosticLine());
      return INIT_FAILED;
   }
   g_log.Info(g_broker_time.DiagnosticLine());

   g_wire.ConfigureRuntime(InpHeartbeatSec, InpSendQueueMax, strategy_id, InpMagic, InpVerboseLog);
   g_wire.UseBrokerTime(GetPointer(g_broker_time));
   if(!g_wire.Init(brain_host, InpBrainPort, brain_token, 3000))
      return INIT_FAILED;
   if(!g_state_reporter.Init(GetPointer(g_wire), GetPointer(g_broker_time),
                             InpMagic, strategy_id, InpBackfillBars, InpStateIntervalSec))
      return INIT_FAILED;

   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   g_wire.Shutdown();
   EventKillTimer();
}

void OnTimer()
{
   if(g_broker_time.Refresh())
   {
      const string detail = g_broker_time.DiagnosticLine();
      const string context = "{"
         "\"old_offset_sec\":" + IntegerToString(g_broker_time.PreviousOffsetSeconds()) + ","
         "\"new_offset_sec\":" + IntegerToString(g_broker_time.OffsetSeconds()) +
      "}";
      g_log.Warn("broker_time_offset_changed " + detail);
      g_wire.SendErrorReportWithContext("WARN", "BROKER_TIME_OFFSET_CHANGED", detail, context, false);
   }

   g_wire.Pump();
   g_state_reporter.Pump();

   string msg;
   while(g_wire.Receive(msg))
      g_log.Debug("received_application_message=" + msg);

   const uint brain_timeout_ms = (uint)(InpBrainTimeoutSec > 0 ? InpBrainTimeoutSec : 0) * 1000;
   if(g_wire.IsAuthenticated() && g_wire.MsSinceLastInbound() >= brain_timeout_ms)
      g_log.Warn("brain_timeout_warning ms_since_last_inbound=" + IntegerToString(g_wire.MsSinceLastInbound()));
}

void OnTick()
{
   g_state_reporter.OnTickSample();
}
