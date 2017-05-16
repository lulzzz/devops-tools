using System;
using System.IO;
using System.Linq;

namespace PruneBackups
{
    class Program
    {
        static void Main(string[] args)
        {
            string path = args.Length > 0 ? args[0] : ".";

            string[] allfiles = Directory.GetFiles(path)
                .Where(f => Path.GetFileName(f).Length == 34)
                .ToArray();

            Log($"Found {allfiles.Length} files.");

            var dategroups = allfiles.GroupBy(f => Path.GetFileName(f).Substring(0, 24));
            Log($"Found {dategroups.Count()} date groups.");
            foreach (var group in dategroups.OrderBy(g => g.Key))
            {
                string date = group.Key;
                string[] datefiles = allfiles.Where(f => Path.GetFileName(f).Substring(0, 24) == date).ToArray();
                Log($"Found {datefiles.Length} files in group '{date}'");

                string keep = datefiles.OrderBy(f => f).Take(1).Single();

                Log($"Keeping file: '{keep}'");

                foreach (string filename in datefiles.OrderBy(f => f).Skip(1))
                {
                    Log($"Deleting file: '{filename}'");
                    File.Delete(filename);
                }
            }
        }

        static void Log(string message)
        {
            string date = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss");
            Console.WriteLine($"{date}: {message}");
            File.AppendAllText("prune-backups.log", $"{date}: {message}{Environment.NewLine}");
        }
    }
}
