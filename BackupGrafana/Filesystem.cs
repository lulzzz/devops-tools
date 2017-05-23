﻿using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace BackupGrafana
{
    class Filesystem
    {
        public static void CopyDirectory(string sourceDir, string targetDir)
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

        public static void RobustDelete(string folder)
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
                        // Will be dealt with when deleting the folder.
                    }
                }

                for (int tries = 1; tries <= 10; tries++)
                {
                    Output.Write($"Try {tries} to delete folder: '{folder}'");
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

        public static bool CompareFolders(string folder1, string folder2)
        {
            if (!Directory.Exists(folder1) || !Directory.Exists(folder2))
            {
                return false;
            }

            Output.Write($"Retrieving files: '{folder1}'");
            string[] files1 = Directory.GetFiles(folder1, "*", SearchOption.AllDirectories);
            Output.Write($"Retrieving files: '{folder2}'");
            string[] files2 = Directory.GetFiles(folder2, "*", SearchOption.AllDirectories);

            if (files1.Length != files2.Length)
            {
                Output.Write($"File count diff: {files1.Length} {files2.Length}");
                return false;
            }

            Array.Sort(files1);
            Array.Sort(files2);

            for (int i = 0; i < files1.Length; i++)
            {
                string file1 = files1[i];
                string file2 = files2[i];

                Output.Write($"Comparing: '{file1}' '{file2}'");
                string f1 = file1.Substring(folder1.Length);
                string f2 = file2.Substring(folder2.Length);

                if (f1 != f2)
                {
                    Output.Write($"Filename diff: '{f1}' '{f2}'");
                    return false;
                }

                string hash1 = GetFileHash(file1);
                string hash2 = GetFileHash(file2);
                if (hash1 != hash2)
                {
                    Output.Write($"Hash diff: '{file1}' '{file2}' {hash1} {hash2}");
                    return false;
                }
            }

            return true;
        }

        public static string GetFileHash(string filename)
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
    }
}
