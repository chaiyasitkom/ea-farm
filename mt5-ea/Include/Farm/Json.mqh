#ifndef FARM_JSON_MQH
#define FARM_JSON_MQH

string FarmStringTrim(const string raw)
{
   int start = 0;
   int end = StringLen(raw) - 1;
   while(start <= end && StringGetCharacter(raw, start) <= ' ')
      start++;
   while(end >= start && StringGetCharacter(raw, end) <= ' ')
      end--;
   if(end < start)
      return "";
   return StringSubstr(raw, start, end - start + 1);
}

string FarmJsonEscape(const string raw)
{
   string out = "";
   const int len = StringLen(raw);
   for(int i = 0; i < len; i++)
   {
      const ushort ch = StringGetCharacter(raw, i);
      if(ch == '\\')
         out += "\\\\";
      else if(ch == '"')
         out += "\\\"";
      else if(ch == '\n')
         out += "\\n";
      else if(ch == '\r')
         out += "\\r";
      else if(ch == '\t')
         out += "\\t";
      else
         out += ShortToString(ch);
   }
   return out;
}

string FarmJsonQuote(const string raw)
{
   return "\"" + FarmJsonEscape(raw) + "\"";
}

int FarmUtf8ByteLen(const string raw)
{
   uchar data[];
   const int bytes_with_null = StringToCharArray(raw, data, 0, WHOLE_ARRAY, CP_UTF8);
   if(bytes_with_null <= 0)
      return 0;
   return bytes_with_null - 1;
}

string FarmBoolJson(const bool value)
{
   return value ? "true" : "false";
}

string FarmDoubleJson(const double value, const int digits=8)
{
   return DoubleToString(value, digits);
}

string FarmFormatIsoUtc(const datetime utc_time)
{
   MqlDateTime dt;
   TimeToStruct(utc_time, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

string FarmJsonGetString(const string json, const string key, const string fallback="")
{
   const string needle = "\"" + key + "\"";
   int pos = StringFind(json, needle);
   if(pos < 0)
      return fallback;
   pos = StringFind(json, ":", pos + StringLen(needle));
   if(pos < 0)
      return fallback;
   pos++;
   while(pos < StringLen(json) && StringGetCharacter(json, pos) <= ' ')
      pos++;
   if(pos >= StringLen(json) || StringGetCharacter(json, pos) != '"')
      return fallback;
   pos++;

   string out = "";
   bool escaped = false;
   for(int i = pos; i < StringLen(json); i++)
   {
      const ushort ch = StringGetCharacter(json, i);
      if(escaped)
      {
         if(ch == 'n')
            out += "\n";
         else if(ch == 'r')
            out += "\r";
         else if(ch == 't')
            out += "\t";
         else
            out += ShortToString(ch);
         escaped = false;
         continue;
      }
      if(ch == '\\')
      {
         escaped = true;
         continue;
      }
      if(ch == '"')
         return out;
      out += ShortToString(ch);
   }
   return fallback;
}

bool FarmJsonGetBool(const string json, const string key, const bool fallback=false)
{
   const string needle = "\"" + key + "\"";
   int pos = StringFind(json, needle);
   if(pos < 0)
      return fallback;
   pos = StringFind(json, ":", pos + StringLen(needle));
   if(pos < 0)
      return fallback;
   pos++;
   while(pos < StringLen(json) && StringGetCharacter(json, pos) <= ' ')
      pos++;
   if(StringSubstr(json, pos, 4) == "true")
      return true;
   if(StringSubstr(json, pos, 5) == "false")
      return false;
   return fallback;
}

bool FarmJsonLooksLikeObject(const string line)
{
   const string trimmed = FarmStringTrim(line);
   return StringLen(trimmed) >= 2
          && StringGetCharacter(trimmed, 0) == '{'
          && StringGetCharacter(trimmed, StringLen(trimmed) - 1) == '}';
}

string FarmMakeEnvelope(const string type, const string msg_id, const string session_id,
                        const datetime server_utc, const datetime sent_utc,
                        const string payload_json)
{
   const string ts_server = FarmFormatIsoUtc(server_utc);
   const string ts_sent = FarmFormatIsoUtc(sent_utc);
   return "{"
          "\"v\":1,"
          "\"type\":" + FarmJsonQuote(type) + ","
          "\"msg_id\":" + FarmJsonQuote(msg_id) + ","
          "\"session_id\":" + FarmJsonQuote(session_id) + ","
          "\"ts_server\":" + FarmJsonQuote(ts_server) + ","
          "\"ts_sent\":" + FarmJsonQuote(ts_sent) + ","
          "\"payload\":" + payload_json +
          "}";
}

#endif
