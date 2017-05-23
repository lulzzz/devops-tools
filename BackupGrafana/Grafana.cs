﻿using Newtonsoft.Json.Linq;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;

namespace BackupGrafana
{
    class Grafana
    {
        public bool SaveDashboards(string serverurl, string username, string password, string folder)
        {
            Output.Replace = new List<string>() { username, password };

            Filesystem.RobustDelete(folder);

            Output.Write($"Creating directory: '{folder}'");
            Directory.CreateDirectory(folder);

            using (HttpClient client = new HttpClient())
            {
                var creds = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{username}:{password}"));
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", creds);

                client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

                Output.Write("Retrieving orgs.");
                string url = $"{serverurl}/api/orgs";
                string result;
                try
                {
                    result = client.GetStringAsync(url).Result;
                }
                catch (AggregateException ex)
                {
                    Output.Write($"Couldn't connect to Grafana server: '{url}' '{ex.Message}'");
                    return false;
                }

                JArray orgs = JArray.Parse(result);

                foreach (dynamic org in orgs)
                {
                    Output.Write($"Switching to org: {org.id} '{org.name}'");
                    url = $"{serverurl}/api/user/using/{org.id}";
                    var postresult = client.PostAsync(url, null);
                    result = postresult.Result.Content.ReadAsStringAsync().Result;

                    Output.Write("Searching for dashboards.");
                    url = $"{serverurl}/api/search/";
                    result = client.GetStringAsync(url).Result;

                    JArray array = JArray.Parse(result);

                    foreach (dynamic j in array)
                    {
                        Output.Write($"Retrieving dashboard: '{j.uri}'");
                        url = $"{serverurl}/api/dashboards/{j.uri}";
                        result = client.GetStringAsync(url).Result;

                        dynamic dashboard = JObject.Parse(result);

                        string name = dashboard.meta.slug;

                        dashboard.meta.Property("expires").Remove();
                        dashboard.meta.Property("created").Remove();
                        dashboard.meta.Property("updated").Remove();
                        dashboard.meta.Property("updatedBy").Remove();
                        dashboard.meta.Property("createdBy").Remove();
                        dashboard.meta.Property("version").Remove();

                        string filename = Path.Combine(folder, PrettyName($"{org.name}_{name}") + ".json");

                        string pretty = dashboard.ToString(Newtonsoft.Json.Formatting.Indented);

                        Output.Write($"Saving: '{filename}'");
                        File.WriteAllText(filename, pretty);
                    }
                }
            }

            return true;
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
    }
}
