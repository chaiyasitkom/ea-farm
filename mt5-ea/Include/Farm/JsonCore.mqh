#ifndef FARM_JSON_CORE_MQH
#define FARM_JSON_CORE_MQH

enum ENUM_FARM_JSON_TYPE
{
   FARM_JSON_NULL,
   FARM_JSON_BOOL,
   FARM_JSON_NUMBER,
   FARM_JSON_STRING,
   FARM_JSON_ARRAY,
   FARM_JSON_OBJECT
};

string g_farm_json_last_error = "";

void FarmJsonSetError(const string code, const string detail="")
{
   g_farm_json_last_error = (detail == "" ? code : code + ": " + detail);
}

string FarmJsonLastError()
{
   return g_farm_json_last_error;
}

string FarmJsonEscapeUtf8(const string raw)
{
   string out = "";
   for(int i = 0; i < StringLen(raw); i++)
   {
      const ushort ch = StringGetCharacter(raw, i);
      if(ch == '"')
         out += "\\\"";
      else if(ch == '\\')
         out += "\\\\";
      else if(ch == '\n')
         out += "\\n";
      else if(ch == '\r')
         out += "\\r";
      else if(ch == '\t')
         out += "\\t";
      else if(ch < 32)
         out += StringFormat("\\u%04X", (int)ch);
      else
         out += ShortToString(ch);
   }
   return out;
}

string FarmJsonQuoteUtf8(const string raw)
{
   return "\"" + FarmJsonEscapeUtf8(raw) + "\"";
}

string FarmJsonFormatDouble(const double value)
{
   string out = DoubleToString(value, 10);
   while(StringLen(out) > 0 && StringFind(out, ".") >= 0
         && StringGetCharacter(out, StringLen(out) - 1) == '0')
      out = StringSubstr(out, 0, StringLen(out) - 1);
   if(StringLen(out) > 0 && StringGetCharacter(out, StringLen(out) - 1) == '.')
      out += "0";
   if(StringFind(out, ".") < 0)
      out += ".0";
   return out;
}

class CFarmJsonValue
{
private:
   CFarmJsonValue *m_children[];
   string          m_keys[];

public:
   ENUM_FARM_JSON_TYPE type;
   string              string_value;
   string              number_raw;
   double              number_value;
   long                integer_value;
   bool                bool_value;

   CFarmJsonValue()
   {
      type = FARM_JSON_NULL;
      string_value = "";
      number_raw = "";
      number_value = 0.0;
      integer_value = 0;
      bool_value = false;
   }

   ~CFarmJsonValue()
   {
      Free();
   }

   void Free()
   {
      for(int i = 0; i < ArraySize(m_children); i++)
      {
         if(CheckPointer(m_children[i]) == POINTER_DYNAMIC)
         {
            m_children[i].Free();
            delete m_children[i];
         }
         m_children[i] = NULL;
      }
      ArrayResize(m_children, 0);
      ArrayResize(m_keys, 0);
      string_value = "";
      number_raw = "";
      number_value = 0.0;
      integer_value = 0;
      bool_value = false;
      type = FARM_JSON_NULL;
   }

   int Size() const
   {
      return ArraySize(m_children);
   }

   bool AddArrayItem(CFarmJsonValue *value)
   {
      if(type != FARM_JSON_ARRAY || CheckPointer(value) == POINTER_INVALID)
         return false;
      const int n = ArraySize(m_children);
      ArrayResize(m_children, n + 1);
      ArrayResize(m_keys, n + 1);
      m_children[n] = value;
      m_keys[n] = "";
      return true;
   }

   bool AddObjectItem(const string key, CFarmJsonValue *value)
   {
      if(type != FARM_JSON_OBJECT || CheckPointer(value) == POINTER_INVALID)
         return false;
      const int n = ArraySize(m_children);
      ArrayResize(m_children, n + 1);
      ArrayResize(m_keys, n + 1);
      m_children[n] = value;
      m_keys[n] = key;
      return true;
   }

   CFarmJsonValue *At(const int index) const
   {
      if(index < 0 || index >= ArraySize(m_children))
         return NULL;
      return m_children[index];
   }

   string KeyAt(const int index) const
   {
      if(index < 0 || index >= ArraySize(m_keys))
         return "";
      return m_keys[index];
   }

   CFarmJsonValue *Get(const string key) const
   {
      if(type != FARM_JSON_OBJECT)
         return NULL;
      for(int i = 0; i < ArraySize(m_keys); i++)
      {
         if(m_keys[i] == key)
            return m_children[i];
      }
      return NULL;
   }

   bool Has(const string key) const
   {
      return (Get(key) != NULL);
   }

   string ToJson() const
   {
      if(type == FARM_JSON_NULL)
         return "null";
      if(type == FARM_JSON_BOOL)
         return bool_value ? "true" : "false";
      if(type == FARM_JSON_NUMBER)
         return number_raw;
      if(type == FARM_JSON_STRING)
         return FarmJsonQuoteUtf8(string_value);
      if(type == FARM_JSON_ARRAY)
      {
         string out = "[";
         for(int i = 0; i < ArraySize(m_children); i++)
         {
            if(i > 0)
               out += ",";
            out += m_children[i].ToJson();
         }
         return out + "]";
      }
      if(type == FARM_JSON_OBJECT)
      {
         string out = "{";
         for(int i = 0; i < ArraySize(m_children); i++)
         {
            if(i > 0)
               out += ",";
            out += FarmJsonQuoteUtf8(m_keys[i]) + ":" + m_children[i].ToJson();
         }
         return out + "}";
      }
      return "null";
   }
};

class CFarmJsonParser
{
private:
   string m_text;
   int    m_pos;
   int    m_len;

   ushort Peek() const
   {
      if(m_pos >= m_len)
         return 0;
      return StringGetCharacter(m_text, m_pos);
   }

   ushort Take()
   {
      if(m_pos >= m_len)
         return 0;
      return StringGetCharacter(m_text, m_pos++);
   }

   void SkipWs()
   {
      while(m_pos < m_len && StringGetCharacter(m_text, m_pos) <= ' ')
         m_pos++;
   }

   bool Match(const string token)
   {
      if(StringSubstr(m_text, m_pos, StringLen(token)) != token)
         return false;
      m_pos += StringLen(token);
      return true;
   }

   bool ParseString(string &out)
   {
      out = "";
      if(Take() != '"')
      {
         FarmJsonSetError("EXPECTED_STRING");
         return false;
      }
      while(m_pos < m_len)
      {
         ushort ch = Take();
         if(ch == '"')
            return true;
         if(ch == '\\')
         {
            if(m_pos >= m_len)
            {
               FarmJsonSetError("BAD_ESCAPE");
               return false;
            }
            ch = Take();
            if(ch == '"' || ch == '\\' || ch == '/')
               out += ShortToString(ch);
            else if(ch == 'b')
               out += ShortToString(8);
            else if(ch == 'f')
               out += ShortToString(12);
            else if(ch == 'n')
               out += "\n";
            else if(ch == 'r')
               out += "\r";
            else if(ch == 't')
               out += "\t";
            else if(ch == 'u')
            {
               if(m_pos + 4 > m_len)
               {
                  FarmJsonSetError("BAD_UNICODE_ESCAPE");
                  return false;
               }
               const string hex = StringSubstr(m_text, m_pos, 4);
               m_pos += 4;
               int code = 0;
               for(int i = 0; i < 4; i++)
               {
                  const ushort h = StringGetCharacter(hex, i);
                  code *= 16;
                  if(h >= '0' && h <= '9')
                     code += h - '0';
                  else if(h >= 'a' && h <= 'f')
                     code += 10 + h - 'a';
                  else if(h >= 'A' && h <= 'F')
                     code += 10 + h - 'A';
                  else
                  {
                     FarmJsonSetError("BAD_UNICODE_ESCAPE");
                     return false;
                  }
               }
               out += ShortToString((ushort)code);
            }
            else
            {
               FarmJsonSetError("BAD_ESCAPE");
               return false;
            }
            continue;
         }
         if(ch < 32)
         {
            FarmJsonSetError("CONTROL_IN_STRING");
            return false;
         }
         out += ShortToString(ch);
      }
      FarmJsonSetError("UNTERMINATED_STRING");
      return false;
   }

   bool ParseNumber(CFarmJsonValue *out)
   {
      const int start = m_pos;
      if(Peek() == '-')
         m_pos++;
      if(Peek() == '0')
         m_pos++;
      else if(Peek() >= '1' && Peek() <= '9')
      {
         while(Peek() >= '0' && Peek() <= '9')
            m_pos++;
      }
      else
      {
         FarmJsonSetError("BAD_NUMBER");
         return false;
      }
      if(Peek() == '.')
      {
         m_pos++;
         if(!(Peek() >= '0' && Peek() <= '9'))
         {
            FarmJsonSetError("BAD_NUMBER");
            return false;
         }
         while(Peek() >= '0' && Peek() <= '9')
            m_pos++;
      }
      if(Peek() == 'e' || Peek() == 'E')
      {
         m_pos++;
         if(Peek() == '+' || Peek() == '-')
            m_pos++;
         if(!(Peek() >= '0' && Peek() <= '9'))
         {
            FarmJsonSetError("BAD_NUMBER");
            return false;
         }
         while(Peek() >= '0' && Peek() <= '9')
            m_pos++;
      }
      out.type = FARM_JSON_NUMBER;
      out.number_raw = StringSubstr(m_text, start, m_pos - start);
      out.number_value = StringToDouble(out.number_raw);
      out.integer_value = (long)StringToInteger(out.number_raw);
      return true;
   }

   bool ParseArray(CFarmJsonValue *out, const int depth)
   {
      out.type = FARM_JSON_ARRAY;
      Take();
      SkipWs();
      if(Peek() == ']')
      {
         Take();
         return true;
      }
      while(true)
      {
         CFarmJsonValue *child = new CFarmJsonValue();
         if(!ParseValue(child, depth + 1))
         {
            delete child;
            return false;
         }
         out.AddArrayItem(child);
         SkipWs();
         if(Peek() == ']')
         {
            Take();
            return true;
         }
         if(Take() != ',')
         {
            FarmJsonSetError("EXPECTED_COMMA_OR_ARRAY_END");
            return false;
         }
         SkipWs();
      }
      return false;
   }

   bool ParseObject(CFarmJsonValue *out, const int depth)
   {
      out.type = FARM_JSON_OBJECT;
      Take();
      SkipWs();
      if(Peek() == '}')
      {
         Take();
         return true;
      }
      while(true)
      {
         string key = "";
         if(Peek() != '"' || !ParseString(key))
            return false;
         SkipWs();
         if(Take() != ':')
         {
            FarmJsonSetError("EXPECTED_COLON", key);
            return false;
         }
         SkipWs();
         CFarmJsonValue *child = new CFarmJsonValue();
         if(!ParseValue(child, depth + 1))
         {
            delete child;
            return false;
         }
         out.AddObjectItem(key, child);
         SkipWs();
         if(Peek() == '}')
         {
            Take();
            return true;
         }
         if(Take() != ',')
         {
            FarmJsonSetError("EXPECTED_COMMA_OR_OBJECT_END", key);
            return false;
         }
         SkipWs();
      }
      return false;
   }

public:
   bool ParseValue(CFarmJsonValue *out, const int depth)
   {
      if(depth > 32)
      {
         FarmJsonSetError("DEPTH_LIMIT");
         return false;
      }
      SkipWs();
      const ushort ch = Peek();
      if(ch == '{')
         return ParseObject(out, depth);
      if(ch == '[')
         return ParseArray(out, depth);
      if(ch == '"')
      {
         out.type = FARM_JSON_STRING;
         return ParseString(out.string_value);
      }
      if(ch == 't')
      {
         if(!Match("true"))
         {
            FarmJsonSetError("BAD_LITERAL");
            return false;
         }
         out.type = FARM_JSON_BOOL;
         out.bool_value = true;
         return true;
      }
      if(ch == 'f')
      {
         if(!Match("false"))
         {
            FarmJsonSetError("BAD_LITERAL");
            return false;
         }
         out.type = FARM_JSON_BOOL;
         out.bool_value = false;
         return true;
      }
      if(ch == 'n')
      {
         if(!Match("null"))
         {
            FarmJsonSetError("BAD_LITERAL");
            return false;
         }
         out.type = FARM_JSON_NULL;
         return true;
      }
      if(ch == '-' || (ch >= '0' && ch <= '9'))
         return ParseNumber(out);
      FarmJsonSetError("EXPECTED_VALUE");
      return false;
   }

   bool Parse(const string text, CFarmJsonValue &out)
   {
      g_farm_json_last_error = "";
      m_text = text;
      m_pos = 0;
      m_len = StringLen(text);
      out.Free();
      if(!ParseValue(GetPointer(out), 0))
         return false;
      SkipWs();
      if(m_pos != m_len)
      {
         FarmJsonSetError("TRAILING_DATA");
         out.Free();
         return false;
      }
      return true;
   }
};

class CFarmJsonDoc
{
private:
   CFarmJsonValue m_root;

public:
   bool Parse(const string text)
   {
      CFarmJsonParser parser;
      return parser.Parse(text, m_root);
   }

   CFarmJsonValue *Root()
   {
      return GetPointer(m_root);
   }

   void Free()
   {
      m_root.Free();
   }
};

#endif
