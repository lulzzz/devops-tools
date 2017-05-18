using Newtonsoft.Json.Linq;
using System;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;

namespace BackupGrafana
{
    class SaveGrafana
    {
        public static string logfile { get; set; }
        public static string[] logreplace { get; set; }

        public void SaveDashboards(string serverurl, string username, string password, string folder)
        {
            logreplace = new[] { username, password };

            if (!Directory.Exists(folder))
            {
                Directory.CreateDirectory(folder);
            }

            using (HttpClient client = new HttpClient())
            {
                var creds = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{username}:{password}"));
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", creds);

                client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

                Log("Retrieving orgs.");
                string url = $"{serverurl}/api/orgs";
                string result = client.GetStringAsync(url).Result;

                JArray orgs = JArray.Parse(result);

                foreach (dynamic org in orgs)
                {
                    Log($"Switching to org: {org.id} '{org.name}'");
                    url = $"{serverurl}/api/user/using/{org.id}";
                    var postresult = client.PostAsync(url, null);
                    result = postresult.Result.Content.ReadAsStringAsync().Result;

                    Log("Searching for dashboards.");
                    url = $"{serverurl}/api/search/";
                    result = client.GetStringAsync(url).Result;

                    JArray array = JArray.Parse(result);

                    foreach (dynamic j in array)
                    {
                        Log($"Retrieving dashboard: '{j.uri}'");
                        url = $"{serverurl}/api/dashboards/{j.uri}";
                        result = client.GetStringAsync(url).Result;

                        dynamic dashboard = JObject.Parse(result);

                        string name = dashboard.meta.slug;

                        string filename = Path.Combine(folder, PrettyName($"{org.name}_{name}") + ".json");

                        string pretty = JToken.Parse(result).ToString(Newtonsoft.Json.Formatting.Indented);

                        Log($"Saving: '{filename}'");
                        File.WriteAllText(filename, pretty);
                    }
                }
            }

            return;
        }

        string PrettyName(string name)
        {
            StringBuilder result = new StringBuilder();

            foreach (char c in name.ToCharArray())
            {
                if (char.IsLetterOrDigit(c) || c == '-' || c == '_')
                {
                    result.Append(c);
                }
            }

            return result.ToString();
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
