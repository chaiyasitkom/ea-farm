#ifndef FARM_LOGGER_MQH
#define FARM_LOGGER_MQH

class CFarmLogger {
private:
   string m_component;
   bool   m_verbose;

   void Write(const string level, const string message) const
   {
      PrintFormat("%s component=%s %s", level, m_component, message);
   }

public:
   void Init(const string component, const bool verbose=false)
   {
      m_component = component;
      m_verbose = verbose;
   }

   void Debug(const string message) const
   {
      if(m_verbose)
         Write("DEBUG", message);
   }

   void Info(const string message) const
   {
      Write("INFO", message);
   }

   void Warn(const string message) const
   {
      Write("WARN", message);
   }

   void Error(const string message) const
   {
      Write("ERROR", message);
   }

   void Fatal(const string message) const
   {
      Write("FATAL", message);
   }
};

#endif
