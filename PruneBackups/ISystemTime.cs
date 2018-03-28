using System;

namespace PruneBackups
{
    public interface ISystemTime
    {
        DateTime Now { get; }
    }
}