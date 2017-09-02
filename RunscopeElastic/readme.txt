This is an integration for injecting monitoring results from Runscope into Elasticsearch.

A webhook needs to be configured in Runscope that post a json document to Elastic for each request.
To make most use of the json document, it has to be transformed a bit before inserted into Elastic,
this is done by utilizing an ingest pipeline. The generic ingest pipeline provied is useful for
monitoring any service. The jsonresult pipeline is useful for monitoring services that returns a
json document as a result, an example of this is the _cluster/health page in Elasticsearch.
I.e the Elasticsearch specific ingest pipeline is should be used when posting monitoring results of
an Elasticsearch cluster.

The ingest pipelines can be installed by running the content of the json files in Kibana Dev Tools.

To configure Runscope to monitor an Elasticsearch cluster and post the json result into the cluster:
Specify Authentication, for a user that has access to the _cluster/health page.
Add a get request like this:
https://mycluster:9200/_cluster/health
Add a variable:
With source "JSON Body", no property, and variable name "result".
And add a webhook like this:
https://runscopeuser:pass@mycluster:9200/runscope/test?pipeline=runscopejsonresult
Ths runscopeuser must have access to the runscope-* index.
