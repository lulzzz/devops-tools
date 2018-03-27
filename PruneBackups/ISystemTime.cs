using System;

namespace PruneBackups
{
    public interface ISystemTime
    {
        DateTimeOffset Now { get; }
    }
}