using System.Collections.Generic;

namespace PruneBackups
{
    public interface IFileRepository
    {
        IEnumerable<string> GetFiles(string path);
        void Delete(string filePath);
        bool PathExists(string path);
    }
}