using System.Collections.Generic;
using System.IO;

namespace PruneBackups
{
    public class ServerFileRepository : IFileRepository
    {
        public IEnumerable<string> GetFiles(string path) => Directory.GetFiles(path);
        public void Delete(string filePath) => File.Delete(filePath);
        public bool PathExists(string path) => Directory.Exists(path);
    }
}