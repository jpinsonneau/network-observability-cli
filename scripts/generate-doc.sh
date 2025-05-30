#!/usr/bin/env bash

source "./scripts/help.sh"

ADOC=./docs/netobserv_cli.adoc

# Header
echo "// Automatically generated by '$0'. Do not edit, or make the NETOBSERV team aware of the editions.
:_mod-docs-content-type: REFERENCE

[id=\"network-observability-netobserv-cli-reference_{context}\"]
= Network Observability CLI usage

You can use the Network Observability CLI (\`oc netobserv\`) to pass command line arguments to capture flows data, packets data, and metrics for further analysis and enable features supported by the Network Observability Operator.

[id=\"cli-syntax_{context}\"]
== Syntax 
The basic syntax for \`oc netobserv\` commands: 

.\`oc netobserv\` syntax
[source,terminal]
----
$ oc netobserv [<command>] [<feature_option>] [<command_options>] <1>
----
<1> Feature options can only be used with the \`oc netobserv flows\` command. They cannot be used with the \`oc netobserv packets\` command.

[id=\"cli-basic-commands_{context}\"]
== Basic commands
[cols=\"3a,8a\",options=\"header\"]
.Basic commands
|===
| Command | Description
| flows
| Capture flows information. For subcommands, see the \"Flows capture options\" table.
| packets
| Capture packets data. For subcommands, see the \"Packets capture options\" table.
| metrics
| Capture metrics data. For subcommands, see the \"Metrics capture options\" table.
| follow
| Follow collector logs when running in background.
| stop
| Stop collection by removing agent daemonset.
| copy
| Copy collector generated files locally.
| cleanup
| Remove the Network Observability CLI components.
| version
| Print the software version.
| help
| Show help.
|===
" > $ADOC

# flows table
{
echo "[id=\"cli-reference-flows-capture-options_{context}\"]
== Flows capture options
Flows capture has mandatory commands as well as additional options, such as enabling extra features about packet drops, DNS latencies, Round-trip time, and filtering.

.\`oc netobserv flows\` syntax
[source,terminal]
----
$ oc netobserv flows [<feature_option>] [<command_options>]
----
[cols=\"1,1,1\",options=\"header\"]
|===
| Option | Description | Default"
features_usage
collector_usage
filters_usage
flowsAndMetrics_filters_usage
echo -e "|==="
# flows example
echo "
.Example running flows capture on TCP protocol and port 49051 with PacketDrop and RTT features enabled:
[source,terminal]
----
$ oc netobserv flows --enable_pkt_drop  --enable_rtt --action=Accept --cidr=0.0.0.0/0 --protocol=TCP --port=49051
----"

# packets table
echo "[id=\"cli-reference-packet-capture-options_{context}\"]
== Packets capture options
You can filter packets capture data the as same as flows capture by using the filters.
Certain features, such as packets drop, DNS, RTT, and network events, are only available for flows and metrics capture.

.\`oc netobserv packets\` syntax
[source,terminal]
----
$ oc netobserv packets [<option>]
----
[cols=\"1,1,1\",options=\"header\"]
|===
| Option | Description | Default"
collector_usage
filters_usage
echo -e "|==="
# packets example
echo "
.Example running packets capture on TCP protocol and port 49051:
[source,terminal]
----
$ oc netobserv packets --action=Accept --cidr=0.0.0.0/0 --protocol=TCP --port=49051
----"

# Metrics table
echo "[id=\"cli-reference-metrics-capture-options_{context}\"]
== Metrics capture options
You can enable features and use filters on metrics capture, the same as flows capture. The generated graphs fill accordingly in the dashboard.

.\`oc netobserv metrics\` syntax
[source,terminal]
----
$ oc netobserv metrics [<option>]
----
[cols=\"1,1,1\",options=\"header\"]
|===
| Option | Description | Default"
features_usage
filters_usage
metrics_options
flowsAndMetrics_filters_usage
echo -e "|==="
# Metrics example
echo "
.Example running metrics capture for TCP drops
[source,terminal]
----
$ oc netobserv metrics --enable_pkt_drop --protocol=TCP 
----"
} >> $ADOC

# remove double spaces
sed -i.bak "s/  */ /" $ADOC
# add table rows
sed -i.bak "/^ /s/ --*/|--/" $ADOC
# add table columns
sed -i.bak "/^|/s/(default: n\/a/| -/" $ADOC # replace n/a by - in the docs
sed -i.bak "/^|/s/(default:/|/" $ADOC
sed -i.bak "/^|/s/: /|/" $ADOC
sed -i.bak "/^|/s/)//" $ADOC

rm ./docs/*.bak
