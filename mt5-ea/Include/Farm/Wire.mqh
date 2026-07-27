#ifndef FARM_WIRE_MQH
#define FARM_WIRE_MQH

#include "Json.mqh"
#include "Logger.mqh"

#define FARM_WIRE_MAX_FRAME_BYTES 65536
#define FARM_WIRE_READ_CHUNK_BYTES 4096
#define FARM_WIRE_HELLO_ACK_TIMEOUT_SEC 5
#define FARM_WIRE_FAILED_AUTH_RETRY_SEC 60
#define FARM_WIRE_HEARTBEAT_MISS_LIMIT 3

enum ENUM_WIRE_STATE {
   WIRE_DISCONNECTED,
   WIRE_CONNECTING,
   WIRE_CONNECTED,
   WIRE_AUTHENTICATING,
   WIRE_READY,
   WIRE_FAILED_AUTH
};

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
   long            m_messages_sent;
   long            m_messages_recv;
   long            m_reconnect_count;
   long            m_bytes_dropped;
   long            m_queue_drop_count;
   string          m_session_id;
   string          m_ea_version;
   string          m_strategy_id;
   int             m_magic;
   bool            m_verbose;
   CFarmLogger     m_log;

   uint NowTick() const
   {
      return GetTickCount();
   }

   int ElapsedSec(const uint since_tick) const
   {
      return (int)((NowTick() - since_tick) / 1000);
   }

   void EnterState(const ENUM_WIRE_STATE state)
   {
      m_state = state;
      m_state_entered_tick = NowTick();
   }

   int JitteredBackoffMs() const
   {
      const int jitter = (int)MathRound((double)m_backoff_sec * 1000.0 * 0.2);
      const int spread = (jitter > 0 ? (int)(GetTickCount() % (uint)(jitter * 2 + 1)) - jitter : 0);
      return m_backoff_sec * 1000 + spread;
   }

   void ScheduleReconnect()
   {
      const int wait_ms = JitteredBackoffMs();
      m_next_connect_tick = NowTick() + (uint)(wait_ms > 100 ? wait_ms : 100);
      const int next_backoff = m_backoff_sec * 2;
      m_backoff_sec = (next_backoff < 30 ? next_backoff : 30);
      EnterState(WIRE_DISCONNECTED);
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

   string NextMsgId()
   {
      static ulong seq = 0;
      seq++;
      return StringFormat("%I64u%08u", (ulong)TimeCurrent(), (uint)(seq % 100000000));
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
      const string session = StringFormat("acct-%I64d-%s-%s", login, symbol, EnumToString((ENUM_TIMEFRAMES)Period()));
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

      return "{"
         "\"token\":" + FarmJsonQuote(m_token) + ","
         "\"ea_version\":" + FarmJsonQuote(m_ea_version) + ","
         "\"terminal_build\":" + IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)) + ","
         "\"account\":" + account + ","
         "\"symbol\":" + symbol_json + ","
         "\"timeframe\":" + FarmJsonQuote(EnumToString((ENUM_TIMEFRAMES)Period())) + ","
         "\"strategy_id\":" + FarmJsonQuote(m_strategy_id) + ","
         "\"magic\":" + IntegerToString(m_magic) + ","
         "\"local_limits\":" + limits +
      "}";
   }

   void SendHello()
   {
      const string payload = BuildHelloPayload();
      const string hello = FarmMakeEnvelope("HELLO", NextMsgId(), m_session_id, TimeCurrent(), payload);
      SendRawLine(hello);
      EnterState(WIRE_AUTHENTICATING);
   }

   void SendHeartbeat()
   {
      const string payload = "{\"uptime_sec\":" + IntegerToString((int)(GetTickCount() / 1000)) + "}";
      const string msg = FarmMakeEnvelope("HEARTBEAT", NextMsgId(), m_session_id, TimeCurrent(), payload);
      if(SendRawLine(msg))
      {
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
      SendRawLine(FarmMakeEnvelope("ERROR", NextMsgId(), m_session_id, TimeCurrent(), payload));
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
      if(type == "HELLO_ACK")
      {
         const bool accepted = FarmJsonGetBool(line, "accepted", false);
         if(accepted)
         {
            m_session_id = FarmJsonGetString(line, "assigned_session_id", m_session_id);
            m_missed_heartbeat_acks = 0;
            m_backoff_sec = 1;
            EnterState(WIRE_READY);
            m_log.Info("wire_ready session_id=" + m_session_id);
         }
         else
         {
            const string reason = FarmJsonGetString(line, "reject_reason", "UNKNOWN");
            m_log.Error("hello_rejected reason=" + reason);
            CloseSocket();
            EnterState(WIRE_FAILED_AUTH);
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

   void ReadAvailable()
   {
      if(m_socket == INVALID_HANDLE || !SocketIsConnected(m_socket))
         return;

      while(SocketIsReadable(m_socket))
      {
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
      EnterState(WIRE_CONNECTING);
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

      EnterState(WIRE_CONNECTED);
      m_reconnect_count++;
      SendHello();
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
      m_messages_sent = 0;
      m_messages_recv = 0;
      m_reconnect_count = 0;
      m_bytes_dropped = 0;
      m_queue_drop_count = 0;
      m_ea_version = "1.0.0";
      m_strategy_id = "trend_v1";
      m_magic = 770001;
      m_verbose = false;
      m_log.Init("wire", false);
   }

   bool Init(const string host, const int port, const string token,
             const int connect_timeout_ms = 3000)
   {
      m_host = host;
      m_port = port;
      m_token = token;
      m_connect_timeout_ms = connect_timeout_ms;
      if(StringLen(m_token) == 0)
      {
         m_log.Fatal("InpBrainToken is empty");
         return false;
      }
      m_next_connect_tick = 0;
      m_backoff_sec = 1;
      EnterState(WIRE_DISCONNECTED);
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
         SendRawLine(FarmMakeEnvelope("ERROR", NextMsgId(), m_session_id, TimeCurrent(), payload));
      }
      CloseSocket();
      EnterState(WIRE_DISCONNECTED);
   }

   void Pump()
   {
      const ulong started = GetMicrosecondCount();

      if(m_state == WIRE_DISCONNECTED || m_state == WIRE_FAILED_AUTH)
         TryConnect();

      if(m_socket != INVALID_HANDLE && !SocketIsConnected(m_socket))
      {
         m_log.Warn("socket_disconnected");
         CloseSocket();
         ScheduleReconnect();
      }

      ReadAvailable();

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

#ifdef FARM_TEST
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
      EnterState(state);
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
