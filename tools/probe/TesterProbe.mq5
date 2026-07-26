//+------------------------------------------------------------------+
//| TesterProbe.mq5 -- harness validation only, NOT product code     |
//|                                                                  |
//| Purpose: prove the headless Strategy Tester pipeline works end to |
//| end (launch terminal -> EA runs in tester -> JSON lands in        |
//| Common\Files -> runner parses it) without depending on any        |
//| product code that might itself be broken.                        |
//|                                                                  |
//| It also demonstrates the correct way to write UTF-8 from MQL5,    |
//| because FILE_UTF8 does not exist -- see WriteUtf8File below.      |
//| Owner: Claude (tools/**). Codex must not edit this file.          |
//+------------------------------------------------------------------+
#property version   "1.00"
#property description "EA Farm tester-harness probe"

input string InpResultFile = "ea-farm-probe-result.json";

//+------------------------------------------------------------------+
//| Write a string as real UTF-8 bytes.                              |
//|                                                                  |
//| MQL5 has NO FILE_UTF8 flag. The options are:                     |
//|   FILE_TXT|FILE_UNICODE -> UTF-16LE (with BOM)                   |
//|   FILE_TXT|FILE_ANSI    -> system codepage (CP874 here, lossy)   |
//|   FILE_BIN + explicit CP_UTF8 conversion -> real UTF-8  <== this |
//| Only the third option is codepage-independent, so it is the only |
//| one safe for a JSON file that Python/CI will read.               |
//+------------------------------------------------------------------+
bool WriteUtf8File(const string filename, const string content)
{
   uchar bytes[];
   int n = StringToCharArray(content, bytes, 0, -1, CP_UTF8);
   // StringToCharArray appends a terminating NUL; JSON must not contain it.
   if(n > 0 && bytes[n - 1] == 0)
      n--;

   const int h = FileOpen(filename, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("probe: FileOpen failed err=", GetLastError(), " file=", filename);
      return false;
   }

   const uint written = FileWriteArray(h, bytes, 0, n);
   FileClose(h);
   Print("probe: wrote ", written, " of ", n, " bytes to Common\\Files\\", filename);
   return (written == (uint)n);
}

int OnInit()
{
   Print("probe: OnInit entered, terminal=", TerminalInfoString(TERMINAL_NAME),
         " tester=", (bool)MQLInfoInteger(MQL_TESTER),
         " symbol=", _Symbol);

   const string json = "{"
                       "\"suite\":\"TesterProbe\","
                       "\"status\":\"PASS\","
                       "\"symbol\":\"" + _Symbol + "\","
                       "\"is_tester\":" + (MQLInfoInteger(MQL_TESTER) ? "true" : "false") +
                       "}";

   WriteUtf8File(InpResultFile, json);
   ExpertRemove();
   return INIT_SUCCEEDED;
}

void OnTick() {}
void OnDeinit(const int reason) {}
