#ifndef FARM_STATE_REPORTER_MQH
#define FARM_STATE_REPORTER_MQH

#include "BrokerTime.mqh"
#include "Logger.mqh"
#include "Wire.mqh"
#include <Farm/FarmMessages.mqh>

#define FARM_STATE_MAX_FRAME_BYTES 65536

string FarmAccountMarginModeText()
{
   const long mode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return "RETAIL_HEDGING";
   if(mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      return "RETAIL_NETTING";
   if(mode == ACCOUNT_MARGIN_MODE_EXCHANGE)
      return "EXCHANGE";
   return "UNKNOWN";
}

string FarmTradeModeText(const long mode)
{
   if(mode == SYMBOL_TRADE_MODE_FULL)
      return "FULL";
   if(mode == SYMBOL_TRADE_MODE_DISABLED)
      return "DISABLED";
   if(mode == SYMBOL_TRADE_MODE_CLOSEONLY)
      return "CLOSE_ONLY";
   if(mode == SYMBOL_TRADE_MODE_LONGONLY)
      return "LONG_ONLY";
   if(mode == SYMBOL_TRADE_MODE_SHORTONLY)
      return "SHORT_ONLY";
   return "UNKNOWN";
}

bool FarmSymbolCloseBySupported(const string symbol)
{
   const long order_mode = SymbolInfoInteger(symbol, SYMBOL_ORDER_MODE);
   return ((order_mode & SYMBOL_ORDER_CLOSEBY) == SYMBOL_ORDER_CLOSEBY);
}

int FarmCurrentSpreadPoints(const string symbol)
{
   const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0;

   MqlTick tick;
   if(SymbolInfoTick(symbol, tick) && tick.ask >= tick.bid && tick.ask > 0.0 && tick.bid > 0.0)
      return (int)MathMax(0.0, MathRound((tick.ask - tick.bid) / point));

   return (int)MathMax(0, (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD));
}

class CStateReporter : public CWirePayloadProvider
{
private:
   CWire       *m_wire;
   CBrokerTime *m_clock;
   CFarmLogger m_log;
   int          m_magic;
   string       m_strategy_id;
   int          m_backfill_bars;
   int          m_state_interval_sec;
   string       m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   string       m_timeframe_code;
   string       m_session_id;
   bool         m_initialized;
   bool         m_backfill_started;
   bool         m_backfill_done;
   int          m_backfill_total;
   int          m_backfill_next_shift;
   int          m_backfill_sent;
   uint         m_backfill_started_tick;
   datetime     m_live_bar_deferred_time;
   datetime     m_last_seen_open_bar;
   uint         m_last_state_tick;
   long         m_last_position_fingerprint;
   double       m_spread_sum;
   int          m_spread_count;
   int          m_spread_max;
   long         m_bars_sent;
   long         m_states_sent;
   long         m_bars_skipped_queue_full;
   long         m_messages_dropped_no_time;
   bool         m_logged_no_time;
   bool         m_logged_spread_zero;
   double       m_equity_hwm;
   double       m_day_start_equity;
   datetime     m_day_start_broker;
   string       m_hwm_key;

   uint NowTick() const
   {
      return GetTickCount();
   }

   int ElapsedSec(const uint tick) const
   {
      return (int)((NowTick() - tick) / 1000);
   }

   string JsonNumber(const double value) const
   {
      return FarmJsonFormatDouble(value);
   }

   bool NormalizePayload(const ENUM_FARM_MSG_TYPE type, const string raw, string &out_payload)
   {
      out_payload = "";
      if(type == FARM_MSG_HELLO)
      {
         FarmHelloPayload payload;
         return FarmParseHello(raw, payload) && FarmSerializeHello(payload, out_payload);
      }
      if(type == FARM_MSG_HEARTBEAT)
      {
         FarmHeartbeatPayload payload;
         return FarmParseHeartbeat(raw, payload) && FarmSerializeHeartbeat(payload, out_payload);
      }
      if(type == FARM_MSG_BAR)
      {
         FarmBarPayload payload;
         return FarmParseBar(raw, payload) && FarmSerializeBar(payload, out_payload);
      }
      if(type == FARM_MSG_STATE)
      {
         FarmStatePayload payload;
         return FarmParseState(raw, payload) && FarmSerializeState(payload, out_payload);
      }
      return false;
   }

   bool SendPayload(const ENUM_FARM_MSG_TYPE type, const string raw_payload)
   {
      if(m_wire == NULL || m_clock == NULL || !m_clock.IsValid())
      {
         m_messages_dropped_no_time++;
         if(!m_logged_no_time)
         {
            m_log.Warn("state_reporter_message_dropped_no_broker_time");
            m_logged_no_time = true;
         }
         return false;
      }

      string payload = "";
      if(!NormalizePayload(type, raw_payload, payload))
      {
         m_log.Error("payload_validation_failed type=" + FarmMsgTypeToString(type) + " err=" + FarmJsonLastError());
         return false;
      }

      const int payload_bytes = FarmUtf8ByteLen(payload);
      if(payload_bytes >= FARM_STATE_MAX_FRAME_BYTES)
      {
         m_log.Error(StringFormat("payload_too_large type=%s bytes=%d", FarmMsgTypeToString(type), payload_bytes));
         return false;
      }

      string line = "";
      if(!m_wire.MakeApplicationEnvelope(FarmMsgTypeToString(type), payload, line))
         return false;

      if(!m_wire.Send(line))
         return false;

      if(type == FARM_MSG_BAR)
         m_bars_sent++;
      else if(type == FARM_MSG_STATE)
         m_states_sent++;
      return true;
   }

   string BuildHelloRaw()
   {
      const long login = AccountInfoInteger(ACCOUNT_LOGIN);
      m_session_id = StringFormat("acct-%I64d-%s-%s", login, m_symbol, m_timeframe_code);

      const string account = "{"
         "\"login\":" + IntegerToString(login) + ","
         "\"server\":" + FarmJsonQuoteUtf8(AccountInfoString(ACCOUNT_SERVER)) + ","
         "\"currency\":" + FarmJsonQuoteUtf8(AccountInfoString(ACCOUNT_CURRENCY)) + ","
         "\"leverage\":" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LEVERAGE)) + ","
         "\"balance\":" + JsonNumber(AccountInfoDouble(ACCOUNT_BALANCE)) + ","
         "\"equity\":" + JsonNumber(AccountInfoDouble(ACCOUNT_EQUITY)) + ","
         "\"is_demo\":" + (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO ? "true" : "false") + ","
         "\"margin_mode\":" + FarmJsonQuoteUtf8(FarmAccountMarginModeText()) +
      "}";

      const long trade_mode = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_MODE);
      const string symbol_json = "{"
         "\"name\":" + FarmJsonQuoteUtf8(m_symbol) + ","
         "\"digits\":" + IntegerToString((int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)) + ","
         "\"point\":" + JsonNumber(SymbolInfoDouble(m_symbol, SYMBOL_POINT)) + ","
         "\"tick_size\":" + JsonNumber(SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE)) + ","
         "\"tick_value\":" + JsonNumber(SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE)) + ","
         "\"contract_size\":" + JsonNumber(SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE)) + ","
         "\"volume_min\":" + JsonNumber(SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN)) + ","
         "\"volume_max\":" + JsonNumber(SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX)) + ","
         "\"volume_step\":" + JsonNumber(SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP)) + ","
         "\"stops_level\":" + IntegerToString((int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL)) + ","
         "\"freeze_level\":" + IntegerToString((int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL)) + ","
         "\"swap_long\":" + JsonNumber(SymbolInfoDouble(m_symbol, SYMBOL_SWAP_LONG)) + ","
         "\"swap_short\":" + JsonNumber(SymbolInfoDouble(m_symbol, SYMBOL_SWAP_SHORT)) + ","
         "\"trade_mode\":" + FarmJsonQuoteUtf8(FarmTradeModeText(trade_mode)) + ","
         "\"order_mode_closeby\":" + (FarmSymbolCloseBySupported(m_symbol) ? "true" : "false") +
      "}";

      string broker_time_field = "";
      if(m_clock != NULL && m_clock.IsValid())
      {
         const string broker_time = "{"
            "\"utc_offset_sec\":" + IntegerToString(m_clock.OffsetSeconds()) + ","
            "\"detected_at\":" + FarmJsonQuoteUtf8(FarmFormatIsoUtc(m_clock.DetectedAtUtc())) + ","
            "\"source\":\"INFERRED_SERVER_MINUS_GMT\","
            "\"local_gmt_offset_sec\":" + IntegerToString(m_clock.LocalGmtOffsetSeconds()) + ","
            "\"local_dst_sec\":" + IntegerToString(m_clock.LocalDstSeconds()) +
         "}";
         broker_time_field = "\"broker_time\":" + broker_time + ",";
      }

      const string limits = "{"
         "\"max_lot_per_order\":0.50,"
         "\"max_net_volume_per_symbol\":0.50,"
         "\"max_tickets_per_symbol\":4,"
         "\"max_total_tickets\":8,"
         "\"max_spread_points\":25,"
         "\"daily_loss_pct\":2.0,"
         "\"max_dd_pct\":6.0"
      "}";

      return "{"
         "\"token\":" + FarmJsonQuoteUtf8(m_wire.Token()) + ","
         "\"ea_version\":\"1.0.0\","
         "\"terminal_build\":" + IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)) + ","
         "\"account\":" + account + ","
         "\"symbol\":" + symbol_json + ","
         "\"timeframe\":" + FarmJsonQuoteUtf8(m_timeframe_code) + ","
         "\"strategy_id\":" + FarmJsonQuoteUtf8(m_strategy_id) + ","
         "\"magic\":" + IntegerToString(m_magic) + ","
         + broker_time_field +
         "\"local_limits\":" + limits +
      "}";
   }

   bool BuildBarRaw(const int shift, string &out_payload)
   {
      out_payload = "";
      if(m_clock == NULL || !m_clock.IsValid())
         return false;
      if(shift <= 0)
         return false;

      const datetime broker_bar = iTime(m_symbol, m_timeframe, shift);
      if(broker_bar <= 0)
         return false;
      const datetime utc_bar = m_clock.BrokerToUtc(broker_bar);
      if(utc_bar <= 0)
         return false;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      const int copied = CopyRates(m_symbol, m_timeframe, shift, 1, rates);
      if(copied != 1)
         return false;

      int spread_avg = 0;
      int spread_max = 0;
      ConsumeSpreadStats(spread_avg, spread_max);

      out_payload = "{"
         "\"symbol\":" + FarmJsonQuoteUtf8(m_symbol) + ","
         "\"timeframe\":" + FarmJsonQuoteUtf8(m_timeframe_code) + ","
         "\"bar_time\":" + FarmJsonQuoteUtf8(FarmFormatIsoUtc(utc_bar)) + ","
         "\"open\":" + JsonNumber(rates[0].open) + ","
         "\"high\":" + JsonNumber(rates[0].high) + ","
         "\"low\":" + JsonNumber(rates[0].low) + ","
         "\"close\":" + JsonNumber(rates[0].close) + ","
         "\"tick_volume\":" + IntegerToString((long)rates[0].tick_volume) + ","
         "\"real_volume\":" + IntegerToString((long)rates[0].real_volume) + ","
         "\"spread_points_avg\":" + IntegerToString(spread_avg) + ","
         "\"spread_points_max\":" + IntegerToString(spread_max) + ","
         "\"is_final\":true"
      "}";
      return true;
   }

   void ConsumeSpreadStats(int &avg, int &max_value)
   {
      if(m_spread_count <= 0)
         OnTickSample();
      if(m_spread_count <= 0)
      {
         avg = 0;
         max_value = 0;
      }
      else
      {
         avg = (int)MathFloor(m_spread_sum / (double)m_spread_count);
         max_value = m_spread_max;
      }
      if(max_value < avg)
         max_value = avg;
      m_spread_sum = 0.0;
      m_spread_count = 0;
      m_spread_max = 0;
   }

   string PriceOrNull(const double value) const
   {
      if(value <= 0.0)
         return "null";
      return JsonNumber(value);
   }

   string PositionSideText(const long type) const
   {
      if(type == POSITION_TYPE_BUY)
         return "BUY";
      if(type == POSITION_TYPE_SELL)
         return "SELL";
      return "UNKNOWN";
   }

   long CurrentPositionFingerprint()
   {
      long fp = 17;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
         fp = fp * 31 + (long)ticket;
         fp = fp * 31 + (long)PositionGetInteger(POSITION_MAGIC);
         fp = fp * 31 + (long)MathRound(PositionGetDouble(POSITION_VOLUME) * 100000.0);
      }
      return fp;
   }

   string BuildPositionsJson(double &owned_net, long &owned_count, bool &has_buy, bool &has_sell,
                             long &foreign_count, double &foreign_volume)
   {
      string positions = "[";
      bool first = true;
      owned_net = 0.0;
      owned_count = 0;
      has_buy = false;
      has_sell = false;
      foreign_count = 0;
      foreign_volume = 0.0;

      for(int i = 0; i < PositionsTotal(); i++)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         const string symbol = PositionGetString(POSITION_SYMBOL);
         const long magic = PositionGetInteger(POSITION_MAGIC);
         const double volume = PositionGetDouble(POSITION_VOLUME);
         const long side_type = PositionGetInteger(POSITION_TYPE);
         const bool owned = (symbol == m_symbol && magic == m_magic);
         if(!owned)
         {
            foreign_count++;
            foreign_volume += volume;
            continue;
         }

         if(owned_count >= 64)
            continue;

         const string side = PositionSideText(side_type);
         if(side == "BUY")
         {
            owned_net += volume;
            has_buy = true;
         }
         else if(side == "SELL")
         {
            owned_net -= volume;
            has_sell = true;
         }

         const datetime time_open = (datetime)PositionGetInteger(POSITION_TIME);
         const datetime utc_open = (m_clock != NULL ? m_clock.BrokerToUtc(time_open) : 0);
         if(utc_open <= 0)
            continue;

         if(!first)
            positions += ",";
         first = false;
         owned_count++;
         const string comment = PositionGetString(POSITION_COMMENT);
         positions += "{"
            "\"ticket\":" + IntegerToString((long)ticket) + ","
            "\"symbol\":" + FarmJsonQuoteUtf8(symbol) + ","
            "\"side\":" + FarmJsonQuoteUtf8(side) + ","
            "\"volume\":" + JsonNumber(volume) + ","
            "\"price_open\":" + JsonNumber(PositionGetDouble(POSITION_PRICE_OPEN)) + ","
            "\"sl\":" + PriceOrNull(PositionGetDouble(POSITION_SL)) + ","
            "\"tp\":" + PriceOrNull(PositionGetDouble(POSITION_TP)) + ","
            "\"profit\":" + JsonNumber(PositionGetDouble(POSITION_PROFIT)) + ","
            "\"swap\":" + JsonNumber(PositionGetDouble(POSITION_SWAP)) + ","
            "\"magic\":" + IntegerToString(magic) + ","
            "\"comment\":" + (StringLen(comment) > 0 ? FarmJsonQuoteUtf8(comment) : "null") + ","
            "\"time_open\":" + FarmJsonQuoteUtf8(FarmFormatIsoUtc(utc_open)) +
         "}";
      }
      positions += "]";
      return positions;
   }

   void RefreshDayAndHwm()
   {
      if(m_clock == NULL || !m_clock.IsValid())
         return;
      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > m_equity_hwm)
      {
         m_equity_hwm = equity;
         GlobalVariableSet(m_hwm_key, m_equity_hwm);
      }

      const datetime broker_now = m_clock.NowBroker();
      const datetime day_start = m_clock.BrokerDayStart(broker_now);
      if(m_day_start_broker <= 0 || day_start != m_day_start_broker)
      {
         m_day_start_broker = day_start;
         m_day_start_equity = equity;
      }
   }

   bool BuildStateRaw(string &out_payload)
   {
      out_payload = "";
      if(m_clock == NULL || !m_clock.IsValid())
         return false;

      RefreshDayAndHwm();

      double owned_net = 0.0;
      long owned_count = 0;
      bool has_buy = false;
      bool has_sell = false;
      long foreign_count = 0;
      double foreign_volume = 0.0;
      const string positions = BuildPositionsJson(owned_net, owned_count, has_buy, has_sell, foreign_count, foreign_volume);
      const bool internal_hedge = has_buy && has_sell;
      const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      const double margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
      const double margin_free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      const string margin_level = (margin_used <= 0.0 ? "null" : JsonNumber(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)));
      const double day_pl = equity - m_day_start_equity;
      const double day_pl_pct = (m_day_start_equity > 0.0 ? day_pl / m_day_start_equity * 100.0 : 0.0);
      const int current_spread = FarmCurrentSpreadPoints(m_symbol);

      out_payload = "{"
         "\"balance\":" + JsonNumber(balance) + ","
         "\"equity\":" + JsonNumber(equity) + ","
         "\"margin_used\":" + JsonNumber(margin_used) + ","
         "\"margin_free\":" + JsonNumber(margin_free) + ","
         "\"margin_level_pct\":" + margin_level + ","
         "\"equity_hwm\":" + JsonNumber(m_equity_hwm) + ","
         "\"day_start_equity\":" + JsonNumber(m_day_start_equity) + ","
         "\"day_pl\":" + JsonNumber(day_pl) + ","
         "\"day_pl_pct\":" + JsonNumber(day_pl_pct) + ","
         "\"positions\":" + positions + ","
         "\"pending_orders\":[],"
         "\"owned_net\":{" + FarmJsonQuoteUtf8(m_symbol) + ":" + JsonNumber(owned_net) + "},"
         "\"owned_ticket_count\":{" + FarmJsonQuoteUtf8(m_symbol) + ":" + IntegerToString(owned_count) + "},"
         "\"foreign_positions\":{\"count\":" + IntegerToString(foreign_count) + ",\"symbols\":[],\"total_volume\":" + JsonNumber(foreign_volume) + ",\"margin_estimate\":0.0},"
         "\"account_margin_mode\":" + FarmJsonQuoteUtf8(FarmAccountMarginModeText()) + ","
         "\"guard\":{\"halted\":false,\"halt_reason\":null,\"mode\":\"NORMAL\",\"current_spread_points\":" + IntegerToString(current_spread) + ",\"internal_hedge_detected\":" + (internal_hedge ? "true" : "false") + ",\"halted_until\":null}"
      "}";
      return true;
   }

   void MaybeStartBackfill()
   {
      if(m_backfill_started || m_wire == NULL || !m_wire.IsAuthenticated())
         return;

      const int available = Bars(m_symbol, m_timeframe) - 1;
      if(available <= 0)
      {
         if(m_backfill_started_tick == 0)
            m_backfill_started_tick = NowTick();
         if(ElapsedSec(m_backfill_started_tick) < 30)
            return;
         m_log.Warn("backfill_history_unavailable total=0");
         m_backfill_total = 0;
         m_backfill_done = true;
         return;
      }

      m_backfill_total = MathMin(m_backfill_bars, available);
      m_backfill_next_shift = m_backfill_total;
      m_backfill_started = true;
      m_backfill_done = (m_backfill_total <= 0);
      m_backfill_started_tick = NowTick();
   }

   void PumpBackfill()
   {
      MaybeStartBackfill();
      if(!m_backfill_started || m_backfill_done || m_wire == NULL)
         return;

      const int half_queue = MathMax(1, m_wire.SendQueueMax() / 2);
      while(m_backfill_next_shift >= 1 && m_wire.SendQueueDepth() < half_queue)
      {
         string payload = "";
         if(!BuildBarRaw(m_backfill_next_shift, payload))
         {
            if(ElapsedSec(m_backfill_started_tick) < 30)
               return;
            m_log.Warn("backfill_bar_unavailable shift=" + IntegerToString(m_backfill_next_shift));
            m_backfill_next_shift--;
            continue;
         }
         const int before_depth = m_wire.SendQueueDepth();
         const long before_dropped = m_wire.BytesDropped();
         if(!SendPayload(FARM_MSG_BAR, payload))
         {
            m_bars_skipped_queue_full++;
            m_log.Warn("backfill_send_deferred shift=" + IntegerToString(m_backfill_next_shift));
            return;
         }
         if(m_wire.SendQueueDepth() < before_depth || m_wire.BytesDropped() != before_dropped)
         {
            m_bars_skipped_queue_full++;
            m_log.Warn("backfill_queue_drop_detected shift=" + IntegerToString(m_backfill_next_shift));
            return;
         }
         m_backfill_sent++;
         m_backfill_next_shift--;
      }

      if(m_backfill_next_shift < 1)
      {
         m_backfill_done = true;
         if(m_backfill_sent < m_backfill_total)
            m_log.Warn(StringFormat("backfill_done sent=%d total=%d", m_backfill_sent, m_backfill_total));
         else
            m_log.Info(StringFormat("backfill_done sent=%d total=%d", m_backfill_sent, m_backfill_total));
      }
   }

   void PumpLiveBar()
   {
      if(m_wire == NULL || !m_wire.IsAuthenticated())
         return;

      const datetime open_bar = iTime(m_symbol, m_timeframe, 0);
      if(open_bar <= 0)
         return;
      if(m_last_seen_open_bar <= 0)
      {
         m_last_seen_open_bar = open_bar;
         return;
      }
      if(open_bar == m_last_seen_open_bar)
         return;

      m_live_bar_deferred_time = m_last_seen_open_bar;
      m_last_seen_open_bar = open_bar;
      if(!m_backfill_done)
         return;

      string payload = "";
      if(BuildBarRaw(1, payload) && !SendPayload(FARM_MSG_BAR, payload))
      {
         m_bars_skipped_queue_full++;
         m_log.Warn("live_bar_send_failed");
      }
      m_live_bar_deferred_time = 0;
   }

   void PumpDeferredLiveBar()
   {
      if(m_live_bar_deferred_time <= 0 || !m_backfill_done)
         return;
      string payload = "";
      if(BuildBarRaw(1, payload) && SendPayload(FARM_MSG_BAR, payload))
         m_live_bar_deferred_time = 0;
   }

   void PumpState()
   {
      if(m_wire == NULL || !m_wire.IsAuthenticated())
         return;
      const long fp = CurrentPositionFingerprint();
      const bool due = (m_last_state_tick == 0 || ElapsedSec(m_last_state_tick) >= m_state_interval_sec);
      const bool changed = (fp != m_last_position_fingerprint);
      if(!due && !changed)
         return;
      string payload = "";
      if(BuildStateRaw(payload) && SendPayload(FARM_MSG_STATE, payload))
      {
         m_last_state_tick = NowTick();
         m_last_position_fingerprint = fp;
      }
   }

public:
   CStateReporter()
   {
      m_wire = NULL;
      m_clock = NULL;
      m_magic = 0;
      m_strategy_id = "";
      m_backfill_bars = 300;
      m_state_interval_sec = 5;
      m_symbol = "";
      m_timeframe = PERIOD_CURRENT;
      m_timeframe_code = "";
      m_session_id = "";
      m_initialized = false;
      m_backfill_started = false;
      m_backfill_done = false;
      m_backfill_total = 0;
      m_backfill_next_shift = 0;
      m_backfill_sent = 0;
      m_backfill_started_tick = 0;
      m_live_bar_deferred_time = 0;
      m_last_seen_open_bar = 0;
      m_last_state_tick = 0;
      m_last_position_fingerprint = 0;
      m_spread_sum = 0.0;
      m_spread_count = 0;
      m_spread_max = 0;
      m_bars_sent = 0;
      m_states_sent = 0;
      m_bars_skipped_queue_full = 0;
      m_messages_dropped_no_time = 0;
      m_logged_no_time = false;
      m_logged_spread_zero = false;
      m_equity_hwm = 0.0;
      m_day_start_equity = 0.0;
      m_day_start_broker = 0;
      m_hwm_key = "";
      m_log.Init("state_reporter", false);
   }

   bool Init(CWire *wire, CBrokerTime *clock,
             const int magic, const string strategy_id,
             const int backfill_bars = 300,
             const int state_interval_sec = 5)
   {
      m_wire = wire;
      m_clock = clock;
      m_magic = magic;
      m_strategy_id = FarmSanitizeInputString(strategy_id);
      m_backfill_bars = (backfill_bars > 0 ? backfill_bars : 300);
      m_state_interval_sec = (state_interval_sec > 0 ? state_interval_sec : 5);
      m_symbol = _Symbol;
      m_timeframe = (ENUM_TIMEFRAMES)Period();
      m_timeframe_code = FarmTimeframeCode(m_timeframe);
      m_log.Init("state_reporter", false);

      if(m_wire == NULL || m_clock == NULL)
         return false;
      if(!FarmIsValidStrategyId(m_strategy_id))
      {
         m_log.Fatal("strategy_id_invalid_after_trim value=" + FarmJsonQuoteUtf8(m_strategy_id));
         return false;
      }
      if(!SymbolSelect(m_symbol, true))
      {
         m_log.Fatal("symbol_select_failed symbol=" + m_symbol);
         return false;
      }
      if(StringLen(m_timeframe_code) == 0)
      {
         m_log.Fatal("unsupported_timeframe actual=" + EnumToString(m_timeframe));
         return false;
      }

      m_hwm_key = StringFormat("ea_farm_equity_hwm_%I64d_%s_%d", AccountInfoInteger(ACCOUNT_LOGIN), m_symbol, m_magic);
      if(GlobalVariableCheck(m_hwm_key))
         m_equity_hwm = GlobalVariableGet(m_hwm_key);
      if(m_equity_hwm <= 0.0)
      {
         m_equity_hwm = AccountInfoDouble(ACCOUNT_EQUITY);
         GlobalVariableSet(m_hwm_key, m_equity_hwm);
      }
      m_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_clock.IsValid())
         m_day_start_broker = m_clock.BrokerDayStart(m_clock.NowBroker());

      string hello_raw = BuildHelloRaw();
      string hello_payload = "";
      if(!NormalizePayload(FARM_MSG_HELLO, hello_raw, hello_payload))
      {
         m_log.Fatal("hello_payload_validation_failed err=" + FarmJsonLastError());
         return false;
      }
      m_wire.SetHelloPayload(hello_payload, m_session_id);
      m_wire.SetPayloadProvider(GetPointer(this));
      m_initialized = true;
      return true;
   }

   void Pump()
   {
      if(!m_initialized)
         return;
      OnTickSample();
      if(m_clock == NULL || !m_clock.IsValid())
      {
         m_messages_dropped_no_time++;
         if(!m_logged_no_time)
         {
            m_log.Warn("state_reporter_waiting_for_valid_broker_time");
            m_logged_no_time = true;
         }
         return;
      }
      m_logged_no_time = false;
      PumpBackfill();
      PumpDeferredLiveBar();
      PumpLiveBar();
      PumpState();
   }

   void OnTickSample()
   {
      const int spread = FarmCurrentSpreadPoints(m_symbol);
      if(spread == 0 && !m_logged_spread_zero)
      {
         m_log.Debug("spread_points_zero symbol=" + m_symbol);
         m_logged_spread_zero = true;
      }
      m_spread_sum += (double)spread;
      m_spread_count++;
      if(spread > m_spread_max)
         m_spread_max = spread;
   }

   bool BackfillDone() const { return m_backfill_done; }
   int  BackfillSent() const { return m_backfill_sent; }
   int  BackfillTotal() const { return m_backfill_total; }
   long BarsSent() const { return m_bars_sent; }
   long StatesSent() const { return m_states_sent; }
   long BarsSkippedQueueFull() const { return m_bars_skipped_queue_full; }

   virtual bool BuildHeartbeatPayload(const int seq,
                                      const string wire_state,
                                      const int send_queue_depth,
                                      const long messages_sent,
                                      const long messages_recv,
                                      const long reconnect_count,
                                      const long bytes_dropped,
                                      const int seconds_since_last_inbound,
                                      const bool broker_offset_known,
                                      const int broker_utc_offset_sec,
                                      const ulong pump_p99_us,
                                      string &out_payload)
   {
      const string raw = "{"
         "\"seq\":" + IntegerToString(seq) + ","
         "\"wire\":{"
            "\"state\":" + FarmJsonQuoteUtf8(wire_state) + ","
            "\"send_queue_depth\":" + IntegerToString(send_queue_depth) + ","
            "\"messages_sent\":" + IntegerToString(messages_sent) + ","
            "\"messages_recv\":" + IntegerToString(messages_recv) + ","
            "\"reconnect_count\":" + IntegerToString(reconnect_count) + ","
            "\"bytes_dropped\":" + IntegerToString(bytes_dropped) + ","
            "\"seconds_since_last_inbound\":" + IntegerToString(seconds_since_last_inbound) + ","
            "\"broker_utc_offset_sec\":" + (broker_offset_known ? IntegerToString(broker_utc_offset_sec) : "null") + ","
            "\"pump_p99_us\":" + IntegerToString((long)pump_p99_us) +
         "}"
      "}";
      return NormalizePayload(FARM_MSG_HEARTBEAT, raw, out_payload);
   }

#ifdef FARM_TEST
   string TestBuildBarPayload(const int shift)
   {
      string payload = "";
      BuildBarRaw(shift, payload);
      string normalized = "";
      NormalizePayload(FARM_MSG_BAR, payload, normalized);
      return normalized;
   }

   string TestBuildStatePayload()
   {
      string payload = "";
      BuildStateRaw(payload);
      string normalized = "";
      NormalizePayload(FARM_MSG_STATE, payload, normalized);
      return normalized;
   }

   void TestForceNewBar()
   {
      m_last_seen_open_bar = 0;
      m_live_bar_deferred_time = iTime(m_symbol, m_timeframe, 1);
   }
#endif
};

#endif
