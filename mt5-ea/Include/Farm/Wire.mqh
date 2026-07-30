#ifndef FARM_WIRE_MQH
#define FARM_WIRE_MQH

#include "BrokerTime.mqh"
#include "Json.mqh"
#include "Logger.mqh"

#define FARM_WIRE_MAX_FRAME_BYTES 65536
#define FARM_WIRE_READ_CHUNK_BYTES 4096
#define FARM_WIRE_HELLO_ACK_TIMEOUT_SEC 5
#define FARM_WIRE_FAILED_AUTH_RETRY_SEC 60
#define FARM_WIRE_HEARTBEAT_MISS_LIMIT 3
#define FARM_ULID_ALPHABET "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
#define FARM_WIRE_DIAG_FILE "ea-farm-wire-diag.jsonl"

enum ENUM_WIRE_STATE {
   WIRE_DISCONNECTED,
   WIRE_CONNECTING,
   WIRE_CONNECTED,
   WIRE_AUTHENTICATING,
   WIRE_READY,
   WIRE_FAILED_AUTH
};

string FarmCrockford32Char(const int value)
{
   return StringSubstr(FARM_ULID_ALPHABET, (value & 31), 1);
}

void FarmSeedUlidRandom(const datetime local_entropy = 0)
{
   const ulong seed = (ulong)GetMicrosecondCount()
                      ^ (ulong)GetTickCount64()
                      ^ (ulong)local_entropy
                      ^ (ulong)ChartID()
                      ^ (ulong)AccountInfoInteger(ACCOUNT_LOGIN);
   MathSrand((int)(seed % 2147483647ULL));
}

string FarmRandomUlidSuffix(const datetime local_entropy = 0)
{
   FarmSeedUlidRandom(local_entropy);
   string out = "";
   for(int i = 0; i < 16; i++)
      out += FarmCrockford32Char(MathRand());
   return out;
}

string FarmEncodeUlidTimestamp(ulong timestamp_ms)
{
   string out = "";
   for(int i = 0; i < 10; i++)
   {
      out = FarmCrockford32Char((int)(timestamp_ms % 32ULL)) + out;
      timestamp_ms /= 32ULL;
   }
   return out;
}

string FarmTimeframeCode(const ENUM_TIMEFRAMES timeframe)
{
   if(timeframe == PERIOD_M1)
      return "M1";
   if(timeframe == PERIOD_M5)
      return "M5";
   if(timeframe == PERIOD_M10)
      return "M10";
   if(timeframe == PERIOD_M15)
      return "M15";
   if(timeframe == PERIOD_M30)
      return "M30";
   if(timeframe == PERIOD_H1)
      return "H1";
   if(timeframe == PERIOD_H4)
      return "H4";
   return "";
}

class CWire {
private:
   string          m_host;
   int             m_port;
   string          m_token;
   int             m_connect_timeout_ms;
   int             m_heartbeat_sec;
   int             m_queue_max;
   ENUM_WIRE_STATE m_state;
   int             m_socket;
   uchar           m_inbound_bytes[];
   string          m_outbound_queue[];
   string          m_received_queue[];
   uchar           m_partial_send_bytes[];
   uint            m_next_connect_tick;
   uint            m_state_entered_tick;
   uint            m_last_inbound_tick;
   uint            m_last_heartbeat_tick;
   int             m_backoff_sec;
   int             m_missed_heartbeat_acks;
   int             m_heartbeat_seq;
   ulong           m_pump_samples_us[];
   int             m_pump_sample_next;
   int             m_pump_sample_count;
   long            m_messages_sent;
   long            m_messages_recv;
   long            m_reconnect_count;
   long            m_bytes_dropped;
   long            m_messages_dropped_no_time_total;
   long            m_messages_dropped_no_time_current;
   long            m_queue_drop_count;
   ulong           m_ulid_last_ms;
   string          m_ulid_rand_suffix;
   string          m_session_id;
   string          m_ea_version;
   string          m_strategy_id;
   int             m_magic;
   bool            m_verbose;
   int             m_diag_handle;
   CFarmLogger     m_log;
   CBrokerTime    *m_broker_time;

   uint NowTick() const
   {
      return GetTickCount();
   }

   int ElapsedSec(const uint since_tick) const
   {
      return (int)((NowTick() - since_tick) / 1000);
   }

   string WireStateTextRaw(const ENUM_WIRE_STATE state) const
   {
      if(state == WIRE_DISCONNECTED)
         return "DISCONNECTED";
      if(state == WIRE_CONNECTING)
         return "CONNECTING";
      if(state == WIRE_CONNECTED)
         return "CONNECTED";
      if(state == WIRE_AUTHENTICATING)
         return "AUTHENTICATING";
      if(state == WIRE_READY)
         return "READY";
      if(state == WIRE_FAILED_AUTH)
         return "FAILED_AUTH";
      return "DISCONNECTED";
   }

   string DiagTsJson() const
   {
      datetime wire_utc = 0;
      if(m_broker_time != NULL && m_broker_time.IsValid())
         wire_utc = m_broker_time.NowUtc();
      if(wire_utc > 0)
         return FarmJsonQuote(FarmFormatIsoUtc(wire_utc));
      return FarmJsonQuote(StringFormat("tick_ms:%I64u", GetTickCount64()));
   }

   void WriteDiagLine(const string json)
   {
      if(!m_verbose || m_diag_handle == INVALID_HANDLE)
         return;
      FileWriteString(m_diag_handle, json + "\n");
      FileFlush(m_diag_handle);
   }

   void OpenDiagFile()
   {
      if(!m_verbose || m_diag_handle != INVALID_HANDLE)
         return;
      ResetLastError();
      m_diag_handle = FileOpen(FARM_WIRE_DIAG_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
      if(m_diag_handle == INVALID_HANDLE)
         m_log.Warn(StringFormat("wire_diag_file_open_failed path=FILE_COMMON\\%s err=%d", FARM_WIRE_DIAG_FILE, GetLastError()));
   }

   void CloseDiagFile()
   {
      if(m_diag_handle == INVALID_HANDLE)
         return;
      FileFlush(m_diag_handle);
      FileClose(m_diag_handle);
      m_diag_handle = INVALID_HANDLE;
   }

   void EnterState(const ENUM_WIRE_STATE state, const string reason)
   {
      const ENUM_WIRE_STATE previous = m_state;
      m_state = state;
      m_state_entered_tick = NowTick();
      WriteDiagLine("{"
         "\"ev\":\"state\","
         "\"ts\":" + DiagTsJson() + ","
         "\"from\":" + FarmJsonQuote(WireStateTextRaw(previous)) + ","
         "\"to\":" + FarmJsonQuote(WireStateTextRaw(state)) + ","
         "\"reason\":" + FarmJsonQuote(reason) +
      "}");
   }

   void EnterState(const ENUM_WIRE_STATE state)
   {
      EnterState(state, "EnterState");
   }

   int JitteredBackoffMs() const
   {
      const int jitter = (int)MathRound((double)m_backoff_sec * 1000.0 * 0.2);
      const int spread = (jitter > 0 ? (int)(GetTickCount() % (uint)(jitter * 2 + 1)) - jitter : 0);
      return m_backoff_sec * 1000 + spread;
   }

   string WireStateText(const ENUM_WIRE_STATE state) const
   {
      return WireStateTextRaw(state);
   }

   string WireStateText() const
   {
      return WireStateText(m_state);
   }

   void RecordPumpElapsed(const ulong elapsed_us)
   {
      if(ArraySize(m_pump_samples_us) != 100)
         ArrayResize(m_pump_samples_us, 100);
      m_pump_samples_us[m_pump_sample_next] = elapsed_us;
      m_pump_sample_next = (m_pump_sample_next + 1) % 100;
      if(m_pump_sample_count < 100)
         m_pump_sample_count++;
   }

   ulong PumpP99Us() const
   {
      if(m_pump_sample_count <= 0)
         return 0;

      ulong sorted[];
      ArrayResize(sorted, m_pump_sample_count);
      for(int i = 0; i < m_pump_sample_count; i++)
         sorted[i] = m_pump_samples_us[i];

      ArraySort(sorted);
      int idx = (int)MathCeil((double)m_pump_sample_count * 0.99) - 1;
      if(idx < 0)
         idx = 0;
      if(idx >= m_pump_sample_count)
         idx = m_pump_sample_count - 1;
      return sorted[idx];
   }

   void ScheduleReconnect()
   {
      const int wait_ms = JitteredBackoffMs();
      const int scheduled_backoff_sec = m_backoff_sec;
      m_next_connect_tick = NowTick() + (uint)(wait_ms > 100 ? wait_ms : 100);
      const int next_backoff = m_backoff_sec * 2;
      m_backoff_sec = (next_backoff < 30 ? next_backoff : 30);
      WriteDiagLine("{"
         "\"ev\":\"reconnect\","
         "\"ts\":" + DiagTsJson() + ","
         "\"backoff_sec\":" + IntegerToString(scheduled_backoff_sec) +
      "}");
      EnterState(WIRE_DISCONNECTED, "ScheduleReconnect");
   }

   void CloseSocket()
   {
      if(m_socket != INVALID_HANDLE)
      {
         SocketClose(m_socket);
         m_socket = INVALID_HANDLE;
      }
      ArrayResize(m_partial_send_bytes, 0);
      ArrayResize(m_inbound_bytes, 0);
   }

   string NextMsgIdFromMs(ulong timestamp_ms)
   {
      if(timestamp_ms <= m_ulid_last_ms)
         timestamp_ms = m_ulid_last_ms + 1ULL;
      m_ulid_last_ms = timestamp_ms;
      return FarmEncodeUlidTimestamp(timestamp_ms) + m_ulid_rand_suffix;
   }

   string NextMsgId()
   {
      datetime utc_now = 0;
      if(m_broker_time != NULL && m_broker_time.IsValid())
         utc_now = m_broker_time.NowUtc();
      if(utc_now <= 0)
         return "";
      return NextMsgIdFromMs((ulong)utc_now * 1000ULL);
   }

   datetime NowUtcForWire() const
   {
      if(m_broker_time != NULL && m_broker_time.IsValid())
         return m_broker_time.NowUtc();
      return 0;
   }

   bool MakeWireEnvelope(const string type, const string payload_json, string &out_line)
   {
      out_line = "";
      const datetime wire_utc = NowUtcForWire();
      if(wire_utc <= 0)
      {
         m_messages_dropped_no_time_total++;
         m_messages_dropped_no_time_current++;
         if((m_messages_dropped_no_time_current % 10) == 1)
            m_log.Warn(StringFormat("message_dropped_no_broker_time type=%s current_drops=%I64d total_drops=%I64d", type, m_messages_dropped_no_time_current, m_messages_dropped_no_time_total));
         return false;
      }
      const string msg_id = NextMsgId();
      if(StringLen(msg_id) == 0)
      {
         m_messages_dropped_no_time_total++;
         m_messages_dropped_no_time_current++;
         if((m_messages_dropped_no_time_current % 10) == 1)
            m_log.Warn(StringFormat("message_dropped_no_broker_time type=%s current_drops=%I64d total_drops=%I64d", type, m_messages_dropped_no_time_current, m_messages_dropped_no_time_total));
         return false;
      }
      if(m_messages_dropped_no_time_current > 0)
      {
         m_log.Warn(StringFormat("broker_time_restored dropped_no_time=%I64d total_drops=%I64d", m_messages_dropped_no_time_current, m_messages_dropped_no_time_total));
         m_messages_dropped_no_time_current = 0;
      }
      out_line = FarmMakeEnvelope(type, msg_id, m_session_id, wire_utc, wire_utc, payload_json);
      return true;
   }

   bool HasPartialSend() const
   {
      return ArraySize(m_partial_send_bytes) > 0;
   }

   void AppendInboundBytes(uchar &data[], const int count)
   {
      if(count <= 0)
         return;
      const int old_size = ArraySize(m_inbound_bytes);
      ArrayResize(m_inbound_bytes, old_size + count);
      for(int i = 0; i < count; i++)
         m_inbound_bytes[old_size + i] = data[i];
   }

   bool InboundHasNewline() const
   {
      const int size = ArraySize(m_inbound_bytes);
      for(int i = 0; i < size; i++)
      {
         if(m_inbound_bytes[i] == 10)
            return true;
      }
      return false;
   }

   bool SendBytes(uchar &data[])
   {
      const int total = ArraySize(data);
      if(total <= 0)
         return true;

      ResetLastError();
      const int sent = SocketSend(m_socket, data, (uint)total);
      if(sent < 0)
      {
         m_log.Warn(StringFormat("socket_send_failed err=%d", GetLastError()));
         CloseSocket();
         ScheduleReconnect();
         return false;
      }

      if(sent < total)
      {
         ArrayResize(m_partial_send_bytes, total - sent);
         for(int i = sent; i < total; i++)
            m_partial_send_bytes[i - sent] = data[i];
      }
      else
      {
         ArrayResize(m_partial_send_bytes, 0);
      }
      return true;
   }

   bool SendRawLine(const string line)
   {
      string frame = line;
      if(StringLen(frame) == 0 || StringGetCharacter(frame, StringLen(frame) - 1) != '\n')
         frame += "\n";

      uchar data[];
      const int total = StringToCharArray(frame, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
      if(total < 0)
         return false;
      if(total <= 0)
         return true;

      ArrayResize(data, total);
      if(!SendBytes(data))
         return false;
      m_messages_sent++;
      return true;
   }

   bool DrainPartialSend()
   {
      if(!HasPartialSend())
         return true;
      uchar pending[];
      const int total = ArraySize(m_partial_send_bytes);
      ArrayResize(pending, total);
      for(int i = 0; i < total; i++)
         pending[i] = m_partial_send_bytes[i];
      ArrayResize(m_partial_send_bytes, 0);
      return SendBytes(pending);
   }

   void DropOldestForCapacity()
   {
      const int depth = ArraySize(m_outbound_queue);
      if(depth < m_queue_max)
         return;

      m_bytes_dropped += FarmUtf8ByteLen(m_outbound_queue[0]);
      for(int i = 1; i < depth; i++)
         m_outbound_queue[i - 1] = m_outbound_queue[i];
      ArrayResize(m_outbound_queue, depth - 1);
      m_queue_drop_count++;
      if((m_queue_drop_count % 10) == 1)
         m_log.Warn(StringFormat("send_queue_full_drop_oldest drops=%I64d", m_queue_drop_count));
   }

   void DrainQueue()
   {
      if(m_state != WIRE_READY)
         return;
      if(!DrainPartialSend())
         return;

      while(ArraySize(m_outbound_queue) > 0 && !HasPartialSend() && SocketIsConnected(m_socket))
      {
         const string line = m_outbound_queue[0];
         const int depth = ArraySize(m_outbound_queue);
         for(int i = 1; i < depth; i++)
            m_outbound_queue[i - 1] = m_outbound_queue[i];
         ArrayResize(m_outbound_queue, depth - 1);
         if(!SendRawLine(line))
            return;
      }
   }

   bool QueueLine(const string json_line)
   {
      if(m_queue_max <= 0)
         return false;
      DropOldestForCapacity();
      const int depth = ArraySize(m_outbound_queue);
      if(depth >= m_queue_max)
         return false;
      ArrayResize(m_outbound_queue, depth + 1);
      m_outbound_queue[depth] = json_line;
      return true;
   }

   string AccountMarginModeText() const
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

   string TradeModeText(const long mode) const
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

   bool SymbolCloseBySupported(const string symbol) const
   {
      const long order_mode = SymbolInfoInteger(symbol, SYMBOL_ORDER_MODE);
      return ((order_mode & SYMBOL_ORDER_CLOSEBY) == SYMBOL_ORDER_CLOSEBY);
   }

   string BuildHelloPayload()
   {
      const string symbol = Symbol();
      const long login = AccountInfoInteger(ACCOUNT_LOGIN);
      const string timeframe = FarmTimeframeCode((ENUM_TIMEFRAMES)Period());
      const string session = StringFormat("acct-%I64d-%s-%s", login, symbol, timeframe);
      m_session_id = session;

      const string account = "{"
         "\"login\":" + IntegerToString(login) + ","
         "\"server\":" + FarmJsonQuote(AccountInfoString(ACCOUNT_SERVER)) + ","
         "\"currency\":" + FarmJsonQuote(AccountInfoString(ACCOUNT_CURRENCY)) + ","
         "\"leverage\":" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LEVERAGE)) + ","
         "\"balance\":" + FarmDoubleJson(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ","
         "\"equity\":" + FarmDoubleJson(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ","
         "\"is_demo\":" + FarmBoolJson(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO) + ","
         "\"margin_mode\":" + FarmJsonQuote(AccountMarginModeText()) +
      "}";

      const long trade_mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      const string symbol_json = "{"
         "\"name\":" + FarmJsonQuote(symbol) + ","
         "\"digits\":" + IntegerToString((int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)) + ","
         "\"point\":" + FarmDoubleJson(SymbolInfoDouble(symbol, SYMBOL_POINT), 10) + ","
         "\"tick_size\":" + FarmDoubleJson(SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE), 10) + ","
         "\"tick_value\":" + FarmDoubleJson(SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE), 8) + ","
         "\"contract_size\":" + FarmDoubleJson(SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE), 2) + ","
         "\"volume_min\":" + FarmDoubleJson(SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN), 2) + ","
         "\"volume_max\":" + FarmDoubleJson(SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX), 2) + ","
         "\"volume_step\":" + FarmDoubleJson(SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP), 2) + ","
         "\"stops_level\":" + IntegerToString((int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL)) + ","
         "\"freeze_level\":" + IntegerToString((int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL)) + ","
         "\"swap_long\":" + FarmDoubleJson(SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG), 8) + ","
         "\"swap_short\":" + FarmDoubleJson(SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT), 8) + ","
         "\"trade_mode\":" + FarmJsonQuote(TradeModeText(trade_mode)) + ","
         "\"order_mode_closeby\":" + FarmBoolJson(SymbolCloseBySupported(symbol)) +
      "}";

      const string limits = "{"
         "\"max_lot_per_order\":0.50,"
         "\"max_net_volume_per_symbol\":0.50,"
         "\"max_tickets_per_symbol\":4,"
         "\"max_total_tickets\":8,"
         "\"max_spread_points\":25,"
         "\"daily_loss_pct\":2.0,"
         "\"max_dd_pct\":6.0"
      "}";

      string broker_time_field = "";
      if(m_broker_time != NULL && m_broker_time.IsValid())
      {
         const string broker_time = "{"
            "\"utc_offset_sec\":" + IntegerToString(m_broker_time.OffsetSeconds()) + ","
            "\"detected_at\":" + FarmJsonQuote(FarmFormatIsoUtc(m_broker_time.DetectedAtUtc())) + ","
            "\"source\":\"INFERRED_SERVER_MINUS_GMT\","
            "\"local_gmt_offset_sec\":" + IntegerToString(m_broker_time.LocalGmtOffsetSeconds()) + ","
            "\"local_dst_sec\":" + IntegerToString(m_broker_time.LocalDstSeconds()) +
         "}";
         broker_time_field = "\"broker_time\":" + broker_time + ",";
      }

      string payload = "{";
      payload += "\"token\":" + FarmJsonQuote(m_token) + ",";
      payload += "\"ea_version\":" + FarmJsonQuote(m_ea_version) + ",";
      payload += "\"terminal_build\":" + IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)) + ",";
      payload += "\"account\":" + account + ",";
      payload += "\"symbol\":" + symbol_json + ",";
      payload += "\"timeframe\":" + FarmJsonQuote(timeframe) + ",";
      payload += "\"strategy_id\":" + FarmJsonQuote(m_strategy_id) + ",";
      payload += "\"magic\":" + IntegerToString(m_magic) + ",";
      payload += broker_time_field;
      payload += "\"local_limits\":" + limits;
      payload += "}";
      return payload;
   }

   void SendHello()
   {
      const string payload = BuildHelloPayload();
      string hello;
      if(!MakeWireEnvelope("HELLO", payload, hello))
      {
         CloseSocket();
         ScheduleReconnect();
         return;
      }
      SendRawLine(hello);
      EnterState(WIRE_AUTHENTICATING, "SendHello");
   }

   void SendHeartbeat()
   {
      const int seq = m_heartbeat_seq + 1;
      const string payload = "{"
         "\"seq\":" + IntegerToString(seq) + ","
         "\"wire\":{"
            "\"state\":" + FarmJsonQuote(WireStateText()) + ","
            "\"send_queue_depth\":" + IntegerToString(SendQueueDepth()) + ","
            "\"messages_sent\":" + IntegerToString(m_messages_sent) + ","
            "\"messages_recv\":" + IntegerToString(m_messages_recv) + ","
            "\"reconnect_count\":" + IntegerToString(m_reconnect_count) + ","
            "\"bytes_dropped\":" + IntegerToString(m_bytes_dropped) + ","
            "\"seconds_since_last_inbound\":" + IntegerToString(SecondsSinceLastInbound()) + ","
            "\"broker_utc_offset_sec\":" + ((m_broker_time != NULL && m_broker_time.IsValid()) ? IntegerToString(m_broker_time.OffsetSeconds()) : "null") + ","
            "\"pump_p99_us\":" + IntegerToString((long)PumpP99Us()) +
         "}" +
      "}";
      string msg;
      if(!MakeWireEnvelope("HEARTBEAT", payload, msg))
         return;
      if(SendRawLine(msg))
      {
         m_heartbeat_seq = seq;
         m_last_heartbeat_tick = NowTick();
         m_missed_heartbeat_acks++;
      }
   }

   void SendProtocolError(const string code, const string message)
   {
      const string payload = "{"
         "\"code\":" + FarmJsonQuote(code) + ","
         "\"severity\":\"ERROR\","
         "\"message\":" + FarmJsonQuote(message) + ","
         "\"context\":{},"
         "\"fatal\":true"
      "}";
      string line;
      if(MakeWireEnvelope("ERROR", payload, line))
         SendRawLine(line);
   }

   void QueueReceived(const string line)
   {
      const int depth = ArraySize(m_received_queue);
      ArrayResize(m_received_queue, depth + 1);
      m_received_queue[depth] = line;
   }

   void HandleInboundLine(const string line)
   {
      if(!FarmJsonLooksLikeObject(line))
      {
         m_log.Warn("malformed_json_skipped");
         return;
      }

      const string type = FarmJsonGetString(line, "type", "");
      WriteDiagLine("{"
         "\"ev\":\"inbound\","
         "\"ts\":" + DiagTsJson() + ","
         "\"type\":" + FarmJsonQuote(type) +
      "}");
      if(type == "HELLO_ACK")
      {
         const bool accepted = FarmJsonGetBool(line, "accepted", false);
         if(accepted)
         {
            m_session_id = FarmJsonGetString(line, "assigned_session_id", m_session_id);
            m_missed_heartbeat_acks = 0;
            m_heartbeat_seq = 0;
            m_backoff_sec = 1;
            EnterState(WIRE_READY, "HELLO_ACK accepted");
            m_log.Info("wire_ready session_id=" + m_session_id);
         }
         else
         {
            const string reason = FarmJsonGetString(line, "reject_reason", "UNKNOWN");
            m_log.Error("hello_rejected reason=" + reason);
            CloseSocket();
            EnterState(WIRE_FAILED_AUTH, "HELLO_ACK rejected " + reason);
         }
         return;
      }

      if(type == "HEARTBEAT_ACK")
      {
         m_missed_heartbeat_acks = 0;
         return;
      }

      if(type == "")
         m_log.Warn("json_without_type_skipped");
      else if(type == "INTENT" || type == "RISK_DIRECTIVE" || type == "CONFIG_UPDATE")
         QueueReceived(line);
      else
         m_log.Debug("unknown_message_type_skipped type=" + type);
   }

   void ReadAvailable(int &read_loops, int &bytes_read)
   {
      if(m_socket == INVALID_HANDLE || !SocketIsConnected(m_socket))
         return;

      while(SocketIsReadable(m_socket))
      {
         read_loops++;
         uchar buf[];
         ArrayResize(buf, FARM_WIRE_READ_CHUNK_BYTES);
         ResetLastError();
         const int n = SocketRead(m_socket, buf, FARM_WIRE_READ_CHUNK_BYTES, 0);
         if(n < 0)
         {
            m_log.Warn(StringFormat("socket_read_failed err=%d", GetLastError()));
            CloseSocket();
            ScheduleReconnect();
            return;
         }
         if(n == 0)
            break;

         bytes_read += n;
         m_last_inbound_tick = NowTick();
         AppendInboundBytes(buf, n);
         if(ArraySize(m_inbound_bytes) > FARM_WIRE_MAX_FRAME_BYTES && !InboundHasNewline())
         {
            SendProtocolError("PROTOCOL_FRAME_TOO_LARGE",
                              StringFormat("frame %d bytes exceeds %d", ArraySize(m_inbound_bytes), FARM_WIRE_MAX_FRAME_BYTES));
            CloseSocket();
            ScheduleReconnect();
            return;
         }

         string line;
         while(PopFrame(line))
         {
            if(StringLen(line) == 0)
               continue;
            m_messages_recv++;
            HandleInboundLine(line);
         }
      }
   }

   void ReadAvailable()
   {
      int read_loops = 0;
      int bytes_read = 0;
      ReadAvailable(read_loops, bytes_read);
   }

   bool PopFrame(string &out_line)
   {
      int newline = -1;
      const int size = ArraySize(m_inbound_bytes);
      for(int i = 0; i < size; i++)
      {
         if(m_inbound_bytes[i] == 10)
         {
            newline = i;
            break;
         }
      }
      if(newline < 0)
         return false;

      int frame_len = newline;
      if(frame_len > 0 && m_inbound_bytes[frame_len - 1] == 13)
         frame_len--;

      uchar frame[];
      ArrayResize(frame, frame_len);
      for(int i = 0; i < frame_len; i++)
         frame[i] = m_inbound_bytes[i];
      out_line = (frame_len == 0 ? "" : CharArrayToString(frame, 0, frame_len, CP_UTF8));

      const int remaining = size - newline - 1;
      uchar rest[];
      ArrayResize(rest, remaining);
      for(int i = 0; i < remaining; i++)
         rest[i] = m_inbound_bytes[newline + 1 + i];
      ArrayResize(m_inbound_bytes, remaining);
      for(int i = 0; i < remaining; i++)
         m_inbound_bytes[i] = rest[i];
      return true;
   }

   void TryConnect()
   {
      if(m_state == WIRE_FAILED_AUTH && ElapsedSec(m_state_entered_tick) < FARM_WIRE_FAILED_AUTH_RETRY_SEC)
         return;
      if(m_state == WIRE_DISCONNECTED && NowTick() < m_next_connect_tick)
         return;

      CloseSocket();
      EnterState(WIRE_CONNECTING, "TryConnect");
      m_socket = SocketCreate();
      if(m_socket == INVALID_HANDLE)
      {
         m_log.Error(StringFormat("socket_create_failed err=%d", GetLastError()));
         ScheduleReconnect();
         return;
      }

      ResetLastError();
      if(!SocketConnect(m_socket, m_host, (ushort)m_port, m_connect_timeout_ms))
      {
         const int err = GetLastError();
         m_log.Error(StringFormat("socket_connect_failed host=%s port=%d err=%d allow_url_hint=Tools->Options->Expert Advisors->Allow WebRequest/listed socket address",
                                  m_host, m_port, err));
         CloseSocket();
         ScheduleReconnect();
         return;
      }

      EnterState(WIRE_CONNECTED, "TryConnect");
      ResetLastError();
      if(!SocketTimeouts(m_socket, m_connect_timeout_ms, m_connect_timeout_ms))
         m_log.Warn(StringFormat("socket_timeouts_failed err=%d", GetLastError()));
      m_log.Info(StringFormat("socket_connected host=%s port=%d", m_host, m_port));
      m_reconnect_count++;
   }

public:
   CWire()
   {
      m_state = WIRE_DISCONNECTED;
      m_socket = INVALID_HANDLE;
      m_connect_timeout_ms = 3000;
      m_heartbeat_sec = 2;
      m_queue_max = 256;
      m_next_connect_tick = 0;
      m_state_entered_tick = 0;
      m_last_inbound_tick = 0;
      m_last_heartbeat_tick = 0;
      m_backoff_sec = 1;
      m_missed_heartbeat_acks = 0;
      m_heartbeat_seq = 0;
      m_pump_sample_next = 0;
      m_pump_sample_count = 0;
      ArrayResize(m_pump_samples_us, 100);
      m_messages_sent = 0;
      m_messages_recv = 0;
      m_reconnect_count = 0;
      m_bytes_dropped = 0;
      m_messages_dropped_no_time_total = 0;
      m_messages_dropped_no_time_current = 0;
      m_queue_drop_count = 0;
      m_ulid_last_ms = 0;
      m_ulid_rand_suffix = FarmRandomUlidSuffix();
      m_ea_version = "1.0.0";
      m_strategy_id = "trend_v1";
      m_magic = 770001;
      m_verbose = false;
      m_diag_handle = INVALID_HANDLE;
      m_broker_time = NULL;
      m_log.Init("wire", false);
   }

   void UseBrokerTime(CBrokerTime *broker_time)
   {
      m_broker_time = broker_time;
      if(m_broker_time != NULL)
         m_ulid_rand_suffix = FarmRandomUlidSuffix(m_broker_time.LocalTime());
   }

   bool Init(const string host, const int port, const string token,
             const int connect_timeout_ms = 3000)
   {
      const int raw_host_len = StringLen(host);
      const int raw_token_len = StringLen(token);
      m_host = FarmStringTrim(host);
      m_port = port;
      m_token = FarmStringTrim(token);
      m_connect_timeout_ms = connect_timeout_ms;
      m_log.Info(StringFormat("wire_input_lengths host_raw=%d host_effective=%d token_raw=%d token_effective=%d",
                              raw_host_len, StringLen(m_host), raw_token_len, StringLen(m_token)));
      if(StringLen(m_token) == 0)
      {
         m_log.Fatal("InpBrainToken is empty");
         return false;
      }
      m_next_connect_tick = 0;
      m_backoff_sec = 1;
      OpenDiagFile();
      EnterState(WIRE_DISCONNECTED, "Init");
      return true;
   }

   void ConfigureRuntime(const int heartbeat_sec, const int queue_max,
                         const string strategy_id, const int magic, const bool verbose)
   {
      m_heartbeat_sec = (heartbeat_sec > 1 ? heartbeat_sec : 1);
      m_queue_max = (queue_max > 1 ? queue_max : 1);
      m_strategy_id = strategy_id;
      m_magic = magic;
      m_verbose = verbose;
      m_log.Init("wire", verbose);
   }

   void Shutdown()
   {
      if(m_socket != INVALID_HANDLE && SocketIsConnected(m_socket))
      {
         const string payload = "{\"code\":\"EA_SHUTDOWN\",\"severity\":\"WARN\",\"message\":\"EA shutting down\",\"context\":{},\"fatal\":false}";
         string line;
         if(MakeWireEnvelope("ERROR", payload, line))
            SendRawLine(line);
      }
      CloseSocket();
      EnterState(WIRE_DISCONNECTED, "Shutdown");
      CloseDiagFile();
   }

   bool SendErrorReport(const string severity, const string code, const string message, const bool fatal)
   {
      return SendErrorReportWithContext(severity, code, message, "{}", fatal);
   }

   bool SendErrorReportWithContext(const string severity, const string code, const string message,
                                   const string context_json, const bool fatal)
   {
      const string payload = "{"
         "\"code\":" + FarmJsonQuote(code) + ","
         "\"severity\":" + FarmJsonQuote(severity) + ","
         "\"message\":" + FarmJsonQuote(message) + ","
         "\"context\":" + context_json + ","
         "\"fatal\":" + FarmBoolJson(fatal) +
      "}";
      string line;
      if(!MakeWireEnvelope("ERROR", payload, line))
         return false;
      return Send(line);
   }

   void Pump()
   {
      const ulong started = GetMicrosecondCount();
      const ENUM_WIRE_STATE state_at_start = m_state;
      int read_loops = 0;
      int bytes_read = 0;

      if(m_state == WIRE_DISCONNECTED || m_state == WIRE_FAILED_AUTH)
         TryConnect();

      if(m_socket != INVALID_HANDLE && !SocketIsConnected(m_socket))
      {
         m_log.Warn("socket_disconnected");
         CloseSocket();
         ScheduleReconnect();
      }

      ReadAvailable(read_loops, bytes_read);

      if(m_state == WIRE_CONNECTED)
      {
         if(state_at_start == WIRE_CONNECTED)
            SendHello();

         if(m_state == WIRE_CONNECTED && ElapsedSec(m_state_entered_tick) >= FARM_WIRE_HELLO_ACK_TIMEOUT_SEC)
         {
            m_log.Warn("connected_hello_timeout");
            CloseSocket();
            ScheduleReconnect();
         }
      }

      if(m_state == WIRE_AUTHENTICATING && ElapsedSec(m_state_entered_tick) >= FARM_WIRE_HELLO_ACK_TIMEOUT_SEC)
      {
         m_log.Warn("hello_ack_timeout");
         CloseSocket();
         ScheduleReconnect();
      }

      if(m_state == WIRE_READY)
      {
         if(ElapsedSec(m_last_heartbeat_tick) >= m_heartbeat_sec)
            SendHeartbeat();
         if(m_missed_heartbeat_acks >= FARM_WIRE_HEARTBEAT_MISS_LIMIT)
         {
            m_log.Warn("heartbeat_ack_missed_reconnect");
            CloseSocket();
            ScheduleReconnect();
         }
         DrainQueue();
      }

      const ulong elapsed_us = GetMicrosecondCount() - started;
      RecordPumpElapsed(elapsed_us);
      WriteDiagLine("{"
         "\"ev\":\"pump\","
         "\"ts\":" + DiagTsJson() + ","
         "\"state_start\":" + FarmJsonQuote(WireStateText(state_at_start)) + ","
         "\"state_end\":" + FarmJsonQuote(WireStateText(m_state)) + ","
         "\"read_loops\":" + IntegerToString(read_loops) + ","
         "\"bytes_read\":" + IntegerToString(bytes_read) + ","
         "\"pump_us\":" + IntegerToString((long)elapsed_us) +
      "}");
      if(m_verbose)
         m_log.Info(StringFormat("pump_diag state_start=%s state_end=%s read_loops=%d bytes_read=%d pump_elapsed_us=%I64u",
                                 WireStateText(state_at_start), WireStateText(m_state), read_loops, bytes_read, elapsed_us));
      if(elapsed_us > 50000)
         m_log.Warn(StringFormat("pump_slow_us=%I64u", elapsed_us));
      else if(m_verbose && elapsed_us > 20000)
         m_log.Debug(StringFormat("pump_p99_budget_warning_us=%I64u", elapsed_us));
   }

   bool Send(const string json_line)
   {
      if(m_state != WIRE_READY)
         return QueueLine(json_line);
      if(HasPartialSend())
         return QueueLine(json_line);
      return SendRawLine(json_line);
   }

   bool Receive(string &out_json_line)
   {
      out_json_line = "";
      const int depth = ArraySize(m_received_queue);
      if(depth <= 0)
         return false;
      out_json_line = m_received_queue[0];
      for(int i = 1; i < depth; i++)
         m_received_queue[i - 1] = m_received_queue[i];
      ArrayResize(m_received_queue, depth - 1);
      return true;
   }

   bool IsConnected() const
   {
      return m_socket != INVALID_HANDLE && SocketIsConnected(m_socket);
   }

   bool IsAuthenticated() const
   {
      return m_state == WIRE_READY;
   }

   int SecondsSinceLastInbound() const
   {
      return ElapsedSec(m_last_inbound_tick);
   }

   ENUM_WIRE_STATE State() const
   {
      return m_state;
   }

   int SendQueueDepth() const
   {
      return ArraySize(m_outbound_queue);
   }

   long MessagesSent() const
   {
      return m_messages_sent;
   }

   long MessagesRecv() const
   {
      return m_messages_recv;
   }

   long ReconnectCount() const
   {
      return m_reconnect_count;
   }

   long BytesDropped() const
   {
      return m_bytes_dropped;
   }

   long MessagesDroppedNoTime() const
   {
      return m_messages_dropped_no_time_total;
   }

#ifdef FARM_TEST
   string TestNextMsgId()
   {
      return NextMsgId();
   }

   string TestNextMsgIdFromMs(const ulong timestamp_ms)
   {
      return NextMsgIdFromMs(timestamp_ms);
   }

   void TestRecordPumpElapsed(const ulong elapsed_us)
   {
      RecordPumpElapsed(elapsed_us);
   }

   ulong TestPumpP99Us() const
   {
      return PumpP99Us();
   }

   string TestWireStateText() const
   {
      return WireStateText();
   }

   bool TestPopFrame(string &out_line)
   {
      return PopFrame(out_line);
   }

   void TestAppendInbound(const string chunk)
   {
      uchar data[];
      const int total = StringToCharArray(chunk, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
      if(total < 0)
         return;
      if(total > 0)
         AppendInboundBytes(data, total);
   }

   void TestAppendInboundBytes(uchar &data[])
   {
      AppendInboundBytes(data, ArraySize(data));
   }

   bool TestInboundFrameTooLargeNoNewline() const
   {
      return ArraySize(m_inbound_bytes) > FARM_WIRE_MAX_FRAME_BYTES && !InboundHasNewline();
   }

   bool TestQueue(const string line)
   {
      return QueueLine(line);
   }

   void TestHandleInboundLine(const string line)
   {
      HandleInboundLine(line);
   }

   void TestSetState(const ENUM_WIRE_STATE state)
   {
      EnterState(state, "TestSetState");
   }

   int TestReceivedQueueDepth() const
   {
      return ArraySize(m_received_queue);
   }

   void TestSimulatePartialSend(const string line, const int sent_bytes)
   {
      string frame = line;
      if(StringLen(frame) == 0 || StringGetCharacter(frame, StringLen(frame) - 1) != '\n')
         frame += "\n";

      uchar data[];
      const int total = StringToCharArray(frame, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
      if(total < 0)
         return;
      const int sent = (sent_bytes < 0 ? 0 : (sent_bytes > total ? total : sent_bytes));
      ArrayResize(m_partial_send_bytes, total - sent);
      for(int i = sent; i < total; i++)
         m_partial_send_bytes[i - sent] = data[i];
   }

   int TestPartialSendBytes() const
   {
      return ArraySize(m_partial_send_bytes);
   }

   string TestPartialSendAsString() const
   {
      return CharArrayToString(m_partial_send_bytes, 0, ArraySize(m_partial_send_bytes), CP_UTF8);
   }
#endif
};

#endif
