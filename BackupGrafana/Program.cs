using System;
using System.IO;
using System.Linq;
using System.Text;

namespace BackupGrafana
{
    class Program
    {
        public static string logfile { get; set; }
        public static string[] logreplace { get; set; }

        static int Main(string[] args)
        {
            logfile = Path.Combine(Directory.GetCurrentDirectory(), "BackupGrafana.log");
            PushToGit.logfile = logfile;
            SaveGrafana.logfile = logfile;
            logreplace = Array.Empty<string>();
            PushToGit.logreplace = logreplace;
            SaveGrafana.logreplace = logreplace;

            if (args.Length != 3)
            {
                Log("Usage: BackupGrafana <serverurl> <username> <password>");
                return 1;
            }

            string url = args[0];
            string username = args[1];
            string password = args[2];
            string folder = "dashboards";

            SaveGrafana grafana = new SaveGrafana();
            grafana.SaveDashboards(url, username, password, folder);

            string gitsourcefolder = folder;
            string gitserver = Environment.GetEnvironmentVariable("gitserver");
            string gitrepopath = Environment.GetEnvironmentVariable("gitrepopath");
            string gitrepofolder = Environment.GetEnvironmentVariable("gitrepofolder");
            string gitusername = Environment.GetEnvironmentVariable("gitusername");
            string gitpassword = Environment.GetEnvironmentVariable("gitpassword");
            string gitemail = Environment.GetEnvironmentVariable("gitemail");
            bool gitsimulatepush = ParseBooleanEnvironmentVariable("gitsimulatepush", false);

            if (string.IsNullOrEmpty(gitserver) || string.IsNullOrEmpty(gitrepopath) || string.IsNullOrEmpty(gitrepofolder) ||
                string.IsNullOrEmpty(gitusername) || string.IsNullOrEmpty(gitpassword) || string.IsNullOrEmpty(gitemail))
            {
                StringBuilder missing = new StringBuilder();
                if (string.IsNullOrEmpty(gitserver))
                    missing.AppendLine("Missing gitserver.");
                if (string.IsNullOrEmpty(gitrepopath))
                    missing.AppendLine("Missing gitrepopath.");
                if (string.IsNullOrEmpty(gitrepofolder))
                    missing.AppendLine("Missing gitrepofolder.");
                if (string.IsNullOrEmpty(gitusername))
                    missing.AppendLine("Missing gitusername.");
                if (string.IsNullOrEmpty(gitpassword))
                    missing.AppendLine("Missing gitpassword.");
                if (string.IsNullOrEmpty(gitemail))
                    missing.AppendLine("Missing gitemail.");

                Log("Missing git environment variables, will not push Grafana dashboard files to Git." + Environment.NewLine + missing.ToString());
            }
            else
            {
                PushToGit git = new PushToGit();
                git.Push(gitsourcefolder, gitserver, gitrepopath, gitrepofolder, gitusername, gitpassword, gitemail, gitsimulatepush);
            }

            return 0;
        }

        static bool ParseBooleanEnvironmentVariable(string variableName, bool defaultValue)
        {
            string stringValue = Environment.GetEnvironmentVariable(variableName);
            if (stringValue == null)
            {
                return defaultValue;
            }
            else
            {
                bool boolValue;
                if (!bool.TryParse(stringValue, out boolValue))
                {
                    return defaultValue;
                }
                return boolValue;
            }
        }

        static void Log(string message)
        {
            string date = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss");

            string replace = message;
            foreach (string replacestring in logreplace)
            {
                replace = replace.Replace(replacestring, string.Join(string.Empty, Enumerable.Repeat("*", replacestring.Length)));
            }

            Console.WriteLine($"{date}: {replace}");
            File.AppendAllText(logfile, $"{date}: {replace}{Environment.NewLine}");
        }
    }
}
