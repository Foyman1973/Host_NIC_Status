# vMotion Connection Check
This PowerCLI script can be run from a PowerShell 5.1+ session with PowerCLI v10+ to perform an automated check of vMotion connectivity of a vCenter, vCenter Datacenter, or vCenter cluster to either audit or troubleshoot vMotion connection issues.

This script will create a /Reports/ sub folder and create a CSV output of connection tests at the end of the script run.

**NOTE:** This script assumes you are already connected to relavent vCenter instances prior to running the script.