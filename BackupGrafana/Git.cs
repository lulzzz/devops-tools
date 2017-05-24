using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace BackupGrafana
{
    class Git
    {
        public bool Push(string gitbinary, string sourcefolder, string server, string repopath, string repofolder, string username, string password, string email, bool gitsimulatepush)
        {
            Output.Replace = new List<string>() { username, password };

            if (!File.Exists(gitbinary))
            {
                Output.Write($"Git not found: '{gitbinary}'");
                return false;
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

            RunCommand(gitbinary, $"--no-pager clone {url}");
            Directory.SetCurrentDirectory(rootfolder);
            Output.Write($"Current directory: '{Directory.GetCurrentDirectory()}'");


            string relativesourcefolder = Path.Combine("..", sourcefolder);
            string targetfolder = subfolder;

            Output.Write("Comparing folders...");
            if (Filesystem.CompareFolders(relativesourcefolder, targetfolder))
            {
                Output.Write($"No changes found: '{relativesourcefolder}' '{targetfolder}'");
                return true;
            }


            if (subfolder != ".")
            {
                Filesystem.RobustDelete(subfolder);
            }

            Output.Write($"Copying files into git folder: '{relativesourcefolder}' -> '{targetfolder}'");
            Filesystem.CopyDirectory(relativesourcefolder, targetfolder);


            Output.Write("Adding/updating/deleting files...");
            RunCommand(gitbinary, "--no-pager add -A");

            Output.Write("Setting config...");
            RunCommand(gitbinary, $"config user.email {email}");
            RunCommand(gitbinary, $"config user.name {username}");

            string date = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss");
            string commitmessage = $"Automatic gathering of Grafana dashboard files: {date}";

            Output.Write("Committing...");
            RunCommand(gitbinary, $"--no-pager commit -m \"{commitmessage}\"");

            Output.Write("Setting config...");
            RunCommand(gitbinary, "config push.default simple");

            Output.Write("Pushing...");
            if (gitsimulatepush)
            {
                Output.Write("...not!");
            }
            else
            {
                RunCommand(gitbinary, "--no-pager push");
            }

            return true;
        }

        string RunCommand(string binfile, string args, bool redirect = false)
        {
            Output.Write($"Running: '{binfile}' '{args}'");

            Process process = new Process();
            if (redirect)
            {
                process.StartInfo = new ProcessStartInfo(binfile, args)
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true
                };
            }
            else
            {
                process.StartInfo = new ProcessStartInfo(binfile, args)
                {
                    UseShellExecute = false
                };
            }

            process.Start();
            process.WaitForExit();

            if (process.ExitCode != 0)
            {
                throw new Exception($"Failed to execute: '{binfile}', args: '{args}'");
            }

            return redirect ? process.StandardOutput.ReadToEnd() : null;
        }
    }
}
