using Newtonsoft.Json.Linq;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace RunAllBuildConfigs
{
    class Program
    {
        static int Main(string[] args)
        {
            int result = 0;
            if (args.Length != 0)
            {
                Console.WriteLine(
@"RunAllBuildConfigs 0.002 - Trigger all builds.

Usage: RunAllBuildConfigs.exe

Environment variables:
BuildServer
BuildUsername
BuildPassword
TEAMCITY_BUILD_PROPERTIES_FILE (can retrieve the 3 above: Server, Username, Password)

Optional environment variables:
BuildExcludeBuildConfigs
BuildSortedExecution
BuildDebug");
                result = 1;
            }
            else
            {
                try
                {
                    TriggerMeEasy();
                }
                catch (ApplicationException ex)
                {
                    LogColor(ex.Message, ConsoleColor.Red);
                    result = 1;
                }
                catch (Exception ex)
                {
                    LogColor(ex.ToString(), ConsoleColor.Red);
                    result = 1;
                }
            }

            if (Environment.UserInteractive)
            {
                Console.WriteLine("Press any key to continue...");
                Console.ReadKey();
            }

            return result;
        }

        static void TriggerMeEasy()
        {
            string server = GetServer();

            string username, password;
            GetCredentials(out username, out password);


            List<string> builds = GetBuildConfigs(server, username, password);

            Log($"Found {builds.Count} build configs.");

            bool sortedExecution = GetSortedExecution();
            string[] excludedBuildConfigs = GetExcludedBuildConfigs();

            if (sortedExecution)
            {
                builds.Sort(StringComparer.OrdinalIgnoreCase);
            }

            foreach (string build in builds)
            {
                Log(build);
            }


            Dictionary<string, string> tcvariables = GetTeamcityBuildVariables();
            if (tcvariables.ContainsKey("teamcity.buildType.id"))
            {
                string buildConfig = tcvariables["teamcity.buildType.id"];
                if (builds.Contains(buildConfig))
                {
                    Log($"Excluding build config (me): '{buildConfig}'");
                    builds.Remove(buildConfig);
                }
                else
                {
                    LogColor($"Couldn't exclude build config: '{buildConfig}'", ConsoleColor.Yellow);
                }
            }

            if (excludedBuildConfigs != null)
            {
                foreach (string buildConfig in excludedBuildConfigs)
                {
                    if (builds.Contains(buildConfig))
                    {
                        Log($"Excluding build config: '{buildConfig}'");
                        builds.Remove(buildConfig);
                    }
                    else
                    {
                        LogColor($"Couldn't exclude build config: '{buildConfig}'", ConsoleColor.Yellow);
                    }
                }
            }

            TriggerBuilds(server, username, password, builds);
        }

        static string GetServer()
        {
            string server = Environment.GetEnvironmentVariable("BuildServer");

            if (server != null)
            {
                Log($"Got server from environment variable: '{server}'");
            }

            if (server == null)
            {
                Dictionary<string, string> tcvariables = GetTeamcityConfigVariables();

                if (server == null && tcvariables.ContainsKey("teamcity.serverUrl"))
                {
                    server = tcvariables["teamcity.serverUrl"];
                    Log($"Got server from Teamcity: '{server}'");
                }
            }

            if (server == null)
            {
                throw new ApplicationException("No server specified.");
            }
            else
            {
                if (!server.StartsWith("http://") && !server.StartsWith("https://"))
                {
                    server = $"https://{server}";
                }
            }

            return server;
        }

        static List<string> GetBuildConfigs(string server, string username, string password)
        {
            List<string> buildids = new List<string>();

            using (WebClient client = new WebClient())
            {
                if (username != null && password != null)
                {
                    string credentials = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{username}:{password}"));
                    client.Headers[HttpRequestHeader.Authorization] = $"Basic {credentials}";
                }

                string address = $"{server}/app/rest/buildTypes";
                client.Headers["Accept"] = "application/json";

                dynamic builds = DownloadJsonContent(client, address, "BuildDebug1.txt");

                foreach (JProperty property in builds)
                {
                    if (property.First.Type == JTokenType.Array)
                    {
                        foreach (dynamic build in property.First)
                        {
                            string buildid = build.id;

                            buildids.Add(buildid);
                        }
                    }
                }
            }

            return buildids;
        }

        static Dictionary<string, bool> writtenLogs = new Dictionary<string, bool>();

        static JObject DownloadJsonContent(WebClient client, string address, string debugFilename)
        {
            Log($"Address: '{address}'");
            try
            {
                string content = client.DownloadString(address);
                if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("BuildDebug")))
                {
                    if (!writtenLogs.ContainsKey(debugFilename))
                    {
                        File.WriteAllText(debugFilename, content);
                        writtenLogs[debugFilename] = true;
                    }
                }
                JObject jobects = JObject.Parse(content);
                return jobects;
            }
            catch (WebException ex)
            {
                throw new ApplicationException(ex.Message, ex);
            }
        }

        static bool GetSortedExecution()
        {
            string sortedExecution = Environment.GetEnvironmentVariable("BuildSortedExecution");

            if (sortedExecution != null)
            {
                Log($"Got sorted execution flag from environment variable: '{sortedExecution}'");
            }
            else
            {
                Log("No sorted execution flag specified.");
            }

            return !string.IsNullOrEmpty(sortedExecution);
        }

        static string[] GetExcludedBuildConfigs()
        {
            string excludedBuildConfigs = Environment.GetEnvironmentVariable("BuildExcludeBuildConfigs");

            if (excludedBuildConfigs != null)
            {
                Log($"Got excluded build configs from environment variable: '{excludedBuildConfigs}'");
                return excludedBuildConfigs.Split(',');
            }
            else
            {
                Log("No excluded build configs specified.");
            }

            return null;
        }

        static void TriggerBuilds(string server, string username, string password, List<string> buildids)
        {
            List<string> buildnames = new List<string>();

            using (WebClient client = new WebClient())
            {
                if (username != null && password != null)
                {
                    string credentials = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{username}:{password}"));
                    client.Headers[HttpRequestHeader.Authorization] = $"Basic {credentials}";
                }

                foreach (string buildid in buildids)
                {
                    string content = $"<build><buildType id='{buildid}'/></build>";

                    string address = $"{server}/app/rest/buildQueue";
                    client.Headers["Content-Type"] = "application/xml";

                    PostXmlContent(client, address, content, "BuildDebug2.txt");
                }
            }
        }

        static void PostXmlContent(WebClient client, string address, string content, string debugFilename)
        {
            Log($"Address: '{address}', content: '{content}'");
            try
            {
                string result = client.UploadString(address, content);
                if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("BuildDebug")))
                {
                    if (!writtenLogs.ContainsKey(debugFilename))
                    {
                        File.WriteAllText(debugFilename, content);
                        writtenLogs[debugFilename] = true;
                    }
                }
            }
            catch (WebException ex)
            {
                throw new ApplicationException(ex.Message, ex);
            }
        }

        static void GetCredentials(out string username, out string password)
        {
            username = Environment.GetEnvironmentVariable("BuildUsername");
            password = Environment.GetEnvironmentVariable("BuildPassword");

            if (username != null)
            {
                Log("Got username from environment variable.");
            }
            if (password != null)
            {
                Log("Got password from environment variable.");
            }

            if (username == null || password == null)
            {
                Dictionary<string, string> tcvariables = GetTeamcityBuildVariables();

                if (username == null && tcvariables.ContainsKey("teamcity.auth.userId"))
                {
                    username = tcvariables["teamcity.auth.userId"];
                    Log("Got username from Teamcity.");
                }
                if (password == null && tcvariables.ContainsKey("teamcity.auth.password"))
                {
                    password = tcvariables["teamcity.auth.password"];
                    Log("Got password from Teamcity.");
                }
            }

            if (username == null)
            {
                Log("No username specified.");
            }
            if (password == null)
            {
                Log("No password specified.");
            }
        }

        static Dictionary<string, string> GetTeamcityBuildVariables()
        {
            string buildpropfile = Environment.GetEnvironmentVariable("TEAMCITY_BUILD_PROPERTIES_FILE");
            if (string.IsNullOrEmpty(buildpropfile))
            {
                Log("Couldn't find Teamcity build properties file.");
                return new Dictionary<string, string>();
            }
            if (!File.Exists(buildpropfile))
            {
                Log($"Couldn't find Teamcity build properties file: '{buildpropfile}'");
                return new Dictionary<string, string>();
            }

            Log($"Reading Teamcity build properties file: '{buildpropfile}'");
            string[] rows = File.ReadAllLines(buildpropfile);

            var valuesBuild = GetPropValues(rows);

            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("BuildDebug")))
            {
                LogTCSection("Teamcity Properties", valuesBuild.Select(p => $"Build: {p.Key}={p.Value}"));
            }

            return valuesBuild;
        }

        static Dictionary<string, string> GetTeamcityConfigVariables()
        {
            string buildpropfile = Environment.GetEnvironmentVariable("TEAMCITY_BUILD_PROPERTIES_FILE");
            if (string.IsNullOrEmpty(buildpropfile))
            {
                Log("Couldn't find Teamcity build properties file.");
                return new Dictionary<string, string>();
            }
            if (!File.Exists(buildpropfile))
            {
                Log($"Couldn't find Teamcity build properties file: '{buildpropfile}'");
                return new Dictionary<string, string>();
            }

            Log($"Reading Teamcity build properties file: '{buildpropfile}'");
            string[] rows = File.ReadAllLines(buildpropfile);

            var valuesBuild = GetPropValues(rows);

            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("BuildDebug")))
            {
                LogTCSection("Teamcity Properties", valuesBuild.Select(p => $"Build: {p.Key}={p.Value}"));
            }

            string configpropfile = valuesBuild["teamcity.configuration.properties.file"];
            if (string.IsNullOrEmpty(configpropfile))
            {
                Log("Couldn't find Teamcity config properties file.");
                return new Dictionary<string, string>();
            }
            if (!File.Exists(configpropfile))
            {
                Log($"Couldn't find Teamcity config properties file: '{configpropfile}'");
                return new Dictionary<string, string>();
            }

            Log($"Reading Teamcity config properties file: '{configpropfile}'");
            rows = File.ReadAllLines(configpropfile);

            var valuesConfig = GetPropValues(rows);

            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("BuildDebug")))
            {
                LogTCSection("Teamcity Properties", valuesConfig.Select(p => $"Config: {p.Key}={p.Value}"));
            }

            return valuesConfig;
        }

        static Dictionary<string, string> GetPropValues(string[] rows)
        {
            Dictionary<string, string> dic = new Dictionary<string, string>();

            foreach (string row in rows)
            {
                int index = row.IndexOf('=');
                if (index != -1)
                {
                    string key = row.Substring(0, index);
                    string value = Regex.Unescape(row.Substring(index + 1));
                    dic[key] = value;
                }
            }

            return dic;
        }

        private static void LogTCSection(string message, IEnumerable<string> collection)
        {
            Console.WriteLine(
                $"##teamcity[blockOpened name='{message}']{Environment.NewLine}" +
                string.Join(string.Empty, collection.Select(t => $"{t}{Environment.NewLine}")) +
                $"##teamcity[blockClosed name='{message}']");
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
            string hostname = Dns.GetHostName();
            Console.WriteLine($"{hostname}: {message}");
        }
    }
}
