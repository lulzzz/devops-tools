using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace BackupGrafana
{
    class PushToGit
    {
        public static string logfile { get; set; }
        public static string[] logreplace { get; set; }

        public void Push(string sourcefolder, string server, string repopath, string repofolder, string username, string password, string email, bool gitsimulatepush)
        {
            logreplace = new[] { username, password };

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

            RobustDelete(rootfolder);


            string url = $"https://{username}:{password}@{server}/{repopath}";

            Log($"Using git url: '{url}'");

            RunCommand(gitexe, $"--no-pager clone {url}");
            Directory.SetCurrentDirectory(rootfolder);
            Log($"Current directory: '{Directory.GetCurrentDirectory()}'");


            string relativesourcefolder = Path.Combine("..", sourcefolder);
            string targetfolder = subfolder;

            Log("Comparing folders...");
            if (CompareFolders(relativesourcefolder, targetfolder))
            {
                Log($"No changes found: '{relativesourcefolder}' '{targetfolder}'");
                return;
            }


            if (subfolder != ".")
            {
                if (Directory.Exists(subfolder))
                {
                    Log($"Deleting folder: '{subfolder}'");
                    Directory.Delete(subfolder, true);
                }
            }

            Log($"Copying files into git folder: '{relativesourcefolder}' -> '{targetfolder}'");
            CopyDirectory(relativesourcefolder, targetfolder);


            Log("Adding/updating/deleting files...");
            RunCommand(gitexe, "--no-pager add -A");

            Log("Setting config...");
            RunCommand(gitexe, $"config user.email {email}");
            RunCommand(gitexe, $"config user.name {username}");

            string commitmessage = "Automatic gathering of Grafana dashboard files: " + DateTime.Now.ToString("yyyyMMdd HHmmss");

            Log("Committing...");
            RunCommand(gitexe, $"--no-pager commit -m \"{commitmessage}\"");

            Log("Setting config...");
            RunCommand(gitexe, "config push.default simple");

            Log("Pushing...");
            if (gitsimulatepush)
            {
                Log("...not!");
            }
            else
            {
                RunCommand(gitexe, "--no-pager push");
            }
        }

        void CopyDirectory(string sourceDir, string targetDir)
        {
            DirectoryInfo dir = new DirectoryInfo(sourceDir);

            DirectoryInfo[] dirs = dir.GetDirectories();
            if (!Directory.Exists(targetDir))
            {
                Directory.CreateDirectory(targetDir);
            }

            FileInfo[] files = dir.GetFiles();
            foreach (FileInfo file in files)
            {
                string temppath = Path.Combine(targetDir, file.Name);
                file.CopyTo(temppath, false);
            }

            foreach (DirectoryInfo subdir in dirs)
            {
                string temppath = Path.Combine(targetDir, subdir.Name);
                CopyDirectory(subdir.FullName, temppath);
            }
        }

        void RobustDelete(string folder)
        {
            if (Directory.Exists(folder))
            {
                string[] files = Directory.GetFiles(folder, "*", SearchOption.AllDirectories);
                foreach (string filename in files)
                {
                    try
                    {
                        File.SetAttributes(filename, File.GetAttributes(filename) & ~FileAttributes.ReadOnly);
                    }
                    catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException)
                    {
                        // Will be dealt with deleting whole folder.
                    }
                }

                for (int tries = 1; tries <= 10; tries++)
                {
                    Log($"Try {tries} to delete folder: '{folder}'");
                    try
                    {
                        Directory.Delete(folder, true);
                        return;
                    }
                    catch (Exception ex) when (tries < 10 && (ex is UnauthorizedAccessException || ex is IOException))
                    {
                        Task.Delay(1000).Wait();
                    }
                }
            }
        }

        bool CompareFolders(string folder1, string folder2)
        {
            if (!Directory.Exists(folder1) || !Directory.Exists(folder2))
            {
                return false;
            }

            Log($"Retrieving files: '{folder1}'");
            string[] files1 = Directory.GetFiles(folder1, "*", SearchOption.AllDirectories);
            Log($"Retrieving files: '{folder2}'");
            string[] files2 = Directory.GetFiles(folder2, "*", SearchOption.AllDirectories);

            if (files1.Length != files2.Length)
            {
                Log($"File count diff: {files1.Length} {files2.Length}");
                return false;
            }

            Array.Sort(files1);
            Array.Sort(files2);

            for (int i = 0; i < files1.Length; i++)
            {
                string file1 = files1[i];
                string file2 = files2[i];

                Log($"Comparing: '{file1}' '{file2}'");
                string f1 = file1.Substring(folder1.Length);
                string f2 = file2.Substring(folder2.Length);

                if (f1 != f2)
                {
                    Log($"Filename diff: '{f1}' '{f2}'");
                    return false;
                }

                string hash1 = GetFileHash(file1);
                string hash2 = GetFileHash(file2);
                if (hash1 != hash2)
                {
                    Log($"Hash diff: '{file1}' '{file2}' {hash1} {hash2}");
                    return false;
                }
            }

            return true;
        }

        string GetFileHash(string filename)
        {
            using (FileStream fs = new FileStream(filename, FileMode.Open))
            {
                using (BufferedStream bs = new BufferedStream(fs))
                {
                    using (SHA1 sha1 = SHA1.Create())
                    {
                        byte[] hash = sha1.ComputeHash(bs);
                        StringBuilder formatted = new StringBuilder(2 * hash.Length);
                        foreach (byte b in hash)
                        {
                            formatted.AppendFormat("{0:X2}", b);
                        }
                        return formatted.ToString();
                    }
                }
            }
        }

        string RunCommand(string exefile, string args, bool redirect = false)
        {
            Log($"Running: '{exefile}' '{args}'");

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
