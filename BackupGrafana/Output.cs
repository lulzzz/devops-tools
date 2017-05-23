using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace BackupGrafana
{
    class Output
    {
        public static string Logfile { get; set; }
        public static List<string> Replace { get; set; } = null;

        public static void Write(string message)
        {
            string date = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss");

            string clean = message;
            if (Replace != null)
            {
                foreach (string replacestring in Replace)
                {
                    clean = clean.Replace(replacestring, string.Join(string.Empty, Enumerable.Repeat("*", replacestring.Length)));
                }
            }

            Console.WriteLine($"{date}: {clean}");
            File.AppendAllText(Logfile, $"{date}: {clean}{Environment.NewLine}");
        }
    }
}
