using System;

namespace PruneBackups
{
    public class SystemTime : ISystemTime
    {
        public DateTimeOffset Now => DateTimeOffset.Now;
    }
}