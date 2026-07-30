#ifndef FARM_BROKER_TIME_MQH
#define FARM_BROKER_TIME_MQH

class CBrokerClockSource
{
public:
   virtual datetime ServerTime() { return TimeTradeServer(); }
   virtual datetime GmtTime() { return TimeGMT(); }
   virtual datetime LocalTime() { return TimeLocal(); }
   virtual int GmtOffsetLocal() { return (int)TimeGMTOffset(); }
   virtual int DstLocal() { return (int)TimeDaylightSavings(); }
   virtual void SleepMs(const int ms) { Sleep(ms); }
};

class CBrokerTime
{
private:
   CBrokerClockSource *m_src;
   CBrokerClockSource  m_default_src;
   bool                m_valid;
   int                 m_offset_sec;
   int                 m_previous_offset_sec;
   datetime            m_last_change_utc;
   int                 m_candidate_offset_sec;
   int                 m_candidate_count;
   datetime            m_last_server;
   datetime            m_last_gmt;
   int                 m_last_raw_offset;
   int                 m_last_local_offset;
   int                 m_last_local_dst;
   datetime            m_bad_sample_started_local;

   void Reset()
   {
      m_src = NULL;
      m_valid = false;
      m_offset_sec = 0;
      m_previous_offset_sec = 0;
      m_last_change_utc = 0;
      m_candidate_offset_sec = 0;
      m_candidate_count = 0;
      m_last_server = 0;
      m_last_gmt = 0;
      m_last_raw_offset = 0;
      m_last_local_offset = 0;
      m_last_local_dst = 0;
      m_bad_sample_started_local = 0;
   }

   int RoundToNearest(const int value, const int quantum) const
   {
      if(value >= 0)
         return ((value + quantum / 2) / quantum) * quantum;
      return -(((-value + quantum / 2) / quantum) * quantum);
   }

   bool DetectOffset(int &out_offset)
   {
      if(m_src == NULL)
         return false;

      m_last_server = m_src.ServerTime();
      m_last_gmt = m_src.GmtTime();
      m_last_local_offset = m_src.GmtOffsetLocal();
      m_last_local_dst = m_src.DstLocal();

      if(m_last_server <= 0 || m_last_gmt <= 0)
         return false;

      m_last_raw_offset = (int)(m_last_server - m_last_gmt);
      const int rounded = RoundToNearest(m_last_raw_offset, 900);
      if(MathAbs(m_last_raw_offset - rounded) > 120)
         return false;
      if(rounded < -43200 || rounded > 50400)
         return false;

      out_offset = rounded;
      return true;
   }

   void MarkGoodSample()
   {
      m_bad_sample_started_local = 0;
   }

   void MarkBadSample()
   {
      if(!m_valid || m_src == NULL)
         return;

      const datetime local_now = m_src.LocalTime();
      if(local_now <= 0)
         return;
      if(m_bad_sample_started_local <= 0)
      {
         m_bad_sample_started_local = local_now;
         return;
      }
      if(local_now - m_bad_sample_started_local > 90)
      {
         m_valid = false;
         m_candidate_count = 0;
      }
   }

   void AcceptOffset(const int detected)
   {
      m_offset_sec = detected;
      m_previous_offset_sec = detected;
      m_valid = true;
      m_candidate_offset_sec = 0;
      m_candidate_count = 0;
      MarkGoodSample();
   }

public:
   CBrokerTime()
   {
      Reset();
   }

   bool Init(CBrokerClockSource *src = NULL)
   {
      Reset();
      m_src = (src == NULL ? &m_default_src : src);

      int elapsed_ms = 0;
      while(elapsed_ms < 3000)
      {
         int detected = 0;
         if(DetectOffset(detected))
         {
            AcceptOffset(detected);
            return true;
         }
         m_src.SleepMs(200);
         elapsed_ms += 200;
      }

      m_valid = false;
      return false;
   }

   bool Refresh()
   {
      int detected = 0;
      if(!DetectOffset(detected))
      {
         MarkBadSample();
         return false;
      }
      MarkGoodSample();

      if(!m_valid)
      {
         AcceptOffset(detected);
         return false;
      }

      if(detected == m_offset_sec)
      {
         m_candidate_count = 0;
         return false;
      }

      if(detected != m_candidate_offset_sec)
      {
         m_candidate_offset_sec = detected;
         m_candidate_count = 1;
         return false;
      }

      m_candidate_count++;
      if(m_candidate_count < 3)
         return false;

      m_previous_offset_sec = m_offset_sec;
      m_offset_sec = detected;
      m_last_change_utc = BrokerToUtc(m_last_server);
      m_candidate_count = 0;
      return true;
   }

   datetime NowBroker() const
   {
      if(m_src == NULL)
         return 0;
      return m_src.ServerTime();
   }

   datetime NowUtc() const
   {
      return BrokerToUtc(NowBroker());
   }

   datetime LocalTime() const
   {
      if(m_src == NULL)
         return 0;
      return m_src.LocalTime();
   }

   datetime BrokerToUtc(const datetime broker_time) const
   {
      if(!m_valid || broker_time <= 0)
         return 0;
      return broker_time - m_offset_sec;
   }

   datetime UtcToBroker(const datetime utc_time) const
   {
      if(!m_valid || utc_time <= 0)
         return 0;
      return utc_time + m_offset_sec;
   }

   int OffsetSeconds() const
   {
      return m_offset_sec;
   }

   bool IsValid() const
   {
      return m_valid;
   }

   datetime LastChangeUtc() const
   {
      return m_last_change_utc;
   }

   int PreviousOffsetSeconds() const
   {
      return m_previous_offset_sec;
   }

   int LocalGmtOffsetSeconds() const
   {
      return m_last_local_offset;
   }

   int LocalDstSeconds() const
   {
      return m_last_local_dst;
   }

   datetime BrokerDayStart(const datetime broker_time) const
   {
      if(!m_valid || broker_time <= 0)
         return 0;
      MqlDateTime dt;
      TimeToStruct(broker_time, dt);
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      return StructToTime(dt);
   }

   int BrokerDayOfWeek(const datetime broker_time) const
   {
      if(!m_valid || broker_time <= 0)
         return -1;
      MqlDateTime dt;
      TimeToStruct(broker_time, dt);
      return dt.day_of_week;
   }

   bool IsSameBrokerDay(const datetime a, const datetime b) const
   {
      if(!m_valid || a <= 0 || b <= 0)
         return false;
      return BrokerDayStart(a) == BrokerDayStart(b);
   }

   string DiagnosticLine() const
   {
      return StringFormat("broker_time valid=%s server=%I64d gmt=%I64d raw_offset=%d offset=%d previous_offset=%d local_gmt_offset=%d local_dst=%d last_change_utc=%I64d",
                          (m_valid ? "true" : "false"),
                          (long)m_last_server,
                          (long)m_last_gmt,
                          m_last_raw_offset,
                          m_offset_sec,
                          m_previous_offset_sec,
                          m_last_local_offset,
                          m_last_local_dst,
                          (long)m_last_change_utc);
   }
};

#endif
