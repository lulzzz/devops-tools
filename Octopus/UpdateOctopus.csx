// This is a script that updates octopus, if that wasn't obvious enough.

// run with: csi.exe UpdateOctopus.csx

using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Security.Cryptography;
using System.Text;

public class Program
{
    public static int Main(string[] args)
    {
        int result = 0;

        if (args.Length != 0)
        {
            Log("Usage: csi.exe UpdateOctopus.csx");
            result = 1;
        }
        else
        {
            string currentdir = null;
            try
            {
                Update();
            }
            catch (ApplicationException ex)
            {
                LogColor(ex.Message, ConsoleColor.Red);
                result = 1;
            }
        }

        if (Environment.UserInteractive)
        {
            Log("Press any key to continue...");
            Console.ReadKey();
        }

        return result;
    }

    private static void Update()
    {
        LogColor("***** Updating octopus *****", ConsoleColor.Cyan);

        Log($"Current Directory: '{Directory.GetCurrentDirectory()}'");

        string url = "http://octopusdeploy.com/downloads/latest/OctopusServer64";
        string localfile = "octopus.msi";
        string oldfile = "octopus_old.msi";

        if (File.Exists(oldfile))
        {
            Log($"Deleting file: '{oldfile}'");
            File.Delete(oldfile);
        }
        if (File.Exists(localfile))
        {
            Log($"Renaming file: '{localfile}' -> '{oldfile}'");
            File.Move(localfile, oldfile);
        }

        WebClient client = new WebClient();

        Log($"Downloading '{url}' -> '{localfile}'");
        try
        {
            client.DownloadFile(url, localfile);
        }
        catch (Exception ex)
        {
            throw new ApplicationException($"Couldn't download '{url}' -> '{localfile}' '{ex.ToString()}'", ex);
        }

        if (!File.Exists(localfile))
        {
            throw new ApplicationException($"Couldn't download '{url}' -> '{localfile}'");
        }

        FileInfo file = new FileInfo(localfile);
        Log($"Download file size: {file.Length} bytes.");
        if (file.Length < 150 * 1024 * 1024)
        {
            throw new ApplicationException($"Downloaded file too small.");
        }

        if (File.Exists(oldfile))
        {
            byte[] oldhash = ComputeHash(oldfile);
            byte[] newhash = ComputeHash(localfile);

            Log($"Old hash: '{BitConverter.ToString(oldhash).Replace("-", string.Empty).ToLower()}'");
            Log($"New hash: '{BitConverter.ToString(newhash).Replace("-", string.Empty).ToLower()}'");
            if (Enumerable.SequenceEqual(newhash, oldhash))
            {
                Log("New file hash same as old, won't update.");
                return;
            }
        }

        string msiexe = "msi.exe";
        string args = $"/i {localfile} /quiet";
        int result = RunCommand(msiexe, args);
        if (result != 0)
        {
            throw new ApplicationException($"Couldn't execute: '{msiexe}' '{args}'");
        }
    }

    static byte[] ComputeHash(string filename)
    {
        using (var md5 = MD5.Create())
        {
            using (var fs = File.OpenRead(filename))
            {
                return md5.ComputeHash(fs);
            }
        }
    }

    private static int RunCommand(string exefile, string args)
    {
        bool verbose = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("UpdateOctopusVerbose"));

        Process process = new Process();
        process.StartInfo = new ProcessStartInfo(exefile, args)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        if (verbose)
        {
            LogColor($"Running: >>{exefile}<< >>{args}<<", ConsoleColor.DarkGray);
        }

        process.Start();
        process.WaitForExit();

        return process.ExitCode;
    }

    private static void LogColor(string message, ConsoleColor color)
    {
        ConsoleColor oldColor = Console.ForegroundColor;
        try
        {
            Console.ForegroundColor = color;
            Log(message);
        }
        finally
        {
            Console.ForegroundColor = oldColor;
        }
    }

    private static void Log(string message)
    {
        string logfile = "UpdateOctopus.log";
        string time = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss");
        string hostname = Dns.GetHostName();

        string logmessage = $"{time}: {hostname}: {message}";

        File.AppendAllText(logfile, logmessage);
        Console.WriteLine(logmessage);
    }
}

return Program.Main(Environment.GetCommandLineArgs().Skip(2).ToArray());
