using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace BackupGrafana
{
    class Git
    {
        public void Push(string sourcefolder, string server, string repopath, string repofolder, string username, string password, string email, bool gitsimulatepush)
        {
            Output.Replace = new List<string>() { username, password };

            string gitexe = Environment.GetEnvironmentVariable("gitexe");
            if (string.IsNullOrEmpty(gitexe))
            {
                throw new Exception("gitexe environment variable not set.");
            }
            if (!File.Exists(gitexe))
            {
                throw new FileNotFoundException($"Git not found: '{gitexe}'");
            }

            string rootfolder, subfolder;
            int offset = repofolder.IndexOfAny(new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar });
            if (offset >= 0)
            {
                rootfolder = repofolder.Substring(0, offset);
                subfolder = repofolder.Substring(offset + 1);
            }
            else
            {
                rootfolder = repofolder;
                subfolder = ".";
            }

            Filesystem.RobustDelete(rootfolder);


            string url = $"https://{username}:{password}@{server}/{repopath}";

            Output.Write($"Using git url: '{url}'");

            RunCommand(gitexe, $"--no-pager clone {url}");
            Directory.SetCurrentDirectory(rootfolder);
            Output.Write($"Current directory: '{Directory.GetCurrentDirectory()}'");


            string relativesourcefolder = Path.Combine("..", sourcefolder);
            string targetfolder = subfolder;

            Output.Write("Comparing folders...");
            if (Filesystem.CompareFolders(relativesourcefolder, targetfolder))
            {
                Output.Write($"No changes found: '{relativesourcefolder}' '{targetfolder}'");
                return;
            }


            if (subfolder != ".")
            {
                Filesystem.RobustDelete(subfolder);
            }

            Output.Write($"Copying files into git folder: '{relativesourcefolder}' -> '{targetfolder}'");
            Filesystem.CopyDirectory(relativesourcefolder, targetfolder);


            Output.Write("Adding/updating/deleting files...");
            RunCommand(gitexe, "--no-pager add -A");

            Output.Write("Setting config...");
            RunCommand(gitexe, $"config user.email {email}");
            RunCommand(gitexe, $"config user.name {username}");

            string commitmessage = "Automatic gathering of Grafana dashboard files: " + DateTime.Now.ToString("yyyyMMdd HHmmss");

            Output.Write("Committing...");
            RunCommand(gitexe, $"--no-pager commit -m \"{commitmessage}\"");

            Output.Write("Setting config...");
            RunCommand(gitexe, "config push.default simple");

            Output.Write("Pushing...");
            if (gitsimulatepush)
            {
                Output.Write("...not!");
            }
            else
            {
                RunCommand(gitexe, "--no-pager push");
            }
        }

        string RunCommand(string exefile, string args, bool redirect = false)
        {
            Output.Write($"Running: '{exefile}' '{args}'");

            Process process = new Process();
            if (redirect)
            {
                process.StartInfo = new ProcessStartInfo(exefile, args)
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true
                };
            }
            else
            {
                process.StartInfo = new ProcessStartInfo(exefile, args)
                {
                    UseShellExecute = false
                };
            }

            process.Start();
            process.WaitForExit();

            if (process.ExitCode != 0)
            {
                throw new Exception($"Failed to execute: '{exefile}', args: '{args}'");
            }

            return redirect ? process.StandardOutput.ReadToEnd() : null;
        }
    }
}
