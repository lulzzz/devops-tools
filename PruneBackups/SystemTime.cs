using System;

namespace PruneBackups
{
    public class SystemTime : ISystemTime
    {
        public DateTime Now => DateTime.Now;
    }
}