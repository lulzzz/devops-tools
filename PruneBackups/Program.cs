using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using McMaster.Extensions.CommandLineUtils;

namespace PruneBackups
{
    [HelpOption]
    public class Program
    {
        public static IFileRepository FileRepository = new ServerFileRepository();
        public static ISystemTime SystemTime = new SystemTime();
        public static int Main(string[] args)
             => CommandLineApplication.Execute<Program>(args.Length == 0 ? new [] {"-h"} : args);

        [Option(Description = "The path of backups")]
        public string Path { get; }

        [Option(Description = "The maxiumum age of backups")]
        public int Age { get; } = 60;

        [Option(Description = "If prune should be debug default = false")]
        public bool DryRun { get; }

        private void OnExecute()
        {
            if (!FileRepository.PathExists(Path))
            {
                Log($"Path: {Path} . Does not exist");
                return;
            }
              
            var maximumAge = SystemTime.Now.AddDays(-Age);

            var filesInPath = FileRepository.GetFiles(Path)
                .Where(HasDateInPath)
                .ToArray();

            Log($"Found {filesInPath.Length} files in path: {Path}");
            foreach (var filename in filesInPath)
            {
                var createdDate = GetDateCreatedFromFileName(filename);
                if (createdDate < maximumAge)
                {
                    Log($"Deleting file: '{filename}'");
                    if(!DryRun)
                        FileRepository.Delete(filename);

                }
                else
                {
                    Log($"Keeping file: '{filename}'");
                }
            }
        }

        private static bool HasDateInPath(string file)
        {
            return DateRegex.IsMatch(file);
        }

        private static readonly Regex DateRegex = new Regex("_.\\d+_", RegexOptions.Compiled);
        public static DateTime GetDateCreatedFromFileName(string file)
        {
            //TODO: get file created from fileInfo
            var result = DateRegex.Match(file);
            if (result.Success)
                return ParseDate(result.Value);
            return SystemTime.Now;
        }

        public static DateTime ParseDate(string value)
        {
            return DateTime.ParseExact(value.Replace("_", string.Empty), "yyyyMMdd",
                CultureInfo.InvariantCulture, DateTimeStyles.None);
        }

        private static void Log(string message)
        {
            var date = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss");
            Console.WriteLine($"{date}: {message}");
            File.AppendAllText("prune-backups.log", $"{date}: {message}{Environment.NewLine}");
        }
    }
}